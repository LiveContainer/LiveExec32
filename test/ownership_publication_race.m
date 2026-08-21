#import <Foundation/Foundation.h>

#include <mach/mach_traps.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ownership_publication_race.h"

extern id objc_retain(id object);
extern void objc_release(id object);

enum {
    LC32WeakWorkerCount = 2,
    LC32WorkerCount = LC32WeakWorkerCount + 2,
    LC32PublisherWorkerIndex = 2,
    LC32RetainWorkerIndex = 3,
    LC32RetainChurnCount = 32,
    LC32DefaultIterationCount = 128,
    LC32WeakResultRacyLoad = 1U << 0,
    LC32WeakResultLoadedObject = 1U << 1,
    LC32WeakResultMarkerPassed = 1U << 2,
};

static NSUInteger LC32RacyWeakLoadCount;
static NSUInteger LC32ProbeDeallocCount;

static BOOL LC32OwnershipPublicationTraceEnabled(void) {
    const char *value = getenv("LC32_PUBLICATION_RACE_TRACE");
    return value && value[0] && strcmp(value, "0") != 0;
}

#define LC32_PUBLICATION_TRACE(state, format, ...) do { \
    if(LC32OwnershipPublicationTraceEnabled()) { \
        fprintf(stderr, "ownership-publication[%u]: " format "\n", \
            (state)->iteration, ##__VA_ARGS__); \
        fflush(stderr); \
    } \
} while(0)

struct LC32OwnershipPublicationRaceState {
    NSMutableArray *hostArray;
    void *probe;
    unsigned int iteration;
    uint32_t workerReady[LC32WorkerCount];
    uint32_t workerResult[LC32WorkerCount];
    uint32_t workerCompleted[LC32WorkerCount];
    uint32_t startWorkers;
    uint32_t releaseWeakLoads;
    uint32_t cancelled;
    uint32_t probeDeallocated;
};

@interface LC32OwnershipPublicationProbe : NSObject {
@public
    LC32OwnershipPublicationRaceState *_raceState;
}
@end

static uint32_t LC32AtomicLoad(const uint32_t *value) {
    return __atomic_load_n(value, __ATOMIC_SEQ_CST);
}

static void LC32AtomicStore(uint32_t *value, uint32_t desired) {
    __atomic_store_n(value, desired, __ATOMIC_SEQ_CST);
}

static BOOL LC32AllWorkerSlotsSet(const uint32_t *slots) {
    for(unsigned int index = 0; index < LC32WorkerCount; index++) {
        if(!LC32AtomicLoad(&slots[index])) return NO;
    }
    return YES;
}

static void LC32WaitForAtomicFlag(
        const uint32_t *flag, const uint32_t *cancelled) {
    while(!LC32AtomicLoad(flag) &&
            (!cancelled || !LC32AtomicLoad(cancelled))) {
        swtch();
    }
}

@implementation LC32OwnershipPublicationProbe
- (NSUInteger)lc32_ownershipPublicationMarker {
    return LC32OwnershipPublicationMarker;
}

- (void)dealloc {
    LC32OwnershipPublicationRaceState *state = _raceState;
    if(state) {
        LC32AtomicStore(&state->probeDeallocated, 1);
    }
    [super dealloc];
}
@end

void *LC32OwnershipPublicationRawProbe(
        LC32OwnershipPublicationRaceState *state) {
    return state->probe;
}

unsigned int LC32OwnershipPublicationIteration(
        LC32OwnershipPublicationRaceState *state) {
    return state->iteration;
}

int LC32OwnershipPublicationWorkerReadyAndWait(
        LC32OwnershipPublicationRaceState *state,
        unsigned int workerIndex) {
    if(workerIndex >= LC32WorkerCount) abort();
    LC32AtomicStore(&state->workerReady[workerIndex], 1);
    LC32_PUBLICATION_TRACE(state, "worker %u ready", workerIndex);
    LC32WaitForAtomicFlag(
        &state->startWorkers, &state->cancelled);
    if(LC32AtomicLoad(&state->cancelled)) return 0;
    LC32_PUBLICATION_TRACE(
        state, "worker %u passed start gate", workerIndex);
    return 1;
}

int LC32OwnershipPublicationWaitForPublisher(
        LC32OwnershipPublicationRaceState *state) {
    LC32WaitForAtomicFlag(
        &state->workerCompleted[LC32PublisherWorkerIndex],
        &state->cancelled);
    return !LC32AtomicLoad(&state->cancelled);
}

void LC32OwnershipPublicationRecordWeakLoadAndWait(
        LC32OwnershipPublicationRaceState *state,
        unsigned int workerIndex,
        int racyLoadSucceeded, int loadedObject, int markerPassed) {
    if(workerIndex >= LC32WeakWorkerCount) abort();
    uint32_t result = 0;
    if(racyLoadSucceeded != 0 &&
            !LC32AtomicLoad(
                &state->workerCompleted[LC32PublisherWorkerIndex])) {
        result |= LC32WeakResultRacyLoad;
    }
    if(loadedObject != 0) result |= LC32WeakResultLoadedObject;
    if(markerPassed != 0) result |= LC32WeakResultMarkerPassed;
    LC32AtomicStore(&state->workerResult[workerIndex], result);
    LC32AtomicStore(&state->workerCompleted[workerIndex], 1);
    LC32_PUBLICATION_TRACE(
        state, "weak worker %u completed", workerIndex);
    LC32WaitForAtomicFlag(
        &state->releaseWeakLoads, &state->cancelled);
    LC32_PUBLICATION_TRACE(
        state, "weak worker %u released", workerIndex);
}

