#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

const MTLRegion MPSRectNoClip = {
    .origin = { 0, 0, 0 },
    .size = { NSUIntegerMax, NSUIntegerMax, NSUIntegerMax },
};

BOOL MPSSupportsMTLDevice(id<MTLDevice> device) {
    /* LiveExec32 only runs on 64-bit iOS-class Metal devices, all of which
     * satisfy the minimum GPU requirement of the iOS 10.3 MPS framework. */
    return device != nil;
}
