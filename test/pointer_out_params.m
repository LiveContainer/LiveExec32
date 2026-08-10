#import <Foundation/Foundation.h>

#include <stdio.h>
#include <math.h>

@interface NSObject (LC32PointerTest)
- (uint64_t)host_self;
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object,
                                       uint64_t selector, ...);

@interface LC32ClassSuperNullProbe : NSNull
+ (BOOL)superSupportsSecureCoding;
@end

@implementation LC32ClassSuperNullProbe
+ (BOOL)superSupportsSecureCoding {
    return [super supportsSecureCoding];
}
@end

@interface LC32RealSetterProbe : NSObject {
    id window;
    BOOL setterCalled;
}
- (void)setWindow:(id)value;
- (BOOL)setterCalled;
@end

@implementation LC32RealSetterProbe
- (void)setWindow:(id)value {
    window = value;
    setterCalled = YES;
}
- (BOOL)setterCalled {
    return setterCalled && window != nil;
}
@end

int main(void) {
    NSScanner *integerScanner =
        [NSScanner scannerWithString:@"-123"];
    NSInteger integer = 0x55555555;
    BOOL integerPassed = [integerScanner scanInteger:&integer] &&
        integer == -123 && integerScanner.isAtEnd;
    printf("pointer-out-integer: %s\n",
        integerPassed ? "PASS" : "FAIL");

    NSScanner *nullIntegerScanner =
        [NSScanner scannerWithString:@"456"];
    BOOL nullIntegerPassed =
        [nullIntegerScanner scanInteger:NULL] &&
        nullIntegerScanner.isAtEnd;
    printf("pointer-out-null-integer: %s\n",
        nullIntegerPassed ? "PASS" : "FAIL");

    NSScanner *objectScanner =
        [NSScanner scannerWithString:@"token"];
    NSString *matched = nil;
    BOOL objectPassed =
        [objectScanner scanString:@"token" intoString:&matched] &&
        [matched isEqualToString:@"token"] && objectScanner.isAtEnd;
    printf("pointer-out-object: %s\n",
        objectPassed ? "PASS" : "FAIL");

    NSScanner *nullObjectScanner =
        [NSScanner scannerWithString:@"token"];
    BOOL nullObjectPassed =
        [nullObjectScanner scanString:@"token" intoString:NULL] &&
        nullObjectScanner.isAtEnd;
    printf("pointer-out-null-object: %s\n",
        nullObjectPassed ? "PASS" : "FAIL");

    BOOL classSuperPassed =
        [LC32ClassSuperNullProbe superSupportsSecureCoding] ==
        [NSNull supportsSecureCoding];
    printf("class-method-super: %s\n",
        classSuperPassed ? "PASS" : "FAIL");

    const float floatValue = [@"1.25" floatValue];
    const double doubleValue = [@"-2.5" doubleValue];
    const BOOL floatingReturnPassed =
        fabsf(floatValue - 1.25f) < 0.0001f &&
        fabs(doubleValue + 2.5) < 0.0001;
    printf("floating-returns: %s\n",
        floatingReturnPassed ? "PASS" : "FAIL");

    LC32RealSetterProbe *setterProbe = [LC32RealSetterProbe new];
    NSString *setterValue = @"window";
    NSString *setterKey = @"window";
    LC32InvokeHostSelector(
        setterProbe.host_self,
        LC32GetHostSelector(@selector(setValue:forKey:)),
        setterValue.host_self, setterKey.host_self, (uint64_t)0);
    const BOOL realSetterPassed = setterProbe.setterCalled;
    printf("host-kvc-real-setter: %s\n",
        realSetterPassed ? "PASS" : "FAIL");

    return !(integerPassed && nullIntegerPassed &&
             objectPassed && nullObjectPassed && classSuperPassed &&
             floatingReturnPassed && realSetterPassed);
}
