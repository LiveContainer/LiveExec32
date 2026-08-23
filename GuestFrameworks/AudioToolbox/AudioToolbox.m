#import <AudioToolbox/AudioToolbox.h>
#import <LC32/LC32.h>

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#import "LC32AudioToolboxBridge.h"

#ifndef LC32_TRACE_AUDIO_OUTPUT
#define LC32_TRACE_AUDIO_OUTPUT 0
#endif

#if LC32_TRACE_AUDIO_OUTPUT
#include <stdio.h>
#endif

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

/*
 * The old FMOD output bundled by several 32-bit games configures a RemoteIO
 * AudioUnit directly. A host AudioUnit cannot be exposed as a raw pointer to
 * the guest, and its realtime callback cannot consume guest AudioBufferList
 * pointers. Keep a small guest-owned unit which invokes the guest callback.
 * A private host AudioQueue sink consumes the rendered PCM without ever
 * calling emulated code from its realtime thread; if the host route is not
 * available, the same pump falls back to its original silent timing mode.
 * Besides producing audio, the callback is how old FMOD wakes its mixer thread
 * after consuming its ring buffer.
 */
typedef struct {
    uint32_t magic;
    AudioStreamBasicDescription format;
    AURenderCallbackStruct renderCallback;
    pthread_mutex_t mutex;
    pthread_t renderThread;
    uint32_t stopRequested;
    uint32_t started;
    uint32_t hostOutputToken;
    uint32_t hostOutputHealthy;
    uint32_t renderFrames;
    BOOL initialized;
    BOOL renderThreadJoinable;
    BOOL joiningRenderThread;
} LC32SilentAudioUnit;

typedef struct {
    LC32SilentAudioUnit *unit;
    AudioStreamBasicDescription format;
    AURenderCallbackStruct callback;
    AudioBufferList *bufferList;
    uint8_t *audioData;
    size_t audioBufferStride;
    UInt32 numberBuffers;
    UInt32 numberFrames;
    struct timespec interval;
} LC32SilentAudioPump;

enum {
    LC32SilentAudioUnitMagic = 0x4c415531, /* "LAU1" */
    LC32SilentAudioDefaultFrames = 512,
    LC32SilentAudioMaximumFrames = 4096,
    LC32SilentAudioMaximumChannels = 32,
    LC32SilentAudioMaximumBufferBytes = 16u * 1024u * 1024u,
};

static uint8_t LC32SilentRemoteIOComponent;
static uint32_t LC32PreferredIOBufferDurationBits;

_Static_assert(sizeof(AudioStreamBasicDescription) == 40,
    "ARM32 AudioStreamBasicDescription layout changed");
_Static_assert(sizeof(AURenderCallbackStruct) == 8,
    "ARM32 AURenderCallbackStruct layout changed");
_Static_assert(sizeof(AudioBuffer) == 12,
    "ARM32 AudioBuffer layout changed");
_Static_assert(offsetof(AudioBufferList, mBuffers) == 4 &&
               sizeof(AudioBufferList) == 16,
    "ARM32 AudioBufferList layout changed");

static LC32SilentAudioUnit *LC32SilentAudioUnitForHandle(AudioUnit unit) {
    LC32SilentAudioUnit *silent = (LC32SilentAudioUnit *)(uintptr_t)unit;
    return silent && silent->magic == LC32SilentAudioUnitMagic
        ? silent : NULL;
}

static BOOL LC32SilentAudioFormatIsValid(
        const AudioStreamBasicDescription *format) {
    if(!format || format->mFormatID != kAudioFormatLinearPCM ||
       !(format->mSampleRate >= 1.0 && format->mSampleRate <= 384000.0) ||
       !format->mBytesPerFrame ||
       format->mBytesPerFrame > LC32SilentAudioMaximumBufferBytes ||
       !format->mChannelsPerFrame ||
       format->mChannelsPerFrame > LC32SilentAudioMaximumChannels) {
        return NO;
    }
    return YES;
}

static UInt32 LC32SilentAudioRenderFrames(
        const AudioStreamBasicDescription *format) {
    UInt32 durationBits = __atomic_load_n(
        &LC32PreferredIOBufferDurationBits, __ATOMIC_ACQUIRE);
    Float32 duration = 0;
    memcpy(&duration, &durationBits, sizeof(duration));
    const double requestedFrames = format->mSampleRate * (double)duration;
    if(requestedFrames >= 1.0 &&
       requestedFrames <= LC32SilentAudioMaximumFrames) {
        UInt32 frames = (UInt32)(requestedFrames + 0.5);
        return frames ? frames : 1;
    }
    return LC32SilentAudioDefaultFrames;
}

