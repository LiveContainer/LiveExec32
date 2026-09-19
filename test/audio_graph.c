#include <AudioToolbox/AudioToolbox.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// The pre-iOS-9 variant is no longer declared by the current SDK.
extern OSStatus AudioUnitRemovePropertyListener(AudioUnit, AudioUnitPropertyID,
    AudioUnitPropertyListenerProc);

static int failures;
static unsigned callbacks;
static unsigned propertyCallbacks, runningChanges;
static void check(const char *name, int passed) {
    printf("audio-graph-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static OSStatus render(void *context, AudioUnitRenderActionFlags *flags,
        const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *buffers) {
    (void)flags; (void)time; (void)bus; (void)frames;
    if(context != &callbacks || !buffers) return kAudio_ParamError;
    for(UInt32 i = 0; i < buffers->mNumberBuffers; ++i)
        memset(buffers->mBuffers[i].mData, 0, buffers->mBuffers[i].mDataByteSize);
    __atomic_store_n(&callbacks, 1, __ATOMIC_RELAXED);
    return noErr;
}
static void propertyChanged(void *context, AudioUnit unit, AudioUnitPropertyID property,
        AudioUnitScope scope, AudioUnitElement element) {
    if(context == &propertyCallbacks) {
        AudioStreamBasicDescription format = {0}; UInt32 size = sizeof(format);
        if(AudioUnitGetProperty(unit, property, scope, element, &format, &size) == noErr &&
           format.mSampleRate == 24000) ++propertyCallbacks;
        AudioUnitRemovePropertyListenerWithUserData(unit, property, propertyChanged, context);
    } else if(context == &runningChanges) {
        ++runningChanges;
    }
}
int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    AUGraph graph = NULL;
    check("create", NewAUGraph(&graph) == noErr && graph);
    if(!graph) return 1;
    Boolean value = true;
    check("initially-closed", AUGraphIsOpen(graph, &value) == noErr && !value);
    check("start-uninitialized", AUGraphStart(graph) == kAudioUnitErr_Uninitialized);
    AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_RemoteIO,
        kAudioUnitManufacturer_Apple, 0, 0};
    AUNode output = 0;
    check("add-output", AUGraphAddNode(graph, &description, &output) == noErr && output);
    UInt32 count = 0; AUNode id = 0;
    check("count", AUGraphGetNodeCount(graph, &count) == noErr && count == 1);
    check("index", AUGraphGetIndNode(graph, 0, &id) == noErr && id == output);
    AudioComponentDescription returned = {0}; AudioUnit unit = (AudioUnit)1;
    check("metadata-before-open", AUGraphNodeInfo(graph, output, &returned, &unit) == noErr &&
        !unit && memcmp(&description, &returned, sizeof(description)) == 0);
    AURenderCallbackStruct callback = {render, &callbacks};
    check("callback-before-open", AUGraphSetNodeInputCallback(graph, output, 0, &callback) == noErr);
    check("invalid-node", AUGraphNodeInfo(graph, -1, NULL, NULL) == kAUGraphErr_NodeNotFound);
    check("self-connection", AUGraphConnectNodeInput(graph, output, 0, output, 0) == kAUGraphErr_InvalidConnection);
    check("open", AUGraphOpen(graph) == noErr && AUGraphIsOpen(graph, &value) == noErr && value);
    check("open-idempotent", AUGraphOpen(graph) == noErr);
    check("node-unit", AUGraphNodeInfo(graph, output, NULL, &unit) == noErr && unit);
    AudioStreamBasicDescription format = {24000, kAudioFormatLinearPCM,
        kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    check("property-listener-add", AudioUnitAddPropertyListener(unit,
        kAudioUnitProperty_StreamFormat, propertyChanged, &propertyCallbacks) == noErr);
    check("set-format", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0, &format, sizeof(format)) == noErr);
    check("property-listener-reentrant", propertyCallbacks == 1);
    AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0, &format, sizeof(format));
    check("property-listener-removed", propertyCallbacks == 1);
    check("running-listener-add", AudioUnitAddPropertyListener(unit,
        kAudioOutputUnitProperty_IsRunning, propertyChanged, &runningChanges) == noErr);
    // Exercise callback updates after the graph has opened, too.
    check("callback-after-open", AUGraphSetNodeInputCallback(graph, output, 0, &callback) == noErr);
    check("initialize", AUGraphInitialize(graph) == noErr &&
        AUGraphIsInitialized(graph, &value) == noErr && value);
    check("start", AUGraphStart(graph) == noErr && AUGraphIsRunning(graph, &value) == noErr && value);
    for(unsigned i = 0; i < 100 && !__atomic_load_n(&callbacks, __ATOMIC_RELAXED); ++i) usleep(10000);
    check("guest-callback-renders", __atomic_load_n(&callbacks, __ATOMIC_RELAXED) != 0);
    check("stop", AUGraphStop(graph) == noErr && AUGraphIsRunning(graph, &value) == noErr && !value);
    check("running-notifications", runningChanges == 2);
    check("direct-unit-restart", AudioOutputUnitStart(unit) == noErr);
    check("uninitialize-running-unit", AudioUnitUninitialize(unit) == noErr &&
        runningChanges == 4);
    check("running-listener-remove", AudioUnitRemovePropertyListener(unit,
        kAudioOutputUnitProperty_IsRunning, propertyChanged) == noErr);
    check("uninitialize", AUGraphUninitialize(graph) == noErr &&
        AUGraphIsInitialized(graph, &value) == noErr && !value);
    check("close", AUGraphClose(graph) == noErr && AUGraphIsOpen(graph, &value) == noErr && !value);
    check("close-preserves-nodes", AUGraphGetNodeCount(graph, &count) == noErr && count == 1);
    check("reopen", AUGraphOpen(graph) == noErr &&
        AUGraphNodeInfo(graph, output, NULL, &unit) == noErr && unit);
    check("dispose", DisposeAUGraph(graph) == noErr);
    check("null-output", NewAUGraph(NULL) == kAudio_ParamError);
    return failures ? 1 : 0;
}
