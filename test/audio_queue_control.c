#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

_Static_assert(sizeof(AudioTimeStamp) == 64, "timestamp ABI");
_Static_assert(sizeof(AudioQueueParameterValue) == 4, "parameter ABI");

static _Atomic int failures;
static void check(const char *name, int ok) {
    printf("%s: %s\n", name, ok ? "PASS" : "FAIL");
    if(!ok) failures = 1;
}
static void status(const char *name, OSStatus result) {
    printf("%s: %s (%d)\n", name, result == noErr ? "PASS" : "FAIL",
        (int)result);
    if(result != noErr) failures = 1;
}

typedef struct {
    AudioQueueRef queue;
    AudioQueueBufferRef buffer;
    _Atomic unsigned callbacks;
    _Atomic int resetInCallback;
    _Atomic int enqueueInCallback;
    _Atomic OSStatus callbackStatus;
} State;

static void output(void *context, AudioQueueRef queue,
                   AudioQueueBufferRef buffer) {
    State *state = context;
    check("callback-identity", queue == state->queue && buffer == state->buffer);
    // There is only one callback writer for this single-buffer queue. Use
    // atomic loads/stores so the test does not need an exclusive RMW loop.
    state->callbacks = state->callbacks + 1;
    if(state->resetInCallback) {
        state->resetInCallback = 0;
        state->callbackStatus = AudioQueueReset(queue);
    } else if(state->enqueueInCallback) {
        state->enqueueInCallback = 0;
        state->callbackStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
}

static void pump(void) {
    for(unsigned i = 0; i < 10; ++i)
        if(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false) ==
                kCFRunLoopRunFinished) usleep(20000);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int guestOnly = 0, workerCallbacks = 0;
    for(int i = 1; i < argc; ++i) {
        if(!strcmp(argv[i], "--guest")) guestOnly = 1;
        if(!strcmp(argv[i], "--worker")) workerCallbacks = 1;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 2, .mFramesPerPacket = 1, .mBytesPerFrame = 2,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 16,
    };
    State state = {0};
    OSStatus result = AudioQueueNewOutput(&format, output, &state,
        workerCallbacks ? NULL : CFRunLoopGetCurrent(),
        workerCallbacks ? NULL : kCFRunLoopCommonModes, 0, &state.queue);
    status("new-output", result);
    if(result || !state.queue) return 1;

    struct { uint32_t before; Float32 value; uint32_t after; } parameter = {
        0x11223344, -1, 0x55667788,
    };
    status("set-volume", AudioQueueSetParameter(state.queue,
        kAudioQueueParam_Volume, 0.25f));
    status("get-volume", AudioQueueGetParameter(state.queue,
        kAudioQueueParam_Volume, &parameter.value));
    check("parameter-value-and-canaries", parameter.value == 0.25f &&
        parameter.before == 0x11223344 && parameter.after == 0x55667788);
    parameter.value = -2;
    check("invalid-parameter", AudioQueueGetParameter(state.queue,
        (AudioQueueParameterID)0xffffffff, &parameter.value) != noErr);
    check("invalid-parameter-keeps-output", parameter.value == -2);

    struct { UInt32 size; uint32_t guard; } property = {0, 0xa5a5a5a5};
    status("get-stream-property-size", AudioQueueGetPropertySize(state.queue,
        kAudioQueueProperty_StreamDescription, &property.size));
    check("property-size-and-canary", property.size == sizeof(format) &&
        property.guard == 0xa5a5a5a5);
    status("get-running-property-size", AudioQueueGetPropertySize(state.queue,
        kAudioQueueProperty_IsRunning, &property.size));
    check("running-property-size", property.size == sizeof(UInt32));
    check("invalid-property", AudioQueueGetPropertySize(state.queue,
        (AudioQueuePropertyID)0xffffffff, &property.size) != noErr);

    status("flush-empty", AudioQueueFlush(state.queue));
    status("reset-empty", AudioQueueReset(state.queue));
    status("allocate", AudioQueueAllocateBuffer(state.queue, 960, &state.buffer));
    if(!state.buffer) return 1;
    memset(state.buffer->mAudioData, 0, 960);
    state.buffer->mAudioDataByteSize = 960;
    for(unsigned cycle = 0; cycle < 3; ++cycle) {
        status("enqueue-before-reset", AudioQueueEnqueueBuffer(state.queue,
            state.buffer, 0, NULL));
        unsigned before = state.callbacks;
        status("reset-queued", AudioQueueReset(state.queue));
        pump();
        check("reset-returns-buffer", state.callbacks == before + 1);
    }

    // Match native behavior when a reset callback tries to enqueue again:
    // reject it with EnqueueDuringReset, without retaining buffer ownership.
    status("enqueue-for-callback-reuse", AudioQueueEnqueueBuffer(state.queue,
        state.buffer, 0, NULL));
    state.enqueueInCallback = 1;
    state.callbackStatus = -1;
    status("reset-with-reenqueue", AudioQueueReset(state.queue));
    pump();
    check("callback-reenqueue-during-reset", state.callbackStatus ==
        kAudioQueueErr_EnqueueDuringReset);
    status("reuse-after-rejected-enqueue", AudioQueueEnqueueBuffer(state.queue,
        state.buffer, 0, NULL));
    status("flush-keeps-buffer", AudioQueueFlush(state.queue));
    if(guestOnly)
        check("reenqueued-buffer-stays-owned", AudioQueueEnqueueBuffer(state.queue,
            state.buffer, 0, NULL) == kAudioQueueErr_BufferInQueue);
    status("reset-reenqueued", AudioQueueReset(state.queue));
    pump();

    status("enqueue-for-nested-reset", AudioQueueEnqueueBuffer(state.queue,
        state.buffer, 0, NULL));
    state.resetInCallback = 1;
    state.callbackStatus = -1;
    status("reset-with-nested-reset", AudioQueueReset(state.queue));
    pump();
    status("callback-reset", state.callbackStatus);
    AudioQueueParameterEvent event = {
        .mID = kAudioQueueParam_Volume, .mValue = 0.75f,
    };
    status("reuse-after-callback-reset", AudioQueueEnqueueBufferWithParameters(
        state.queue, state.buffer, 0, NULL, 0, 0, 1, &event, NULL, NULL));
    status("start-after-reset", AudioQueueStart(state.queue, NULL));

    struct { AudioTimeStamp time; uint64_t guard; } time = {
        .guard = UINT64_C(0x1122334455667788),
    };
    result = AudioQueueDeviceGetCurrentTime(state.queue, &time.time);
    printf("device-current-time: %d flags=0x%x\n", (int)result,
        (unsigned)time.time.mFlags);
    if(result == noErr) {
        AudioTimeStamp input = time.time;
        time.time.mFlags = kAudioTimeStampHostTimeValid;
        result = AudioQueueDeviceTranslateTime(state.queue, &input, &time.time);
        status("device-translate-time", result);
        if(result == noErr)
            check("translated-host-time", (time.time.mFlags &
                kAudioTimeStampHostTimeValid) && time.time.mHostTime != 0);
        result = AudioQueueDeviceTranslateTime(state.queue, &time.time, &time.time);
        status("device-in-place-translate", result);
    }
    result = AudioQueueDeviceGetNearestStartTime(state.queue, &time.time, 0);
    status("device-nearest-start-time", result);
    check("timestamp-canary", time.guard == UINT64_C(0x1122334455667788));
    pump();
    status("get-played-buffer-volume", AudioQueueGetParameter(state.queue,
        kAudioQueueParam_Volume, &parameter.value));
    check("played-buffer-preserves-global-volume", parameter.value == 0.25f);
    status("flush-after-playback", AudioQueueFlush(state.queue));
    status("stop", AudioQueueStop(state.queue, true));
    status("free", AudioQueueFreeBuffer(state.queue, state.buffer));
    status("dispose", AudioQueueDispose(state.queue, true));
    if(guestOnly) {
        check("stale-reset", AudioQueueReset(state.queue) == kAudio_ParamError);
        check("stale-flush", AudioQueueFlush(state.queue) == kAudio_ParamError);
        check("stale-get-parameter", AudioQueueGetParameter(state.queue,
            kAudioQueueParam_Volume, &parameter.value) == kAudio_ParamError);
        check("stale-property-size", AudioQueueGetPropertySize(state.queue,
            kAudioQueueProperty_IsRunning, &property.size) == kAudio_ParamError);
        check("stale-translate", AudioQueueDeviceTranslateTime(state.queue,
            &time.time, &time.time) == kAudio_ParamError);
        check("stale-nearest-start", AudioQueueDeviceGetNearestStartTime(
            state.queue, &time.time, 0) == kAudio_ParamError);
    }
    printf("audio-queue-control: %d failures\n", failures);
    return failures != 0;
}
