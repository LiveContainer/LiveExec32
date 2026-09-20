#import <LC32/LC32.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <stdint.h>
#include "LC32UIKitCompatibility.h"
#if LC32_UIKIT_COMPATIBILITY

static uint64_t LC32HostLegacyControllerOrientation;

@implementation UIViewController (LC32LegacyOrientation)

+ (void)load {
    if(!LC32GuestUIKitLegacyCompatibilityEnabled()) return;
    const uint64_t sdkFunction = LC32Dlsym(
        "LC32GetGuestExecutableSDKVersion", YES);
    const uint32_t sdk = sdkFunction ? LC32InvokeHostCRet32(sdkFunction) : 0;
    if(!sdk || sdk >= 0x80000) return;
    LC32HostLegacyControllerOrientation = LC32Dlsym(
        "LC32UIKitGetLegacyControllerOrientation", YES);
    if(!LC32HostLegacyControllerOrientation) return;
    Method original = class_getInstanceMethod(
        self, @selector(interfaceOrientation));
    Method compatibility = class_getInstanceMethod(
        self, @selector(lc32_interfaceOrientation));
    if(original && compatibility)
        method_exchangeImplementations(original, compatibility);
}

- (UIInterfaceOrientation)lc32_interfaceOrientation {
    const uint64_t host = self.host_self;
    if(LC32HostLegacyControllerOrientation) {
        const UIInterfaceOrientation fallback = (UIInterfaceOrientation)
            LC32InvokeHostCRet32(LC32HostLegacyControllerOrientation,
                (uint32_t)host, (uint32_t)(host >> 32));
        if(fallback != UIInterfaceOrientationUnknown) return fallback;
    }

    /* The exchanged generated method uses _cmd, so forward the public
     * selector explicitly instead of calling it under the lc32_ name. */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(interfaceOrientation), NO);
    return (UIInterfaceOrientation)(uint32_t)LC32InvokeHostSelector(
        host, selector, (uint64_t)0);
}

@end
#endif // LC32_UIKIT_COMPATIBILITY
