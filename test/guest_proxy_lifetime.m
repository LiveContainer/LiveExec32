#import <Foundation/Foundation.h>

#include <stdio.h>

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
    const BOOL survivedHostOwnership =
        [stored marker] == 0x51a7;
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
    const BOOL survivedGuestAutoreleasePool =
        [storedAutoreleased marker] == 0x51a7 && deallocCount == 2;
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
        cleanupArray.count == 0 && cleanupCallbackCount == 1 &&
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
        cleanupArray.count == 0 && cleanupCallbackCount == 2 &&
        cleanupDeallocCount == 2;
    printf("native-final-release-keeps-host-peer-alive: %s\n",
        nativeFinalCleanupPassed ? "PASS" : "FAIL");

    [cleanupArray release];
    cleanupArray = nil;

    [hostBackedArray release];
    [pool drain];
    return !(guestOnlyObjectStayedLocal && survivedHostOwnership &&
             releasedWithHostOwnership &&
             survivedGuestAutoreleasePool &&
             autoreleasedProxyDeallocatedOnce &&
             guestFinalCleanupPassed && nativeFinalCleanupPassed);
}