static void LC32OwnershipPublicationRecordPublisher(
        LC32OwnershipPublicationRaceState *state, BOOL passed) {
    LC32AtomicStore(
        &state->workerResult[LC32PublisherWorkerIndex], passed != NO);
    LC32AtomicStore(
        &state->workerCompleted[LC32PublisherWorkerIndex], 1);
    LC32_PUBLICATION_TRACE(state, "publisher done (passed=%d)", passed);
}

static void LC32OwnershipPublicationRecordRetainWorker(
        LC32OwnershipPublicationRaceState *state) {
    LC32AtomicStore(&state->workerResult[LC32RetainWorkerIndex], 1);
    LC32AtomicStore(&state->workerCompleted[LC32RetainWorkerIndex], 1);
    LC32_PUBLICATION_TRACE(state, "retain worker done");
}

static void *LC32OwnershipPublicationPublisher(void *opaqueState) {
    LC32OwnershipPublicationRaceState *state = opaqueState;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if(!LC32OwnershipPublicationWorkerReadyAndWait(
            state, LC32PublisherWorkerIndex)) {
        [pool drain];
        return NULL;
    }

    if((state->iteration & 1U) == 0) {
        swtch();
    }

    id probe = (id)state->probe;
    [state->hostArray addObject:probe];
    const BOOL inserted = state->hostArray.count == 1;
    [state->hostArray removeLastObject];
    const BOOL removed = state->hostArray.count == 0;

    [pool drain];
    LC32OwnershipPublicationRecordPublisher(
        state, inserted && removed);
    return NULL;
}

static void *LC32OwnershipPublicationRetainWorker(void *opaqueState) {
    LC32OwnershipPublicationRaceState *state = opaqueState;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if(!LC32OwnershipPublicationWorkerReadyAndWait(
            state, LC32RetainWorkerIndex)) {
        [pool drain];
        return NULL;
    }

    id probe = (id)state->probe;
    for(unsigned int index = 0;
            index < LC32RetainChurnCount; index++) {
        if(index & 1U) {
            id retained = [probe retain];
            if((index & 3U) == 1U) swtch();
            [retained release];
        } else {
            id retained = objc_retain(probe);
            if((index & 3U) == 0) swtch();
            objc_release(retained);
        }
    }

    [pool drain];
    LC32OwnershipPublicationRecordRetainWorker(state);
    return NULL;
}

static void LC32OpenStartGateAfterCreateFailure(
        LC32OwnershipPublicationRaceState *state) {
    LC32AtomicStore(&state->cancelled, 1);
    LC32AtomicStore(&state->startWorkers, 1);
    LC32AtomicStore(&state->releaseWeakLoads, 1);
}

