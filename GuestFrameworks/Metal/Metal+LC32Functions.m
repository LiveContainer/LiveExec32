#import <Metal/Metal.h>
#import <LC32/LC32.h>

#include <pthread.h>

static pthread_once_t LC32MetalDefaultDeviceOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32MetalDefaultDeviceAddress;

static void LC32ResolveMetalDefaultDevice(void) {
    if(!LC32LoadHostFramework("Metal")) return;
    LC32MetalDefaultDeviceAddress = LC32Dlsym(
        "LC32_Metal_MTLCreateSystemDefaultDevice", YES);
}

id<MTLDevice> MTLCreateSystemDefaultDevice(void) {
    pthread_once(&LC32MetalDefaultDeviceOnce,
        LC32ResolveMetalDefaultDevice);
    if(!LC32MetalDefaultDeviceAddress) return nil;

    return (id<MTLDevice>)(uintptr_t)LC32InvokeHostCRet32(
        LC32MetalDefaultDeviceAddress);
}
