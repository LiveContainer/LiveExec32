#import <Foundation/Foundation.h>

#include <stdio.h>

static NSUInteger deallocCount;

@interface LC32GuestProxyLifetimeProbe : NSObject {
    NSUInteger marker;
}
- (NSUInteger)marker;
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
    LC32GuestProxyLifetimeProbe *probe =
        [[LC32GuestProxyLifetimeProbe alloc] init];

    [hostBackedArray addObject:probe];
    [probe release];

    LC32GuestProxyLifetimeProbe *stored =
        [hostBackedArray objectAtIndex:0];
    const BOOL survivedHostOwnership =
        [stored marker] == 0x51a7;
    printf("host-retains-guest-proxy: %s\n",
        survivedHostOwnership ? "PASS" : "FAIL");

    [hostBackedArray removeAllObjects];
    const BOOL releasedWithHostOwnership = deallocCount == 1;
    printf("host-releases-guest-proxy: %s\n",
        releasedWithHostOwnership ? "PASS" : "FAIL");

    NSAutoreleasePool *innerPool = [NSAutoreleasePool new];
    LC32GuestProxyLifetimeProbe *autoreleasedProbe =
        [[[LC32GuestProxyLifetimeProbe alloc] init] autorelease];
    [hostBackedArray addObject:autoreleasedProbe];
    [innerPool drain];

    LC32GuestProxyLifetimeProbe *storedAutoreleased =
        [hostBackedArray objectAtIndex:0];
    const BOOL survivedGuestAutoreleasePool =
        [storedAutoreleased marker] == 0x51a7 && deallocCount == 1;
    printf("host-retains-autoreleased-guest-proxy: %s\n",
        survivedGuestAutoreleasePool ? "PASS" : "FAIL");

    [hostBackedArray removeAllObjects];
    const BOOL autoreleasedProxyDeallocatedOnce = deallocCount == 2;
    printf("host-releases-autoreleased-guest-proxy-once: %s\n",
        autoreleasedProxyDeallocatedOnce ? "PASS" : "FAIL");

    [hostBackedArray release];
    [pool drain];
    return !(survivedHostOwnership && releasedWithHostOwnership &&
             survivedGuestAutoreleasePool &&
             autoreleasedProxyDeallocatedOnce);
}