static BOOL LC32RunOwnershipPublicationIteration(
        NSMutableArray *hostArray, unsigned int iteration) {
    LC32OwnershipPublicationRaceState *state =
        calloc(1, sizeof(*state));
    if(!state) {
        fprintf(stderr, "ownership-publication: state allocation failed\n");
        return NO;
    }
    state->hostArray = hostArray;
    state->iteration = iteration;

    LC32OwnershipPublicationProbe *probe =
        [LC32OwnershipPublicationProbe new];
    probe->_raceState = state;
    state->probe = probe;

    pthread_t workers[LC32WorkerCount];
    unsigned int createdWorkers = 0;
    LC32OwnershipPublicationWeakWorkerContext
        weakContexts[LC32WeakWorkerCount];
    int createError = 0;
    for(unsigned int index = 0;
            index < LC32WeakWorkerCount; index++) {
        weakContexts[index].state = state;
        weakContexts[index].workerIndex = index;
        createError = pthread_create(
            &workers[createdWorkers], NULL,
            LC32OwnershipPublicationWeakWorker,
            &weakContexts[index]);
        if(createError != 0) break;
        createdWorkers++;
    }
    if(createError == 0) {
        createError = pthread_create(
            &workers[createdWorkers], NULL,
            LC32OwnershipPublicationPublisher, state);
        if(createError == 0) createdWorkers++;
    }
    if(createError == 0) {
        createError = pthread_create(
            &workers[createdWorkers], NULL,
            LC32OwnershipPublicationRetainWorker, state);
        if(createError == 0) createdWorkers++;
    }

    if(createError != 0) {
        fprintf(stderr,
            "ownership-publication: pthread_create failed: %d\n",
            createError);
        LC32OpenStartGateAfterCreateFailure(state);
        for(unsigned int index = 0;
                index < createdWorkers; index++) {
            pthread_join(workers[index], NULL);
        }
        [probe release];
        if(LC32AtomicLoad(&state->probeDeallocated)) {
            LC32ProbeDeallocCount++;
            free(state);
        }
        return NO;
    }

    while(!LC32AllWorkerSlotsSet(state->workerReady)) {
        swtch();
    }
    LC32_PUBLICATION_TRACE(state, "main opening start gate");
    LC32AtomicStore(&state->startWorkers, 1);
    while(!LC32AllWorkerSlotsSet(state->workerCompleted)) {
        swtch();
    }
    LC32_PUBLICATION_TRACE(state, "main observed completed operations");
    BOOL operationsPassed =
        LC32AtomicLoad(
            &state->workerResult[LC32PublisherWorkerIndex]) != 0 &&
        LC32AtomicLoad(
            &state->workerResult[LC32RetainWorkerIndex]) != 0;
    for(unsigned int index = 0;
            index < LC32WeakWorkerCount; index++) {
        const uint32_t result =
            LC32AtomicLoad(&state->workerResult[index]);
        operationsPassed &=
            (result & (LC32WeakResultLoadedObject |
                       LC32WeakResultMarkerPassed)) ==
            (LC32WeakResultLoadedObject |
             LC32WeakResultMarkerPassed);
        if(result & LC32WeakResultRacyLoad) {
            LC32RacyWeakLoadCount++;
        }
    }

    /* No worker can touch the raw probe after reaching the completion gate.
     * Release the original guest-only owner while both ARC weak loads still
     * hold the object, then let those paired references race each other out. */
    state->probe = NULL;
    LC32_PUBLICATION_TRACE(state, "main releasing original owner");
    [probe release];

    LC32_PUBLICATION_TRACE(state, "main opening weak-release gate");
    LC32AtomicStore(&state->releaseWeakLoads, 1);

    BOOL joinsPassed = YES;
    for(unsigned int index = 0;
            index < LC32WorkerCount; index++) {
        LC32_PUBLICATION_TRACE(state, "main joining worker %u", index);
        joinsPassed &= pthread_join(workers[index], NULL) == 0;
    }
    LC32_PUBLICATION_TRACE(state, "main joined all workers");

    /* Any final release deferred by a foreign native guest thread is drained
     * by the next bridge entry on this registered guest thread. */
    for(unsigned int attempt = 0; attempt < 32 &&
            !LC32AtomicLoad(&state->probeDeallocated); attempt++) {
        (void)hostArray.count;
        swtch();
    }
    const BOOL deallocatedExactlyOnce =
        LC32AtomicLoad(&state->probeDeallocated) != 0;
    if(deallocatedExactlyOnce) {
        LC32ProbeDeallocCount++;
    }

    const BOOL passed =
        operationsPassed && joinsPassed && deallocatedExactlyOnce;
    /* If destruction did not finish, retain the tiny state allocation so a
     * deferred -dealloc cannot publish through a dangling stack pointer. */
    if(deallocatedExactlyOnce) free(state);
    return passed;
}

static unsigned int LC32IterationCount(void) {
    const char *value = getenv("LC32_PUBLICATION_RACE_ITERATIONS");
    if(!value || !value[0]) return LC32DefaultIterationCount;
    char *end = NULL;
    const unsigned long parsed = strtoul(value, &end, 10);
    if(end == value || *end != '\0' || parsed == 0 || parsed > 100000) {
        fprintf(stderr,
            "invalid LC32_PUBLICATION_RACE_ITERATIONS: %s\n", value);
        return 0;
    }
    return (unsigned int)parsed;
}

int main(void) {
    const char *nativeThreads = getenv("NATIVE_GUEST_THREADS");
    if(!nativeThreads || !nativeThreads[0] ||
            strcmp(nativeThreads, "0") == 0) {
        fprintf(stderr,
            "ownership-publication requires NATIVE_GUEST_THREADS=1\n");
        return 2;
    }

    const unsigned int iterations = LC32IterationCount();
    if(iterations == 0) return 2;

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSMutableArray *hostArray = [[NSMutableArray alloc] init];
    BOOL passed = YES;
    for(unsigned int iteration = 0;
            iteration < iterations; iteration++) {
        if(!LC32RunOwnershipPublicationIteration(
                hostArray, iteration)) {
            fprintf(stderr,
                "ownership-publication iteration %u failed "
                "(dealloc count %lu)\n",
                iteration, (unsigned long)LC32ProbeDeallocCount);
            passed = NO;
            break;
        }
    }
    if(passed && LC32RacyWeakLoadCount == 0) {
        fprintf(stderr,
            "ownership-publication did not overlap a successful weak load "
            "with the publisher; increase the iteration count\n");
        passed = NO;
    }

    printf("ownership-publication-native-thread-race: %s "
           "(%u iterations, %lu deallocations)\n",
           passed ? "PASS" : "FAIL", iterations,
           (unsigned long)LC32ProbeDeallocCount);
    printf("ownership-publication-racy-weak-loads: %lu/%u\n",
           (unsigned long)LC32RacyWeakLoadCount,
           iterations * LC32WeakWorkerCount);
    [hostArray release];
    [pool drain];
    return passed ? 0 : 1;
}
