#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum {
    kOutputBufferCount = 3,
    kOutputFramesPerBuffer = 480,
    kOutputBytesPerFrame = 2,
    kOutputBytesPerBuffer =
        kOutputFramesPerBuffer * kOutputBytesPerFrame,
};

/* Current simulator AudioToolbox can return this unpublished status when
 * its logical output route has no usable host CoreAudio device behind it.
 */
static const OSStatus kSimulatorAudioDeviceUnavailable = -66628;

typedef struct {
    AudioQueueRef queue;
    CFRunLoopRef runLoop;
    AudioQueueBufferRef buffers[kOutputBufferCount];
    volatile UInt32 callbackCount;
    volatile UInt32 callbackMask;
    volatile UInt32 listenerCount;
    volatile int callbackValid;
    volatile int listenerValid;
    volatile int allowReenqueue;
    volatile int reenqueueAttempted;
    volatile OSStatus reenqueueStatus;
} OutputState;

static int report_status(const char *name, OSStatus status) {
    const int passed = status == noErr;
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

static int device_unavailable(OSStatus status) {
    return status == kAudioQueueErr_InvalidDevice ||
        status == kAudioQueueErr_CannotStart ||
        status == kAudioQueueErr_CannotStartYet ||
        status == kSimulatorAudioDeviceUnavailable;
}

static int buffer_index(const OutputState *state,
                        AudioQueueBufferRef buffer) {
    if(!state || !buffer) return -1;
    for(int index = 0; index < kOutputBufferCount; ++index) {
        if(state->buffers[index] == buffer) return index;
    }
    return -1;
}

static void fill_buffer(AudioQueueBufferRef buffer, UInt8 value) {
    if(!buffer || !buffer->mAudioData ||
       buffer->mAudioDataBytesCapacity < kOutputBytesPerBuffer) return;
    memset(buffer->mAudioData, value, kOutputBytesPerBuffer);
    buffer->mAudioDataByteSize = kOutputBytesPerBuffer;
    /* GIPAudioPlayer preserves the CBR packet count here even though the
     * buffer has no packet-description storage. Older AudioQueue accepted
     * that informational count and ignored it for PCM. */
    buffer->mPacketDescriptionCount = kOutputFramesPerBuffer;
}

static void output_callback(void *userData, AudioQueueRef queue,
                            AudioQueueBufferRef buffer) {
    OutputState *state = (OutputState *)userData;
    const int index = buffer_index(state, buffer);
    int valid = state && state->queue == queue && index >= 0 &&
        CFRunLoopGetCurrent() == state->runLoop && buffer->mAudioData &&
        buffer->mAudioDataBytesCapacity >= kOutputBytesPerBuffer &&
        buffer->mAudioDataByteSize <= buffer->mAudioDataBytesCapacity &&
        buffer->mUserData == (void *)(uintptr_t)(0x100u + (UInt32)index);

    if(state) {
        state->callbackValid &= valid;
        if(index >= 0) state->callbackMask |= 1u << (UInt32)index;
        ++state->callbackCount;
        if(valid && state->allowReenqueue &&
           !state->reenqueueAttempted) {
            state->reenqueueAttempted = 1;
            fill_buffer(buffer, 0);
            state->reenqueueStatus = AudioQueueEnqueueBuffer(
                queue, buffer, 0, NULL);
        }
        if(state->runLoop) CFRunLoopStop(state->runLoop);
    }
}

static void running_listener(void *userData, AudioQueueRef queue,
                             AudioQueuePropertyID property) {
    OutputState *state = (OutputState *)userData;
    if(state) {
        state->listenerValid &= state->queue == queue &&
            property == kAudioQueueProperty_IsRunning;
        ++state->listenerCount;
        if(state->runLoop) CFRunLoopStop(state->runLoop);
    }
}

static void pump_run_loop(OutputState *state, UInt32 callbackTarget,
                          UInt32 listenerTarget, double timeout) {
    const double slice = 0.05;
    unsigned int attempts = (unsigned int)(timeout / slice);
    if(!attempts) attempts = 1;
    for(unsigned int attempt = 0; attempt < attempts; ++attempt) {
        if(state->callbackCount >= callbackTarget &&
           state->listenerCount >= listenerTarget) return;
        (void)CFRunLoopRunInMode(kCFRunLoopDefaultMode, slice, false);
    }
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const int requireCallback = argc == 2 &&
        !strcmp(argv[1], "--require-callback");
    int passed = 1;

    AudioQueueRef invalidQueue =
        (AudioQueueRef)(uintptr_t)0x12345678;
    OSStatus invalidNewStatus = AudioQueueNewOutput(NULL, output_callback,
        NULL, NULL, NULL, 0, &invalidQueue);
    const int invalidNewSafe = invalidNewStatus == kAudio_ParamError &&
        invalidQueue == NULL;
    passed &= invalidNewSafe;
    printf("audio-queue-output-invalid-new-clears-result: %s (%d)\n",
        invalidNewSafe ? "PASS" : "FAIL", (int)invalidNewStatus);

    UInt32 invalidPrepared = UINT32_MAX;
    OSStatus invalidPrimeStatus = AudioQueuePrime(NULL, 0,
        &invalidPrepared);
    const int invalidPrimeSafe =
        invalidPrimeStatus == kAudio_ParamError && invalidPrepared == 0;
    passed &= invalidPrimeSafe;
    printf("audio-queue-output-invalid-prime-clears-result: %s (%d)\n",
        invalidPrimeSafe ? "PASS" : "FAIL", (int)invalidPrimeStatus);

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 48000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger |
        kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = kOutputBytesPerFrame;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = kOutputBytesPerFrame;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;
    /* Exercise compatibility normalization at the guest/host boundary. */
    format.mReserved = 0xa5a5a5a5;

    OutputState state = {
        .runLoop = CFRunLoopGetCurrent(),
        .callbackValid = 1,
        .listenerValid = 1,
        .allowReenqueue = 1,
        .reenqueueStatus = kAudio_ParamError,
    };
    AudioQueueRef output = NULL;
    OSStatus newStatus = AudioQueueNewOutput(&format, output_callback,
        &state, state.runLoop, kCFRunLoopCommonModes, 0, &output);
    if(newStatus != noErr || !output) {
        const int unavailable = device_unavailable(newStatus) &&
            output == NULL;
        passed &= unavailable && !requireCallback;
        printf("audio-queue-new-output: %s (%d)\n",
            unavailable ? (requireCallback ? "FAIL" : "UNAVAILABLE") :
                "FAIL", (int)newStatus);
        return !passed;
    }
    state.queue = output;
    passed &= report_status("audio-queue-new-output", newStatus);

    AudioStreamBasicDescription returnedFormat = {0};
    UInt32 returnedFormatSize = sizeof(returnedFormat);
    OSStatus formatStatus = AudioQueueGetProperty(output,
        kAudioQueueProperty_StreamDescription, &returnedFormat,
        &returnedFormatSize);
    passed &= report_status("audio-queue-output-stream-description",
        formatStatus);
    const int formatMatches = returnedFormatSize == sizeof(returnedFormat) &&
        returnedFormat.mFormatID == format.mFormatID &&
        returnedFormat.mSampleRate == format.mSampleRate &&
        returnedFormat.mChannelsPerFrame == format.mChannelsPerFrame &&
        returnedFormat.mBytesPerFrame == format.mBytesPerFrame &&
        returnedFormat.mReserved == 0;
    passed &= formatMatches;
    printf("audio-queue-output-stream-description-layout: %s "
           "(size=%u reserved=%u)\n", formatMatches ? "PASS" : "FAIL",
        (unsigned int)returnedFormatSize,
        (unsigned int)returnedFormat.mReserved);

    passed &= report_status("audio-queue-output-set-volume",
        AudioQueueSetParameter(output, kAudioQueueParam_Volume, 0.25f));
    OSStatus addListenerStatus = AudioQueueAddPropertyListener(output,
        kAudioQueueProperty_IsRunning, running_listener, &state);
    passed &= report_status("audio-queue-output-add-listener",
        addListenerStatus);

    for(int index = 0; index < kOutputBufferCount; ++index) {
        OSStatus allocateStatus = AudioQueueAllocateBuffer(output,
            kOutputBytesPerBuffer, &state.buffers[index]);
        passed &= report_status("audio-queue-output-allocate",
            allocateStatus);
        AudioQueueBufferRef buffer = state.buffers[index];
        const int layoutValid = allocateStatus == noErr && buffer &&
            buffer->mAudioDataBytesCapacity == kOutputBytesPerBuffer &&
            buffer->mAudioData && buffer->mAudioDataByteSize == 0 &&
            buffer->mPacketDescriptionCapacity == 0 &&
            buffer->mPacketDescriptions == NULL &&
            buffer->mPacketDescriptionCount == 0;
        passed &= layoutValid;
        printf("audio-queue-output-buffer-layout-%d: %s\n", index,
            layoutValid ? "PASS" : "FAIL");
        if(!layoutValid) goto cleanup;
        buffer->mUserData =
            (void *)(uintptr_t)(0x100u + (UInt32)index);
    }

    state.buffers[0]->mAudioDataByteSize =
        state.buffers[0]->mAudioDataBytesCapacity + 1;
    OSStatus oversizedStatus = AudioQueueEnqueueBuffer(output,
        state.buffers[0], 0, NULL);
    const int oversizedRejected =
        oversizedStatus == kAudioQueueErr_InvalidBuffer;
    passed &= oversizedRejected;
    printf("audio-queue-output-oversized-buffer-rejected: %s (%d)\n",
        oversizedRejected ? "PASS" : "FAIL", (int)oversizedStatus);

    state.buffers[0]->mAudioDataByteSize = 0;
    OSStatus emptyStatus = AudioQueueEnqueueBuffer(output,
        state.buffers[0], 0, NULL);
    const int emptyRejected = emptyStatus == kAudioQueueErr_BufferEmpty;
    passed &= emptyRejected;
    printf("audio-queue-output-empty-buffer-rejected: %s (%d)\n",
        emptyRejected ? "PASS" : "FAIL", (int)emptyStatus);

    for(int index = 0; index < kOutputBufferCount; ++index) {
        fill_buffer(state.buffers[index], 0);
        passed &= report_status("audio-queue-output-enqueue",
            AudioQueueEnqueueBuffer(output, state.buffers[index], 0, NULL));
    }
    OSStatus duplicateStatus = AudioQueueEnqueueBuffer(output,
        state.buffers[0], 0, NULL);
    const int duplicateRejected =
        duplicateStatus == kAudioQueueErr_BufferInQueue;
    passed &= duplicateRejected;
    printf("audio-queue-output-duplicate-buffer-rejected: %s (%d)\n",
        duplicateRejected ? "PASS" : "FAIL", (int)duplicateStatus);

    UInt32 prepared = UINT32_MAX;
    OSStatus primeStatus = AudioQueuePrime(output, 0, &prepared);
    const UInt32 enqueuedFrames =
        kOutputBufferCount * kOutputFramesPerBuffer;
    const int primeAvailable = primeStatus == noErr ||
        device_unavailable(primeStatus);
    const int primeResultValid = prepared != UINT32_MAX &&
        prepared <= enqueuedFrames;
    passed &= primeAvailable && primeResultValid;
    printf("audio-queue-output-prime: %s (%d prepared=%u)\n",
        primeStatus == noErr ? "PASS" :
            (primeAvailable ? "UNAVAILABLE" : "FAIL"),
        (int)primeStatus, (unsigned int)prepared);

    OSStatus startStatus = AudioQueueStart(output, NULL);
    for(unsigned int attempt = 0;
            startStatus == kAudioQueueErr_CannotStartYet && attempt < 2;
            ++attempt) {
        usleep(50000);
        startStatus = AudioQueueStart(output, NULL);
    }
    const int startAvailable = startStatus == noErr ||
        device_unavailable(startStatus);
    passed &= startAvailable;
    printf("audio-queue-output-start: %s (%d)\n",
        startStatus == noErr ? "PASS" :
            (startAvailable ? "UNAVAILABLE" : "FAIL"),
        (int)startStatus);

    if(startStatus == noErr) {
        pump_run_loop(&state, kOutputBufferCount + 1, 1, 3.0);
        const UInt32 expectedMask = (1u << kOutputBufferCount) - 1u;
        const int callbacksValid = state.callbackCount >=
                kOutputBufferCount + 1 &&
            state.callbackMask == expectedMask && state.callbackValid &&
            state.reenqueueAttempted && state.reenqueueStatus == noErr;
        passed &= callbacksValid;
        printf("audio-queue-output-callback-reenqueue: %s "
               "(callbacks=%u mask=0x%x reenqueue=%d)\n",
            callbacksValid ? "PASS" : "FAIL",
            (unsigned int)state.callbackCount,
            (unsigned int)state.callbackMask,
            (int)state.reenqueueStatus);

        const int startListenerValid = state.listenerCount > 0 &&
            state.listenerValid;
        passed &= startListenerValid;
        printf("audio-queue-output-running-listener-start: %s "
               "(callbacks=%u)\n",
            startListenerValid ? "PASS" : "FAIL",
            (unsigned int)state.listenerCount);

        state.allowReenqueue = 0;
        const UInt32 listenerCountBeforeStop = state.listenerCount;
        passed &= report_status("audio-queue-output-stop",
            AudioQueueStop(output, true));
        pump_run_loop(&state, state.callbackCount,
            listenerCountBeforeStop + 1, 1.0);
        const int stopListenerValid =
            state.listenerCount > listenerCountBeforeStop &&
            state.listenerValid;
        passed &= stopListenerValid;
        printf("audio-queue-output-running-listener-stop: %s "
               "(callbacks=%u)\n",
            stopListenerValid ? "PASS" : "FAIL",
            (unsigned int)state.listenerCount);
    } else {
        if(requireCallback) passed = 0;
        printf("audio-queue-output-callback-reenqueue: %s "
               "(callbacks=%u)\n",
            requireCallback ? "FAIL" : "SKIP",
            (unsigned int)state.callbackCount);
    }

cleanup:
    if(addListenerStatus == noErr) {
        passed &= report_status("audio-queue-output-remove-listener",
            AudioQueueRemovePropertyListener(output,
                kAudioQueueProperty_IsRunning, running_listener, &state));
    }
    passed &= report_status("audio-queue-output-dispose",
        AudioQueueDispose(output, true));
    return !passed;
}
