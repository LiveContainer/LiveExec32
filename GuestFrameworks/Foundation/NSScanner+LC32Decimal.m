#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

/*
 * NSDecimal has the same byte representation across the ARM32 guest and
 * ARM64 host: one 32-bit bitfield word followed by eight 16-bit mantissa
 * words. Its alignment differs, so the host bridge copies these bytes into
 * aligned native storage before invoking NSScanner.
 */
_Static_assert(sizeof(NSDecimal) == 20, "unexpected NSDecimal layout");
_Static_assert(_Alignof(NSDecimal) == 2,
    "unexpected ARM32 NSDecimal alignment");
_Static_assert(offsetof(NSDecimal, _mantissa) == 4,
    "unexpected NSDecimal mantissa offset");

@implementation NSScanner (LC32Decimal)

- (BOOL)scanDecimal:(NSDecimal *)guestDecimal {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);

    LC32HostSizedIndirectDescriptor descriptor;
    uint64_t argument = 0;
    if(guestDecimal) {
        LC32InitializeHostSizedIndirectDescriptor(
            &descriptor, guestDecimal, sizeof(*guestDecimal));
        argument = LC32HostSizedIndirectArgument(&descriptor);
    }

    return (BOOL)LC32InvokeHostSelector(
        self.host_self, selector, argument, (uint64_t)0);
}

@end
