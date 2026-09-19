#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int Check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return !passed;
}

static int CheckTransformValues(void) {
    // Distinct, signed, fractional entries catch transposition and truncation.
    const CATransform3D expected = {
        1.25f, -2.5f, 3.75f, -4.125f,
        5.5f, -6.75f, 7.125f, -8.25f,
        9.75f, -10.125f, 11.25f, -12.5f,
        13.125f, -14.25f, 15.5f, -16.75f,
    };
    NSValue *value = [NSValue valueWithCATransform3D:expected];
    int failed = Check("nsvalue-transform-create", value != nil);
    if(!value) return failed;

    struct {
        uint32_t before;
        CATransform3D transform;
        uint32_t after;
    } output = { UINT32_C(0x12345678), {0}, UINT32_C(0x87654321) };
    [value getValue:&output.transform];
    failed += Check("nsvalue-transform-guest-round-trip",
        !memcmp(&output.transform, &expected, sizeof(expected)));
    failed += Check("nsvalue-transform-guest-write-width",
        output.before == UINT32_C(0x12345678) &&
        output.after == UINT32_C(0x87654321));
    failed += Check("nsvalue-transform-guest-type",
        !strcmp([value objCType], @encode(CATransform3D)));
    CATransform3D categoryResult = [value CATransform3DValue];
    failed += Check("nsvalue-transform-category-round-trip",
        !memcmp(&categoryResult, &expected, sizeof(expected)));

    // Bypass the guest adapter to inspect the box native Core Animation sees.
    struct {
        uint64_t before;
        double elements[16];
        uint64_t after;
    } native = { UINT64_C(0x123456789abcdef0), {0},
                 UINT64_C(0xfedcba9876543210) };
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(
        &descriptor, native.elements, sizeof(native.elements));
    LC32InvokeHostSelector(value.host_self,
        LC32GetHostSelector(@selector(getValue:)),
        LC32HostSizedIndirectArgument(&descriptor), (uint64_t)0);
    float guestElements[16];
    memcpy(guestElements, &expected, sizeof(guestElements));
    BOOL widened = YES;
    for(unsigned i = 0; i < 16; i++) {
        widened &= native.elements[i] == (double)guestElements[i];
    }
    failed += Check("nsvalue-transform-native-layout", widened);
    failed += Check("nsvalue-transform-native-write-width",
        native.before == UINT64_C(0x123456789abcdef0) &&
        native.after == UINT64_C(0xfedcba9876543210));

    // Create a genuinely native box with no cached guest bytes, then exercise
    // objCType and getValue: in that order to cover cached-encoding narrowing.
    float narrowed[16];
    for(unsigned i = 0; i < 16; i++) {
        native.elements[i] = ((double)i - 7.0) / 3.0;
        narrowed[i] = (float)native.elements[i];
    }
    const uint64_t type = LC32GuestToHostCString(
        "{CATransform3D=dddddddddddddddd}", 0);
    NSValue *nativeValue = LC32InvokeHostObjectSelector(
        [(id)[NSValue class] host_self],
        LC32GetHostSelector(@selector(valueWithBytes:objCType:)),
        LC32HostSizedIndirectArgument(&descriptor), type, (uint64_t)0);
    LC32GuestToHostCStringFree(type);
    failed += Check("nsvalue-transform-native-create", nativeValue != nil);
    if(!nativeValue) return failed;
    failed += Check("nsvalue-transform-native-type",
        !strcmp([nativeValue objCType], @encode(CATransform3D)));
    memset(&output.transform, 0, sizeof(output.transform));
    [nativeValue getValue:&output.transform];
    failed += Check("nsvalue-transform-native-narrow",
        !memcmp(&output.transform, narrowed, sizeof(narrowed)));
    failed += Check("nsvalue-transform-native-to-guest-write-width",
        output.before == UINT32_C(0x12345678) &&
        output.after == UINT32_C(0x87654321));
    return failed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    const SEL expected = @selector(lc32SelectorRoundTrip:);
    NSValue *value = [NSValue valueWithBytes:&expected
                                    objCType:@encode(SEL)];
    NSDictionary *container = [NSDictionary dictionaryWithObject:value
                                                           forKey:@"selector"];

    struct {
        SEL selector;
        uint32_t canary;
    } output = { NULL, UINT32_C(0x51ec70a5) };
    [[container objectForKey:@"selector"] getValue:&output.selector];

    const BOOL selectorPassed = sel_isEqual(output.selector, expected);
    const BOOL canaryPassed = output.canary == UINT32_C(0x51ec70a5);
    const BOOL typePassed =
        !strcmp([[container objectForKey:@"selector"] objCType],
                @encode(SEL));
    printf("nsvalue-selector-round-trip: %s\n",
           selectorPassed ? "PASS" : "FAIL");
    printf("nsvalue-selector-write-width: %s\n",
           canaryPassed ? "PASS" : "FAIL");
    printf("nsvalue-selector-type: %s\n",
           typePassed ? "PASS" : "FAIL");

    uint32_t pointee = UINT32_C(0xc01df00d);
    const void *expectedPointer = &pointee;
    NSValue *pointerValue = [NSValue valueWithPointer:expectedPointer];
    NSDictionary *pointerContainer =
        [NSDictionary dictionaryWithObject:pointerValue forKey:@"pointer"];
    NSValue *storedPointer = [pointerContainer objectForKey:@"pointer"];

    const BOOL pointerPassed =
        [storedPointer pointerValue] == expectedPointer;
    struct {
        void *pointer;
        uint32_t canary;
    } pointerOutput = { NULL, UINT32_C(0xa11c32ed) };
    [storedPointer getValue:&pointerOutput.pointer];
    const BOOL pointerBytesPassed =
        pointerOutput.pointer == expectedPointer;
    const BOOL pointerCanaryPassed =
        pointerOutput.canary == UINT32_C(0xa11c32ed);
    const BOOL pointerTypePassed =
        !strcmp([storedPointer objCType], @encode(void *));
    printf("nsvalue-pointer-round-trip: %s\n",
           pointerPassed ? "PASS" : "FAIL");
    printf("nsvalue-pointer-get-value: %s\n",
           pointerBytesPassed ? "PASS" : "FAIL");
    printf("nsvalue-pointer-write-width: %s\n",
           pointerCanaryPassed ? "PASS" : "FAIL");
    printf("nsvalue-pointer-type: %s\n",
           pointerTypePassed ? "PASS" : "FAIL");

    const int transformFailures = CheckTransformValues();
    [pool drain];
    return !(selectorPassed && canaryPassed && typePassed &&
             pointerPassed && pointerBytesPassed &&
             pointerCanaryPassed && pointerTypePassed && !transformFailures);
}
