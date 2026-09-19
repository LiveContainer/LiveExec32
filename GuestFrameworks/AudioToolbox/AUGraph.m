#import <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdlib.h>

// Keep graph handles, AudioUnits, and render callbacks in guest address space.
// Rendering is performed by the existing AudioUnit adapters, not by native
// AUGraph (which cannot call an ARM32 function pointer).
typedef struct LC32GraphNode {
    struct LC32GraphNode *next;
    AUNode id;
    AudioComponentDescription description;
    AudioUnit unit;
} LC32GraphNode;

typedef struct LC32GraphInput {
    struct LC32GraphInput *next;
    AUNode source, destination;
    UInt32 output, input;
    AURenderCallbackStruct callback;
} LC32GraphInput;

struct OpaqueAUGraph {
    LC32GraphNode *nodes;
    LC32GraphInput *inputs;
    AUNode nextID;
    Boolean open, initialized, running;
};

static LC32GraphNode *FindNode(AUGraph graph, AUNode id) {
    for(LC32GraphNode *node = graph ? graph->nodes : NULL; node; node = node->next)
        if(node->id == id) return node;
    return NULL;
}

static OSStatus ApplyInput(AUGraph graph, LC32GraphInput *input) {
    LC32GraphNode *destination = FindNode(graph, input->destination);
    if(!destination || !destination->unit) return kAUGraphErr_NodeNotFound;
    if(input->source) {
        LC32GraphNode *source = FindNode(graph, input->source);
        if(!source || !source->unit) return kAUGraphErr_NodeNotFound;
        AudioUnitConnection connection = {source->unit, input->output, input->input};
        return AudioUnitSetProperty(destination->unit, kAudioUnitProperty_MakeConnection,
            kAudioUnitScope_Input, input->input, &connection, sizeof(connection));
    }
    AudioUnitScope scope = destination->description.componentType == kAudioUnitType_Output
        ? kAudioUnitScope_Global : kAudioUnitScope_Input;
    return AudioUnitSetProperty(destination->unit, kAudioUnitProperty_SetRenderCallback,
        scope, input->input, &input->callback, sizeof(input->callback));
}

OSStatus NewAUGraph(AUGraph *outGraph) {
    if(!outGraph) return kAudio_ParamError;
    *outGraph = calloc(1, sizeof(**outGraph));
    if(!*outGraph) return kAudio_MemFullError;
    (*outGraph)->nextID = 1;
    return noErr;
}

OSStatus AUGraphAddNode(AUGraph graph, const AudioComponentDescription *description, AUNode *outNode) {
    if(!graph || !description || !outNode) return kAudio_ParamError;
    if(graph->initialized) return kAUGraphErr_CannotDoInCurrentContext;
    AudioComponent component = AudioComponentFindNext(NULL, description);
    if(!component) return kAUGraphErr_InvalidAudioUnit;
    if(graph->nextID == INT32_MAX) return kAudio_MemFullError;
    LC32GraphNode *node = calloc(1, sizeof(*node));
    if(!node) return kAudio_MemFullError;
    if(graph->open) {
        OSStatus result = AudioComponentInstanceNew(component, &node->unit);
        if(result) { free(node); return result; }
    }
    node->description = *description;
    node->id = graph->nextID++;
    LC32GraphNode **tail = &graph->nodes;
    while(*tail) tail = &(*tail)->next;
    *tail = node;
    *outNode = node->id;
    return noErr;
}

OSStatus AUGraphNodeInfo(AUGraph graph, AUNode id,
        AudioComponentDescription *description, AudioUnit *unit) {
    if(!graph) return kAudio_ParamError;
    LC32GraphNode *node = FindNode(graph, id);
    if(!node) return kAUGraphErr_NodeNotFound;
    if(description) *description = node->description;
    if(unit) *unit = node->unit;
    return noErr;
}

OSStatus AUGraphGetNodeCount(AUGraph graph, UInt32 *count) {
    if(!graph || !count) return kAudio_ParamError;
    *count = 0;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) ++*count;
    return noErr;
}

OSStatus AUGraphGetIndNode(AUGraph graph, UInt32 index, AUNode *id) {
    if(!graph || !id) return kAudio_ParamError;
    LC32GraphNode *node = graph->nodes;
    while(node && index--) node = node->next;
    if(!node) return kAUGraphErr_NodeNotFound;
    *id = node->id;
    return noErr;
}

