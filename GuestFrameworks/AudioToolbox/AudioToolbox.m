#import <AudioToolbox/AudioToolbox.h>
#import <LC32/LC32.h>

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#import "LC32AudioToolboxBridge.h"

/* Deprecated AudioSession route dictionary values retained for old apps. */
const CFStringRef kAudioSessionInputRoute_BuiltInMic =
    CFSTR("MicrophoneBuiltIn");
const CFStringRef kAudioSession_AudioRouteKey_Inputs =
    CFSTR("RouteDetailedDescription_Inputs");
const CFStringRef kAudioSession_AudioRouteKey_Type =
    CFSTR("RouteDetailedDescription_PortType");

static pthread_once_t LC32AudioToolboxDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32AudioToolboxDispatcherAddress;

static void LC32AudioToolboxResolveDispatcher(void) {
    LC32AudioToolboxDispatcherAddress =
        LC32Dlsym("LC32_AudioToolbox_Dispatch", YES);
}

static uint32_t LC32AudioToolboxDispatch(LC32AudioToolboxOpcode opcode,
                                         const uint64_t *slots,
                                         uint32_t slotCount) {
    if(slotCount > LC32AudioToolboxMaxSlots) return (uint32_t)kAudio_ParamError;
    pthread_once(&LC32AudioToolboxDispatcherOnce,
        LC32AudioToolboxResolveDispatcher);
    if(!LC32AudioToolboxDispatcherAddress) return (uint32_t)kAudio_ParamError;

    LC32AudioToolboxCall call = {
        .version = LC32AudioToolboxABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32AudioToolboxDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}

#define LC32_AUDIO_CALL(opcode, ...) \
    LC32AudioToolboxDispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t)))
#define LC32_AUDIO_U32(value) ((uint64_t)(uint32_t)(value))

typedef struct LC32GuestAudioQueueBuffer {
    uint32_t audioDataBytesCapacity;
    uint32_t audioData;
    uint32_t audioDataByteSize;
    uint32_t userData;
    uint32_t packetDescriptionCapacity;
    uint32_t packetDescriptions;
    uint32_t packetDescriptionCount;
} LC32GuestAudioQueueBuffer;

typedef struct LC32GuestAudioQueueInputCallbackStorage {
    AudioTimeStamp timeStamp;
    uint32_t packetCount;
    uint32_t packetDescriptions;
} LC32GuestAudioQueueInputCallbackStorage;

typedef struct LC32GuestAudioQueueAllocation {
    struct LC32GuestAudioQueueAllocation *next;
    AudioQueueRef queue;
    LC32GuestAudioQueueInputCallbackStorage callbackStorage;
    LC32GuestAudioQueueBuffer buffer;
} LC32GuestAudioQueueAllocation;

typedef struct LC32GuestAudioQueueLifecycle {
    struct LC32GuestAudioQueueLifecycle *next;
    AudioQueueRef queue;
    pthread_mutex_t mutex;
    uint32_t users;
    BOOL disposing;
    BOOL removed;
} LC32GuestAudioQueueLifecycle;

_Static_assert(sizeof(LC32GuestAudioQueueBuffer) == 28,
    "ARM32 AudioQueueBuffer layout changed");
_Static_assert(sizeof(AudioTimeStamp) == 64,
    "ARM32 AudioTimeStamp layout changed");
_Static_assert(offsetof(LC32GuestAudioQueueInputCallbackStorage,
    packetCount) == 64, "AudioQueue callback scratch layout changed");

static pthread_mutex_t LC32AudioQueueAllocationsMutex =
    PTHREAD_MUTEX_INITIALIZER;
static LC32GuestAudioQueueAllocation *LC32AudioQueueAllocations;
static pthread_mutex_t LC32AudioQueueLifecyclesMutex =
    PTHREAD_MUTEX_INITIALIZER;
static LC32GuestAudioQueueLifecycle *LC32AudioQueueLifecycles;
enum {
    LC32AudioQueueMaximumAllocationBytes = 256u * 1024u * 1024u,
};

static size_t LC32AudioQueueAlign8(size_t value) {
    return (value + 7u) & ~(size_t)7u;
}

static LC32GuestAudioQueueLifecycle *LC32AudioQueueCreateLifecycle(
        AudioQueueRef queue) {
    LC32GuestAudioQueueLifecycle *lifecycle =
        calloc(1, sizeof(*lifecycle));
    if(!lifecycle) return NULL;
    lifecycle->queue = queue;
    if(pthread_mutex_init(&lifecycle->mutex, NULL)) {
        free(lifecycle);
        return NULL;
    }

    pthread_mutex_lock(&LC32AudioQueueLifecyclesMutex);
    for(LC32GuestAudioQueueLifecycle *candidate =
            LC32AudioQueueLifecycles; candidate;
            candidate = candidate->next) {
        if(candidate->queue == queue && !candidate->removed) {
            pthread_mutex_unlock(&LC32AudioQueueLifecyclesMutex);
            pthread_mutex_destroy(&lifecycle->mutex);
            free(lifecycle);
            return NULL;
        }
    }
    lifecycle->next = LC32AudioQueueLifecycles;
    LC32AudioQueueLifecycles = lifecycle;
    pthread_mutex_unlock(&LC32AudioQueueLifecyclesMutex);
    return lifecycle;
}

