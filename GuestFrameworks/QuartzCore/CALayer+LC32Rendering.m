#import <QuartzCore/QuartzCore.h>
#import <LC32/LC32.h>

@implementation CALayer (LC32Rendering)
- (void)renderInContext:(CGContextRef)context {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(renderInContext:), NO);
    LC32InvokeHostSelector(self.host_self, selector, [(id)context host_self], (uint64_t)0);
    // Drawing bypasses the CG dispatcher; flush also copies native shadow
    // pixels back to the caller's guest-owned bitmap buffer.
    CGContextFlush(context);
}
@end
