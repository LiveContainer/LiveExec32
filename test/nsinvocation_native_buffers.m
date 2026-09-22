// Native ARM64 simulator regression. Link LiveExec32Shared to load its real
// hook registrations, then call Foundation normally (outside the guest bridge).
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdio.h>

@interface NativeInvocationTarget : NSObject
- (NSRange)adjusted:(NSRange)range;
- (id)echo:(id)object;
@end
@implementation NativeInvocationTarget
- (NSRange)adjusted:(NSRange)range { return NSMakeRange(range.location + 7, range.length + 11); }
- (id)echo:(id)object { return object; }
@end

static unsigned checks, failures;
static void check(const char *name, BOOL pass) {
    printf("native-invocation-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
int main(void) {
    @autoreleasepool {
        check("real-adapters-loaded", [NSInvocation instancesRespondToSelector:
            NSSelectorFromString(@"lc32_getGuestArgument:atIndex:")]);
        NativeInvocationTarget *target = [NativeInvocationTarget new];
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:
            [target methodSignatureForSelector:@selector(adjusted:)]];
        call.target = target;
        call.selector = @selector(adjusted:);
        check("selector-remains-native", call.selector == @selector(adjusted:));
        NSRange range = NSMakeRange(UINT64_C(0x123456789), UINT64_C(0x234567890));
        [call setArgument:&range atIndex:2];
        [call retainArguments];
        struct { uint64_t before; NSRange range; uint64_t after; } result =
            {UINT64_C(0x1122334455667788), {0, 0}, UINT64_C(0x8877665544332211)};
        [call getArgument:&result.range atIndex:2];
        check("argument-native-width", NSEqualRanges(result.range, range));
        check("argument-canaries", result.before == UINT64_C(0x1122334455667788) &&
            result.after == UINT64_C(0x8877665544332211));
        [call invoke];
        [call getReturnValue:&result.range];
        check("invoke-native-result", result.range.location == range.location + 7 &&
            result.range.length == range.length + 11);
        [call setReturnValue:&range];
        [call getReturnValue:&result.range];
        check("return-storage-native-width", NSEqualRanges(result.range, range));
        check("return-canaries", result.before == UINT64_C(0x1122334455667788) &&
            result.after == UINT64_C(0x8877665544332211));
        call = [NSInvocation invocationWithMethodSignature:
            [target methodSignatureForSelector:@selector(echo:)]];
        call.target = target; call.selector = @selector(echo:);
        id object = [NSMutableString stringWithString:@"native pointer"];
        [call setArgument:&object atIndex:2];
        [call invoke];
        __unsafe_unretained id echoed = nil;
        [call getReturnValue:&echoed];
        check("object-remains-native", echoed == object);
    }
    printf("native invocation: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
