#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>

extern uint64_t LC32LookupHostMapping(uint32_t guestObject);

@interface NSObject (LC32RootDeallocReentry)
- (uint64_t)host_self;
@end

typedef struct {
    unsigned callbacks;
    uint64_t before;
    uint64_t resolved;
    uint64_t after;
    uint64_t afterNested;
} Observation;

static char observationKey;
static unsigned failures;

static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

@interface LC32RootAssociationProbe : NSObject {
@public
    id owner; // Unretained; it is still allocated while its associations die.
    Observation *observation;
    id nestedOwner; // Optional transferred +1, released inside outer cleanup.
}
@end

@implementation LC32RootAssociationProbe
- (void)dealloc {
    const uint32_t address = (uint32_t)(uintptr_t)owner;
    observation->callbacks++;
    observation->before = LC32LookupHostMapping(address);
    observation->resolved = [owner host_self];
    observation->after = LC32LookupHostMapping(address);
    if(nestedOwner) {
        [nestedOwner release];
        observation->afterNested = [owner host_self];
    }
    [super dealloc];
}
@end

static void observeRootCleanup(id owner, Observation *observation, id nestedOwner) {
    // No native mirror for the observer: its last guest association reference
    // must invoke -dealloc synchronously inside owner's object_dispose.
    LC32RootAssociationProbe *probe = class_createInstance(
        [LC32RootAssociationProbe class], 0);
    probe->owner = owner;
    probe->observation = observation;
    probe->nestedOwner = nestedOwner;
    objc_setAssociatedObject(owner, &observationKey, probe,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [probe release];
}

@interface LC32OwnedTeardownProbe : NSObject
@end

@implementation LC32OwnedTeardownProbe
@end

static Observation subclassCleanup;
@interface LC32GuestOnlySubclassTeardown : NSObject
@end
@implementation LC32GuestOnlySubclassTeardown
- (void)dealloc {
    const uint32_t address = (uint32_t)(uintptr_t)self;
    subclassCleanup.callbacks++;
    subclassCleanup.before = LC32LookupHostMapping(address);
    subclassCleanup.resolved = [self host_self];
    subclassCleanup.after = LC32LookupHostMapping(address);
    [super dealloc];
}
@end

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    Observation detached = {};
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    // The convenience result's native autorelease drains its lifetime pin.
    // Guest root -dealloc has detached that dead peer by the time libobjc
    // releases this object's associated observer.
    NSMutableData *data = [NSMutableData dataWithLength:32];
    observeRootCleanup(data, &detached, nil);
    [pool drain];
    check("root-association-runs-before-free",
        detached.callbacks == 1);
    check("root-association-observes-detached-key", detached.before == 0);
    check("root-association-does-not-recreate-peer",
        detached.resolved == 0 && detached.after == 0);
    if(detached.callbacks != 1 ||
            detached.before || detached.resolved || detached.after) {
        printf("  callbacks=%u before=0x%llx "
               "resolved=0x%llx after=0x%llx\n", detached.callbacks,
            (unsigned long long)detached.before,
            (unsigned long long)detached.resolved,
            (unsigned long long)detached.after);
    }

    Observation owned = {};
    pool = [NSAutoreleasePool new];
    LC32OwnedTeardownProbe *object = [LC32OwnedTeardownProbe new];
    const uint64_t nativePeer = [object host_self];
    observeRootCleanup(object, &owned, nil);
    [object release];
    [pool drain];
    check("root-owned-teardown-keeps-native-peer",
        nativePeer && owned.callbacks == 1 &&
        owned.before == nativePeer && owned.resolved == nativePeer &&
        owned.after == nativePeer);
    if(!nativePeer || owned.callbacks != 1 ||
            owned.before != nativePeer || owned.resolved != nativePeer ||
            owned.after != nativePeer) {
        printf("  peer=0x%llx callbacks=%u before=0x%llx "
               "resolved=0x%llx after=0x%llx\n",
            (unsigned long long)nativePeer, owned.callbacks,
            (unsigned long long)owned.before,
            (unsigned long long)owned.resolved,
            (unsigned long long)owned.after);
    }

    // Association cleanup structurally runs during root disposal. Nest a
    // second owner's complete root cleanup, then reenter the first owner:
    // leaving the inner scope must restore, not clear, the outer TLS frame.
    Observation outer = {}, inner = {};
    pool = [NSAutoreleasePool new];
    id innerOwner = class_createInstance([LC32OwnedTeardownProbe class], 0);
    observeRootCleanup(innerOwner, &inner, nil);
    data = [NSMutableData dataWithLength:16];
    observeRootCleanup(data, &outer, innerOwner);
    [pool drain];
    check("nested-root-cleanup-rejects-inner-reentry", inner.callbacks == 1 &&
        inner.before == 0 && inner.resolved == 0 && inner.after == 0);
    check("nested-root-cleanup-restores-outer-frame", outer.callbacks == 1 &&
        outer.before == 0 && outer.resolved == 0 && outer.after == 0 &&
        outer.afterNested == 0);

    // The zero-count scope begins before subclass cleanup, not just at the
    // eventual NSObject root implementation.
    id guestOnly = class_createInstance([LC32GuestOnlySubclassTeardown class], 0);
    [guestOnly release];
    check("guest-only-subclass-does-not-recreate-peer",
        subclassCleanup.callbacks == 1 && subclassCleanup.before == 0 &&
        subclassCleanup.resolved == 0 && subclassCleanup.after == 0);

    // A normal unmapped guest and a class must still be able to acquire peers.
    pool = [NSAutoreleasePool new];
    id unmapped = class_createInstance([LC32OwnedTeardownProbe class], 0);
    const BOOL initiallyUnmapped = LC32LookupHostMapping(
        (uint32_t)(uintptr_t)unmapped) == 0;
    check("live-unmapped-object-can-create-peer", initiallyUnmapped &&
        [unmapped host_self] != 0);
    check("class-can-resolve-peer", [[LC32OwnedTeardownProbe class]
        host_self] != 0);
    [unmapped release];
    [pool drain];
    return failures ? 1 : 0;
}
