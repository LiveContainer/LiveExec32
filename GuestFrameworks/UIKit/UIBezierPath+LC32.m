#import <UIKit/UIKit.h>
#import <LC32/LC32.h>

@implementation UIBezierPath (LC32Path)
+ (instancetype)bezierPathWithCGPath:(CGPathRef)path {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(bezierPathWithCGPath:), NO);
    return LC32ReturnBorrowedGuestObject(LC32InvokeHostObjectSelector(
        self.host_self, selector, [(__bridge id)path host_self], (uint64_t)0));
}

- (CGPathRef)CGPath {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(CGPath), NO);
    return (__bridge CGPathRef)LC32ReturnBorrowedGuestObject(
        LC32InvokeHostObjectSelector(self.host_self, selector, (uint64_t)0));
}

- (void)setCGPath:(CGPathRef)path {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(setCGPath:), NO);
    LC32InvokeHostSelector(self.host_self, selector,
        [(__bridge id)path host_self], (uint64_t)0);
}
@end
