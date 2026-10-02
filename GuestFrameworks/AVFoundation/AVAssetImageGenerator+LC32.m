#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <LC32/LC32.h>

@implementation AVAssetImageGenerator (LC32Thumbnail)
- (CGImageRef)copyCGImageAtTime:(CMTime)time actualTime:(CMTime *)actualTime
        error:(NSError **)error {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    _Static_assert(sizeof(CMTime) == 24, "CMTime must match the native layout");
    // This API's pointer is a synchronous output, not an array or retained
    // buffer. Stage exactly one CMTime; never expose a guest stack pointer.
    CMTime hostActual = kCMTimeInvalid;
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(&descriptor, &hostActual, sizeof(hostActual));
    uint64_t hostError = 0;
    const uint64_t image = LC32InvokeHostSelector(self.host_self, selector,
        LC32HostAggregateArgument(&time),
        LC32HostSizedIndirectArgument(actualTime ? &descriptor : NULL),
        LC32HostIndirectArgument(error ? &hostError : NULL), (uint64_t)0);
    if(image && actualTime) *actualTime = hostActual;
    if(error) *error = hostError ? LC32HostToGuestObject(hostError) : nil;
    return (__bridge CGImageRef)LC32HostToGuestOwnedObject(image);
}
@end
