#import <LC32/LC32.h>
#import <UIKit/UIKit.h>

#include <pthread.h>
#include <stdint.h>

static pthread_once_t LC32LegacyOrientationOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32HostLegacyOrientation;

static void LC32ResolveLegacyOrientation(void) {
    LC32HostLegacyOrientation = LC32Dlsym(
        "LC32UIKitHandleLegacyStatusBarOrientation", YES);
}

static void LC32ForwardLegacyOrientation(
        UIInterfaceOrientation orientation) {
    pthread_once(&LC32LegacyOrientationOnce,
        LC32ResolveLegacyOrientation);
    if(!LC32HostLegacyOrientation) return;
    LC32InvokeHostCRet32(LC32HostLegacyOrientation,
        (uint32_t)orientation, (uint32_t)0);
}

@implementation UIApplication (LC32LegacyOrientation)

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation {
    /* GenerateShimAPI deliberately omits this obsolete forwarding shim.
     * Modern UIApplication ignores it, while LC32's host scene adapter must
     * retain the old app's orientation intent. Calling the UIKit-specific C
     * bridge here keeps that policy out of the generic Objective-C bridge. */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
    LC32ForwardLegacyOrientation(orientation);
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
                        animated:(BOOL)animated {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
    LC32ForwardLegacyOrientation(orientation);
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation,
        (uint64_t)(animated != NO), (uint64_t)0);
}

@end