static void LC32AudioQueueReleaseLifecycleReference(
        LC32GuestAudioQueueLifecycle *lifecycle) {
    BOOL destroy = NO;
    pthread_mutex_lock(&LC32AudioQueueLifecyclesMutex);
    if(lifecycle->users) --lifecycle->users;
    destroy = lifecycle->removed && lifecycle->users == 0;
    pthread_mutex_unlock(&LC32AudioQueueLifecyclesMutex);
    if(destroy) {
        pthread_mutex_destroy(&lifecycle->mutex);
        free(lifecycle);
    }
}

static LC32GuestAudioQueueLifecycle *LC32AudioQueueAcquireLifecycle(
        AudioQueueRef queue) {
    LC32GuestAudioQueueLifecycle *lifecycle = NULL;
    pthread_mutex_lock(&LC32AudioQueueLifecyclesMutex);
    for(LC32GuestAudioQueueLifecycle *candidate =
            LC32AudioQueueLifecycles; candidate;
            candidate = candidate->next) {
        if(candidate->queue == queue && !candidate->removed) {
            lifecycle = candidate;
            ++lifecycle->users;
            break;
        }
    }
    pthread_mutex_unlock(&LC32AudioQueueLifecyclesMutex);
    if(!lifecycle) return NULL;

    pthread_mutex_lock(&lifecycle->mutex);
    if(lifecycle->removed || lifecycle->disposing) {
        pthread_mutex_unlock(&lifecycle->mutex);
        LC32AudioQueueReleaseLifecycleReference(lifecycle);
        return NULL;
    }
    return lifecycle;
}

static void LC32AudioQueueReleaseLifecycle(
        LC32GuestAudioQueueLifecycle *lifecycle) {
    pthread_mutex_unlock(&lifecycle->mutex);
    LC32AudioQueueReleaseLifecycleReference(lifecycle);
}

static void LC32AudioQueueRemoveLifecycleLocked(
        LC32GuestAudioQueueLifecycle *lifecycle) {
    pthread_mutex_lock(&LC32AudioQueueLifecyclesMutex);
    LC32GuestAudioQueueLifecycle **cursor = &LC32AudioQueueLifecycles;
    while(*cursor && *cursor != lifecycle) cursor = &(*cursor)->next;
    if(*cursor == lifecycle) *cursor = lifecycle->next;
    lifecycle->removed = YES;
    pthread_mutex_unlock(&LC32AudioQueueLifecyclesMutex);
}

static void LC32AudioQueueTrackAllocation(
        LC32GuestAudioQueueAllocation *allocation) {
    pthread_mutex_lock(&LC32AudioQueueAllocationsMutex);
    allocation->next = LC32AudioQueueAllocations;
    LC32AudioQueueAllocations = allocation;
    pthread_mutex_unlock(&LC32AudioQueueAllocationsMutex);
}

static void LC32AudioQueueReleaseAllocations(AudioQueueRef queue) {
    LC32GuestAudioQueueAllocation *released = NULL;
    pthread_mutex_lock(&LC32AudioQueueAllocationsMutex);
    LC32GuestAudioQueueAllocation **cursor = &LC32AudioQueueAllocations;
    while(*cursor) {
        LC32GuestAudioQueueAllocation *allocation = *cursor;
        if(allocation->queue != queue) {
            cursor = &allocation->next;
            continue;
        }
        *cursor = allocation->next;
        allocation->next = released;
        released = allocation;
    }
    pthread_mutex_unlock(&LC32AudioQueueAllocationsMutex);
    while(released) {
        LC32GuestAudioQueueAllocation *next = released->next;
        free(released);
        released = next;
    }
}

/* Invoked by the host only after a dispose requested from inside a queue
 * callback has drained all callbacks/users and detached the native mirrors.
 * Keeping this in the guest preserves malloc ownership without leaking every
 * buffer allocated by a queue which disposes itself from its callback. */
static void LC32AudioQueueReleaseDeferredAllocations(AudioQueueRef queue) {
    LC32AudioQueueReleaseAllocations(queue);
}

static void LC32AudioQueueCallbackScope(AudioQueueRef queue, BOOL entering) {
    if(!queue) return;
    (void)LC32_AUDIO_CALL(entering
        ? LC32AudioToolboxOpAudioQueueCallbackEnter
        : LC32AudioToolboxOpAudioQueueCallbackLeave,
        LC32_AUDIO_U32((uintptr_t)queue));
}

