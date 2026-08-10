#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdio.h>

@interface NSObject (LC32CxxLifecycleTest)
- (uint64_t)host_self;
@end

static int LC32GuestConstructorCount;
static int LC32GuestDestructorCount;

struct LC32LifecycleTracker {
    LC32LifecycleTracker() {
        LC32GuestConstructorCount++;
    }
    ~LC32LifecycleTracker() {
        LC32GuestDestructorCount++;
    }
};

// UIViewController gives the host mirror an inherited native C++ lifecycle
// chain as well as the guest subclass's own .cxx_construct/.cxx_destruct.
// Mirroring the latter through a normal Objective-C IMP used to treat x1 as a
// selector even though the runtime calls these hooks with self only.
@interface LC32CxxLifecycleProbe : UIViewController {
    LC32LifecycleTracker _tracker;
}
@end

@implementation LC32CxxLifecycleProbe
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    LC32CxxLifecycleProbe *probe =
        [[LC32CxxLifecycleProbe alloc] init];

    // Force creation of the corresponding dynamic host subclass.
    (void)probe.host_self;
    [probe release];

    // UIViewController's native initializer keeps temporary ownership in the
    // current host autorelease pool. The mirror (and therefore its guest-only
    // lifetime pin) is allowed to outlive the guest's explicit release until
    // that pool drains.
    [pool drain];

    const BOOL passed = LC32GuestConstructorCount == 1 &&
        LC32GuestDestructorCount == 1;
    printf("guest-cxx-lifecycle: %s (construct=%d destruct=%d)\n",
        passed ? "PASS" : "FAIL", LC32GuestConstructorCount,
        LC32GuestDestructorCount);
    return !passed;
}
