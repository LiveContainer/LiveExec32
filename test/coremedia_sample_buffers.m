#import <CoreMedia/CoreMedia.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks, failures;
static void check(const char *name, int pass) {
    printf("coremedia-sample-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static OSStatus unsupportedCallback(CMSampleBufferRef sample, void *refcon) {
    (void)sample; (void)refcon;
    return -1;
}
int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        for(unsigned planar = 0; planar < 2; ++planar) {
            AudioStreamBasicDescription asbd = {44100, kAudioFormatLinearPCM,
                kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |
                    (planar ? kAudioFormatFlagIsNonInterleaved : 0),
                planar ? 2 : 4, 1, planar ? 2 : 4, 2, 16, 0};
            struct { uint32_t before; CMAudioFormatDescriptionRef value; uint32_t after; }
                format = {0x12345678, NULL, 0x87654321};
            OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorSystemDefault,
                &asbd, 0, NULL, 0, NULL, NULL, &format.value);
            check("create-format", status == 0 && format.value);
            check("format-output-canaries", format.before == 0x12345678 && format.after == 0x87654321);
            if(!format.value) continue;
            CMSampleTimingInfo timing = {CMTimeMake(1, 44100), CMTimeMake(123, 7), kCMTimeInvalid};
            size_t bytesPerSample = asbd.mBytesPerFrame;
            CMSampleBufferRef sample = NULL;
            status = CMSampleBufferCreate(NULL, NULL, false, NULL, NULL, format.value,
                4096, 1, &timing, planar ? 0 : 1, planar ? NULL : &bytesPerSample, &sample);
            CFRelease(format.value);
            check("create-sample", status == 0 && sample);
            if(!sample) continue;
            check("sample-type", CFGetTypeID(sample) == CMSampleBufferGetTypeID());
            check("sample-valid", CMSampleBufferIsValid(sample));
            check("sample-timestamp", CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), timing.presentationTimeStamp) == 0);
            check("audio-has-no-image", CMSampleBufferGetImageBuffer(sample) == NULL);
            const unsigned count = planar ? 2 : 1;
            const size_t bytes = 4096 * asbd.mBytesPerFrame;
            AudioBufferList *buffers = calloc(1, offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer));
            buffers->mNumberBuffers = count;
            for(unsigned i = 0; i < count; ++i) {
                buffers->mBuffers[i] = (AudioBuffer){planar ? 1 : 2, (UInt32)bytes, malloc(bytes)};
                memset(buffers->mBuffers[i].mData, 0x19 + i, bytes);
            }
            status = CMSampleBufferSetDataBufferFromAudioBufferList(sample, NULL, NULL,
                kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, buffers);
            check("set-audio-data", status == 0);
            check("duplicate-data-error", CMSampleBufferSetDataBufferFromAudioBufferList(sample,
                NULL, NULL, 0, buffers) == kCMSampleBufferError_AlreadyHasDataBuffer);
            for(unsigned i = 0; i < count; ++i) free(buffers->mBuffers[i].mData);
            free(buffers);
            check("set-ready-after-freeing-input", CMSampleBufferSetDataReady(sample) == 0);
            CFRelease(sample);
        }
        check("null-ready-error", CMSampleBufferSetDataReady(NULL) != 0);
#if !__LP64__
        CMSampleBufferRef rejected = (CMSampleBufferRef)1;
        check("unsupported-callback-error", CMSampleBufferCreate(NULL, NULL, false,
            unsupportedCallback, NULL, NULL, 0, 0, NULL, 0, NULL, &rejected) == -4 && !rejected);
#else
        (void)unsupportedCallback;
#endif
    }
    printf("coremedia-sample-guest: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