static void LC32AudioQueueInvokeInputCallback(
        uint32_t callbackAddress, void *userData, AudioQueueRef queue,
        AudioQueueBufferRef buffer,
        LC32GuestAudioQueueInputCallbackStorage *storage) {
    if(!callbackAddress || !storage) return;
    AudioQueueInputCallback callback =
        (AudioQueueInputCallback)(uintptr_t)callbackAddress;
    LC32AudioQueueCallbackScope(queue, YES);
    @try {
        callback(userData, queue, buffer, &storage->timeStamp,
            storage->packetCount,
            (const AudioStreamPacketDescription *)(uintptr_t)
                storage->packetDescriptions);
    } @finally {
        LC32AudioQueueCallbackScope(queue, NO);
    }
}

static void LC32AudioQueueInvokeOutputCallback(
        uint32_t callbackAddress, void *userData, AudioQueueRef queue,
        AudioQueueBufferRef buffer) {
    if(!callbackAddress) return;
    AudioQueueOutputCallback callback =
        (AudioQueueOutputCallback)(uintptr_t)callbackAddress;
    LC32AudioQueueCallbackScope(queue, YES);
    @try {
        callback(userData, queue, buffer);
    } @finally {
        LC32AudioQueueCallbackScope(queue, NO);
    }
}

static void LC32AudioQueueInvokePropertyListener(
        uint32_t callbackAddress, void *userData, AudioQueueRef queue,
        AudioQueuePropertyID property) {
    if(!callbackAddress) return;
    AudioQueuePropertyListenerProc callback =
        (AudioQueuePropertyListenerProc)(uintptr_t)callbackAddress;
    LC32AudioQueueCallbackScope(queue, YES);
    @try {
        callback(userData, queue, property);
    } @finally {
        LC32AudioQueueCallbackScope(queue, NO);
    }
}

// TODO: remaining AudioServices stubs

OSStatus AudioServicesCreateSystemSoundID(CFURLRef inFileURL, SystemSoundID *outSystemSoundID) {
    //static hostAddr = host_dlsym("AudioServicesCreateSystemSoundID");
    return 0;
}

OSStatus AudioServicesDisposeSystemSoundID(SystemSoundID inSystemSoundID) {
    return 0;
}

void AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID) {
    
}

OSStatus AudioQueueAddPropertyListener(AudioQueueRef inAQ, AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void * inUserData) {
    if(!inAQ || !inProc) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueAddPropertyListener,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inID),
        LC32_AUDIO_U32((uintptr_t)inProc),
        LC32_AUDIO_U32((uintptr_t)&LC32AudioQueueInvokePropertyListener),
        LC32_AUDIO_U32((uintptr_t)inUserData));
}

OSStatus AudioServicesSetProperty(AudioServicesPropertyID inPropertyID, UInt32 inSpecifierSize, const void * inSpecifier, UInt32 inPropertyDataSize, const void * inPropertyData) {
    return 0;
}

OSStatus AudioQueueAllocateBuffer(AudioQueueRef inAQ, UInt32 inBufferByteSize, AudioQueueBufferRef * outBuffer) {
    return AudioQueueAllocateBufferWithPacketDescriptions(
        inAQ, inBufferByteSize, 0, outBuffer);
}

