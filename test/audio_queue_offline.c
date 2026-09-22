#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(AudioQueueParameterEvent) == 8, "event ABI");
_Static_assert(sizeof(AudioChannelDescription) == 20, "layout ABI");

static int failures;
static unsigned callbacks;
static void check(const char *name, int ok) {
    printf("%s: %s\n", name, ok ? "PASS" : "FAIL");
    if(!ok) ++failures;
}
static int status(const char *name, OSStatus result) {
    printf("%s: %s (%d)\n", name, result == noErr ? "PASS" : "FAIL",
        (int)result);
    if(result != noErr) ++failures;
    return result == noErr;
}
static void output(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)context; (void)queue; (void)buffer;
    ++callbacks;
}
static void pump(void) {
    for(unsigned i = 0; i < 10; ++i)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const int guestOnly = argc > 1 && !strcmp(argv[1], "--guest");
    AudioStreamBasicDescription format = {
        .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 2, .mFramesPerPacket = 1, .mBytesPerFrame = 2,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 16,
    };
    AudioQueueRef queue = NULL;
    if(!status("new-offline-output", AudioQueueNewOutput(&format, output, NULL,
            CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queue))) return 1;
    AudioChannelLayout layout = {.mChannelLayoutTag = kAudioChannelLayoutTag_Mono};
    if(!status("set-offline-format", AudioQueueSetOfflineRenderFormat(queue,
            &format, &layout))) goto cleanup;
    AudioQueueBufferRef input = NULL, rendered = NULL;
    if(!status("allocate-input", AudioQueueAllocateBuffer(queue, 2048, &input)) ||
       !status("allocate-output", AudioQueueAllocateBuffer(queue, 1024, &rendered)))
        goto cleanup;
    for(unsigned i = 0; i < 1024; ++i)
        ((int16_t *)input->mAudioData)[i] = (int16_t)(1000 + i);
    input->mAudioDataByteSize = 2048;
    input->mUserData = (void *)(uintptr_t)0x12345678;
    rendered->mUserData = (void *)(uintptr_t)0x87654321;
    AudioTimeStamp start = {.mFlags = kAudioTimeStampSampleTimeValid, .mSampleTime = 0};
    struct { AudioTimeStamp time; uint64_t guard; } actual = {
        .guard = UINT64_C(0x1122334455667788),
    };
    AudioQueueParameterEvent parameter = {.mID = kAudioQueueParam_Volume, .mValue = 0.5f};
    status("set-initial-volume", AudioQueueSetParameter(queue,
        kAudioQueueParam_Volume, 0.25f));
    if(!status("enqueue-trimmed-with-parameter", AudioQueueEnqueueBufferWithParameters(
            queue, input, 0, NULL, 8, 24, 1, &parameter, &start, &actual.time)))
        goto cleanup;
    check("actual-start-time", (actual.time.mFlags & kAudioTimeStampSampleTimeValid) &&
        actual.time.mSampleTime == 0);
    check("actual-start-canary", actual.guard == UINT64_C(0x1122334455667788));
    if(!status("start-offline", AudioQueueStart(queue, NULL))) goto cleanup;
    memset(rendered->mAudioData, 0xa5, rendered->mAudioDataBytesCapacity);
    if(status("offline-render", AudioQueueOfflineRender(queue, &start, rendered, 512))) {
        check("rendered-size", rendered->mAudioDataByteSize == 1024);
        int matches = rendered->mAudioDataByteSize == 1024;
        for(unsigned i = 0; i < rendered->mAudioDataByteSize / 2; ++i) {
            // The native reference renders at the global 0.25 volume even
            // with a scheduled 0.5 buffer event. Check parity, not a synthetic
            // volume override that would differ from native AudioToolbox.
            const int expected = (1008 + (int)i) / 4;
            const int value = ((int16_t *)rendered->mAudioData)[i];
            if(value < expected - 1 || value > expected + 1) matches = 0;
        }
        check("trimmed-pcm-copyback", matches);
        AudioQueueParameterValue volume = -1;
        status("get-rendered-volume", AudioQueueGetParameter(queue,
            kAudioQueueParam_Volume, &volume));
        // Per-buffer events do not overwrite the queue's global parameter.
        check("native-offline-global-volume", volume == 0.25f);
        printf("first-samples: %d %d %d\n", ((int16_t *)rendered->mAudioData)[0],
            ((int16_t *)rendered->mAudioData)[1], ((int16_t *)rendered->mAudioData)[2]);
        check("mirrors-preserved", input->mUserData == (void *)(uintptr_t)0x12345678 &&
            rendered->mUserData == (void *)(uintptr_t)0x87654321 &&
            rendered->mAudioDataBytesCapacity == 1024 &&
            rendered->mPacketDescriptions == NULL);
    }
    status("reset-offline", AudioQueueReset(queue));
    pump();
    // Native offline queues can retain the input buffer until disposal even
    // after Reset. Use fresh buffers when testing additional enqueue options.
    AudioQueueBufferRef optional = NULL, aliased = NULL;
    if(!status("allocate-optional-input", AudioQueueAllocateBuffer(queue, 32, &optional)) ||
       !status("allocate-aliased-input", AudioQueueAllocateBuffer(queue, 32, &aliased)))
        goto cleanup;
    memset(optional->mAudioData, 0, 32);
    memset(aliased->mAudioData, 0, 32);
    optional->mAudioDataByteSize = aliased->mAudioDataByteSize = 32;
    // Test nullable options and in-place start/actual timestamp copyback.
    status("enqueue-null-options", AudioQueueEnqueueBufferWithParameters(
        queue, optional, 0, NULL, 0, 0, 0, NULL, NULL, NULL));
    status("reset-null-options", AudioQueueReset(queue));
    pump();
    actual.time = start;
    status("enqueue-aliased-timestamp", AudioQueueEnqueueBufferWithParameters(
        queue, aliased, 0, NULL, 0, 0, 0, NULL, &actual.time, &actual.time));
    check("aliased-timestamp-canary", actual.guard == UINT64_C(0x1122334455667788));
    printf("aliased-timestamp: %.0f flags=0x%x\n", actual.time.mSampleTime,
        (unsigned)actual.time.mFlags);
    status("reset-aliased-timestamp", AudioQueueReset(queue));
    pump();
    if(guestOnly) {
        check("invalid-parameter-pointer", AudioQueueEnqueueBufferWithParameters(
            queue, input, 0, NULL, 0, 0, 1, NULL, NULL, NULL) == kAudio_ParamError);
        // A forged guest pointer must not be sent to the native queue.
        void *savedData = rendered->mAudioData;
        *(void **)&rendered->mAudioData = (void *)(uintptr_t)0x1234;
        check("invalid-render-mirror", AudioQueueOfflineRender(queue, &start,
            rendered, 8) == kAudioQueueErr_InvalidBuffer);
        *(void **)&rendered->mAudioData = savedData;
    }
    status("stop-offline", AudioQueueStop(queue, true));
    pump();
    status("disable-offline", AudioQueueSetOfflineRenderFormat(queue, NULL, NULL));
    OSStatus freeInput = AudioQueueFreeBuffer(queue, input);
    printf("free-offline-input: %d\n", (int)freeInput);
    check("free-offline-input-native-status", freeInput == noErr ||
        freeInput == kAudioQueueErr_BufferInQueue);
    status("free-output", AudioQueueFreeBuffer(queue, rendered));
cleanup:
    status("dispose-offline", AudioQueueDispose(queue, true));
    printf("offline-callbacks: %u\n", callbacks);
    printf("audio-queue-offline: %d failures\n", failures);
    return failures != 0;
}
