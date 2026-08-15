#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdio.h>

/*
 * These helpers are compiled without ARC.  In particular, the opaque pool is
 * an actual bridged NSAutoreleasePool, not the guest-only pool emitted for an
 * ARC @autoreleasepool statement.  Draining it therefore exercises native
 * autoreleased-return-value stabilization in LC32InvokeHostSelector.
 */
extern void *LC32CreateBridgedAutoreleasePool(void);
extern void LC32DrainBridgedAutoreleasePool(void *pool);
extern NSUInteger LC32AttachReturnProxyProbeAndGetBaseline(id object);
extern BOOL LC32ReturnProxyProbeWasReleased(NSUInteger baseline);
extern BOOL LC32TestBorrowedReturnWithoutImmediateRetain(void);
extern BOOL LC32TestRetainedFamilyReturnExclusion(void);
extern BOOL LC32TestDirectObjCRetainBridgesHost(void);

static BOOL LC32TestARCGeneratedBorrowedReturn(void) {
    __strong UIBezierPath *path = nil;

    void *nativePool = LC32CreateBridgedAutoreleasePool();
    path = [UIBezierPath bezierPath];
    const NSUInteger initialDeallocCount =
        LC32AttachReturnProxyProbeAndGetBaseline(path);
    [path moveToPoint:CGPointMake(1.0, 2.0)];
    [path addLineToPoint:CGPointMake(3.0, 4.0)];
    const BOOL callableBeforePoolDrain = !path.empty;

    /*
     * UIBezierPath.m is generated as part of UIKit, whose guest framework is
     * compiled with ARC.  Draining the real native pool therefore exercises
     * both halves of the generated return sequence:
     *
     *   LC32InvokeHostObjectSelector -> objc_retainAutoreleasedReturnValue
     *   generated shim return        -> objc_autoreleaseReturnValue
     *
     * The caller's strong reference must keep the proxy/native pair alive
     * after the host convenience result's original autorelease fires.
     */
    LC32DrainBridgedAutoreleasePool(nativePool);
    [path addLineToPoint:CGPointMake(5.0, 6.0)];
    const BOOL callableAfterPoolDrain =
        callableBeforePoolDrain && !path.empty;

    path = nil;
    const BOOL releasedAfterStrongClear =
        LC32ReturnProxyProbeWasReleased(initialDeallocCount);

    printf("arc-generated-shim-borrowed-return-callable: %s\n",
           callableAfterPoolDrain ? "PASS" : "FAIL");
    printf("arc-generated-shim-borrowed-return-released: %s\n",
           releasedAfterStrongClear ? "PASS" : "FAIL");
    return callableAfterPoolDrain && releasedAfterStrongClear;
}

static BOOL LC32TestARCReleaseBeforeNativePoolDrain(void) {
    __strong NSBlockOperation *operation = nil;

    void *nativePool = LC32CreateBridgedAutoreleasePool();
    operation = [NSBlockOperation blockOperationWithBlock:^{}];
    const NSUInteger initialDeallocCount =
        LC32AttachReturnProxyProbeAndGetBaseline(operation);

    /*
     * This is the ordering used by YouTube/CFNetwork: the ARC owner gives up
     * the operation while the native method's original convenience-result
     * autorelease and the guest shim's +0 handoff are still in the same host
     * pool.  Return-value optimization must not let the caller and bridge
     * token accidentally share one mirrored +1.
     */
    operation = nil;
    const BOOL aliveUntilPoolDrain =
        !LC32ReturnProxyProbeWasReleased(initialDeallocCount);
    LC32DrainBridgedAutoreleasePool(nativePool);
    const BOOL releasedByPoolDrain =
        LC32ReturnProxyProbeWasReleased(initialDeallocCount);

    printf("arc-return-release-before-pool-stays-alive: %s\n",
           aliveUntilPoolDrain ? "PASS" : "FAIL");
    printf("arc-return-release-before-pool-balanced: %s\n",
           releasedByPoolDrain ? "PASS" : "FAIL");
    return aliveUntilPoolDrain && releasedByPoolDrain;
}