OSStatus AudioQueueAllocateBufferWithPacketDescriptions(
        AudioQueueRef inAQ, UInt32 inBufferByteSize,
        UInt32 inNumberPacketDescriptions,
        AudioQueueBufferRef *outBuffer) {
    if(outBuffer) *outBuffer = NULL;
    if(!inAQ || !outBuffer) return kAudio_ParamError;
    if(inBufferByteSize > LC32AudioQueueMaximumAllocationBytes)
        return kAudio_ParamError;
    if(inNumberPacketDescriptions >
            SIZE_MAX / sizeof(AudioStreamPacketDescription)) {
        return kAudio_ParamError;
    }

    const size_t packetBytes = (size_t)inNumberPacketDescriptions *
        sizeof(AudioStreamPacketDescription);
    if(packetBytes > LC32AudioQueueMaximumAllocationBytes)
        return kAudio_ParamError;
    if(sizeof(LC32GuestAudioQueueAllocation) > SIZE_MAX - 7u)
        return kAudio_ParamError;
    const size_t dataOffset = LC32AudioQueueAlign8(
        sizeof(LC32GuestAudioQueueAllocation));
    if((size_t)inBufferByteSize > SIZE_MAX - dataOffset)
        return kAudio_ParamError;
    const size_t unalignedPacketOffset =
        dataOffset + (size_t)inBufferByteSize;
    if(unalignedPacketOffset > SIZE_MAX - 7u) return kAudio_ParamError;
    const size_t packetOffset =
        LC32AudioQueueAlign8(unalignedPacketOffset);
    if(packetOffset > LC32AudioQueueMaximumAllocationBytes ||
       packetBytes > LC32AudioQueueMaximumAllocationBytes - packetOffset) {
        return kAudio_ParamError;
    }

    LC32GuestAudioQueueAllocation *allocation =
        calloc(1, packetOffset + packetBytes);
    if(!allocation) return kAudio_MemFullError;
    allocation->queue = inAQ;
    allocation->buffer.audioDataBytesCapacity = inBufferByteSize;
    allocation->buffer.audioData =
        (uint32_t)(uintptr_t)((uint8_t *)allocation + dataOffset);
    allocation->buffer.packetDescriptionCapacity =
        inNumberPacketDescriptions;
    allocation->buffer.packetDescriptions = inNumberPacketDescriptions
        ? (uint32_t)(uintptr_t)((uint8_t *)allocation + packetOffset) : 0;
    allocation->callbackStorage.packetDescriptions =
        allocation->buffer.packetDescriptions;

    LC32GuestAudioQueueLifecycle *lifecycle =
        LC32AudioQueueAcquireLifecycle(inAQ);
    if(!lifecycle) {
        free(allocation);
        return kAudio_ParamError;
    }

    OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueAllocateBuffer,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inBufferByteSize),
        LC32_AUDIO_U32(inNumberPacketDescriptions),
        LC32_AUDIO_U32((uintptr_t)&allocation->buffer),
        LC32_AUDIO_U32(allocation->buffer.audioData),
        LC32_AUDIO_U32(allocation->buffer.packetDescriptions),
        LC32_AUDIO_U32((uintptr_t)&allocation->callbackStorage));
    if(status != noErr) {
        LC32AudioQueueReleaseLifecycle(lifecycle);
        free(allocation);
        return status;
    }
    LC32AudioQueueTrackAllocation(allocation);
    *outBuffer = (AudioQueueBufferRef)&allocation->buffer;
    LC32AudioQueueReleaseLifecycle(lifecycle);
    return noErr;
}

OSStatus AudioQueueDispose(AudioQueueRef inAQ, Boolean inImmediate) {
    if(!inAQ) return kAudio_ParamError;
    LC32GuestAudioQueueLifecycle *lifecycle =
        LC32AudioQueueAcquireLifecycle(inAQ);
    if(!lifecycle) return kAudio_ParamError;

    /* Do not hold this mutex while a control thread waits for a callback to
     * leave the native queue. A callback is allowed to reenter AudioQueue APIs;
     * mark the lifecycle first so those calls fail instead of deadlocking on
     * the disposing thread. Keep the users reference until the result has been
     * applied so the lifecycle itself cannot disappear while unlocked. */
    lifecycle->disposing = YES;
    pthread_mutex_unlock(&lifecycle->mutex);

    uint32_t terminal = 0;
    OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueDispose,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inImmediate),
        LC32_AUDIO_U32((uintptr_t)&terminal),
        LC32_AUDIO_U32((uintptr_t)
            &LC32AudioQueueReleaseDeferredAllocations));

    pthread_mutex_lock(&lifecycle->mutex);
    if(terminal != LC32AudioQueueDisposeTerminalNone) {
        if(terminal == LC32AudioQueueDisposeTerminalReleaseMirrors)
            LC32AudioQueueReleaseAllocations(inAQ);
        LC32AudioQueueRemoveLifecycleLocked(lifecycle);
    } else {
        lifecycle->disposing = NO;
    }
    LC32AudioQueueReleaseLifecycle(lifecycle);
    return status;
}

OSStatus AudioQueueEnqueueBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription * inPacketDescs) {
    if(!inAQ || !inBuffer || (inNumPacketDescs && !inPacketDescs))
        return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueEnqueueBuffer,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)inBuffer),
        LC32_AUDIO_U32(inNumPacketDescs),
        LC32_AUDIO_U32((uintptr_t)inPacketDescs));
}

OSStatus AudioQueueFreeBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    if(!inAQ || !inBuffer) return kAudio_ParamError;
    pthread_mutex_lock(&LC32AudioQueueAllocationsMutex);
    LC32GuestAudioQueueAllocation **cursor = &LC32AudioQueueAllocations;
    while(*cursor && (&(*cursor)->buffer != inBuffer ||
            (*cursor)->queue != inAQ)) {
        cursor = &(*cursor)->next;
    }
    LC32GuestAudioQueueAllocation *allocation = *cursor;
    if(!allocation) {
        pthread_mutex_unlock(&LC32AudioQueueAllocationsMutex);
        return kAudioQueueErr_InvalidBuffer;
    }
    OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueFreeBuffer,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)inBuffer));
    if(status == noErr) {
        *cursor = allocation->next;
        pthread_mutex_unlock(&LC32AudioQueueAllocationsMutex);
        free(allocation);
    } else {
        pthread_mutex_unlock(&LC32AudioQueueAllocationsMutex);
    }
    return status;
}

