#import <CoreMedia/CoreMedia.h>

#include "bridge.h"
#include "../../GuestFrameworks/CoreMedia/LC32CoreMediaBridge.h"
#include <cstring>
#include <vector>

namespace {

bool Range(u32 address, size_t size) {
    return address && uint64_t(address) + size <= uint64_t(UINT32_MAX) + 1;
}

bool ReadCall(u32 address, LC32CoreMediaCall &call) {
    // Read only populated slots, retaining compatibility with the original
    // 24-byte requests (which may end at a guest page boundary).
    call = {};
    if(!Range(address, 8) || Dynarmic_mem_1read(address, 8, (char *)&call) ||
       call.version != LC32CoreMediaABIVersion ||
       call.slotCount > LC32CoreMediaMaxSlots) return false;
    const size_t size = 8 + call.slotCount * sizeof(uint64_t);
    return Range(address, size) &&
        Dynarmic_mem_1read(address, size, (char *)&call) == 0;
}

constexpr size_t MaxBytes = 16 * 1024 * 1024;
bool Read(u32 address, size_t size, void *output) {
    return !size || (size <= MaxBytes && Range(address, size) &&
        !Dynarmic_mem_1read(address, size, (char *)output));
}
bool Write(u32 address, u32 value) {
    return Range(address, sizeof(value)) &&
        !Dynarmic_mem_1write(address, sizeof(value), (char *)&value);
}
template<typename T> T Object(uint64_t value) {
    return reinterpret_cast<T>(uintptr_t(value));
}
CFAllocatorRef Allocator(uint64_t value) {
    const CFAllocatorRef allocators[] = {nullptr, kCFAllocatorSystemDefault,
        kCFAllocatorMalloc, kCFAllocatorMallocZone, kCFAllocatorNull};
    return allocators[value]; // caller validates the allocator identity
}
OSStatus Created(OSStatus status, CFTypeRef result, u32 output) {
    if(status) { if(result) CFRelease(result); return status; }
    u32 guest = LC32GuestObjectForOwnedHostObject(result);
    if(!guest) return kCMSampleBufferError_AllocationFailed;
    if(Write(output, guest)) return 0;
    (void)LC32InvokeGuestC(guest_dlsym("CFRelease"), false, 1, &guest);
    return kCMSampleBufferError_RequiredParameterMissing;
}

OSStatus CreateAudioFormat(const LC32CoreMediaCall &call) {
    const auto &s = call.slots;
    constexpr OSStatus bad = kCMFormatDescriptionError_InvalidParameter;
    if(call.slotCount != 8 || !Write(u32(s[7]), 0) || s[0] > 4) return bad;
    AudioStreamBasicDescription asbd;
    static_assert(sizeof(asbd) == 40 && sizeof(AudioChannelDescription) == 20);
    static_assert(offsetof(AudioChannelLayout, mChannelDescriptions) == 12);
    if(!Read(u32(s[1]), sizeof(asbd), &asbd) || s[2] > MaxBytes || s[4] > MaxBytes)
        return bad;
    std::vector<uint8_t> layout(s[2]), cookie(s[4]);
    if(!Read(u32(s[3]), layout.size(), layout.data()) ||
       !Read(u32(s[5]), cookie.size(), cookie.data())) return bad;
    if(!layout.empty()) {
        if(layout.size() < 12) return bad;
        u32 descriptions;
        memcpy(&descriptions, layout.data() + 8, sizeof(descriptions));
        if(descriptions > (layout.size() - 12) / sizeof(AudioChannelDescription)) return bad;
    }
    CMAudioFormatDescriptionRef format = nullptr;
    OSStatus status = CMAudioFormatDescriptionCreate(Allocator(s[0]), &asbd,
        layout.size(), layout.empty() ? nullptr : (AudioChannelLayout *)layout.data(),
        cookie.size(), cookie.empty() ? nullptr : cookie.data(),
        Object<CFDictionaryRef>(s[6]), &format);
    return Created(status, format, u32(s[7]));
}

OSStatus CreateSample(const LC32CoreMediaCall &call) {
    const auto &s = call.slots;
    if(call.slotCount != 12 || !Write(u32(s[11]), 0) || s[0] > 4)
        return kCMSampleBufferError_RequiredParameterMissing;
    // Never give native CoreMedia a guest code pointer or refcon. Async
    // make-data-ready callbacks need a separate lifetime/thread adapter.
    if(s[3]) return -4; // unimpErr
    const int32_t count = int32_t(s[6]), times = int32_t(s[7]), sizes = int32_t(s[9]);
    if(count < 0 || times < 0 || sizes < 0 ||
       (times != 0 && times != 1 && times != count) ||
       (sizes != 0 && sizes != 1 && sizes != count) ||
       uint32_t(times) > MaxBytes / sizeof(CMSampleTimingInfo) ||
       uint32_t(sizes) > MaxBytes / sizeof(size_t))
        return kCMSampleBufferError_InvalidEntryCount;
    static_assert(sizeof(CMSampleTimingInfo) == 72 && sizeof(CMTime) == 24);
    std::vector<CMSampleTimingInfo> timing(times);
    std::vector<u32> guestSizes(sizes);
    if(!Read(u32(s[8]), timing.size() * sizeof(timing[0]), timing.data()) ||
       !Read(u32(s[10]), guestSizes.size() * sizeof(u32), guestSizes.data()))
        return kCMSampleBufferError_RequiredParameterMissing;
    // ARM32 size_t entries are four bytes; native entries are eight.
    std::vector<size_t> nativeSizes(guestSizes.begin(), guestSizes.end());
    CMSampleBufferRef sample = nullptr;
    OSStatus status = CMSampleBufferCreate(Allocator(s[0]), Object<CMBlockBufferRef>(s[1]),
        s[2] != 0, nullptr, nullptr, Object<CMFormatDescriptionRef>(s[5]), count,
        times, timing.empty() ? nullptr : timing.data(), sizes,
        nativeSizes.empty() ? nullptr : nativeSizes.data(), &sample);
    return Created(status, sample, u32(s[11]));
}

OSStatus SetAudioData(const LC32CoreMediaCall &call) {
    const auto &s = call.slots;
    constexpr OSStatus bad = kCMSampleBufferError_RequiredParameterMissing;
    if(call.slotCount != 5 || !s[0] || s[1] > 4 || s[2] > 4) return bad;
    struct GuestBuffer { u32 channels, bytes, data; };
    static_assert(sizeof(GuestBuffer) == 12);
    u32 count;
    if(!Read(u32(s[4]), sizeof(count), &count) || !count || count > 256 ||
       !Range(u32(s[4]), sizeof(count) + size_t(count) * sizeof(GuestBuffer))) return bad;
    std::vector<GuestBuffer> guest(count);
    if(!Read(u32(s[4]) + 4, guest.size() * sizeof(guest[0]), guest.data())) return bad;
    std::vector<uint8_t> storage(offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer));
    auto *buffers = (AudioBufferList *)storage.data();
    buffers->mNumberBuffers = count;
    std::vector<std::vector<uint8_t>> audio(count);
    size_t total = 0;
    for(u32 i = 0; i < count; ++i) {
        if(guest[i].bytes > MaxBytes - total) return bad;
        total += guest[i].bytes;
        audio[i].resize(guest[i].bytes);
        if(!Read(guest[i].data, audio[i].size(), audio[i].data())) return bad;
        buffers->mBuffers[i] = {guest[i].channels, guest[i].bytes,
            audio[i].empty() ? nullptr : audio[i].data()};
    }
    // This API copies the PCM data; no temporary host pointer survives it.
    return CMSampleBufferSetDataBufferFromAudioBufferList(Object<CMSampleBufferRef>(s[0]),
        Allocator(s[1]), Allocator(s[2]), u32(s[3]), buffers);
}

