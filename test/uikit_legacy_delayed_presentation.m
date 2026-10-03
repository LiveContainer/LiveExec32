// Native ARM64 regression; link LegacyAlerts.mm for the repaired variant.
// Run an SDK 7 baseline with --expect-missing, then the repair with --expect-alias.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static unsigned failures;
static void check(const char *name, BOOL pass) {
    printf("legacy-delayed-%s: %s\n", name, pass ? "PASS" : "FAIL");
    failures += !pass;
}

@interface LC32DelayedPresentationProbe : UIViewController
@property(nonatomic) UIViewController *receivedController;
@property(nonatomic) int receivedTransition;
@property(nonatomic) SEL receivedSelector;
@end
@implementation LC32DelayedPresentationProbe
- (void)presentViewController:(UIViewController *)controller
              withTransition:(int)transition completion:(void (^)(void))completion {
    self.receivedController = controller;
    self.receivedTransition = transition;
    self.receivedSelector = _cmd;
    if(completion) completion();
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL expectAlias = argc == 2 && !strcmp(argv[1], "--expect-alias");
        BOOL expectMissing = argc == 2 && !strcmp(argv[1], "--expect-missing");
        if(!expectAlias && !expectMissing) return 2;
        SEL resume = NSSelectorFromString(
            @"_windowControllerBasedPresentViewController:withTransition:completion:");
        SEL present = NSSelectorFromString(@"presentViewController:withTransition:completion:");
        Method native = class_getInstanceMethod(UIViewController.class, present);
        check("native-entry-exists", native != NULL);
        check("resume-instance-availability",
            [UIViewController instancesRespondToSelector:resume] == expectAlias);
        NSMethodSignature *signature = [UIViewController instanceMethodSignatureForSelector:resume];
        printf("legacy-delayed-signature: %s\n", signature.description.UTF8String);
        if(expectMissing) {
            check("missing-signature", signature == nil);
            BOOL caught = NO;
            @try { (void)[NSInvocation invocationWithMethodSignature:signature]; }
            @catch(NSException *exception) {
                printf("legacy-delayed-exception: %s: %s\n", exception.name.UTF8String,
                    exception.reason.UTF8String);
                caught = [exception.name isEqualToString:NSInvalidArgumentException];
            }
            check("nil-signature-reproduces-exception", caught);
        } else {
            check("restored-signature", signature != nil);
            if(signature) {
                Method alias = class_getInstanceMethod(UIViewController.class, resume);
                check("native-argument-encoding", !strcmp(method_getTypeEncoding(alias),
                    method_getTypeEncoding(native)));
                LC32DelayedPresentationProbe *target = [LC32DelayedPresentationProbe new];
                UIViewController *presented = [UIViewController new];
                int transition = 7;
                __block unsigned completions = 0;
                void (^completion)(void) = ^{ ++completions; };
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                invocation.target = target;
                invocation.selector = resume;
                [invocation setArgument:&presented atIndex:2];
                [invocation setArgument:&transition atIndex:3];
                [invocation setArgument:&completion atIndex:4];
                [invocation retainArguments];
                [invocation invoke];
                check("dispatches-to-presenter-override", target.receivedController == presented);
                check("transition-preserved", target.receivedTransition == transition);
                check("selector-preserved", target.receivedSelector == present);
                check("completion-once", completions == 1);
                completion = nil;
                [invocation setArgument:&completion atIndex:4];
                [invocation invoke];
                check("nil-completion", completions == 1);
            }
        }
    }
    printf("legacy-delayed-presentation: %s (%u failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures != 0;
}
