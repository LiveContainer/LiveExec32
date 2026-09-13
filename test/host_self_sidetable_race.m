#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

// Native harness check: -DLC32_SIDETABLE_NATIVE_CHECK=1 -fno-objc-arc.
// Only the guest run exercises LC32_rawHostSelf and ARM32 libobjc's SideTable.
#ifndef LC32_SIDETABLE_NATIVE_CHECK
@interface NSObject (LC32SideTableRace)
- (uint64_t)host_self;
@end
extern uint64_t LC32LookupHostMapping(uint32_t guestObject);
#endif

enum { WorkerCount = 4, ObjectsPerWorker = 3000, RoundCount = 4, BridgesPerRound = 128 };
static unsigned checks, failures, publishedCreated, publishedDeallocated;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    struct timespec deadline;
    Class probeClass;
    unsigned ready, started, done, generation, progress;
    BOOL stop;
} Shared;

typedef struct {
    Shared *shared;
    unsigned created, deallocated, rounds;
    BOOL allocationFailed;
} Worker;

@interface LC32SideTableRaceProbe : NSObject {
@public
    unsigned *deallocCounter;
    unsigned marker;
}
@end
@implementation LC32SideTableRaceProbe
- (void)dealloc {
    if(deallocCounter) ++*deallocCounter;
    [super dealloc];
}
@end

