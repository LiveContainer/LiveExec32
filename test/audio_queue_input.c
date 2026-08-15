#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    AudioQueueRef queue;
    CFRunLoopRef runLoop;
    volatile UInt32 callbackCount;
    volatile int callbackValid;
    volatile OSStatus reenqueueStatus;
} InputState;

typedef struct {
    AudioQueueRef queue;
    volatile UInt32 callbackCount;
    volatile int callbackValid;
    volatile OSStatus disposeStatus;
} ReentrantDisposeState;

static int report_status(const char *name, OSStatus status) {
    const int passed = status == noErr;
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

static void input_callback(void *userData, AudioQueueRef queue,
                           AudioQueueBufferRef buffer,
                           const AudioTimeStamp *startTime,
                           UInt32 packetCount,
                           const AudioStreamPacketDescription *descriptions) {
    InputState *state = (InputState *)userData;
    int valid = state && state->queue == queue && buffer && startTime &&
        buffer->mAudioData &&
        buffer->mAudioDataByteSize <= buffer->mAudioDataBytesCapacity;
    if(descriptions) {
        valid &= buffer->mPacketDescriptions == descriptions;
        valid &= buffer->mPacketDescriptionCount == packetCount;
    } else {
        /* CBR still reports inNumPackets, but has no packet descriptions. */
        valid &= buffer->mPacketDescriptionCount == 0;
    }
    if(state) {
        state->callbackValid &= valid;
        ++state->callbackCount;
        if(state->callbackCount < 2) {
            state->reenqueueStatus = AudioQueueEnqueueBuffer(
                queue, buffer, 0, NULL);
        }
        if(state->runLoop) CFRunLoopStop(state->runLoop);
    }
}

static void null_run_loop_dispose_callback(
        void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer,
        const AudioTimeStamp *startTime, UInt32 packetCount,
        const AudioStreamPacketDescription *descriptions) {
    ReentrantDisposeState *state = (ReentrantDisposeState *)userData;
    if(!state || state->callbackCount) return;
    state->callbackValid &= state->queue == queue && buffer && startTime &&
        buffer->mAudioData &&
        buffer->mAudioDataByteSize <= buffer->mAudioDataBytesCapacity;
    if(descriptions) {
        state->callbackValid &=
            buffer->mPacketDescriptions == descriptions;
        state->callbackValid &=
            buffer->mPacketDescriptionCount == packetCount;
    }
    state->disposeStatus = AudioQueueDispose(queue, true);
    /* Publish completion last so the polling thread observes disposeStatus. */
    __sync_synchronize();
    state->callbackCount = 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const int requireCallback = argc == 2 &&
        !strcmp(argv[1], "--require-callback");
    int passed = 1;
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 8000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger |
        kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;
    /* Old applications often left this field uninitialized. */
    format.mReserved = 0xa5a5a5a5;

    InputState state = {
        .runLoop = CFRunLoopGetCurrent(),
        .callbackValid = 1,
        .reenqueueStatus = noErr,
    };
    AudioQueueRef input = NULL;
    OSStatus newInputStatus = AudioQueueNewInput(&format, input_callback,
        &state, state.runLoop, kCFRunLoopCommonModes, 0, &input);
    passed &= report_status("audio-queue-new-input", newInputStatus);
    passed &= input != NULL;
    if(newInputStatus != noErr || !input) return !passed;
    state.queue = input;

    AudioStreamBasicDescription returnedFormat = {0};
    UInt32 formatSize = sizeof(returnedFormat);
    OSStatus formatStatus = AudioQueueGetProperty(input,
        kAudioQueueProperty_StreamDescription, &returnedFormat, &formatSize);
    passed &= report_status("audio-queue-stream-description", formatStatus);
    const int formatMatches = formatSize == sizeof(returnedFormat) &&
        returnedFormat.mFormatID == format.mFormatID &&
        returnedFormat.mChannelsPerFrame == format.mChannelsPerFrame &&
        returnedFormat.mReserved == 0;
    passed &= formatMatches;
    printf("audio-queue-stream-description-layout: %s (size=%u)\n",
        formatMatches ? "PASS" : "FAIL", (unsigned int)formatSize);

    UInt32 enableMetering = 1;
    OSStatus meteringStatus = AudioQueueSetProperty(input,
        kAudioQueueProperty_EnableLevelMetering,
        &enableMetering, sizeof(enableMetering));
    const int meteringAvailable = meteringStatus == noErr ||
        meteringStatus == kAudioQueueErr_InvalidDevice;
    passed &= meteringAvailable;
    printf("audio-queue-enable-metering: %s (%d)\n",
        meteringStatus == noErr ? "PASS" :
            (meteringAvailable ? "UNAVAILABLE" : "FAIL"),
        (int)meteringStatus);

    AudioQueueBufferRef spareBuffer = NULL;
    OSStatus spareStatus = AudioQueueAllocateBufferWithPacketDescriptions(
        input, 512, 4, &spareBuffer);
    passed &= report_status("audio-queue-allocate-packet-mirror", spareStatus);
    const int spareLayout = spareBuffer &&
        spareBuffer->mAudioDataBytesCapacity == 512 &&
        spareBuffer->mAudioData && spareBuffer->mAudioDataByteSize == 0 &&
        spareBuffer->mPacketDescriptionCapacity == 4 &&
        spareBuffer->mPacketDescriptions &&
        spareBuffer->mPacketDescriptionCount == 0;
    passed &= spareLayout;
    printf("audio-queue-packet-mirror-layout: %s\n",
        spareLayout ? "PASS" : "FAIL");
    if(spareBuffer) passed &= report_status("audio-queue-free-packet-mirror",
        AudioQueueFreeBuffer(input, spareBuffer));

    OSStatus invalidFreeStatus = AudioQueueFreeBuffer(input,
        (AudioQueueBufferRef)(uintptr_t)0x1234);
    const int invalidFreeSafe =
        invalidFreeStatus == kAudioQueueErr_InvalidBuffer;
    passed &= invalidFreeSafe;
    printf("audio-queue-invalid-buffer-safe: %s (%d)\n",
        invalidFreeSafe ? "PASS" : "FAIL", (int)invalidFreeStatus);

    AudioQueueBufferRef inputBuffer = NULL;
    OSStatus allocateStatus =
        AudioQueueAllocateBuffer(input, 2048, &inputBuffer);
    passed &= report_status("audio-queue-allocate-input-mirror",
        allocateStatus);
    const int inputLayout = inputBuffer &&
        inputBuffer->mAudioDataBytesCapacity == 2048 &&
        inputBuffer->mAudioData && inputBuffer->mAudioDataByteSize == 0 &&
        inputBuffer->mPacketDescriptionCapacity == 0 &&
        inputBuffer->mPacketDescriptions == NULL &&
        inputBuffer->mPacketDescriptionCount == 0;
    passed &= inputLayout;
    printf("audio-queue-input-mirror-layout: %s\n",
        inputLayout ? "PASS" : "FAIL");

    if(inputBuffer) passed &= report_status("audio-queue-enqueue-input-cbr",
        AudioQueueEnqueueBuffer(input, inputBuffer, 0, NULL));

    AudioTimeStamp deviceTime;
    memset(&deviceTime, 0xa5, sizeof(deviceTime));
    OSStatus timeStatus =
        AudioQueueDeviceGetCurrentTime(input, &deviceTime);
    const int timeAvailable = timeStatus == noErr ||
        timeStatus == kAudioQueueErr_InvalidDevice;
    passed &= timeAvailable;
    printf("audio-queue-device-time: %s (%d)\n",
        timeStatus == noErr ? "PASS" :
            (timeAvailable ? "UNAVAILABLE" : "FAIL"), (int)timeStatus);

    OSStatus startStatus = AudioQueueStart(input, NULL);
    const int startAvailable = startStatus == noErr ||
        startStatus == kAudioQueueErr_InvalidDevice ||
        startStatus == kAudioQueueErr_Permissions;
    passed &= startAvailable;
    printf("audio-queue-start: %s (%d)\n",
        startStatus == noErr ? "PASS" :
            (startAvailable ? "UNAVAILABLE" : "FAIL"), (int)startStatus);
    if(startStatus == noErr) {
        for(unsigned int attempt = 0;
                attempt < 3 && state.callbackCount == 0; ++attempt) {
            (void)CFRunLoopRunInMode(
                kCFRunLoopDefaultMode, 0.5, false);
        }
        passed &= report_status("audio-queue-pause", AudioQueuePause(input));
        passed &= report_status("audio-queue-stop",
            AudioQueueStop(input, true));
    }

    const int callbackObserved = state.callbackCount > 0 &&
        state.callbackValid && state.reenqueueStatus == noErr;
    if(requireCallback) passed &= callbackObserved;
    printf("audio-queue-input-callback-copy: %s (callbacks=%u reenqueue=%d)\n",
        callbackObserved ? "PASS" :
            (requireCallback ? "FAIL" : "SKIP"),
        (unsigned int)state.callbackCount, (int)state.reenqueueStatus);

    passed &= report_status("audio-queue-dispose",
        AudioQueueDispose(input, true));

    ReentrantDisposeState reentrantState = {
        .callbackValid = 1,
        .disposeStatus = kAudio_ParamError,
    };
    AudioQueueRef reentrantInput = NULL;
    OSStatus reentrantNewStatus = AudioQueueNewInput(&format,
        null_run_loop_dispose_callback, &reentrantState,
        NULL, NULL, 0, &reentrantInput);
    passed &= report_status("audio-queue-null-runloop-new-input",
        reentrantNewStatus);
    if(reentrantNewStatus == noErr && reentrantInput) {
        reentrantState.queue = reentrantInput;
        AudioQueueBufferRef reentrantBuffer = NULL;
        OSStatus reentrantAllocateStatus = AudioQueueAllocateBuffer(
            reentrantInput, 2048, &reentrantBuffer);
        passed &= report_status("audio-queue-null-runloop-allocate",
            reentrantAllocateStatus);
        OSStatus reentrantEnqueueStatus = reentrantAllocateStatus == noErr
            ? AudioQueueEnqueueBuffer(reentrantInput,
                reentrantBuffer, 0, NULL)
            : reentrantAllocateStatus;
        passed &= report_status("audio-queue-null-runloop-enqueue",
            reentrantEnqueueStatus);

        OSStatus reentrantStartStatus = reentrantEnqueueStatus == noErr
            ? AudioQueueStart(reentrantInput, NULL)
            : reentrantEnqueueStatus;
        const int reentrantStartAvailable =
            reentrantStartStatus == noErr ||
            reentrantStartStatus == kAudioQueueErr_InvalidDevice ||
            reentrantStartStatus == kAudioQueueErr_Permissions;
        passed &= reentrantStartAvailable;
        printf("audio-queue-null-runloop-start: %s (%d)\n",
            reentrantStartStatus == noErr ? "PASS" :
                (reentrantStartAvailable ? "UNAVAILABLE" : "FAIL"),
            (int)reentrantStartStatus);
        if(reentrantStartStatus == noErr) {
            for(unsigned int attempt = 0;
                    attempt < 200 && !reentrantState.callbackCount;
                    ++attempt) {
                usleep(10000);
            }
        }

        const int reentrantCallbackObserved =
            reentrantState.callbackCount > 0 &&
            reentrantState.callbackValid &&
            reentrantState.disposeStatus == noErr;
        if(requireCallback) passed &= reentrantCallbackObserved;
        printf("audio-queue-null-runloop-reentrant-dispose: %s "
               "(callbacks=%u dispose=%d)\n",
            reentrantCallbackObserved ? "PASS" :
                (requireCallback ? "FAIL" : "SKIP"),
            (unsigned int)reentrantState.callbackCount,
            (int)reentrantState.disposeStatus);
        if(!reentrantState.callbackCount) {
            passed &= report_status("audio-queue-null-runloop-dispose",
                AudioQueueDispose(reentrantInput, true));
        }
    }
    return !passed;
}
