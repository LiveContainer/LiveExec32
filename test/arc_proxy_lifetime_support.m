#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>

/*
 * These entry points are deliberately called directly below.  A normal
 * `[object retain]` message always reaches LC32's swizzled method and would
 * therefore fail to detect libobjc's default-RR fast path.
 */
extern id objc_retain(id object);
extern void objc_release(id object);

@interface NSObject (LC32RetainProbe)
/* Original guest-only retainCount after LC32FrameworkInit's exchange. */
- (NSUInteger)LC32_retainCount;
@end

static NSUInteger LC32ReturnProxyProbeDeallocCount;
static char LC32ReturnProxyProbeKey;

@interface LC32ReturnProxyProbe : NSObject
@end

@implementation LC32ReturnProxyProbe
- (void)dealloc {
    LC32ReturnProxyProbeDeallocCount++;
    [super dealloc];
}
@end

static void LC32AttachReturnProxyProbe(id object) {
    LC32ReturnProxyProbe *probe = [LC32ReturnProxyProbe new];
    objc_setAssociatedObject(object, &LC32ReturnProxyProbeKey, probe,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [probe release];
}

NSUInteger LC32AttachReturnProxyProbeAndGetBaseline(id object) {
    const NSUInteger baseline = LC32ReturnProxyProbeDeallocCount;
    LC32AttachReturnProxyProbe(object);
    return baseline;
}

BOOL LC32ReturnProxyProbeWasReleased(NSUInteger baseline) {
    return LC32ReturnProxyProbeDeallocCount == baseline + 1;
}

void *LC32CreateBridgedAutoreleasePool(void) {
    return [NSAutoreleasePool new];
}

void LC32DrainBridgedAutoreleasePool(void *opaquePool) {
    [(NSAutoreleasePool *)opaquePool drain];
}

BOOL LC32TestDirectObjCRetainBridgesHost(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSBlockOperation *operation =
        [NSBlockOperation blockOperationWithBlock:^{}];

    /*
     * objc_class::bits is the fifth 32-bit word in the iOS 10 armv7 runtime.
     * FAST_HAS_DEFAULT_RR is bit 1: when set, objc_retain/objc_release update
     * only the guest side table instead of messaging LC32's bridge methods.
     * Keep this as diagnostics rather than the pass criterion so the useful
     * ownership assertion remains valid if the runtime changes its encoding.
     */
    Class operationClass = object_getClass(operation);
    const uintptr_t classDataBits = ((const uintptr_t *)operationClass)[4];
    const BOOL hasDefaultRRFastPath = (classDataBits & (uintptr_t)2) != 0;

    const NSUInteger hostBefore = [operation retainCount];
    const NSUInteger guestBefore = [operation LC32_retainCount];
    id retained = objc_retain(operation);
    const NSUInteger hostAfterRetain = [operation retainCount];
    const NSUInteger guestAfterRetain = [operation LC32_retainCount];
    objc_release(retained);
    const NSUInteger hostAfterRelease = [operation retainCount];
    const NSUInteger guestAfterRelease = [operation LC32_retainCount];

    const BOOL identityPreserved = retained == operation;
    const BOOL hostRetainMirrored =
        hostAfterRetain == hostBefore + 1 && hostAfterRelease == hostBefore;
    const BOOL guestRetainBalanced =
        guestAfterRetain == guestBefore + 1 &&
        guestAfterRelease == guestBefore;
    const BOOL passed =
        identityPreserved && hostRetainMirrored && guestRetainBalanced;

    printf("direct-objc-retain-class-data-bits: 0x%08lx\n",
           (unsigned long)classDataBits);
    printf("direct-objc-retain-default-rr-fast-path: %s\n",
           hasDefaultRRFastPath ? "YES" : "NO");
    printf("direct-objc-retain-host-counts: %lu -> %lu -> %lu\n",
           (unsigned long)hostBefore, (unsigned long)hostAfterRetain,
           (unsigned long)hostAfterRelease);
    printf("direct-objc-retain-guest-counts: %lu -> %lu -> %lu\n",
           (unsigned long)guestBefore, (unsigned long)guestAfterRetain,
           (unsigned long)guestAfterRelease);
    printf("direct-objc-retain-bridges-host: %s\n",
           passed ? "PASS" : "FAIL");

    [pool drain];
    return passed;
}

BOOL LC32TestBorrowedReturnWithoutImmediateRetain(void) {
    const NSUInteger initialDeallocCount =
        LC32ReturnProxyProbeDeallocCount;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    /*
     * This file is MRC, so the convenience result is never retained by the
     * guest caller. It must nevertheless remain usable until the surrounding
     * native autorelease pool drains. This matches YouTube's
     * blockOperationWithBlock:/setCompletionBlock: sequence.
     */
    NSBlockOperation *operation =
        [NSBlockOperation blockOperationWithBlock:^{}];
    LC32AttachReturnProxyProbe(operation);
    [operation setCompletionBlock:^{}];
    operation.name = @"LC32 borrowed operation";
    const BOOL callableBeforePoolDrain =
        [operation.name isEqualToString:@"LC32 borrowed operation"];
    operation.completionBlock = nil;

    [pool drain];
    const BOOL proxyReleasedAtPoolDrain =
        LC32ReturnProxyProbeDeallocCount == initialDeallocCount + 1;

    printf("borrowed-return-usable-without-retain: %s\n",
           callableBeforePoolDrain ? "PASS" : "FAIL");
    printf("borrowed-return-released-with-pool: %s\n",
           proxyReleasedAtPoolDrain ? "PASS" : "FAIL");
    return callableBeforePoolDrain && proxyReleasedAtPoolDrain;
}

BOOL LC32TestRetainedFamilyReturnExclusion(void) {
    const NSUInteger initialDeallocCount =
        LC32ReturnProxyProbeDeallocCount;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    /*
     * LC32InvokeHostSelector must not stabilize +1 method-family results by
     * adding a native autorelease.  Releasing the only guest ownership should
     * consequently destroy each native peer and its guest lifetime pin before
     * this pool drains.  If init/copy/mutableCopy are misclassified as +0, the
     * associated probe remains alive until the extra host autorelease fires.
     */
    NSMutableString *initialized =
        [[NSMutableString alloc] initWithCapacity:8];
    LC32AttachReturnProxyProbe(initialized);
    [initialized release];
    const BOOL initReleasedImmediately =
        LC32ReturnProxyProbeDeallocCount == initialDeallocCount + 1;

    NSMutableString *source =
        [[NSMutableString alloc] initWithCapacity:8];
    [source appendString:@"source"];

    NSString *copied = [source copy];
    LC32AttachReturnProxyProbe(copied);
    [copied release];
    const BOOL copyReleasedImmediately =
        LC32ReturnProxyProbeDeallocCount == initialDeallocCount + 2;

    NSMutableString *mutableCopied = [source mutableCopy];
    LC32AttachReturnProxyProbe(mutableCopied);
    [mutableCopied release];
    const BOOL mutableCopyReleasedImmediately =
        LC32ReturnProxyProbeDeallocCount == initialDeallocCount + 3;

    [source release];
    const NSUInteger countBeforePoolDrain =
        LC32ReturnProxyProbeDeallocCount;
    [pool drain];
    const BOOL poolDrainWasBalanced =
        LC32ReturnProxyProbeDeallocCount == countBeforePoolDrain &&
        countBeforePoolDrain == initialDeallocCount + 3;

    printf("retained-init-excluded-from-stabilization: %s\n",
           initReleasedImmediately ? "PASS" : "FAIL");
    printf("retained-copy-excluded-from-stabilization: %s\n",
           copyReleasedImmediately ? "PASS" : "FAIL");
    printf("retained-mutable-copy-excluded-from-stabilization: %s\n",
           mutableCopyReleasedImmediately ? "PASS" : "FAIL");
    printf("retained-return-host-pool-balanced: %s\n",
           poolDrainWasBalanced ? "PASS" : "FAIL");

    return initReleasedImmediately && copyReleasedImmediately &&
        mutableCopyReleasedImmediately && poolDrainWasBalanced;
}
