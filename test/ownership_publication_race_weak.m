#import <Foundation/Foundation.h>

#include <mach/mach_traps.h>

#include "ownership_publication_race.h"

@interface NSObject (LC32OwnershipPublicationRaceMarker)
- (NSUInteger)lc32_ownershipPublicationMarker;
@end

/*
 * Keep this worker in its own ARC translation unit.  The strong assignment
 * below must compile to a real objc_loadWeakRetained/objc_release pair while
 * the object is still guest-only or is acquiring its first native mirror.
 */
void *LC32OwnershipPublicationWeakWorker(void *opaqueContext) {
    @autoreleasepool {
        LC32OwnershipPublicationWeakWorkerContext *context =
            opaqueContext;
        LC32OwnershipPublicationRaceState *state = context->state;

        __weak id weakProbe = (__bridge id)
            LC32OwnershipPublicationRawProbe(state);
        if(!LC32OwnershipPublicationWorkerReadyAndWait(
                state, context->workerIndex)) {
            return NULL;
        }

        /* Exercise both sides of the publication race rather than always
         * letting the first-created worker win the gate. */
        const unsigned int iteration =
            LC32OwnershipPublicationIteration(state);
        if(((iteration + context->workerIndex) & 1U) != 0) {
            swtch();
        }

        __strong id loadedProbe = weakProbe;
        const BOOL racyLoadSucceeded = loadedProbe != nil;
        if(!loadedProbe) {
            /* A weak try-retain is deliberately allowed to lose to a closed
             * publication gate rather than waiting under libobjc's weak
             * SideTable lock. Retry after publication while the original
             * guest owner is still held; that second load must succeed. */
            if(!LC32OwnershipPublicationWaitForPublisher(state)) {
                return NULL;
            }
            loadedProbe = weakProbe;
        }
        const BOOL loadedObject = loadedProbe != nil;
        const BOOL markerPassed = loadedObject &&
            [loadedProbe lc32_ownershipPublicationMarker] ==
                LC32OwnershipPublicationMarker;

        /* Hold this +1 until the publisher has removed its collection retain,
         * the retain churn is balanced, and the original guest owner is
         * released.  The last weak temporary must then drive an exactly-once
         * coordinated final release. */
        LC32OwnershipPublicationRecordWeakLoadAndWait(
            state, context->workerIndex,
            racyLoadSucceeded, loadedObject, markerPassed);
        loadedProbe = nil;
    }
    return NULL;
}