CMSampleBufferRef SampleBuffer(const LC32CoreMediaCall &call) {
    return reinterpret_cast<CMSampleBufferRef>(
        static_cast<uintptr_t>(call.slots[0]));
}

} // namespace

extern "C" u32 LC32_CoreMedia_Dispatch(u32 operation, u32 guestCall) {
    LC32CoreMediaCall call;
    if(!ReadCall(guestCall, call))
        return operation >= LC32CMAudioFormatDescriptionCreate
            ? u32(kCMSampleBufferError_RequiredParameterMissing) : 0;
    switch(operation) {
        case LC32CMAudioFormatDescriptionCreate: return u32(CreateAudioFormat(call));
        case LC32CMSampleBufferCreate: return u32(CreateSample(call));
        case LC32CMSampleBufferSetDataBufferFromAudioBufferList: return u32(SetAudioData(call));
        case LC32CMSampleBufferSetDataReady:
            return call.slotCount == 1 && call.slots[0]
                ? u32(CMSampleBufferSetDataReady(SampleBuffer(call)))
                : u32(kCMSampleBufferError_RequiredParameterMissing);
        case LC32CMSampleBufferGetTypeID:
            if(call.slotCount != 0) return 0;
            return u32(CMSampleBufferGetTypeID());
        case LC32CMSampleBufferIsValid: {
            if(call.slotCount != 1) return 0;
            auto sampleBuffer = SampleBuffer(call);
            return sampleBuffer && CMSampleBufferIsValid(sampleBuffer);
        }
        case LC32CMSampleBufferGetImageBuffer: {
            if(call.slotCount != 1) return 0;
            auto sampleBuffer = SampleBuffer(call);
            CVImageBufferRef image = sampleBuffer
                ? CMSampleBufferGetImageBuffer(sampleBuffer) : nullptr;
            return image ? [(id)image guest_self] : 0;
        }
        case LC32CMSampleBufferGetPresentationTimeStamp: {
            if(call.slotCount != 2 || call.slots[1] > UINT32_MAX) return 0;
            const u32 output = u32(call.slots[1]);
            if(!Range(output, sizeof(LC32CoreMediaTime))) return 0;
            auto sampleBuffer = SampleBuffer(call);
            const CMTime time = sampleBuffer
                ? CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                : kCMTimeInvalid;
            LC32CoreMediaTime wire = {
                time.value, time.timescale, time.flags, time.epoch,
            };
            return Dynarmic_mem_1write(output, sizeof(wire), (char *)&wire) == 0;
        }
        default:
            return 0;
    }
}
