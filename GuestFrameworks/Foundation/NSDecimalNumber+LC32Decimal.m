#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

_Static_assert(sizeof(NSDecimal) == 20, "unexpected NSDecimal layout");
_Static_assert(_Alignof(NSDecimal) == 2,
    "unexpected ARM32 NSDecimal alignment");
_Static_assert(offsetof(NSDecimal, _mantissa) == 4,
    "unexpected NSDecimal mantissa offset");

@implementation NSDecimalNumber (LC32Decimal)

+ (instancetype)decimalNumberWithDecimal:(NSDecimal)decimal {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, selector,
        LC32HostAggregateArgument(&decimal), (uint64_t)0);
    return LC32ReturnBorrowedGuestObject(result);
}

- (instancetype)initWithDecimal:(NSDecimal)decimal {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostResult = LC32InvokeHostSelector(
        self.host_self, selector,
        LC32HostAggregateArgument(&decimal), (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, hostResult);
}

@end
