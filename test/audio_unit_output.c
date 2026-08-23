#include <AudioToolbox/AudioToolbox.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    AudioUnit unit;
    volatile uint32_t callbackCount;
    volatile uint32_t callbackValid;
    volatile uint32_t lastFrameCount;
    volatile uint32_t reentrantStopAttempted;
    volatile OSStatus reentrantStopStatus;
} OutputState;

static OSStatus render_callback(void *refCon,
                                AudioUnitRenderActionFlags *actionFlags,
                                const AudioTimeStamp *timeStamp,
                                UInt32 bus,
                                UInt32 frameCount,
                                AudioBufferList *buffers) {
    OutputState *state = (OutputState *)refCon;
    const UInt32 requiredBytes = frameCount * 4u;
    const int valid = state && actionFlags && timeStamp && bus == 0 &&
        frameCount > 0 && frameCount <= 4096 && buffers &&
        buffers->mNumberBuffers == 1 &&
        buffers->mBuffers[0].mNumberChannels == 2 &&
        buffers->mBuffers[0].mData &&
        buffers->mBuffers[0].mDataByteSize == requiredBytes;
    if(!valid) {
        if(state) state->callbackValid = 0;
        return kAudio_ParamError;
    }

    int16_t *samples = (int16_t *)buffers->mBuffers[0].mData;
    for(UInt32 frame = 0; frame < frameCount; ++frame) {
        const int16_t sample = (frame & 16u) ? 1800 : -1800;
        samples[frame * 2] = sample;
        samples[frame * 2 + 1] = sample;
    }
    buffers->mBuffers[0].mDataByteSize = requiredBytes;
    state->lastFrameCount = frameCount;
    ++state->callbackCount;
    if(!state->reentrantStopAttempted && state->unit) {
        state->reentrantStopAttempted = 1;
        state->reentrantStopStatus = AudioOutputUnitStop(state->unit);
    }
    return noErr;
}

static int report_status(const char *name, OSStatus status) {
    const int passed = status == noErr;
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int passed = 1;

    AudioComponentDescription description = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
    };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    const int found = component != NULL;
    passed &= found;
    printf("audio-unit-output-find-remoteio: %s\n",
        found ? "PASS" : "FAIL");
    if(!found) return 1;

    AudioUnit unit = NULL;
    OSStatus newStatus = AudioComponentInstanceNew(component, &unit);
    passed &= report_status("audio-unit-output-new", newStatus);
    if(newStatus != noErr || !unit) return 1;

    const Float32 preferredDuration = 1024.0f / 24000.0f;
    passed &= report_status("audio-unit-output-buffer-duration",
        AudioSessionSetProperty(
            kAudioSessionProperty_PreferredHardwareIOBufferDuration,
            sizeof(preferredDuration), &preferredDuration));

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 24000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger |
        kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    passed &= report_status("audio-unit-output-format",
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 0, &format, sizeof(format)));

    OutputState state = {
        .unit = unit,
        .callbackValid = 1,
    };
    AURenderCallbackStruct callback = {
        .inputProc = render_callback,
        .inputProcRefCon = &state,
    };
    passed &= report_status("audio-unit-output-callback",
        AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Global, 0, &callback, sizeof(callback)));

    UInt32 maximumFrames = 0;
    UInt32 maximumFramesSize = sizeof(maximumFrames);
    OSStatus maximumFramesStatus = AudioUnitGetProperty(unit,
        kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global, 0, &maximumFrames, &maximumFramesSize);
    const int maximumFramesValid = maximumFramesStatus == noErr &&
        maximumFramesSize == sizeof(maximumFrames) && maximumFrames == 4096;
    passed &= maximumFramesValid;
    printf("audio-unit-output-maximum-frames: %s (%u)\n",
        maximumFramesValid ? "PASS" : "FAIL", (unsigned)maximumFrames);

    passed &= report_status("audio-unit-output-initialize",
        AudioUnitInitialize(unit));
    passed &= report_status("audio-unit-output-start",
        AudioOutputUnitStart(unit));
    usleep(300000);
    passed &= report_status("audio-unit-output-stop",
        AudioOutputUnitStop(unit));

    const uint32_t firstCount = state.callbackCount;
    const int firstRunValid = state.callbackValid && firstCount >= 1 &&
        state.lastFrameCount == 1024;
    passed &= firstRunValid;
    printf("audio-unit-output-rendered: %s (callbacks=%u frames=%u)\n",
        firstRunValid ? "PASS" : "FAIL", (unsigned)firstCount,
        (unsigned)state.lastFrameCount);

    const int reentrantStopSafe = state.reentrantStopAttempted &&
        state.reentrantStopStatus ==
            kAudioUnitErr_CannotDoInCurrentContext;
    passed &= reentrantStopSafe;
    printf("audio-unit-output-reentrant-stop: %s (%d)\n",
        reentrantStopSafe ? "PASS" : "FAIL",
        (int)state.reentrantStopStatus);

    usleep(100000);
    const uint32_t stoppedCount = state.callbackCount;
    const int stoppedIsQuiescent = stoppedCount == firstCount;
    passed &= stoppedIsQuiescent;
    printf("audio-unit-output-stop-quiescent: %s\n",
        stoppedIsQuiescent ? "PASS" : "FAIL");

    passed &= report_status("audio-unit-output-restart",
        AudioOutputUnitStart(unit));
    usleep(200000);
    passed &= report_status("audio-unit-output-restop",
        AudioOutputUnitStop(unit));
    const uint32_t secondCount = state.callbackCount;
    const int restartRendered = secondCount > stoppedCount;
    passed &= restartRendered;
    printf("audio-unit-output-restart-rendered: %s (callbacks=%u)\n",
        restartRendered ? "PASS" : "FAIL", (unsigned)secondCount);

    passed &= report_status("audio-unit-output-uninitialize",
        AudioUnitUninitialize(unit));
    passed &= report_status("audio-unit-output-dispose",
        AudioComponentInstanceDispose(unit));
    return !passed;
}
