#import <LC32/LC32.h>
#import <UIKit/UIKit.h>

/*
 * Some legacy Apple LLVM compilers set BLOCK_HAS_SIGNATURE while leaving the
 * descriptor's signature pointer null.  The generic bridge cannot infer an
 * arbitrary callback ABI from that block, but UIApplication defines this one
 * as void(void).  Capture the legacy callback in a compiler-generated wrapper
 * so the bridge sees a complete signature while the guest invokes the original
 * block directly.
 */
@implementation UIApplication (LC32BlockCompatibility)

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
        (void (^)(void))handler {
    void (^typedHandler)(void) = nil;
    if(handler) {
        typedHandler = ^{
            handler();
        };
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    return (UIBackgroundTaskIdentifier)(uint32_t)LC32InvokeHostSelector(
        self.host_self, command, [typedHandler host_self], (uint64_t)0);
}

@end
