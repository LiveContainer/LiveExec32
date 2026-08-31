#import <Foundation/Foundation.h>

#include <stdio.h>
#include <LC32ObjCBridgeABI.h>

@interface NSObject (LC32GuestProxyLifetimeTests)
- (uint64_t)host_self;
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(
    uint64_t object, uint64_t selector, ...);
extern id LC32HostToGuestObject(uint64_t hostObject);
extern uint64_t LC32LookupHostMapping(uint32_t guestObject);

static NSUInteger deallocCount;
static NSUInteger cleanupDeallocCount;
static NSUInteger cleanupCallbackCount;
static NSMutableArray *cleanupArray;

@interface LC32GuestProxyLifetimeProbe : NSObject {
    NSUInteger marker;
}
- (NSUInteger)marker;
@end

@interface LC32GuestProxyDeallocCleanupProbe : NSObject
@end

@implementation LC32GuestProxyDeallocCleanupProbe
- (void)dealloc {
    cleanupCallbackCount++;
    [cleanupArray removeObject:self];
    cleanupDeallocCount++;
    [super dealloc];
}
@end

@implementation LC32GuestProxyLifetimeProbe
- (instancetype)init {
    if((self = [super init])) {
        marker = 0x51a7;
    }
    return self;
}

- (NSUInteger)marker {
    return marker;
}