OSStatus AudioQueueGetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, void * outData, UInt32 * ioDataSize) {
    if(!inAQ || !ioDataSize || (*ioDataSize && !outData))
        return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueGetProperty,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inID),
        LC32_AUDIO_U32((uintptr_t)outData),
        LC32_AUDIO_U32((uintptr_t)ioDataSize));
}

OSStatus AudioQueueNewInput(const AudioStreamBasicDescription * inFormat, AudioQueueInputCallback inCallbackProc, void * inUserData, CFRunLoopRef inCallbackRunLoop, CFStringRef inCallbackRunLoopMode, UInt32 inFlags, AudioQueueRef * outAQ) {
    if(outAQ) *outAQ = NULL;
    if(!inFormat || !inCallbackProc || !outAQ) return kAudio_ParamError;
    AudioQueueRef queue = NULL;
    OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueNewInput,
        LC32_AUDIO_U32((uintptr_t)inFormat),
        LC32_AUDIO_U32((uintptr_t)inCallbackProc),
        LC32_AUDIO_U32((uintptr_t)&LC32AudioQueueInvokeInputCallback),
        LC32_AUDIO_U32((uintptr_t)inUserData),
        inCallbackRunLoop ? [(id)inCallbackRunLoop host_self] : 0,
        inCallbackRunLoopMode ? [(id)inCallbackRunLoopMode host_self] : 0,
        LC32_AUDIO_U32(inFlags),
        LC32_AUDIO_U32((uintptr_t)&queue));
    if(status != noErr) return status;
    if(!queue || !LC32AudioQueueCreateLifecycle(queue)) {
        uint32_t terminal = 0;
        (void)LC32_AUDIO_CALL(LC32AudioToolboxOpAudioQueueDispose,
            LC32_AUDIO_U32((uintptr_t)queue), LC32_AUDIO_U32(YES),
            LC32_AUDIO_U32((uintptr_t)&terminal),
            LC32_AUDIO_U32((uintptr_t)
                &LC32AudioQueueReleaseDeferredAllocations));
        return kAudio_MemFullError;
    }
    *outAQ = queue;
    return noErr;
}

OSStatus AudioQueueNewOutput(
        const AudioStreamBasicDescription *inFormat,
        AudioQueueOutputCallback inCallbackProc, void *inUserData,
        CFRunLoopRef inCallbackRunLoop,
        CFStringRef inCallbackRunLoopMode, UInt32 inFlags,
        AudioQueueRef *outAQ) {
    if(outAQ) *outAQ = NULL;
    if(!inFormat || !inCallbackProc || !outAQ) return kAudio_ParamError;
    AudioQueueRef queue = NULL;
    OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueNewOutput,
        LC32_AUDIO_U32((uintptr_t)inFormat),
        LC32_AUDIO_U32((uintptr_t)inCallbackProc),
        LC32_AUDIO_U32((uintptr_t)&LC32AudioQueueInvokeOutputCallback),
        LC32_AUDIO_U32((uintptr_t)inUserData),
        inCallbackRunLoop ? [(id)inCallbackRunLoop host_self] : 0,
        inCallbackRunLoopMode ? [(id)inCallbackRunLoopMode host_self] : 0,
        LC32_AUDIO_U32(inFlags),
        LC32_AUDIO_U32((uintptr_t)&queue));
    if(status != noErr) return status;
    if(!queue || !LC32AudioQueueCreateLifecycle(queue)) {
        uint32_t terminal = 0;
        (void)LC32_AUDIO_CALL(LC32AudioToolboxOpAudioQueueDispose,
            LC32_AUDIO_U32((uintptr_t)queue), LC32_AUDIO_U32(YES),
            LC32_AUDIO_U32((uintptr_t)&terminal),
            LC32_AUDIO_U32((uintptr_t)
                &LC32AudioQueueReleaseDeferredAllocations));
        return kAudio_MemFullError;
    }
    *outAQ = queue;
    return noErr;
}

OSStatus AudioQueuePause(AudioQueueRef inAQ) {
    if(!inAQ) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueuePause,
        LC32_AUDIO_U32((uintptr_t)inAQ));
}

OSStatus AudioQueueSetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, const void * inData, UInt32 inDataSize) {
    if(!inAQ || (inDataSize && !inData)) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueSetProperty,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inID),
        LC32_AUDIO_U32((uintptr_t)inData), LC32_AUDIO_U32(inDataSize));
}

