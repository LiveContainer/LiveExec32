#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stddef.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef LC32_EXT_AUDIO_NATIVE_CHECK
_Static_assert(sizeof(ExtAudioFileRef) == 4, "guest wrapper tokens must be 4 bytes");
#endif

typedef struct {
    uint32_t before;
    ExtAudioFileRef file;
    uint32_t after;
} GuardedWrapper;
_Static_assert(offsetof(GuardedWrapper, after) ==
    offsetof(GuardedWrapper, file) + sizeof(ExtAudioFileRef), "immediate output canary");

static const int16_t samples[] = {-32768, -1234, 0, 1234, 22222, 32767};
static int failures;

static int check(const char *name, int condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
    return condition;
}

static int statusOK(const char *name, OSStatus status) {
    printf("%s: %s (%d)\n", name, status == noErr ? "PASS" : "FAIL", (int)status);
    failures += status != noErr;
    return status == noErr;
}

static int canariesIntact(const GuardedWrapper *guard) {
    return guard->before == 0x13579bdf && guard->after == 0xfedcba98;
}

static AudioStreamBasicDescription pcmFormat(void) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 8000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = format.mBytesPerFrame = 2;
    format.mFramesPerPacket = format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;
    return format;
}

static int matchesPCM(const AudioStreamBasicDescription *format) {
    return format->mSampleRate == 8000.0 && format->mFormatID == kAudioFormatLinearPCM &&
        format->mChannelsPerFrame == 1 && format->mBitsPerChannel == 16 &&
        format->mBytesPerFrame == 2 && format->mFramesPerPacket == 1;
}

static void checkWrapperFormats(ExtAudioFileRef wrapper) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof(format);
    if(statusOK("wrap-get-file-format", ExtAudioFileGetProperty(wrapper,
            kExtAudioFileProperty_FileDataFormat, &size, &format))) {
        check("wrap-file-format-value", size == sizeof(format) && matchesPCM(&format));
    }
    format = pcmFormat();
    statusOK("wrap-set-client-format", ExtAudioFileSetProperty(wrapper,
        kExtAudioFileProperty_ClientDataFormat, sizeof(format), &format));
    memset(&format, 0, sizeof(format));
    size = sizeof(format);
    if(statusOK("wrap-get-client-format", ExtAudioFileGetProperty(wrapper,
            kExtAudioFileProperty_ClientDataFormat, &size, &format))) {
        check("wrap-client-format-value", size == sizeof(format) && matchesPCM(&format));
    }
}

static ExtAudioFileRef wrap(AudioFileID original, Boolean forWriting) {
    GuardedWrapper guard = {0x13579bdf, NULL, 0xfedcba98};
    OSStatus result = ExtAudioFileWrapAudioFileID(original, forWriting, &guard.file);
    int success = statusOK(forWriting ? "wrap-writing" : "wrap-reading", result);
    success &= check("wrap-output-canaries", canariesIntact(&guard));
    success &= check("wrap-output-token-nonnull", guard.file != NULL);
    return success ? guard.file : NULL;
}

static void checkUnderlyingFile(AudioFileID original) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof(format);
    if(statusOK("original-property-after-wrapper-dispose", AudioFileGetProperty(original,
            kAudioFilePropertyDataFormat, &size, &format))) {
        check("original-format-after-wrapper-dispose", matchesPCM(&format));
    }
    int16_t output[6] = {0};
    UInt32 bytes = sizeof(output);
    OSStatus result = AudioFileReadBytes(original, false, 0, &bytes, output);
    check("original-read-after-wrapper-dispose", (result == noErr ||
        result == kAudioFileEndOfFileError) && bytes == sizeof(samples) &&
        memcmp(output, samples, sizeof(samples)) == 0);
}

static void readWrapper(AudioFileID original) {
    ExtAudioFileRef wrapper = wrap(original, false);
    if(!wrapper) return;
    checkWrapperFormats(wrapper);
    int16_t output[6] = {0};
    AudioBufferList buffers = {1, {{1, sizeof(output), output}}};
    UInt32 frames = 6;
    if(statusOK("wrap-read-frames", ExtAudioFileRead(wrapper, &frames, &buffers))) {
        check("wrap-read-samples", frames == 6 &&
            memcmp(output, samples, sizeof(samples)) == 0);
    }
    statusOK("wrap-seek", ExtAudioFileSeek(wrapper, 2));
    memset(output, 0, sizeof(output));
    buffers.mBuffers[0].mDataByteSize = sizeof(output);
    frames = 2;
    if(statusOK("wrap-read-after-seek", ExtAudioFileRead(wrapper, &frames, &buffers))) {
        check("wrap-seek-samples", frames == 2 && output[0] == samples[2] &&
            output[1] == samples[3]);
    }
    statusOK("wrap-dispose-reading", ExtAudioFileDispose(wrapper));
    checkUnderlyingFile(original);
}