- (void)dealloc {
    deallocCount++;
    [super dealloc];
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSMutableArray *hostBackedArray = [[NSMutableArray alloc] init];

    LC32GuestProxyLifetimeProbe *guestOnlyProbe =
        [[LC32GuestProxyLifetimeProbe alloc] init];
    [guestOnlyProbe release];
    const BOOL guestOnlyObjectStayedLocal = deallocCount == 1;
    printf("guest-only-object-stays-local: %s\n",
        guestOnlyObjectStayedLocal ? "PASS" : "FAIL");

    /* Deliberately consume the provisional native peer without releasing its
     * guest allocation. The authoritative entry remains Live while its native
     * weak slot becomes nil; a later cached raw-address dispatch must return
     * safely instead of reading the freed object's isa. */
    NSAutoreleasePool *stalePool = [NSAutoreleasePool new];
    NSObject *staleMappedProbe = [NSObject alloc];
    const uint32_t staleGuestAddress =
        (uint32_t)(uintptr_t)staleMappedProbe;
    const uint64_t staleHostAddress = staleMappedProbe.host_self;
    const BOOL staleMappedSetupSucceeded = staleMappedProbe != nil &&
        staleHostAddress != 0 &&
        LC32LookupHostMapping(staleGuestAddress) == staleHostAddress;
    LC32InvokeHostSelector(staleHostAddress,
        LC32GetHostSelector(@selector(release)), (uint64_t)0);
    const uint64_t staleRetainCount = LC32InvokeHostSelector(
        staleHostAddress, LC32GetHostSelector(@selector(retainCount)),
        (uint64_t)0);
    const BOOL staleMappedReceiverWasRejected = staleRetainCount == 0;
    [staleMappedProbe autorelease];
    [stalePool drain];
    const BOOL staleMappingWasRemoved =
        LC32LookupHostMapping(staleGuestAddress) == 0;
    const uint64_t staleAfterCleanupRetainCount = LC32InvokeHostSelector(
        staleHostAddress, LC32GetHostSelector(@selector(retainCount)),
        (uint64_t)0);
    const BOOL staleUnmappedReceiverWasRejected =
        staleAfterCleanupRetainCount == 0 && staleMappingWasRemoved;
    printf("dead-mapped-receiver-setup: %s\n",
        staleMappedSetupSucceeded ? "PASS" : "FAIL");
    printf("dead-mapped-receiver-is-rejected: %s\n",
        staleMappedReceiverWasRejected ? "PASS" : "FAIL");
    printf("dead-unmapped-receiver-is-rejected: %s\n",
        staleUnmappedReceiverWasRejected ? "PASS" : "FAIL");

    const uint64_t arbitraryReceiverResult = LC32InvokeHostSelector(
        UINT64_C(0x1b8), LC32GetHostSelector(@selector(retainCount)),
        (uint64_t)0);
    const BOOL arbitraryUnmappedReceiverWasRejected =
        arbitraryReceiverResult == 0;
    printf("arbitrary-unmapped-receiver-is-rejected: %s\n",
        arbitraryUnmappedReceiverWasRejected ? "PASS" : "FAIL");

    const uint64_t rawOwnedHostObject = LC32InvokeHostSelector(
        [(id)NSObject.class host_self],
        LC32GetHostSelector(@selector(new)), (uint64_t)0);
    const uint64_t rawOwnedRetainCount = LC32InvokeHostSelector(
        rawOwnedHostObject,
        LC32GetHostSelector(@selector(retainCount)) |
            LC32_HOST_SELECTOR_ALLOW_UNMAPPED_RECEIVER,
        (uint64_t)0);
    LC32InvokeHostSelector(rawOwnedHostObject,
        LC32GetHostSelector(@selector(release)) |
            LC32_HOST_SELECTOR_ALLOW_UNMAPPED_RECEIVER,
        (uint64_t)0);
    const BOOL explicitlyOwnedUnmappedReceiverWorked =
        rawOwnedHostObject != 0 && rawOwnedRetainCount == 1;
    printf("explicitly-owned-unmapped-receiver-works: %s\n",
        explicitlyOwnedUnmappedReceiverWorked ? "PASS" : "FAIL");

    /* A native-to-guest conversion installs a Pinned mapping. Destroy its
     * native peer while an extra guest owner remains, reproducing the state
     * created when LC32GuestLifetimePin runs during native deallocation. The
     * Retiring entry belongs to this thread, but it has no native lifetime
     * lease and therefore must still reject a later raw-address dispatch. */
    const uint64_t hostNSObjectClass = [(id)NSObject.class host_self];
    const uint64_t deadPinnedHostAddress = LC32InvokeHostSelector(
        hostNSObjectClass, LC32GetHostSelector(@selector(new)),
        (uint64_t)0);
    NSObject *deadPinnedProbe =
        LC32HostToGuestObject(deadPinnedHostAddress);
    const uint32_t deadPinnedGuestAddress =
        (uint32_t)(uintptr_t)deadPinnedProbe;
    const uint64_t hostRelease =
        LC32GetHostSelector(@selector(release));
    const BOOL deadPinnedSetupSucceeded = hostNSObjectClass != 0 &&
        deadPinnedHostAddress != 0 && deadPinnedProbe != nil &&
        LC32LookupHostMapping(deadPinnedGuestAddress) ==
            deadPinnedHostAddress;
    BOOL deadPinnedReceiverWasRejected = NO;
    BOOL deadPinnedMappingBecameDead = NO;
    BOOL deadPinnedMappingWasCleaned = NO;
    if(deadPinnedSetupSucceeded) {
        [deadPinnedProbe retain];
        LC32InvokeHostSelector(
            deadPinnedHostAddress, hostRelease, (uint64_t)0);
        LC32InvokeHostSelector(
            deadPinnedHostAddress, hostRelease, (uint64_t)0);
        deadPinnedMappingBecameDead =
            LC32LookupHostMapping(deadPinnedGuestAddress) ==
                LC32_HOST_MAPPING_DEAD;
        const uint64_t deadPinnedRetainCount = LC32InvokeHostSelector(
            deadPinnedHostAddress,
            LC32GetHostSelector(@selector(retainCount)), (uint64_t)0);
        deadPinnedReceiverWasRejected = deadPinnedRetainCount == 0;
        [deadPinnedProbe release];
        const BOOL deadPinnedMappingWasRemoved =
            LC32LookupHostMapping(deadPinnedGuestAddress) == 0;
        const uint64_t deadPinnedAfterCleanupRetainCount =
            LC32InvokeHostSelector(deadPinnedHostAddress,
                LC32GetHostSelector(@selector(retainCount)), (uint64_t)0);
        deadPinnedMappingWasCleaned =
            deadPinnedAfterCleanupRetainCount == 0 &&
            deadPinnedMappingWasRemoved;
    } else if(deadPinnedHostAddress) {
        /* The raw +1 from +new must not leak merely because proxy setup failed. */
        LC32InvokeHostSelector(deadPinnedHostAddress,
            hostRelease | LC32_HOST_SELECTOR_ALLOW_UNMAPPED_RECEIVER,
            (uint64_t)0);
    }
    printf("dead-retiring-pinned-receiver-setup: %s\n",
        deadPinnedSetupSucceeded ? "PASS" : "FAIL");
    printf("dead-pinned-mapping-becomes-dead: %s\n",
        deadPinnedMappingBecameDead ? "PASS" : "FAIL");
    printf("dead-retiring-pinned-receiver-is-rejected: %s\n",
        deadPinnedReceiverWasRejected ? "PASS" : "FAIL");
    printf("dead-pinned-mapping-is-cleaned: %s\n",
        deadPinnedMappingWasCleaned ? "PASS" : "FAIL");

    LC32GuestProxyLifetimeProbe *probe =
        [[LC32GuestProxyLifetimeProbe alloc] init];

    // Retains which predate the first host_self lookup must be transferred to
    // the lazily-created native peer. Otherwise the second release below can
    // destroy that peer while hostBackedArray still holds it.
    [probe retain];
    [hostBackedArray addObject:probe];
    [probe release];
    [probe release];

    LC32GuestProxyLifetimeProbe *stored =
        [hostBackedArray objectAtIndex:0];
    const NSUInteger storedMarker = [stored marker];
    const BOOL survivedHostOwnership = hostBackedArray != nil &&
        probe != nil && storedMarker == 0x51a7 && deallocCount == 1;
    if(!survivedHostOwnership) {
        fprintf(stderr,
            "pre-retained proxy diagnostic: original=%p stored=%p "
            "marker=0x%lx deallocCount=%lu\n",
            probe, stored, (unsigned long)storedMarker,
            (unsigned long)deallocCount);
    }
    printf("host-retains-pre-retained-guest-proxy: %s\n",
        survivedHostOwnership ? "PASS" : "FAIL");

    [hostBackedArray removeAllObjects];
    const BOOL releasedWithHostOwnership = deallocCount == 2;
    printf("host-releases-guest-proxy: %s\n",
        releasedWithHostOwnership ? "PASS" : "FAIL");

    NSAutoreleasePool *innerPool = [NSAutoreleasePool new];
    // Schedule autorelease while the object is still guest-only, then make
    // addObject: perform its first host_self lookup before the pool drains.
    LC32GuestProxyLifetimeProbe *autoreleasedProbe =
        [[[LC32GuestProxyLifetimeProbe alloc] init] autorelease];
    [hostBackedArray addObject:autoreleasedProbe];
    [innerPool drain];

    LC32GuestProxyLifetimeProbe *storedAutoreleased =
        [hostBackedArray objectAtIndex:0];
    const NSUInteger storedAutoreleasedMarker =
        [storedAutoreleased marker];
    const BOOL survivedGuestAutoreleasePool = hostBackedArray != nil &&
        autoreleasedProbe != nil &&
        storedAutoreleasedMarker == 0x51a7 && deallocCount == 2;
    if(!survivedGuestAutoreleasePool) {
        fprintf(stderr,
            "autoreleased proxy diagnostic: original=%p stored=%p "
            "marker=0x%lx deallocCount=%lu\n",
            autoreleasedProbe, storedAutoreleased,
            (unsigned long)storedAutoreleasedMarker,
            (unsigned long)deallocCount);
    }
    printf("host-retains-autoreleased-guest-proxy: %s\n",
        survivedGuestAutoreleasePool ? "PASS" : "FAIL");

    [hostBackedArray removeAllObjects];
    const BOOL autoreleasedProxyDeallocatedOnce = deallocCount == 3;
    printf("host-releases-autoreleased-guest-proxy-once: %s (count=%lu)\n",
        autoreleasedProxyDeallocatedOnce ? "PASS" : "FAIL",
        (unsigned long)deallocCount);

    cleanupArray = [[NSMutableArray alloc] init];

    /* The guest is the last logical owner. Its -dealloc still sends `self`
     * through a host collection, so the synthesized native mirror must remain
     * retainable until guest teardown completes. */
    LC32GuestProxyDeallocCleanupProbe *guestFinalProbe =
        [[LC32GuestProxyDeallocCleanupProbe alloc] init];
    [cleanupArray addObject:guestFinalProbe];
    [cleanupArray removeObject:guestFinalProbe];
    [guestFinalProbe release];
    const BOOL guestFinalCleanupPassed =
        cleanupArray != nil && cleanupArray.count == 0 &&
        cleanupCallbackCount == 1 &&
        cleanupDeallocCount == 1;
    printf("guest-final-release-keeps-host-peer-alive: %s\n",
        guestFinalCleanupPassed ? "PASS" : "FAIL");

    /* The native collection is now the last owner. removeAllObjects empties
     * its storage before releasing members; the guest dealloc's defensive
     * duplicate remove therefore exercises reentrant native retain/release
     * without using a released guest variable. */
    LC32GuestProxyDeallocCleanupProbe *nativeFinalProbe =
        [[LC32GuestProxyDeallocCleanupProbe alloc] init];
    [cleanupArray addObject:nativeFinalProbe];
    [nativeFinalProbe release];
    [cleanupArray removeAllObjects];
    const BOOL nativeFinalCleanupPassed =
        cleanupArray != nil && cleanupArray.count == 0 &&
        cleanupCallbackCount == 2 &&
        cleanupDeallocCount == 2;
    printf("native-final-release-keeps-host-peer-alive: %s\n",
        nativeFinalCleanupPassed ? "PASS" : "FAIL");

    [cleanupArray release];
    cleanupArray = nil;

    [hostBackedArray release];
    [pool drain];
    return !(guestOnlyObjectStayedLocal &&
             staleMappedSetupSucceeded &&
             staleMappedReceiverWasRejected &&
             staleUnmappedReceiverWasRejected &&
             arbitraryUnmappedReceiverWasRejected &&
             explicitlyOwnedUnmappedReceiverWorked &&
             deadPinnedSetupSucceeded && deadPinnedMappingBecameDead &&
             deadPinnedReceiverWasRejected &&
             deadPinnedMappingWasCleaned && survivedHostOwnership &&
             releasedWithHostOwnership &&
             survivedGuestAutoreleasePool &&
             autoreleasedProxyDeallocatedOnce &&
             guestFinalCleanupPassed && nativeFinalCleanupPassed);
}