static void check(const char *name, BOOL passed) {
    printf("host-self-sidetable-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static uint64_t hostSelf(id object) {
#ifdef LC32_SIDETABLE_NATIVE_CHECK
    return (uint64_t)(uintptr_t)object;
#else
    return [object host_self];
#endif
}

static BOOL yieldWorker(Shared *shared) {
    pthread_mutex_lock(&shared->mutex);
    ++shared->progress;
    BOOL keepGoing = !shared->stop;
    pthread_mutex_unlock(&shared->mutex);
    sched_yield();
    return keepGoing;
}

static void *churn(void *context) {
    Worker *worker = context;
    Shared *shared = worker->shared;
    LC32SideTableRaceProbe **objects = calloc(ObjectsPerWorker, sizeof(*objects));
    @autoreleasepool {
        pthread_mutex_lock(&shared->mutex);
        worker->allocationFailed = objects == NULL;
        ++shared->ready;
        pthread_cond_broadcast(&shared->changed);
        unsigned generation = 0;
        while(!shared->stop && objects) {
            while(!shared->stop && generation == shared->generation)
                pthread_cond_wait(&shared->changed, &shared->mutex);
            if(shared->stop) break;
            generation = shared->generation;
            ++shared->started;
            pthread_cond_broadcast(&shared->changed);
            pthread_mutex_unlock(&shared->mutex);

            // class_createInstance bypasses Foundation's native allocation.
            // Holding thousands of extra guest retains at once grows the
            // SideTable; releasing the full batch removes those entries.
            unsigned count = 0;
            for(; count < ObjectsPerWorker; ++count) {
                LC32SideTableRaceProbe *object = class_createInstance(shared->probeClass, 0);
                if(!object) { worker->allocationFailed = YES; break; }
                object->deallocCounter = &worker->deallocated;
                objects[count] = object;
                ++worker->created;
                [object retain];
                [object retain];
                if((count & 127U) == 127U && !yieldWorker(shared)) { ++count; break; }
            }
            while(count) {
                LC32SideTableRaceProbe *object = objects[--count];
                [object release];
                [object release];
                [object release];
                objects[count] = nil;
                if((count & 127U) == 0) (void)yieldWorker(shared);
            }
            pthread_mutex_lock(&shared->mutex);
            ++worker->rounds;
            ++shared->done;
            pthread_cond_broadcast(&shared->changed);
        }
        pthread_mutex_unlock(&shared->mutex);
    }
    free(objects);
    return NULL;
}

// Called with the mutex held. All waits share one 30-second test deadline.
static BOOL waitFor(Shared *shared, const unsigned *counter, unsigned expected) {
    while(*counter < expected && !shared->stop) {
        int error = pthread_cond_timedwait(&shared->changed, &shared->mutex, &shared->deadline);
        if(error) {
            fprintf(stderr, "host-self-sidetable: wait failed (%d%s)\n", error,
                error == ETIMEDOUT ? ", deadline reached" : "");
            shared->stop = YES;
            pthread_cond_broadcast(&shared->changed);
        }
    }
    return *counter == expected && !shared->stop;
}

static BOOL publishOne(Class probeClass, unsigned marker) {
    BOOL valid = YES;
    @autoreleasepool {
        LC32SideTableRaceProbe *probe = class_createInstance(probeClass, 0);
        if(!probe) return NO;
        probe->deallocCounter = &publishedDeallocated;
        probe->marker = marker;
        ++publishedCreated;
#ifndef LC32_SIDETABLE_NATIVE_CHECK
        valid &= LC32LookupHostMapping((uint32_t)(uintptr_t)probe) == 0;
#endif
        [probe retain]; // Pre-publication ownership must be mirrored exactly.
        const uint64_t host = hostSelf(probe);
        NSObject *nativeObject = [[NSObject alloc] init];
        NSMutableArray *array = [[NSMutableArray alloc] init];
        [array addObject:probe];
        [array addObject:nativeObject];
        valid &= host != 0 && hostSelf(probe) == host && hostSelf(nativeObject) != 0 &&
            hostSelf(array) != 0 && array.count == 2 && [array objectAtIndex:0] == probe &&
            [array objectAtIndex:1] == nativeObject;
        [probe release];
        [probe release];
        LC32SideTableRaceProbe *stored = [array objectAtIndex:0];
        valid &= stored == probe && stored->marker == marker;
        [array removeAllObjects];
        valid &= array.count == 0;
        [nativeObject release];
        [array release];
    }
    return valid;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    // Keep callback counters valid even if a failing bridge defers destruction.
    static Shared shared;
    static Worker workers[WorkerCount];
    pthread_t threads[WorkerCount];
    pthread_mutex_init(&shared.mutex, NULL);
    pthread_cond_init(&shared.changed, NULL);
    struct timeval start;
    gettimeofday(&start, NULL);
    shared.deadline.tv_sec = start.tv_sec + 30;
    shared.deadline.tv_nsec = start.tv_usec * 1000;
    @autoreleasepool {
        shared.probeClass = [LC32SideTableRaceProbe class];
        // Resolve class metadata before workers begin, leaving instance peer
        // creation itself concurrent with their retain-table mutations.
        check("class-peer-ready", hostSelf(shared.probeClass) != 0);
        unsigned createdThreads = 0;
        for(; createdThreads < WorkerCount; ++createdThreads) {
            workers[createdThreads].shared = &shared;
            int error = pthread_create(&threads[createdThreads], NULL, churn, &workers[createdThreads]);
            if(error) { fprintf(stderr, "pthread_create: %d\n", error); break; }
        }
        check("four-workers-started", createdThreads == WorkerCount);
        pthread_mutex_lock(&shared.mutex);
        BOOL ready = createdThreads == WorkerCount && waitFor(&shared, &shared.ready, WorkerCount);
        for(unsigned i = 0; i < createdThreads; ++i) ready &= !workers[i].allocationFailed;
        pthread_mutex_unlock(&shared.mutex);
        check("workers-ready", ready);

        unsigned overlappedRounds = 0, rounds = 0;
        BOOL publicationsValid = YES;
        for(; ready && rounds < RoundCount; ++rounds) {
            pthread_mutex_lock(&shared.mutex);
            shared.started = shared.done = 0;
            ++shared.generation;
            pthread_cond_broadcast(&shared.changed);
            ready = waitFor(&shared, &shared.started, WorkerCount);
            pthread_mutex_unlock(&shared.mutex);
            BOOL overlapped = NO;
            for(unsigned i = 0; ready && i < BridgesPerRound; ++i) {
                pthread_mutex_lock(&shared.mutex);
                overlapped |= shared.done < WorkerCount;
                pthread_mutex_unlock(&shared.mutex);
                publicationsValid &= publishOne(shared.probeClass, rounds * BridgesPerRound + i + 1);
            }
            pthread_mutex_lock(&shared.mutex);
            ready &= waitFor(&shared, &shared.done, WorkerCount);
            pthread_mutex_unlock(&shared.mutex);
            overlappedRounds += overlapped;
            printf("host-self-sidetable-round-%u: %s\n", rounds + 1,
                ready && publicationsValid && overlapped ? "PASS" : "FAIL");
        }
        pthread_mutex_lock(&shared.mutex);
        shared.stop = YES;
        pthread_cond_broadcast(&shared.changed);
        pthread_mutex_unlock(&shared.mutex);
        BOOL joined = YES, workersBalanced = YES, workersCompleted = YES;
        unsigned totalCreated = 0, totalDeallocated = 0;
        for(unsigned i = 0; i < createdThreads; ++i) {
            joined &= pthread_join(threads[i], NULL) == 0;
            totalCreated += workers[i].created;
            totalDeallocated += workers[i].deallocated;
            workersBalanced &= workers[i].created == workers[i].deallocated;
            workersCompleted &= !workers[i].allocationFailed && workers[i].rounds == RoundCount &&
                workers[i].created == RoundCount * ObjectsPerWorker;
        }
        check("workers-joined", joined);
        check("all-rounds-completed", ready && rounds == RoundCount && workersCompleted);
        check("publication-overlaps-every-churn-round", overlappedRounds == RoundCount);
        check("array-and-object-peer-identity", publicationsValid);
        check("all-guest-churn-objects-deallocated", workersBalanced);
        check("all-published-probes-deallocated", publishedCreated == RoundCount * BridgesPerRound &&
            publishedCreated == publishedDeallocated);
        printf("host-self-sidetable-counts: worker %u/%u, published %u/%u\n",
            totalDeallocated, totalCreated, publishedDeallocated, publishedCreated);
    }
    pthread_cond_destroy(&shared.changed);
    pthread_mutex_destroy(&shared.mutex);
    printf("host self SideTable summary: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
