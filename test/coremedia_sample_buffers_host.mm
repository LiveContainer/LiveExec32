#import <CoreMedia/CoreMedia.h>
#include "coremedia-stubs/bridge.h"
#include "../GuestFrameworks/CoreMedia/LC32CoreMediaBridge.h"
#include <cstdio>
#include <cstring>
#include <map>
#include <vector>

static unsigned char memory[65536];
static std::map<u32, CFTypeRef> objects;
static u32 nextObject = 0x90000000;
static unsigned checks, failures, outputWrites;
static bool failResultWrite;
int Dynarmic_mem_1read(u32 address, u32 bytes, char *out) {
    if(address < 0x1000 || address > sizeof(memory) || bytes > sizeof(memory) - address) return -1;
    memcpy(out, memory + address, bytes); return 0;
}
int Dynarmic_mem_1write(u32 address, u32 bytes, const char *in) {
    if(address < 0x1000 || address > sizeof(memory) || bytes > sizeof(memory) - address) return -1;
    if(address == 0x2000 && ++outputWrites == 2 && failResultWrite) return -1;
    memcpy(memory + address, in, bytes); return 0;
}
u32 LC32GuestObjectForOwnedHostObject(CFTypeRef object) {
    if(!object) return 0;
    objects[++nextObject] = object; return nextObject;
}
u32 guest_dlsym(const char *) { return 1; }
uint64_t LC32InvokeGuestC(u32, bool, int, u32 *args) {
    CFRelease(objects.at(args[0])); objects.erase(args[0]); return 0;
}
@implementation NSObject (CoreMediaFixture)
- (u32)guest_self { return 0; }
@end
#include "../HostFrameworks/CoreMedia/CoreMedia.mm"

