#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

static unsigned checks, failures;
static void check(const char *name, BOOL passed) {
    printf("responds-to-selector-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

@interface ResponseProbe : NSObject
- (void)guestMethod;
- (void)hiddenGuestMethod;
@end
@implementation ResponseProbe
- (void)guestMethod {}
- (void)hiddenGuestMethod {}
- (BOOL)respondsToSelector:(SEL)selector {
    if(selector == @selector(hiddenGuestMethod) || selector == @selector(description)) return NO;
    if(selector == sel_registerName("lc32ForwardedResponseProbe")) return YES;
    return [super respondsToSelector:selector];
}
+ (BOOL)respondsToSelector:(SEL)selector {
    if(selector == @selector(description)) return NO;
    return [super respondsToSelector:selector];
}
@end
@interface ResponseChild : ResponseProbe @end
@implementation ResponseChild @end

// Native NSInvocation dispatches to the mirror's override, unlike an ordinary
// guest message or a guest-to-host super call. The SEL argument crosses both
// ABIs before the native caller receives the override's BOOL result.
static BOOL nativeResponse(id target, SEL query) {
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:
        [NSObject instanceMethodSignatureForSelector:@selector(respondsToSelector:)]];
    call.target = target;
    call.selector = @selector(respondsToSelector:);
    [call setArgument:&query atIndex:2];
    [call invoke];
    BOOL response = NO;
    [call getReturnValue:&response];
    return response;
}

int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        // This existing host bridge method is absent from guest method lists;
        // unlike a private UIKit selector it is stable across test OS versions.
        SEL nativeOnly = sel_registerName("LC32_nativeMethodSignatureForSelector:instanceMethods:");
        check("fixture-native-only", class_getInstanceMethod(ResponseProbe.class, nativeOnly) == NULL);
        ResponseProbe *probe = [ResponseProbe new];
        ResponseChild *child = [ResponseChild new];
        check("guest-still-cannot-call-native-only", ![probe respondsToSelector:nativeOnly]);
        check("native-inherited-method", nativeResponse(probe, nativeOnly));
        check("native-subclass-inherited-method", nativeResponse(child, nativeOnly));
        check("guest-method", nativeResponse(probe, @selector(guestMethod)));
        check("hidden-guest-method", !nativeResponse(probe, @selector(hiddenGuestMethod)));
        check("hidden-inherited-method", !nativeResponse(probe, @selector(description)));
        check("forwarded-response", nativeResponse(probe, sel_registerName("lc32ForwardedResponseProbe")));
        check("unknown-method", !nativeResponse(probe, sel_registerName("lc32MissingResponseProbe")));
        check("null-selector", !nativeResponse(probe, NULL));
        check("guest-class-still-cannot-call-native-only", ![ResponseProbe respondsToSelector:nativeOnly]);
        check("native-class-inherited-method", nativeResponse(ResponseProbe.class, nativeOnly));
        check("class-hidden-inherited-method", !nativeResponse(ResponseProbe.class, @selector(description)));
        check("class-existing-method", nativeResponse(ResponseProbe.class, @selector(alloc)));
        check("class-unknown-method", !nativeResponse(ResponseProbe.class, sel_registerName("lc32MissingResponseProbe")));
        [probe release];
        [child release];
    }
    printf("responds-to-selector: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
