#import <LC32/LC32.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <pthread.h>
#include <stdint.h>
#include "LC32UIKitCompatibility.h"

#if LC32_UIKIT_COMPATIBILITY
static pthread_once_t LC32LegacyOrientationOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32HostLegacyOrientation;
static uint64_t LC32HostLegacyStatusBarOrientation;

static void LC32ResolveLegacyOrientation(void) {
    if(!LC32GuestUIKitLegacyCompatibilityEnabled()) return;
    LC32HostLegacyOrientation = LC32Dlsym(
        "LC32UIKitHandleLegacyStatusBarOrientation", YES);
    LC32HostLegacyStatusBarOrientation = LC32Dlsym(
        "LC32UIKitGetLegacyStatusBarOrientation", YES);
}

static BOOL LC32NeedsLegacyStatusBarOrientationOverride(void) {
    pthread_once(&LC32LegacyOrientationOnce,
        LC32ResolveLegacyOrientation);
    if(!LC32HostLegacyStatusBarOrientation) return NO;

    return (UIInterfaceOrientation)LC32InvokeHostCRet32(
        LC32HostLegacyStatusBarOrientation) !=
        UIInterfaceOrientationUnknown;
}

static void LC32ForwardLegacyOrientation(
        UIInterfaceOrientation orientation) {
    pthread_once(&LC32LegacyOrientationOnce,
        LC32ResolveLegacyOrientation);
    if(!LC32HostLegacyOrientation) return;
    LC32InvokeHostCRet32(LC32HostLegacyOrientation,
        (uint32_t)orientation, (uint32_t)0);
}

#endif

@implementation UIApplication (LC32LegacyOrientation)

#if LC32_UIKIT_COMPATIBILITY
+ (void)load {
    /* Most phone applications must keep the generated direct forwarder.
     * Install this override only for the fixed legacy canvases whose scene
     * orientation and guest projection need to remain paired. Besides
     * avoiding an extra bridge round trip, this leaves applications that
     * manage both landscape sides themselves (such as old movie-based
     * launchers) completely untouched. */
    if(!LC32NeedsLegacyStatusBarOrientationOverride()) return;

    Method original = class_getInstanceMethod(
        self, @selector(statusBarOrientation));
    Method compatibility = class_getInstanceMethod(
        self, @selector(lc32_statusBarOrientation));
    if(original && compatibility) {
        method_exchangeImplementations(original, compatibility);
    }
}

- (UIInterfaceOrientation)lc32_statusBarOrientation {
    pthread_once(&LC32LegacyOrientationOnce,
        LC32ResolveLegacyOrientation);
    if(LC32HostLegacyStatusBarOrientation) {
        const UIInterfaceOrientation orientation =
            (UIInterfaceOrientation)LC32InvokeHostCRet32(
            LC32HostLegacyStatusBarOrientation);
        if(orientation != UIInterfaceOrientationUnknown) {
            return orientation;
        }
    }

    /* The generated forwarder uses _cmd, so calling its exchanged IMP would
     * incorrectly ask native UIApplication for lc32_statusBarOrientation.
     * Forward the original selector explicitly when the compatibility host
     * has no legacy-canvas override. */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(statusBarOrientation), NO);
    return (UIInterfaceOrientation)(uint32_t)LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0);
}

#endif // LC32_UIKIT_COMPATIBILITY

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation {
    /* GenerateShimAPI deliberately omits this obsolete forwarding shim.
     * Modern UIApplication ignores it, while LC32's host scene adapter must
     * retain the old app's orientation intent. Calling the UIKit-specific C
     * bridge here keeps that policy out of the generic Objective-C bridge. */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
                        animated:(BOOL)animated {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation,
        (uint64_t)(animated != NO), (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
                     animation:(int)animation duration:(NSTimeInterval)duration {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, (uint64_t)(int64_t)animation,
        (double)duration, (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
           animationParameters:(id)parameters {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
    const uint64_t hostParameters = [parameters host_self];
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, hostParameters, (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
           animationParameters:(id)parameters notifySpringBoardAndFence:(BOOL)notify {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
    const uint64_t hostParameters = [parameters host_self];
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, hostParameters,
        (uint64_t)(notify != NO), (uint64_t)0);
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation
           animationParameters:(id)parameters notifySpringBoardAndFence:(BOOL)notify
                   updateBlock:(id)update {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t hostSelf = self.host_self;
    const uint64_t hostParameters = [parameters host_self];
    // Preserve the existing NSBlock bridge and the block's actual signature;
    // this orientation adapter must not guess its ABI or run it eagerly.
    const uint64_t hostUpdate = [update host_self];
#if LC32_UIKIT_COMPATIBILITY
    LC32ForwardLegacyOrientation(orientation);
#endif
    LC32InvokeHostSelector(hostSelf, selector,
        (uint64_t)(int64_t)orientation, hostParameters,
        (uint64_t)(notify != NO), hostUpdate, (uint64_t)0);
}

@end
