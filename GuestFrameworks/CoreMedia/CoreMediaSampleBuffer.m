#import <CoreMedia/CoreMedia.h>
#import <LC32/LC32.h>
#import "LC32CoreMediaBridge.h"

#include <pthread.h>
#include <string.h>

static pthread_once_t dispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t dispatcherAddress;

static void ResolveDispatcher(void) {
    dispatcherAddress = LC32Dlsym("LC32_CoreMedia_Dispatch", YES);
}

static uint32_t Dispatch(LC32CoreMediaOpcode opcode,
                         const uint64_t *slots, uint32_t count) {
    pthread_once(&dispatcherOnce, ResolveDispatcher);
    if(!dispatcherAddress || count > LC32CoreMediaMaxSlots)
        return opcode >= LC32CMAudioFormatDescriptionCreate ? (uint32_t)-4 : 0;
    LC32CoreMediaCall call = { .version = LC32CoreMediaABIVersion,
                              .slotCount = count };
    if(count) memcpy(call.slots, slots, count * sizeof(*slots));
    return LC32InvokeHostCRet32(dispatcherAddress, (uint32_t)opcode,
                              (uint32_t)(uintptr_t)&call);
}

static uint64_t Host(CFTypeRef object) {
    return object ? [(id)object host_self] : 0;
}

// Guest allocator constants are identities, not Objective-C proxies.
static uint64_t Allocator(CFAllocatorRef allocator) {
    if(!allocator) return 0;
    if(allocator == kCFAllocatorSystemDefault) return 1;
    if(allocator == kCFAllocatorMalloc) return 2;
    if(allocator == kCFAllocatorMallocZone) return 3;
    if(allocator == kCFAllocatorNull) return 4;
    return UINT64_MAX; // custom guest callbacks are not native allocators
}

OSStatus CMAudioFormatDescriptionCreate(CFAllocatorRef allocator,
        const AudioStreamBasicDescription *asbd, size_t layoutSize,
        const AudioChannelLayout *layout, size_t cookieSize, const void *cookie,
        CFDictionaryRef extensions, CMAudioFormatDescriptionRef *output) {
    const uint64_t slots[] = {Allocator(allocator), (uintptr_t)asbd,
        layoutSize, (uintptr_t)layout, cookieSize, (uintptr_t)cookie,
        Host(extensions), (uintptr_t)output};
    return (OSStatus)Dispatch(LC32CMAudioFormatDescriptionCreate, slots, 8);
}

OSStatus CMSampleBufferCreate(CFAllocatorRef allocator, CMBlockBufferRef data,
        Boolean ready, CMSampleBufferMakeDataReadyCallback callback, void *refcon,
        CMFormatDescriptionRef format, CMItemCount samples, CMItemCount timingCount,
        const CMSampleTimingInfo *timing, CMItemCount sizeCount, const size_t *sizes,
        CMSampleBufferRef *output) {
    const uint64_t slots[] = {Allocator(allocator), Host(data), ready,
        (uintptr_t)callback, (uintptr_t)refcon, Host(format), (uint32_t)samples,
        (uint32_t)timingCount, (uintptr_t)timing, (uint32_t)sizeCount,
        (uintptr_t)sizes, (uintptr_t)output};
    return (OSStatus)Dispatch(LC32CMSampleBufferCreate, slots, 12);
}

OSStatus CMSampleBufferSetDataBufferFromAudioBufferList(CMSampleBufferRef sample,
        CFAllocatorRef structureAllocator, CFAllocatorRef memoryAllocator,
        uint32_t flags, const AudioBufferList *buffers) {
    const uint64_t slots[] = {Host(sample), Allocator(structureAllocator),
        Allocator(memoryAllocator), flags, (uintptr_t)buffers};
    return (OSStatus)Dispatch(LC32CMSampleBufferSetDataBufferFromAudioBufferList, slots, 5);
}

OSStatus CMSampleBufferSetDataReady(CMSampleBufferRef sample) {
    const uint64_t slots[] = {Host(sample)};
    return (OSStatus)Dispatch(LC32CMSampleBufferSetDataReady, slots, 1);
}

CFTypeID CMSampleBufferGetTypeID(void) {
    return (CFTypeID)Dispatch(LC32CMSampleBufferGetTypeID, NULL, 0);
}

Boolean CMSampleBufferIsValid(CMSampleBufferRef sampleBuffer) {
    const uint64_t slots[] = {Host(sampleBuffer)};
    return Dispatch(LC32CMSampleBufferIsValid, slots, 1) != 0;
}

CVImageBufferRef CMSampleBufferGetImageBuffer(CMSampleBufferRef sampleBuffer) {
    const uint64_t slots[] = {Host(sampleBuffer)};
    // A Get result remains borrowed from its sample buffer. Do not retain it
    // or apply the owned Create/Copy conversion on either side of the bridge.
    return (CVImageBufferRef)(uintptr_t)Dispatch(
        LC32CMSampleBufferGetImageBuffer, slots, 1);
}

CMTime CMSampleBufferGetPresentationTimeStamp(CMSampleBufferRef sampleBuffer) {
    LC32CoreMediaTime time = {0};
    const uint64_t slots[] = {
        Host(sampleBuffer), (uint32_t)(uintptr_t)&time,
    };
    if(!Dispatch(LC32CMSampleBufferGetPresentationTimeStamp, slots, 2))
        return kCMTimeInvalid;
    return (CMTime){time.value, time.timescale, time.flags, time.epoch};
}
