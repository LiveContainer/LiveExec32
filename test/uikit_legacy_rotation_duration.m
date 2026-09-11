#import <UIKit/UIKit.h>
#import <LC32/LC32.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Run with an arm64 shim whose effective process SDK is below iOS 8.
 * Native NSInvocation exercises the typed native IMP, not a direct
 * guest-to-guest Objective-C call. LC32InvokeHostSelector on the controller
 * itself intentionally skips synthesized guest classes and would only call
 * UIViewController's no-op superclass implementation. Both halves of 0.1's
 * double are nonzero, so a missing word or incorrect alignment is observable. */
static id observedReceiver;
static UIInterfaceOrientation observedOrientation;
static uint64_t observedDuration;
static unsigned calls;

static NSInvocation *nativeRotationInvocation(UIViewController *controller) {
    const SEL selector = @selector(willRotateToInterfaceOrientation:duration:);
    const uint64_t signature = LC32InvokeHostSelector([controller host_self],
        LC32GetHostSelector(@selector(methodSignatureForSelector:)),
        LC32GetHostSelector(selector), (uint64_t)0);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
        LC32HostToGuestObject(signature)];
    [invocation setTarget:controller];
    [invocation setSelector:selector];
    return invocation;
}

@interface LC32RotationDurationController : UIViewController
@end
@implementation LC32RotationDurationController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    (void)orientation;
    return YES;
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
                              duration:(NSTimeInterval)duration {
    observedReceiver = self;
    observedOrientation = orientation;
    memcpy(&observedDuration, &duration, sizeof(observedDuration));
    ++calls;
}
@end

@interface LC32InheritedRotationDurationController : LC32RotationDurationController
@end
@implementation LC32InheritedRotationDurationController
@end

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        int failures = 0;
        Class classes[] = {
            LC32RotationDurationController.class,
            LC32InheritedRotationDurationController.class,
        };
        const double durations[] = {0.1, 0.375, 1.23456789, -2.75, -0.0};
        for(unsigned kind = 0; kind < sizeof(classes) / sizeof(*classes); ++kind) {
            UIViewController *controller = [[classes[kind] alloc] init];
            NSInvocation *invocation = nativeRotationInvocation(controller);
            for(unsigned index = 0; index < sizeof(durations) / sizeof(*durations); ++index) {
                UIInterfaceOrientation orientation = index % 2
                    ? UIInterfaceOrientationLandscapeLeft
                    : UIInterfaceOrientationLandscapeRight;
                double duration = durations[index];
                const unsigned previousCalls = calls;
                uint64_t expectedDuration;
                memcpy(&expectedDuration, &durations[index], sizeof(expectedDuration));
                [invocation setArgument:&orientation atIndex:2];
                [invocation setArgument:&duration atIndex:3];
                [invocation invoke];
                const BOOL passed = calls == previousCalls + 1 &&
                    observedReceiver == controller &&
                    observedOrientation == orientation &&
                    observedDuration == expectedDuration;
                printf("rotation-duration-%s-%u: %s (bits=%016llx expected=%016llx "
                    "calls=%u receiver=%s orientation=%ld expected=%ld)\n",
                    kind ? "inherited" : "own", index,
                    passed ? "PASS" : "FAIL",
                    (unsigned long long)observedDuration,
                    (unsigned long long)expectedDuration, calls - previousCalls,
                    observedReceiver == controller ? "same" : "different",
                    (long)observedOrientation, (long)orientation);
                failures += !passed;
            }
#if !__has_feature(objc_arc)
            [controller release];
#endif
        }
        printf("rotation-duration-regression: %s\n", failures ? "FAIL" : "PASS");
        return failures != 0;
    }
}