#ifndef LC32_EXT_AUDIO_NATIVE_CHECK
// NULL/stale native AudioFileID values are outside Apple's documented input
// contract. Exercise only the guest token layer's safe rejection policy.
static void checkInvalidInputs(AudioFileID valid) {
    GuardedWrapper guard = {0x13579bdf, NULL, 0xfedcba98};
    AudioFileID nullFile = NULL;
    ExtAudioFileRef *nullOutput = NULL;
    check("wrap-null-input-rejected",
        ExtAudioFileWrapAudioFileID(nullFile, false, &guard.file) != noErr);
    check("wrap-invalid-input-canaries", canariesIntact(&guard));
    check("wrap-null-output-rejected",
        ExtAudioFileWrapAudioFileID(valid, false, nullOutput) != noErr);
}

static void checkStaleInput(AudioFileID stale) {
    GuardedWrapper guard = {0x13579bdf, NULL, 0xfedcba98};
    check("wrap-closed-original-rejected",
        ExtAudioFileWrapAudioFileID(stale, false, &guard.file) != noErr);
    check("wrap-stale-input-canaries", canariesIntact(&guard));
}
#endif

static void testCAF(const char *temporaryDirectory) {
    if(!temporaryDirectory) temporaryDirectory = getenv("TMPDIR");
    if(!temporaryDirectory || !temporaryDirectory[0]) temporaryDirectory = "/private/tmp";
    char path[PATH_MAX];
    int pathLength = snprintf(path, sizeof(path), "%s/lc32-ext-audio-wrap.XXXXXX",
        temporaryDirectory);
    if(!check("wrap-temporary-path", pathLength > 0 &&
            (size_t)pathLength < sizeof(path))) return;
    int fd = mkstemp(path);
    if(!check("wrap-create-temporary-file", fd >= 0)) { perror(path); return; }
    close(fd);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
        (const UInt8 *)path, strlen(path), false);
    if(!check("wrap-create-file-url", url != NULL)) { unlink(path); return; }
    AudioStreamBasicDescription format = pcmFormat();
    AudioFileID original = NULL;
    if(statusOK("wrap-create-caf", AudioFileCreateWithURL(url, kAudioFileCAFType,
            &format, kAudioFileFlags_EraseFile, &original)) && original) {
#ifndef LC32_EXT_AUDIO_NATIVE_CHECK
        checkInvalidInputs(original);
#endif
        // forWriting requires a newly created file. The guest currently has
        // no ExtAudioFileWrite shim; exercise its mode and format setup, then
        // write through the still-open original after disposing the wrapper.
        ExtAudioFileRef writer = wrap(original, true);
        if(writer) {
            checkWrapperFormats(writer);
            statusOK("wrap-dispose-writing", ExtAudioFileDispose(writer));
        }
        UInt32 bytes = sizeof(samples);
        statusOK("original-write-after-wrapper-dispose",
            AudioFileWriteBytes(original, false, 0, &bytes, samples));
        check("original-written-byte-count", bytes == sizeof(samples));
        checkUnderlyingFile(original);
        statusOK("original-close-after-writing", AudioFileClose(original));
#ifndef LC32_EXT_AUDIO_NATIVE_CHECK
        checkStaleInput(original);
#endif
    }
    original = NULL;
    if(statusOK("wrap-reopen-caf", AudioFileOpenURL(url, kAudioFileReadPermission,
            kAudioFileCAFType, &original)) && original) {
        readWrapper(original);
        statusOK("original-close-after-reading", AudioFileClose(original));
    }
    CFRelease(url);
    check("wrap-remove-temporary-file", unlink(path) == 0);
}

// Mono signed little-endian PCM WAV containing the same six sample values.
static const UInt8 wave[] = {
    'R','I','F','F', 48,0,0,0, 'W','A','V','E',
    'f','m','t',' ', 16,0,0,0, 1,0,1,0, 0x40,0x1f,0,0,
    0x80,0x3e,0,0, 2,0,16,0, 'd','a','t','a', 12,0,0,0,
    0,0x80, 0x2e,0xfb, 0,0, 0xd2,4, 0xce,0x56, 0xff,0x7f
};

typedef struct { unsigned reads; unsigned sizes; } MemoryFile;

static OSStatus readMemory(void *context, SInt64 position, UInt32 requested,
                            void *buffer, UInt32 *actual) {
    MemoryFile *file = context;
    ++file->reads;
    *actual = 0;
    if(position < 0) return kAudio_ParamError;
    if((UInt64)position >= sizeof(wave)) return noErr;
    size_t available = sizeof(wave) - (size_t)position;
    *actual = requested < available ? requested : (UInt32)available;
    memcpy(buffer, wave + (size_t)position, *actual);
    return noErr;
}

static SInt64 sizeMemory(void *context) {
    ++((MemoryFile *)context)->sizes;
    return sizeof(wave);
}

static void testCallbackFile(void) {
    MemoryFile context = {0};
    AudioFileID original = NULL;
    if(statusOK("wrap-open-callback-wav", AudioFileOpenWithCallbacks(&context,
            readMemory, NULL, sizeMemory, NULL, kAudioFileWAVEType, &original)) && original) {
        readWrapper(original);
        check("wrap-callback-context-used", context.reads > 0 && context.sizes > 0);
        statusOK("original-close-callback-file", AudioFileClose(original));
    }
}

int main(int argc, char **argv) {
    // A CLI guest's synthetic TMPDIR need not exist on its host. Accept the
    // same explicit host-visible scratch directory as other audio-file tests.
    testCAF(argc > 1 ? argv[1] : NULL);
    testCallbackFile();
    return failures != 0;
}
