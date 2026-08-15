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

    [pool drain];
    return !(selectorPassed && canaryPassed && typePassed);
}
