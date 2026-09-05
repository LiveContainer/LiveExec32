#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

    [pool drain];
    return !(selectorPassed && canaryPassed && typePassed &&
             pointerPassed && pointerBytesPassed &&
             pointerCanaryPassed && pointerTypePassed);
}
