#import <StoreKit/StoreKit.h>
#import <LC32/LC32.h>

@implementation SKRequest (LC32Delegate)
- (void)setDelegate:(id<SKRequestDelegate>)delegate {
    /* This assign/weak setter must not introduce guest ownership. Legacy
     * singleton delegates can override -retain without incrementing their
     * root count; an ARC parameter temporary would still release them. */
    static uint64_t cachedSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &cachedSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
        [(id)delegate host_self], (uint64_t)0);
}
@end