static OSStatus SetInput(AUGraph graph, const LC32GraphInput *value) {
    if(!graph) return kAudio_ParamError;
    if(graph->initialized) return kAUGraphErr_CannotDoInCurrentContext;
    if(!FindNode(graph, value->destination) ||
       (value->source && !FindNode(graph, value->source))) return kAUGraphErr_NodeNotFound;
    if(value->source == value->destination) return kAUGraphErr_InvalidConnection;
    LC32GraphInput *input = graph->inputs;
    while(input && (input->destination != value->destination || input->input != value->input))
        input = input->next;
    LC32GraphInput *allocated = input ? NULL : calloc(1, sizeof(*input));
    if(!input && !allocated) return kAudio_MemFullError;
    if(graph->open) {
        OSStatus result = ApplyInput(graph, (LC32GraphInput *)value);
        if(result) { free(allocated); return result; }
    }
    if(!input) { input = allocated; input->next = graph->inputs; graph->inputs = input; }
    LC32GraphInput *next = input->next;
    *input = *value;
    input->next = next;
    return noErr;
}

OSStatus AUGraphConnectNodeInput(AUGraph graph, AUNode source, UInt32 output,
        AUNode destination, UInt32 input) {
    if(!source) return kAUGraphErr_NodeNotFound;
    LC32GraphInput connection = {.source = source, .destination = destination,
        .output = output, .input = input};
    return SetInput(graph, &connection);
}

OSStatus AUGraphSetNodeInputCallback(AUGraph graph, AUNode destination, UInt32 input,
        const AURenderCallbackStruct *callback) {
    if(!callback) return kAudio_ParamError;
    LC32GraphInput connection = {.destination = destination, .input = input, .callback = *callback};
    return SetInput(graph, &connection);
}

OSStatus AUGraphOpen(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    if(graph->open) return noErr;
    OSStatus result = noErr;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        result = AudioComponentInstanceNew(AudioComponentFindNext(NULL, &node->description), &node->unit);
        if(result) break;
    }
    if(!result) {
        for(LC32GraphInput *input = graph->inputs; input; input = input->next) {
            result = ApplyInput(graph, input);
            if(result) break;
        }
    }
    if(result) {
        for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
            if(node->unit) AudioComponentInstanceDispose(node->unit);
            node->unit = NULL;
        }
        return result;
    }
    graph->open = true;
    return noErr;
}

OSStatus AUGraphInitialize(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    if(!graph->open) return kAudioUnitErr_Uninitialized;
    if(graph->initialized) return noErr;
    unsigned outputs = 0;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next)
        outputs += node->description.componentType == kAudioUnitType_Output;
    if(outputs != 1) return kAUGraphErr_OutputNodeErr;
    OSStatus result = noErr;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        result = AudioUnitInitialize(node->unit);
        if(result) break;
    }
    if(result) {
        for(LC32GraphNode *node = graph->nodes; node; node = node->next)
            AudioUnitUninitialize(node->unit);
        return result;
    }
    graph->initialized = true;
    return noErr;
}

OSStatus AUGraphStart(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    if(!graph->initialized) return kAudioUnitErr_Uninitialized;
    if(graph->running) return noErr;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        if(node->description.componentType == kAudioUnitType_Output) {
            OSStatus result = AudioOutputUnitStart(node->unit);
            if(result) return result;
        }
    }
    graph->running = true;
    return noErr;
}

OSStatus AUGraphStop(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    if(!graph->running) return noErr;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        if(node->description.componentType == kAudioUnitType_Output) {
            OSStatus result = AudioOutputUnitStop(node->unit);
            if(result) return result;
        }
    }
    graph->running = false;
    return noErr;
}

OSStatus AUGraphUninitialize(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    OSStatus result = AUGraphStop(graph);
    if(result || !graph->initialized) return result;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        result = AudioUnitUninitialize(node->unit);
        if(result) return result;
    }
    graph->initialized = false;
    return noErr;
}

OSStatus AUGraphClose(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    OSStatus result = AUGraphUninitialize(graph);
    if(result) return result;
    for(LC32GraphNode *node = graph->nodes; node; node = node->next) {
        if(node->unit) {
            result = AudioComponentInstanceDispose(node->unit);
            if(result) return result;
            node->unit = NULL;
        }
    }
    graph->open = false;
    return noErr;
}

OSStatus DisposeAUGraph(AUGraph graph) {
    if(!graph) return kAudio_ParamError;
    OSStatus result = AUGraphClose(graph);
    if(result) return result;
    while(graph->inputs) {
        LC32GraphInput *input = graph->inputs;
        graph->inputs = input->next;
        free(input);
    }
    while(graph->nodes) {
        LC32GraphNode *node = graph->nodes;
        graph->nodes = node->next;
        free(node);
    }
    free(graph);
    return noErr;
}

OSStatus AUGraphIsOpen(AUGraph graph, Boolean *value) {
    if(!graph || !value) return kAudio_ParamError;
    *value = graph->open;
    return noErr;
}

OSStatus AUGraphIsInitialized(AUGraph graph, Boolean *value) {
    if(!graph || !value) return kAudio_ParamError;
    *value = graph->initialized;
    return noErr;
}

OSStatus AUGraphIsRunning(AUGraph graph, Boolean *value) {
    if(!graph || !value) return kAudio_ParamError;
    *value = graph->running;
    return noErr;
}