static void LC32SilentAudioResetBufferList(LC32SilentAudioPump *pump) {
    const BOOL nonInterleaved =
        (pump->format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    const UInt32 channels = pump->format.mChannelsPerFrame;
    const UInt32 bytes = pump->numberFrames * pump->format.mBytesPerFrame;
    pump->bufferList->mNumberBuffers = pump->numberBuffers;
    for(UInt32 index = 0; index < pump->numberBuffers; ++index) {
        AudioBuffer *buffer = &pump->bufferList->mBuffers[index];
        buffer->mNumberChannels = nonInterleaved ? 1 : channels;
        buffer->mDataByteSize = bytes;
        buffer->mData = pump->audioData + pump->audioBufferStride * index;
        memset(buffer->mData, 0, bytes);
    }
}

static void LC32SilentAudioDestroyPump(LC32SilentAudioPump *pump) {
    if(!pump) return;
    free(pump->audioData);
    free(pump->bufferList);
    free(pump);
}

static LC32SilentAudioPump *LC32SilentAudioCreatePump(
        LC32SilentAudioUnit *unit) {
    if(!unit || !unit->renderCallback.inputProc ||
       !LC32SilentAudioFormatIsValid(&unit->format)) {
        return NULL;
    }

    LC32SilentAudioPump *pump = calloc(1, sizeof(*pump));
    if(!pump) return NULL;
    pump->unit = unit;
    pump->format = unit->format;
    pump->callback = unit->renderCallback;
    pump->numberFrames = LC32SilentAudioRenderFrames(&pump->format);
    pump->numberBuffers =
        (pump->format.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
        ? pump->format.mChannelsPerFrame : 1;

    if(pump->format.mBytesPerFrame >
       LC32SilentAudioMaximumBufferBytes / pump->numberFrames) {
        LC32SilentAudioDestroyPump(pump);
        return NULL;
    }
    const size_t bytes = (size_t)pump->numberFrames *
        pump->format.mBytesPerFrame;
    if(bytes > SIZE_MAX - 15u) {
        LC32SilentAudioDestroyPump(pump);
        return NULL;
    }
    pump->audioBufferStride = (bytes + 15u) & ~(size_t)15u;
    if(pump->numberBuffers >
       LC32SilentAudioMaximumBufferBytes / pump->audioBufferStride) {
        LC32SilentAudioDestroyPump(pump);
        return NULL;
    }

    const size_t listBytes = offsetof(AudioBufferList, mBuffers) +
        (size_t)pump->numberBuffers * sizeof(AudioBuffer);
    pump->bufferList = calloc(1, listBytes);
    pump->audioData = calloc(pump->numberBuffers,
        pump->audioBufferStride);
    if(!pump->bufferList || !pump->audioData) {
        LC32SilentAudioDestroyPump(pump);
        return NULL;
    }

    const double seconds =
        (double)pump->numberFrames / pump->format.mSampleRate;
    pump->interval.tv_sec = (time_t)seconds;
    pump->interval.tv_nsec = (long)((seconds - pump->interval.tv_sec) *
        1000000000.0);
    if(pump->interval.tv_sec == 0 && pump->interval.tv_nsec < 1000000L)
        pump->interval.tv_nsec = 1000000L;
    LC32SilentAudioResetBufferList(pump);
    return pump;
}

static void *LC32SilentAudioPumpMain(void *context) {
    LC32SilentAudioPump *pump = context;
    Float64 sampleTime = 0;
    while(!__atomic_load_n(&pump->unit->stopRequested,
                           __ATOMIC_ACQUIRE)) {
        if(!__atomic_load_n(&pump->unit->started, __ATOMIC_ACQUIRE)) {
            const struct timespec idleInterval = {
                .tv_sec = 0,
                .tv_nsec = 1000000L,
            };
            (void)nanosleep(&idleInterval, NULL);
            continue;
        }
        LC32SilentAudioResetBufferList(pump);
        AudioUnitRenderActionFlags actionFlags = 0;
        AudioTimeStamp timeStamp = {0};
        timeStamp.mSampleTime = sampleTime;
        timeStamp.mFlags = kAudioTimeStampSampleTimeValid;
        const OSStatus renderStatus = pump->callback.inputProc(
            pump->callback.inputProcRefCon,
            &actionFlags, &timeStamp, 0, pump->numberFrames,
            pump->bufferList);
        sampleTime += pump->numberFrames;

        BOOL hostPaced = NO;
        const uint32_t hostOutputToken = __atomic_load_n(
            &pump->unit->hostOutputToken, __ATOMIC_ACQUIRE);
        if(hostOutputToken && __atomic_load_n(
                &pump->unit->hostOutputHealthy, __ATOMIC_ACQUIRE)) {
            const BOOL silence = renderStatus != noErr ||
                (actionFlags & kAudioUnitRenderAction_OutputIsSilence) != 0;
            const OSStatus submitStatus = (OSStatus)LC32_AUDIO_CALL(
                LC32AudioToolboxOpRemoteIOOutputSubmit,
                LC32_AUDIO_U32(hostOutputToken),
                LC32_AUDIO_U32((uintptr_t)pump->bufferList),
                LC32_AUDIO_U32(pump->numberFrames),
                LC32_AUDIO_U32(silence));
            if(submitStatus == noErr) {
                /* Waiting for a returned native AudioQueue buffer supplies
                 * the pacing for the next render quantum. */
                hostPaced = YES;
            } else {
                __atomic_store_n(&pump->unit->hostOutputHealthy, 0,
                    __ATOMIC_RELEASE);
#if LC32_TRACE_AUDIO_OUTPUT
                fprintf(stderr,
                    "LC32: RemoteIO output submit failed: status=%d\n",
                    (int)submitStatus);
#endif
            }
        }
        if(hostPaced) continue;

        struct timespec remaining = pump->interval;
        while(!__atomic_load_n(&pump->unit->stopRequested,
                               __ATOMIC_ACQUIRE) &&
              nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {}
    }
    LC32SilentAudioDestroyPump(pump);
    return NULL;
}

/* Allocate and create the first pump while initializing the AudioUnit. Tiny's
 * FMOD backend allocates its ring and starts its mixer only after Initialize
 * succeeds, so a resource failure here follows FMOD's safe early-unwind path.
 * The new thread remains idle until AudioOutputUnitStart publishes started. */
static OSStatus LC32SilentAudioPrepareThreadLocked(
        LC32SilentAudioUnit *unit) {
    LC32SilentAudioPump *pump = LC32SilentAudioCreatePump(unit);
    if(!pump) return kAudio_MemFullError;
    __atomic_store_n(&unit->stopRequested, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&unit->started, 0, __ATOMIC_RELEASE);
    const int result = pthread_create(&unit->renderThread, NULL,
        LC32SilentAudioPumpMain, pump);
    if(result != 0) {
        __atomic_store_n(&unit->stopRequested, 1, __ATOMIC_RELEASE);
        LC32SilentAudioDestroyPump(pump);
        return kAudio_MemFullError;
    }
    unit->renderThreadJoinable = YES;
    unit->renderFrames = pump->numberFrames;
    return noErr;
}

/* Called and returned with unit->mutex held. Drop the mutex around join so a
 * callback already in flight may safely query/reenter the unit while Stop is
 * waiting for it. A competing lifecycle operation fails while this join owns
 * the thread; successful Stop/Uninitialize/Dispose calls still guarantee that
 * no callback can be executing after they return. */
static OSStatus LC32SilentAudioStopLocked(LC32SilentAudioUnit *unit) {
    if(unit->joiningRenderThread ||
       (unit->renderThreadJoinable &&
        pthread_equal(pthread_self(), unit->renderThread))) {
        return kAudioUnitErr_CannotDoInCurrentContext;
    }
    __atomic_store_n(&unit->started, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&unit->stopRequested, 1, __ATOMIC_RELEASE);
    __atomic_store_n(&unit->hostOutputHealthy, 0, __ATOMIC_RELEASE);

    /* Retire the host token first. This marks the sink disposing and wakes a
     * render thread which may be blocked waiting for a returned native
     * AudioQueue buffer. The host keeps the in-flight submission alive until
     * it unwinds, so it is safe to join only after this cancellation. */
    const uint32_t hostOutputToken = __atomic_load_n(
        &unit->hostOutputToken, __ATOMIC_ACQUIRE);
    __atomic_store_n(&unit->hostOutputToken, 0, __ATOMIC_RELEASE);
    if(hostOutputToken) {
        const OSStatus outputStatus = (OSStatus)LC32_AUDIO_CALL(
            LC32AudioToolboxOpRemoteIOOutputStop,
            LC32_AUDIO_U32(hostOutputToken));
#if LC32_TRACE_AUDIO_OUTPUT
        if(outputStatus != noErr) {
            fprintf(stderr,
                "LC32: RemoteIO output stop failed: status=%d\n",
                (int)outputStatus);
        }
#else
        (void)outputStatus;
#endif
    }

    if(unit->renderThreadJoinable) {
        unit->joiningRenderThread = YES;
        const pthread_t renderThread = unit->renderThread;
        pthread_mutex_unlock(&unit->mutex);
        const int result = pthread_join(renderThread, NULL);
        pthread_mutex_lock(&unit->mutex);
        unit->joiningRenderThread = NO;
        if(result != 0) return kAudioUnitErr_CannotDoInCurrentContext;
        unit->renderThreadJoinable = NO;
    }
    return noErr;
}

AudioComponent AudioComponentFindNext(
        AudioComponent inComponent,
        const AudioComponentDescription *inDesc) {
    if(inComponent || !inDesc) return NULL;
    const BOOL typeMatches = !inDesc->componentType ||
        inDesc->componentType == kAudioUnitType_Output;
    const BOOL subtypeMatches = !inDesc->componentSubType ||
        inDesc->componentSubType == kAudioUnitSubType_RemoteIO;
    const BOOL manufacturerMatches = !inDesc->componentManufacturer ||
        inDesc->componentManufacturer == kAudioUnitManufacturer_Apple;
    const BOOL flagsMatch =
        (inDesc->componentFlags & inDesc->componentFlagsMask) == 0;
    return typeMatches && subtypeMatches && manufacturerMatches && flagsMatch
        ? (AudioComponent)&LC32SilentRemoteIOComponent : NULL;
}

OSStatus AudioComponentInstanceNew(AudioComponent inComponent,
                                   AudioComponentInstance *outInstance) {
    if(outInstance) *outInstance = NULL;
    if(inComponent != (AudioComponent)&LC32SilentRemoteIOComponent ||
            !outInstance) {
        return kAudio_ParamError;
    }
    LC32SilentAudioUnit *silent = calloc(1, sizeof(*silent));
    if(!silent) return kAudio_MemFullError;
    if(pthread_mutex_init(&silent->mutex, NULL) != 0) {
        free(silent);
        return kAudio_MemFullError;
    }
    silent->magic = LC32SilentAudioUnitMagic;
    *outInstance = (AudioComponentInstance)silent;
    return noErr;
}

OSStatus AudioComponentInstanceDispose(AudioComponentInstance inInstance) {
    LC32SilentAudioUnit *silent =
        LC32SilentAudioUnitForHandle((AudioUnit)inInstance);
    if(!silent) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    const OSStatus status = LC32SilentAudioStopLocked(silent);
    if(status != noErr) {
        pthread_mutex_unlock(&silent->mutex);
        return status;
    }
    silent->magic = 0;
    pthread_mutex_unlock(&silent->mutex);
    pthread_mutex_destroy(&silent->mutex);
    free(silent);
    return noErr;
}

OSStatus AudioUnitSetProperty(AudioUnit inUnit, AudioUnitPropertyID inID,
                              AudioUnitScope inScope,
                              AudioUnitElement inElement,
                              const void *inData, UInt32 inDataSize) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(inUnit);
    if(!silent || (inDataSize && !inData)) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    if(silent->initialized || silent->renderThreadJoinable) {
        pthread_mutex_unlock(&silent->mutex);
        return kAudioUnitErr_Initialized;
    }
    if(inID == kAudioUnitProperty_StreamFormat &&
            inScope == kAudioUnitScope_Input && inElement == 0 &&
            inDataSize == sizeof(silent->format)) {
        memcpy(&silent->format, inData, sizeof(silent->format));
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    if(inID == kAudioUnitProperty_SetRenderCallback &&
            inScope == kAudioUnitScope_Global && inElement == 0 &&
            inDataSize == sizeof(silent->renderCallback)) {
        memcpy(&silent->renderCallback, inData,
            sizeof(silent->renderCallback));
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    pthread_mutex_unlock(&silent->mutex);
    return kAudioUnitErr_InvalidProperty;
}

OSStatus AudioUnitGetProperty(AudioUnit inUnit, AudioUnitPropertyID inID,
                              AudioUnitScope inScope,
                              AudioUnitElement inElement,
                              void *outData, UInt32 *ioDataSize) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(inUnit);
    if(!silent || !ioDataSize || (*ioDataSize && !outData))
        return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    if(inID == kAudioUnitProperty_MaximumFramesPerSlice &&
            inScope == kAudioUnitScope_Global && inElement == 0) {
        const UInt32 required = sizeof(UInt32);
        if(*ioDataSize < required) {
            *ioDataSize = required;
            pthread_mutex_unlock(&silent->mutex);
            return kAudio_ParamError;
        }
        *(UInt32 *)outData = LC32SilentAudioMaximumFrames;
        *ioDataSize = required;
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    if(inID == kAudioUnitProperty_StreamFormat &&
            *ioDataSize >= sizeof(silent->format)) {
        memcpy(outData, &silent->format, sizeof(silent->format));
        *ioDataSize = sizeof(silent->format);
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    pthread_mutex_unlock(&silent->mutex);
    return kAudioUnitErr_InvalidProperty;
}

OSStatus AudioUnitInitialize(AudioUnit inUnit) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(inUnit);
    if(!silent) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    if(silent->initialized) {
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    if(!silent->renderCallback.inputProc ||
       !LC32SilentAudioFormatIsValid(&silent->format)) {
        pthread_mutex_unlock(&silent->mutex);
        return kAudioUnitErr_InvalidPropertyValue;
    }
    const OSStatus status = LC32SilentAudioPrepareThreadLocked(silent);
    if(status != noErr) {
        pthread_mutex_unlock(&silent->mutex);
        return status;
    }
    silent->initialized = YES;
    pthread_mutex_unlock(&silent->mutex);
    return noErr;
}

OSStatus AudioUnitUninitialize(AudioUnit inUnit) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(inUnit);
    if(!silent) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    const OSStatus status = LC32SilentAudioStopLocked(silent);
    if(status != noErr) {
        pthread_mutex_unlock(&silent->mutex);
        return status;
    }
    silent->initialized = NO;
    pthread_mutex_unlock(&silent->mutex);
    return noErr;
}

OSStatus AudioOutputUnitStart(AudioUnit ci) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(ci);
    if(!silent) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    if(!silent->initialized) {
        pthread_mutex_unlock(&silent->mutex);
        return kAudioUnitErr_Uninitialized;
    }
    if(__atomic_load_n(&silent->started, __ATOMIC_ACQUIRE)) {
        pthread_mutex_unlock(&silent->mutex);
        return noErr;
    }
    if(silent->joiningRenderThread) {
        pthread_mutex_unlock(&silent->mutex);
        return kAudioUnitErr_CannotDoInCurrentContext;
    }
    if(!silent->renderThreadJoinable) {
        const OSStatus status = LC32SilentAudioPrepareThreadLocked(silent);
        if(status != noErr) {
            pthread_mutex_unlock(&silent->mutex);
            return status;
        }
    }

    uint32_t hostOutputToken = 0;
    const OSStatus outputStatus = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpRemoteIOOutputStart,
        LC32_AUDIO_U32((uintptr_t)&silent->format),
        LC32_AUDIO_U32(silent->renderFrames),
        LC32_AUDIO_U32((uintptr_t)&hostOutputToken));
    if(outputStatus == noErr && hostOutputToken) {
        __atomic_store_n(&silent->hostOutputToken, hostOutputToken,
            __ATOMIC_RELEASE);
        __atomic_store_n(&silent->hostOutputHealthy, 1,
            __ATOMIC_RELEASE);
#if LC32_TRACE_AUDIO_OUTPUT
        fprintf(stderr,
            "LC32: RemoteIO host output started: token=0x%x frames=%u\n",
            hostOutputToken, silent->renderFrames);
#endif
    } else {
        /* Native Simulator audio can be unavailable (for example status
         * -66628 with no route). Preserve the compatibility pump so FMOD's
         * mixer and game-side timing continue even when output is silent. */
        if(hostOutputToken) {
            (void)LC32_AUDIO_CALL(LC32AudioToolboxOpRemoteIOOutputStop,
                LC32_AUDIO_U32(hostOutputToken));
        }
        __atomic_store_n(&silent->hostOutputToken, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&silent->hostOutputHealthy, 0,
            __ATOMIC_RELEASE);
#if LC32_TRACE_AUDIO_OUTPUT
        fprintf(stderr,
            "LC32: RemoteIO host output unavailable; using silent pacing "
            "(status=%d token=0x%x)\n", (int)outputStatus,
            hostOutputToken);
#endif
    }
    __atomic_store_n(&silent->started, 1, __ATOMIC_RELEASE);
    pthread_mutex_unlock(&silent->mutex);
    return noErr;
}

OSStatus AudioOutputUnitStop(AudioUnit ci) {
    LC32SilentAudioUnit *silent = LC32SilentAudioUnitForHandle(ci);
    if(!silent) return kAudio_ParamError;
    pthread_mutex_lock(&silent->mutex);
    const OSStatus status = LC32SilentAudioStopLocked(silent);
    pthread_mutex_unlock(&silent->mutex);
    return status;
}

OSStatus AudioUnitRender(AudioUnit inUnit,
                         AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp,
                         UInt32 inOutputBusNumber,
                         UInt32 inNumberFrames,
                         AudioBufferList *ioData) {
    (void)ioActionFlags;
    (void)inTimeStamp;
    (void)inOutputBusNumber;
    (void)inNumberFrames;
    if(!LC32SilentAudioUnitForHandle(inUnit) || !ioData ||
            ioData->mNumberBuffers > 64) {
        return kAudio_ParamError;
    }
    for(UInt32 index = 0; index < ioData->mNumberBuffers; ++index) {
        AudioBuffer *buffer = &ioData->mBuffers[index];
        if(buffer->mData && buffer->mDataByteSize)
            memset(buffer->mData, 0, buffer->mDataByteSize);
    }
    return noErr;
}

OSStatus AudioQueueFlush(AudioQueueRef inAQ) {
    return inAQ ? noErr : kAudio_ParamError;
}

OSStatus AudioQueueSetOfflineRenderFormat(
        AudioQueueRef inAQ,
        const AudioStreamBasicDescription *inFormat,
        const AudioChannelLayout *inLayout) {
    (void)inAQ;
    (void)inFormat;
    (void)inLayout;
    return kAudio_ParamError;
}

OSStatus AudioQueueOfflineRender(AudioQueueRef inAQ,
                                 const AudioTimeStamp *inTimestamp,
                                 AudioQueueBufferRef ioBuffer,
                                 UInt32 inNumberFrames) {
    (void)inTimestamp;
    (void)inNumberFrames;
    if(!inAQ || !ioBuffer) return kAudio_ParamError;
    ioBuffer->mAudioDataByteSize = 0;
    ioBuffer->mPacketDescriptionCount = 0;
    return kAudio_ParamError;
}

// TODO: remaining AudioServices forwarding

OSStatus AudioServicesAddSystemSoundCompletion(
        SystemSoundID inSystemSoundID, CFRunLoopRef inRunLoop,
        CFStringRef inRunLoopMode,
        AudioServicesSystemSoundCompletionProc inCompletionRoutine,
        void *inClientData) {
    (void)inSystemSoundID;
    (void)inRunLoop;
    (void)inRunLoopMode;
    (void)inCompletionRoutine;
    (void)inClientData;
    return noErr;
}

void AudioServicesRemoveSystemSoundCompletion(SystemSoundID inSystemSoundID) {
    (void)inSystemSoundID;
}

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
    const OSStatus status = (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioSessionSetProperty,
        LC32_AUDIO_U32(inID), LC32_AUDIO_U32(inDataSize),
        LC32_AUDIO_U32((uintptr_t)inData));
    if(status == noErr &&
       inID == kAudioSessionProperty_PreferredHardwareIOBufferDuration &&
       inDataSize == sizeof(Float32)) {
        uint32_t durationBits;
        memcpy(&durationBits, inData, sizeof(durationBits));
        __atomic_store_n(&LC32PreferredIOBufferDurationBits, durationBits,
            __ATOMIC_RELEASE);
    }
    return status;
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