static BOOL LC32TestARCWeakOnlyBorrowedReturn(void) {
    void *nativePool = LC32CreateBridgedAutoreleasePool();

    /*
     * GTMHTTPFetcher uses this exact ownership shape in
     * -[YTBaseService performBackgroundBlock:cancellationBlock:]: the +0
     * NSBlockOperation convenience result is stored only in a __weak local,
     * loaded to set its completion block, then loaded again for addOperation:.
     * There is deliberately no strong local retaining the proxy between the
     * generated shim return and objc_initWeak/objc_loadWeak.
     */
    __weak NSBlockOperation *weakOperation =
        [NSBlockOperation blockOperationWithBlock:^{}];
    [weakOperation setCompletionBlock:^{}];
    const BOOL callableBeforePoolDrain = weakOperation != nil;
    weakOperation.completionBlock = nil;

    LC32DrainBridgedAutoreleasePool(nativePool);
    const BOOL zeroedAfterPoolDrain = weakOperation == nil;

    printf("arc-weak-only-borrowed-return-callable: %s\n",
           callableBeforePoolDrain ? "PASS" : "FAIL");
    printf("arc-weak-only-borrowed-return-zeroed: %s\n",
           zeroedAfterPoolDrain ? "PASS" : "FAIL");
    return callableBeforePoolDrain && zeroedAfterPoolDrain;
}

int main(void) {
    __strong NSBlockOperation *operation = nil;

    void *nativePool = LC32CreateBridgedAutoreleasePool();
    operation = [NSBlockOperation blockOperationWithBlock:^{}];
    LC32DrainBridgedAutoreleasePool(nativePool);

    /*
     * The native convenience result has now left its autorelease pool.  ARC's
     * strong reference to the ARM32 proxy must also have retained the native
     * peer; YouTube reaches this same sequence before setCompletionBlock:.
     */
    [operation setCompletionBlock:^{}];
    operation.name = @"LC32 autoreleased operation";
    const BOOL callableAfterPoolDrain =
        [operation.name isEqualToString:@"LC32 autoreleased operation"] &&
        !operation.cancelled;
    [operation cancel];
    const BOOL passed = callableAfterPoolDrain && operation.cancelled;
    printf("arc-proxy-survives-native-autorelease: %s\n",
           passed ? "PASS" : "FAIL");

    /* Do not run the blocks: native Foundation is allowed to execute an
     * operation callback on a host worker which has no registered guest JIT.
     * Clearing them still checks the exact setter which received YouTube's
     * stale NSBlockOperation, while keeping this test single-threaded. */
    operation.completionBlock = nil;
    operation = nil;

    /*
     * Run the exact non-retaining call shape from an MRC translation unit.
     * A strong ARC local would emit objc_retainAutoreleasedReturnValue and
     * conceal a missing +0 bridge lifetime.
     */
    const BOOL unretainedBorrowedPassed =
        LC32TestBorrowedReturnWithoutImmediateRetain();
    const BOOL directObjCRetainPassed =
        LC32TestDirectObjCRetainBridgesHost();
    const BOOL retainedFamilyPassed =
        LC32TestRetainedFamilyReturnExclusion();
    const BOOL arcGeneratedShimPassed =
        LC32TestARCGeneratedBorrowedReturn();
    const BOOL arcEarlyReleasePassed =
        LC32TestARCReleaseBeforeNativePoolDrain();
    const BOOL arcWeakOnlyPassed =
        LC32TestARCWeakOnlyBorrowedReturn();
    return passed && unretainedBorrowedPassed && directObjCRetainPassed &&
        retainedFamilyPassed && arcGeneratedShimPassed &&
        arcEarlyReleasePassed && arcWeakOnlyPassed ? 0 : 1;
}