OSStatus AudioQueueStart(AudioQueueRef inAQ, const AudioTimeStamp * inStartTime) {
    if(!inAQ) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueStart,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)inStartTime));
}

OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate) {
    if(!inAQ) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueStop,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inImmediate));
}

OSStatus AudioQueueDeviceGetCurrentTime(
        AudioQueueRef inAQ, AudioTimeStamp *outTimeStamp) {
    if(outTimeStamp) memset(outTimeStamp, 0, sizeof(*outTimeStamp));
    if(!inAQ || !outTimeStamp) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueDeviceGetCurrentTime,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)outTimeStamp));
}

OSStatus AudioQueueCreateTimeline(AudioQueueRef inAQ,
                                  AudioQueueTimelineRef *outTimeline) {
    if(outTimeline) *outTimeline = NULL;
    if(!inAQ || !outTimeline) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueCreateTimeline,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)outTimeline));
}

OSStatus AudioQueueDisposeTimeline(AudioQueueRef inAQ,
                                   AudioQueueTimelineRef inTimeline) {
    if(!inAQ || !inTimeline) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueDisposeTimeline,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)inTimeline));
}

OSStatus AudioQueueGetCurrentTime(
        AudioQueueRef inAQ, AudioQueueTimelineRef inTimeline,
        AudioTimeStamp *outTimeStamp,
        Boolean *outTimelineDiscontinuity) {
    if(outTimeStamp) memset(outTimeStamp, 0, sizeof(*outTimeStamp));
    if(outTimelineDiscontinuity) *outTimelineDiscontinuity = false;
    if(!inAQ || (!outTimeStamp && !outTimelineDiscontinuity))
        return kAudio_ParamError;
    if(!inTimeline && outTimelineDiscontinuity)
        return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueGetCurrentTime,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32((uintptr_t)inTimeline),
        LC32_AUDIO_U32((uintptr_t)outTimeStamp),
        LC32_AUDIO_U32((uintptr_t)outTimelineDiscontinuity));
}

OSStatus AudioQueueEnqueueBufferWithParameters(
        AudioQueueRef inAQ, AudioQueueBufferRef inBuffer,
        UInt32 inNumPacketDescs,
        const AudioStreamPacketDescription *inPacketDescs,
        UInt32 inTrimFramesAtStart, UInt32 inTrimFramesAtEnd,
        UInt32 inNumParamValues,
        const AudioQueueParameterEvent *inParamValues,
        const AudioTimeStamp *inStartTime,
        AudioTimeStamp *outActualStartTime) {
    if(outActualStartTime)
        memset(outActualStartTime, 0, sizeof(*outActualStartTime));
    if(inTrimFramesAtStart || inTrimFramesAtEnd || inNumParamValues ||
       inParamValues || inStartTime) {
        return kAudio_UnimplementedError;
    }
    return AudioQueueEnqueueBuffer(inAQ, inBuffer, inNumPacketDescs,
        inPacketDescs);
}

OSStatus AudioQueuePrime(AudioQueueRef inAQ,
                         UInt32 inNumberOfFramesToPrepare,
                         UInt32 *outNumberOfFramesPrepared) {
    if(outNumberOfFramesPrepared) *outNumberOfFramesPrepared = 0;
    if(!inAQ) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueuePrime,
        LC32_AUDIO_U32((uintptr_t)inAQ),
        LC32_AUDIO_U32(inNumberOfFramesToPrepare),
        LC32_AUDIO_U32((uintptr_t)outNumberOfFramesPrepared));
}

OSStatus AudioQueueRemovePropertyListener(
        AudioQueueRef inAQ, AudioQueuePropertyID inID,
        AudioQueuePropertyListenerProc inProc, void *inUserData) {
    if(!inAQ || !inProc) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueRemovePropertyListener,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inID),
        LC32_AUDIO_U32((uintptr_t)inProc),
        LC32_AUDIO_U32((uintptr_t)inUserData));
}

OSStatus AudioQueueSetParameter(AudioQueueRef inAQ,
                                AudioQueueParameterID inParamID,
                                AudioQueueParameterValue inValue) {
    if(!inAQ) return kAudio_ParamError;
    union {
        AudioQueueParameterValue value;
        uint32_t bits;
    } representation = { .value = inValue };
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioQueueSetParameter,
        LC32_AUDIO_U32((uintptr_t)inAQ), LC32_AUDIO_U32(inParamID),
        LC32_AUDIO_U32(representation.bits));
}

OSStatus AudioSessionInitialize(CFRunLoopRef inRunLoop, CFStringRef inRunLoopMode, AudioSessionInterruptionListener inInterruptionListener, void * inClientData) {
    /*
     * The host half initializes the process-wide legacy AudioSession lazily
     * before the first operation. Interruption callback forwarding remains a
     * separate bridge concern, so retain the compatibility no-op here.
     */
    (void)inRunLoop;
    (void)inRunLoopMode;
    (void)inInterruptionListener;
    (void)inClientData;
    return noErr;
}
OSStatus AudioSessionSetActive(Boolean active) {
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioSessionSetActive,
        LC32_AUDIO_U32(active != false));
}

