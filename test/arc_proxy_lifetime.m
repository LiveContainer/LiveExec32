#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdio.h>
#include <LC32ObjCBridgeABI.h>

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

@interface NSObject (LC32InitializerAdoptionTests)
- (uint64_t)host_self;
@end

static NSUInteger LC32ARCGuestViewDeallocCount;

@interface LC32ARCGuestView : UIView
@end

@implementation LC32ARCGuestView
- (void)dealloc {
    LC32ARCGuestViewDeallocCount++;
}
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(
    uint64_t object, uint64_t selector, ...);
extern uint64_t LC32LookupHostMapping(uint32_t guestObject);
extern id LC32AdoptHostInitializerResultARC(
    id object, uint64_t hostResult) NS_RETURNS_RETAINED;

static id LC32CreateARCAdoptedObject(Class cls) NS_RETURNS_RETAINED;

static id LC32CreateARCAdoptedObject(Class cls) {
    id allocatedObject = [cls alloc];
    const uint64_t hostResult = LC32InvokeHostSelector(
        [allocatedObject host_self], LC32GetHostSelector(@selector(init)),
        (uint64_t)0);
    return LC32AdoptHostInitializerResultARC(allocatedObject, hostResult);
}

static BOOL LC32TestARCInitializerAdoption(void) {
    /* Prime NSDictionary's native empty singleton so the explicit initializer
     * must return an existing canonical guest proxy rather than its freshly
     * allocated receiver. */
    __strong NSDictionary *convenienceDictionary =
        [NSDictionary dictionary];
    __strong NSDictionary *initializedDictionary =
        LC32CreateARCAdoptedObject(NSDictionary.class);
    const BOOL canonicalPassed = convenienceDictionary != nil &&
        initializedDictionary != nil &&
        initializedDictionary == convenienceDictionary &&
        initializedDictionary.count == 0 &&
        [initializedDictionary objectForKey:@"missing"] == nil;
    initializedDictionary = nil;
    const BOOL canonicalSurvivedRelease =
        [convenienceDictionary objectForKey:@"missing"] == nil;

    /* A mutable dictionary initializer returns a unique native instance, so
     * its result binds to the allocated guest receiver. This exercises the ARC
     * helper's paired retain which is balanced by strong-local cleanup. */
    __strong NSMutableDictionary *initializedMutableDictionary =
        LC32CreateARCAdoptedObject(NSMutableDictionary.class);
    const uint32_t directGuestAddress =
        (uint32_t)(uintptr_t)initializedMutableDictionary;
    const uint64_t directHostAddress =
        LC32LookupHostMapping(directGuestAddress);
    const BOOL directMappingWasLive = directGuestAddress != 0 &&
        directHostAddress != 0 &&
        directHostAddress != LC32_HOST_MAPPING_DEAD;
    const uint64_t reverseMappedGuest = directMappingWasLive
        ? LC32InvokeHostSelector(
            directHostAddress, LC32GetHostSelector(@selector(guest_self)),
            (uint64_t)0)
        : 0;
    const BOOL directMappingStayedLive = directMappingWasLive &&
        LC32LookupHostMapping(directGuestAddress) == directHostAddress;
    const BOOL directPassed = initializedMutableDictionary != nil &&
        directMappingWasLive && directMappingStayedLive &&
        initializedMutableDictionary.count == 0 &&
        (uint32_t)reverseMappedGuest == directGuestAddress;
    initializedMutableDictionary = nil;

    printf("arc-initializer-canonical-adoption: %s\n",
           canonicalPassed && canonicalSurvivedRelease ? "PASS" : "FAIL");
    printf("arc-initializer-direct-adoption: %s\n",
           directPassed ? "PASS" : "FAIL");
    return canonicalPassed && canonicalSurvivedRelease && directPassed;
}

static BOOL LC32TestARCGuestMirrorInitializerHandoff(void) {
    /* The regression is initializer ownership. A nonzero size still exercises
     * the CGRect argument and return bridges without coupling lifetime coverage
     * to the separate origin-translation behavior. */
    const CGRect initialFrame = CGRectMake(0.0, 0.0, 180.0, 48.0);
    const NSUInteger deallocCountBefore =
        LC32ARCGuestViewDeallocCount;
    __strong LC32ARCGuestView *view =
        [[LC32ARCGuestView alloc] initWithFrame:initialFrame];
    const uint32_t guestAddress = (uint32_t)(uintptr_t)view;
    const uint64_t hostAddress = LC32LookupHostMapping(guestAddress);
    const BOOL mappingWasLive = guestAddress != 0 && hostAddress != 0 &&
        hostAddress != LC32_HOST_MAPPING_DEAD;
    const CGRect returnedFrame = view.frame;
    const BOOL frameMatches =
        returnedFrame.origin.x == initialFrame.origin.x &&
        returnedFrame.origin.y == initialFrame.origin.y &&
        returnedFrame.size.width == initialFrame.size.width &&
        returnedFrame.size.height == initialFrame.size.height;
    const BOOL classMatches =
        [view isKindOfClass:LC32ARCGuestView.class];
    const BOOL initialized = view != nil && frameMatches && classMatches;
    const BOOL mappingStayedLive = mappingWasLive &&
        LC32LookupHostMapping(guestAddress) == hostAddress;
    view = nil;
    const BOOL mappingWasRemoved = guestAddress != 0 &&
        LC32LookupHostMapping(guestAddress) == 0;
    const BOOL passed = initialized && mappingWasLive && mappingStayedLive &&
        mappingWasRemoved &&
        LC32ARCGuestViewDeallocCount == deallocCountBefore + 1;

    printf("arc-guest-mirror-initializer-handoff: %s\n",
           passed ? "PASS" : "FAIL");
    if(!passed) {
        printf("  initialized=%d frame=%d class=%d "
               "actual={{%.0f,%.0f},{%.0f,%.0f}} "
               "mapping-live=%d mapping-stayed-live=%d "
               "mapping-removed=%d dealloc=%lu->%lu "
               "guest=0x%08x host=0x%llx\n",
               initialized, frameMatches, classMatches,
               returnedFrame.origin.x, returnedFrame.origin.y,
               returnedFrame.size.width, returnedFrame.size.height,
               mappingWasLive, mappingStayedLive, mappingWasRemoved,
               (unsigned long)deallocCountBefore,
               (unsigned long)LC32ARCGuestViewDeallocCount, guestAddress,
               (unsigned long long)hostAddress);
    }
    return passed;
}

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
    const BOOL arcInitializerAdoptionPassed =
        LC32TestARCInitializerAdoption();
    const BOOL arcGuestMirrorInitializerPassed =
        LC32TestARCGuestMirrorInitializerHandoff();
    return passed && unretainedBorrowedPassed && directObjCRetainPassed &&
        retainedFamilyPassed && arcGeneratedShimPassed &&
        arcEarlyReleasePassed && arcWeakOnlyPassed &&
        arcInitializerAdoptionPassed &&
        arcGuestMirrorInitializerPassed ? 0 : 1;
}