static void check(const char *name, bool pass) {
    printf("coremedia-sample-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
template<typename T> static void put(u32 address, const T &value) {
    memcpy(memory + address, &value, sizeof(value));
}
static u32 output() { u32 value; memcpy(&value, memory + 0x2000, 4); return value; }
static OSStatus invoke(u32 opcode, std::initializer_list<uint64_t> slots) {
    LC32CoreMediaCall call = {1, u32(slots.size()), {}};
    std::copy(slots.begin(), slots.end(), call.slots);
    put(0x1000, call); outputWrites = 0;
    return OSStatus(LC32_CoreMedia_Dispatch(opcode, 0x1000));
}
static AudioStreamBasicDescription format = {44100, kAudioFormatLinearPCM,
    kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
static OSStatus createFormat(u32 layoutSize = 0, u32 layout = 0) {
    put(0x3000, format);
    return invoke(LC32CMAudioFormatDescriptionCreate, {0, 0x3000, layoutSize, layout, 0, 0, 0, 0x2000});
}
static OSStatus createSample(CFTypeRef desc, int32_t entries = 1, u32 callback = 0) {
    CMSampleTimingInfo timing = {CMTimeMake(1, 44100), CMTimeMake(123, 7), kCMTimeInvalid};
    put(0x4000, timing); put(0x5000, u32(4)); put(0x5004, u32(0xaabbccdd));
    return invoke(LC32CMSampleBufferCreate, {0, 0, 0, callback, 0, uintptr_t(desc),
        4, 1, 0x4000, uint32_t(entries), 0x5000, 0x2000});
}
int main() {
    @autoreleasepool {
        put(0x1ffc, u32(0x12345678)); put(0x2004, u32(0x87654321));
        check("format-create", createFormat() == 0 && output());
        auto desc = (CMAudioFormatDescriptionRef)objects.at(output());
        check("format-fields", !memcmp(CMAudioFormatDescriptionGetStreamBasicDescription(desc), &format, sizeof(format)));
        check("output-width", !memcmp(memory + 0x1ffc, "\x78\x56\x34\x12", 4) &&
            !memcmp(memory + 0x2004, "\x21\x43\x65\x87", 4));
        check("sample-create", createSample(desc) == 0 && output());
        auto sample = (CMSampleBufferRef)objects.at(output());
        check("sample-count", CMSampleBufferGetNumSamples(sample) == 4);
        check("timing-copy", CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), CMTimeMake(123, 7)) == 0);
        check("32-bit-size-array", CMSampleBufferGetSampleSize(sample, 0) == 4 && CMSampleBufferGetTotalSampleSize(sample) == 16);
        check("initially-not-ready", !CMSampleBufferDataIsReady(sample));
        const u32 list[] = {1, 2, 16, 0x7000};
        memcpy(memory + 0x6000, list, sizeof(list));
        for(unsigned i = 0; i < 16; ++i) memory[0x7000+i] = i + 1;
        check("audio-data-copy", invoke(LC32CMSampleBufferSetDataBufferFromAudioBufferList,
            {uintptr_t(sample), 0, 0, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, 0x6000}) == 0);
        memset(memory + 0x7000, 0xa5, 16);
        uint8_t bytes[16] = {};
        check("native-block-buffer", CMBlockBufferCopyDataBytes(CMSampleBufferGetDataBuffer(sample), 0, 16, bytes) == 0);
        bool copied = true; for(unsigned i = 0; i < 16; ++i) copied &= bytes[i] == i + 1;
        check("owns-pcm-copy", copied);
        check("already-has-data", invoke(LC32CMSampleBufferSetDataBufferFromAudioBufferList,
            {uintptr_t(sample), 0, 0, 0, 0x6000}) == kCMSampleBufferError_AlreadyHasDataBuffer);
        check("set-ready", invoke(LC32CMSampleBufferSetDataReady, {uintptr_t(sample)}) == 0 && CMSampleBufferDataIsReady(sample));
        check("guest-getter-unchanged", invoke(LC32CMSampleBufferIsValid, {uintptr_t(sample)}) == 1);
        // Old requests need only header + declared slots, not the enlarged struct.
        LC32CoreMediaCall old = {1, 1, {uintptr_t(sample)}};
        memcpy(memory + sizeof(memory) - 16, &old, 16);
        check("old-request-page-boundary", LC32_CoreMedia_Dispatch(LC32CMSampleBufferIsValid, sizeof(memory) - 16) == 1);
        check("reject-ready-null", invoke(LC32CMSampleBufferSetDataReady, {0}) != 0);
        check("reject-callback", createSample(desc, 1, 0x1234) == -4 && !output());
        check("reject-invalid-count", createSample(desc, 2) == kCMSampleBufferError_InvalidEntryCount && !output());
        check("reject-negative-count", createSample(desc, -1) == kCMSampleBufferError_InvalidEntryCount && !output());
        check("reject-format-pointer", invoke(LC32CMAudioFormatDescriptionCreate, {0, 0xfffffff0, 0, 0, 0, 0, 0, 0x2000}) != 0 && !output());
        check("reject-cookie-pointer", invoke(LC32CMAudioFormatDescriptionCreate, {0, 0x3000, 0, 0, 4, 0, 0, 0x2000}) != 0);
        check("reject-custom-allocator", invoke(LC32CMAudioFormatDescriptionCreate, {UINT64_MAX, 0x3000, 0, 0, 0, 0, 0, 0x2000}) != 0);
        u32 channelLayout[] = {kAudioChannelLayoutTag_Stereo, 0, 0};
        memcpy(memory + 0x6000, channelLayout, sizeof(channelLayout));
        check("channel-layout", createFormat(12, 0x6000) == 0);
        put(0x6008, u32(100));
        check("reject-truncated-channel-layout", createFormat(12, 0x6000) != 0);
        check("reject-short-channel-layout", createFormat(4, 0x6000) != 0);
        put(0x6000, u32(0xffffffff));
        check("reject-buffer-count", invoke(LC32CMSampleBufferSetDataBufferFromAudioBufferList,
            {uintptr_t(sample), 0, 0, 0, 0x6000}) != 0);
        const auto before = objects.size(); failResultWrite = true;
        check("failed-output-release", createFormat() != 0 && objects.size() == before);
        failResultWrite = false;
        check("malformed-request", OSStatus(LC32_CoreMedia_Dispatch(LC32CMSampleBufferCreate, 0xfffffff0)) != 0);
        for(auto &entry : objects) CFRelease(entry.second);
        objects.clear();
    }
    printf("coremedia-sample-host: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