OSStatus AudioSessionSetProperty(AudioSessionPropertyID inID, UInt32 inDataSize, const void * inData) {
    if(inDataSize && !inData) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioSessionSetProperty,
        LC32_AUDIO_U32(inID), LC32_AUDIO_U32(inDataSize),
        LC32_AUDIO_U32((uintptr_t)inData));
}

OSStatus AudioSessionAddPropertyListener(
        AudioSessionPropertyID inID,
        AudioSessionPropertyListener inProc,
        void *inClientData) {
    /*
     * Modern AVAudioSession notifications cover the properties used by old
     * applications.  Keep registration source-compatible for now; forwarding
     * the callback itself requires a host-to-guest trampoline and is added
     * independently of the legacy API's basic availability.
     */
    (void)inID;
    (void)inProc;
    (void)inClientData;
    return noErr;
}

OSStatus AudioSessionRemovePropertyListener(AudioSessionPropertyID inID) {
    (void)inID;
    return noErr;
}

OSStatus AudioSessionRemovePropertyListenerWithUserData(
        AudioSessionPropertyID inID,
        AudioSessionPropertyListener inProc,
        void *inClientData) {
    (void)inID;
    (void)inProc;
    (void)inClientData;
    return noErr;
}

OSStatus AudioSessionGetProperty(AudioSessionPropertyID property,
                                 UInt32 *ioDataSize,
                                 void *outData) {
    if(!ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioSessionGetProperty,
        LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

#pragma mark Audio File Services

OSStatus AudioFileCreateWithURL(
        CFURLRef fileURL,
        AudioFileTypeID fileType,
        const AudioStreamBasicDescription *format,
        AudioFileFlags flags,
        AudioFileID *outAudioFile) {
    if(!fileURL || !format || !outAudioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileCreateWithURL,
        [(id)fileURL host_self], LC32_AUDIO_U32(fileType),
        LC32_AUDIO_U32((uintptr_t)format), LC32_AUDIO_U32(flags),
        LC32_AUDIO_U32((uintptr_t)outAudioFile));
}

OSStatus AudioFileOpenURL(CFURLRef fileURL,
                          AudioFilePermissions permissions,
                          AudioFileTypeID fileTypeHint,
                          AudioFileID *outAudioFile) {
    if(!fileURL || !outAudioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileOpenURL,
        [(id)fileURL host_self], LC32_AUDIO_U32(permissions),
        LC32_AUDIO_U32(fileTypeHint),
        LC32_AUDIO_U32((uintptr_t)outAudioFile));
}

OSStatus AudioFileOpenWithCallbacks(
        void *clientData, AudioFile_ReadProc readFunction,
        AudioFile_WriteProc writeFunction,
        AudioFile_GetSizeProc getSizeFunction,
        AudioFile_SetSizeProc setSizeFunction,
        AudioFileTypeID fileTypeHint, AudioFileID *outAudioFile) {
    if(outAudioFile) *outAudioFile = NULL;
    if(!readFunction || !getSizeFunction || !outAudioFile)
        return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileOpenWithCallbacks,
        LC32_AUDIO_U32((uintptr_t)clientData),
        LC32_AUDIO_U32((uintptr_t)readFunction),
        LC32_AUDIO_U32((uintptr_t)writeFunction),
        LC32_AUDIO_U32((uintptr_t)getSizeFunction),
        LC32_AUDIO_U32((uintptr_t)setSizeFunction),
        LC32_AUDIO_U32(fileTypeHint),
        LC32_AUDIO_U32((uintptr_t)outAudioFile));
}

OSStatus AudioFileGetProperty(AudioFileID audioFile,
                              AudioFilePropertyID property,
                              UInt32 *ioDataSize,
                              void *outData) {
    if(!audioFile || !ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileGetProperty,
        LC32_AUDIO_U32((uintptr_t)audioFile),
        LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

OSStatus AudioFileGetPropertyInfo(AudioFileID audioFile,
                                  AudioFilePropertyID property,
                                  UInt32 *outDataSize,
                                  UInt32 *isWritable) {
    if(!audioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileGetPropertyInfo,
        LC32_AUDIO_U32((uintptr_t)audioFile),
        LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)outDataSize),
        LC32_AUDIO_U32((uintptr_t)isWritable));
}

OSStatus AudioFileReadBytes(AudioFileID audioFile,
                            Boolean useCache,
                            SInt64 startingByte,
                            UInt32 *ioNumBytes,
                            void *outBuffer) {
    if(!audioFile || !ioNumBytes) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileReadBytes,
        LC32_AUDIO_U32((uintptr_t)audioFile), LC32_AUDIO_U32(useCache),
        (uint64_t)startingByte,
        LC32_AUDIO_U32((uintptr_t)ioNumBytes),
        LC32_AUDIO_U32((uintptr_t)outBuffer));
}

