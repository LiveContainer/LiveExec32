// Exercise the real guest category against a recording host, without UIKit UI.
// This checks forwarding and policy gating, not private-selector OS availability.
#import <UIKit/UIKit.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../GuestFrameworks/UIKit/LC32UIKitCompatibility.h"

@implementation UIApplication
- (UIInterfaceOrientation)statusBarOrientation { return UIInterfaceOrientationPortrait; }
@end
@implementation NSObject (LC32OrientationTestBridge)
// Distinct guest/host identities catch accidental direct object forwarding.
- (uint64_t)host_self { return (uintptr_t)(__bridge void *)self + 0x1000; }
@end

static unsigned checks, failures, lookups, hostCalls, policyCalls;
static uint32_t policyOrientation;
static BOOL expectsPolicy;
static uint64_t expectedReceiver;
static SEL expectedSelector;
static int variant;
static UIInterfaceOrientation expectedOrientation;
static int expectedAnimation;
static NSTimeInterval expectedDuration;
static id expectedParameters, expectedUpdate;
static BOOL expectedNotify;
static void (^pendingUpdate)(void);

static void check(BOOL passed, const char *description) {
    ++checks;
    if(!passed) ++failures;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

BOOL LC32GuestUIKitLegacyCompatibilityEnabled(void) {
    const char *disabled = getenv("LC32_ORIENTATION_TEST_DISABLE_POLICY");
    return !(disabled && !strcmp(disabled, "1"));
}

uint64_t LC32Dlsym(const char *name, BOOL host) {
    (void)host;
    ++lookups;
    if(!strcmp(name, "LC32UIKitHandleLegacyStatusBarOrientation")) return 1;
    if(!strcmp(name, "LC32UIKitGetLegacyStatusBarOrientation")) return 2;
    abort();
}

uint32_t LC32InvokeHostCRet32(uint64_t function, ...) {
    if(function == 2) return UIInterfaceOrientationUnknown;
    if(function != 1) abort();
    va_list args;
    va_start(args, function);
    policyOrientation = va_arg(args, uint32_t);
    check(va_arg(args, uint32_t) == 0, "policy bridge terminator");
    va_end(args);
    ++policyCalls;
    return 0;
}

uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL superCall) {
    check(!superCall, "native instance dispatch");
    return *cache = (uintptr_t)sel_getName(selector);
}

uint64_t LC32InvokeHostSelector(uint64_t receiver, uint64_t command, ...) {
    ++hostCalls;
    check(receiver == expectedReceiver, "host receiver preserved");
    check(!strcmp((const char *)(uintptr_t)command, sel_getName(expectedSelector)), "native selector preserved");
    check(policyCalls == (unsigned)expectsPolicy, "policy notified exactly once before native call");
    if(expectsPolicy)
        check(policyOrientation == (uint32_t)expectedOrientation, "orientation intent preserved");
    va_list args;
    va_start(args, command);
    check(va_arg(args, uint64_t) == (uint64_t)(int64_t)expectedOrientation,
        "orientation marshalled as signed host integer");
    if(variant == 1) {
        check(va_arg(args, uint64_t) == (uint64_t)expectedNotify, "animated flag preserved");
    } else if(variant == 2) {
        check(va_arg(args, uint64_t) == (uint64_t)(int64_t)expectedAnimation, "animation integer preserved");
        check(va_arg(args, double) == expectedDuration, "duration remains double precision");
    } else if(variant >= 3) {
        check(va_arg(args, uint64_t) == [expectedParameters host_self], "animation parameters translated including nil");
        if(variant >= 4)
            check(va_arg(args, uint64_t) == (uint64_t)expectedNotify, "notification/fence flag preserved");
        if(variant == 5) {
            uint64_t update = va_arg(args, uint64_t);
            check(update == [expectedUpdate host_self], "update block translated including nil");
            id block = update ? (__bridge id)(void *)(uintptr_t)(update - 0x1000) : nil;
            pendingUpdate = [block copy];
        }
    }
    check(va_arg(args, uint64_t) == 0, "native bridge terminator");
    va_end(args);
    return 0;
}

int main(void) {
    @autoreleasepool {
        expectsPolicy = LC32_UIKIT_COMPATIBILITY && LC32GuestUIKitLegacyCompatibilityEnabled();
        check(lookups == (expectsPolicy ? 2u : 0u), "disabled mode does not resolve policy helpers");
        UIApplication *app = [UIApplication new];
        expectedReceiver = app.host_self;
        NSArray<NSString *> *selectors = @[
            @"setStatusBarOrientation:",
            @"setStatusBarOrientation:animated:",
            @"setStatusBarOrientation:animation:duration:",
            @"setStatusBarOrientation:animationParameters:",
            @"setStatusBarOrientation:animationParameters:notifySpringBoardAndFence:",
            @"setStatusBarOrientation:animationParameters:notifySpringBoardAndFence:updateBlock:",
        ];
        for(variant = 0; variant < (int)selectors.count; ++variant) {
            expectedSelector = NSSelectorFromString(selectors[variant]);
            BOOL available = [app respondsToSelector:expectedSelector];
            check(available, selectors[variant].UTF8String);
            if(!available) continue;
            // Both sides, false/true flags, nil objects and signed integer ABI.
            for(int sample = 0; sample < 3; ++sample) {
                expectedOrientation = sample == 2 ? -1 :
                    (sample ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationLandscapeRight);
                expectedAnimation = sample == 2 ? -2 : 1;
                expectedDuration = 0.123456789012345;
                expectedNotify = sample != 0;
                expectedParameters = sample ? nil : @{ @"duration": @(expectedDuration) };
                __block unsigned updates = 0;
                expectedUpdate = sample ? nil : ^{ ++updates; };
                hostCalls = policyCalls = 0;
                switch(variant) {
                    case 0: [app setStatusBarOrientation:expectedOrientation]; break;
                    case 1: [app setStatusBarOrientation:expectedOrientation animated:expectedNotify]; break;
                    case 2: [app setStatusBarOrientation:expectedOrientation animation:expectedAnimation duration:expectedDuration]; break;
                    case 3: [app setStatusBarOrientation:expectedOrientation animationParameters:expectedParameters]; break;
                    case 4: [app setStatusBarOrientation:expectedOrientation animationParameters:expectedParameters notifySpringBoardAndFence:expectedNotify]; break;
                    case 5: [app setStatusBarOrientation:expectedOrientation animationParameters:expectedParameters notifySpringBoardAndFence:expectedNotify updateBlock:expectedUpdate]; break;
                }
                check(hostCalls == 1, "one native call per setter");
                check(updates == 0, "shim does not invoke update block eagerly");
                if(variant == 5) {
                    expectedUpdate = nil;
                    if(pendingUpdate) pendingUpdate();
                    check(updates == (sample ? 0u : 1u), "host may retain and invoke update block after return");
                    pendingUpdate = nil;
                }
            }
        }
    }
    printf("%u/%u status-bar orientation checks passed (mode=%d policy=%d)\n",
        checks-failures, checks, LC32_UIKIT_COMPATIBILITY, expectsPolicy);
    return failures ? 1 : 0;
}