OSStatus AudioFileReadPackets(
        AudioFileID audioFile,
        Boolean useCache,
        UInt32 *outNumBytes,
        AudioStreamPacketDescription *outPacketDescriptions,
        SInt64 startingPacket,
        UInt32 *ioNumPackets,
        void *outBuffer) {
    if(!audioFile || !outNumBytes || !ioNumPackets)
        return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileReadPackets,
        LC32_AUDIO_U32((uintptr_t)audioFile), LC32_AUDIO_U32(useCache),
        LC32_AUDIO_U32((uintptr_t)outNumBytes),
        LC32_AUDIO_U32((uintptr_t)outPacketDescriptions),
        (uint64_t)startingPacket,
        LC32_AUDIO_U32((uintptr_t)ioNumPackets),
        LC32_AUDIO_U32((uintptr_t)outBuffer));
}

OSStatus AudioFileReadPacketData(
        AudioFileID audioFile, Boolean useCache,
        UInt32 *ioNumBytes,
        AudioStreamPacketDescription *outPacketDescriptions,
        SInt64 startingPacket, UInt32 *ioNumPackets,
        void *outBuffer) {
    if(!audioFile || !ioNumBytes || !ioNumPackets)
        return kAudio_ParamError;
    if(*ioNumBytes && !outBuffer) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileReadPacketData,
        LC32_AUDIO_U32((uintptr_t)audioFile), LC32_AUDIO_U32(useCache),
        LC32_AUDIO_U32((uintptr_t)ioNumBytes),
        LC32_AUDIO_U32((uintptr_t)outPacketDescriptions),
        (uint64_t)startingPacket,
        LC32_AUDIO_U32((uintptr_t)ioNumPackets),
        LC32_AUDIO_U32((uintptr_t)outBuffer));
}

OSStatus AudioFileWriteBytes(AudioFileID audioFile,
                             Boolean useCache,
                             SInt64 startingByte,
                             UInt32 *ioNumBytes,
                             const void *inBuffer) {
    if(!audioFile || !ioNumBytes) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileWriteBytes,
        LC32_AUDIO_U32((uintptr_t)audioFile), LC32_AUDIO_U32(useCache),
        (uint64_t)startingByte,
        LC32_AUDIO_U32((uintptr_t)ioNumBytes),
        LC32_AUDIO_U32((uintptr_t)inBuffer));
}

OSStatus AudioFileClose(AudioFileID audioFile) {
    if(!audioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileClose,
        LC32_AUDIO_U32((uintptr_t)audioFile));
}

#pragma mark Extended Audio File Services

OSStatus ExtAudioFileOpenURL(CFURLRef url, ExtAudioFileRef *outFile) {
    if(!url || !outFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileOpenURL,
        [(id)url host_self], LC32_AUDIO_U32((uintptr_t)outFile));
}

OSStatus ExtAudioFileDispose(ExtAudioFileRef file) {
    if(!file) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileDispose,
        LC32_AUDIO_U32((uintptr_t)file));
}

OSStatus ExtAudioFileGetProperty(ExtAudioFileRef file,
                                 ExtAudioFilePropertyID property,
                                 UInt32 *ioDataSize,
                                 void *outData) {
    if(!file || !ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileGetProperty,
        LC32_AUDIO_U32((uintptr_t)file), LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

OSStatus ExtAudioFileSetProperty(ExtAudioFileRef file,
                                 ExtAudioFilePropertyID property,
                                 UInt32 dataSize,
                                 const void *data) {
    if(!file || (dataSize && !data)) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileSetProperty,
        LC32_AUDIO_U32((uintptr_t)file), LC32_AUDIO_U32(property),
        LC32_AUDIO_U32(dataSize), LC32_AUDIO_U32((uintptr_t)data));
}

OSStatus ExtAudioFileRead(ExtAudioFileRef file,
                          UInt32 *ioNumberFrames,
                          AudioBufferList *ioData) {
    if(!file || !ioNumberFrames || !ioData) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileRead,
        LC32_AUDIO_U32((uintptr_t)file),
        LC32_AUDIO_U32((uintptr_t)ioNumberFrames),
        LC32_AUDIO_U32((uintptr_t)ioData));
}

OSStatus ExtAudioFileSeek(ExtAudioFileRef file, SInt64 frameOffset) {
    if(!file) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileSeek,
        LC32_AUDIO_U32((uintptr_t)file),
        (uint64_t)frameOffset);
}
