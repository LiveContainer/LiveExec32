#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSThread *expectedWorkerThread;
static pthread_t workerPthread;
static uint64_t mainThreadID;
static uint64_t workerThreadID;
static dispatch_semaphore_t workerReadySemaphore;
static dispatch_semaphore_t asyncCallbackSemaphore;
static volatile uint32_t stopWorker;
static BOOL workerEntryPassed;
static BOOL sameThreadSchedulingReturned;
static BOOL sameThreadAsyncCallbackPassed;
static BOOL sameThreadSyncCallbackPassed;
static BOOL asyncCallbackPassed;
static BOOL syncCallbackPassed;
static BOOL syncCallbackCompleted;

static BOOL LC32ExerciseBridgeOnCurrentThread(void) {
    NSString *text = [NSString stringWithFormat:@"%d", 1234];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSInteger value = 0;
    return [scanner scanInteger:&value] && value == 1234 &&
        scanner.isAtEnd;
}

static BOOL LC32CallbackArrivedOnWorker(NSString *marker,
                                        NSString *expectedMarker) {
    uint64_t currentThreadID = 0;
    (void)pthread_threadid_np(NULL, &currentThreadID);
    return [marker isEqualToString:expectedMarker] &&
        [NSThread currentThread] == expectedWorkerThread &&
        pthread_equal(pthread_self(), workerPthread) &&
        currentThreadID == workerThreadID &&
        currentThreadID != mainThreadID &&
        ![NSThread isMainThread] &&
        LC32ExerciseBridgeOnCurrentThread();
}

@interface LC32ThreadPerformProbe : NSObject
- (void)runWorker:(id)unused;
- (void)receiveSameThreadMarker:(NSString *)marker;
- (void)receiveSameThreadSyncMarker:(NSString *)marker;
- (void)receiveAsyncMarker:(NSString *)marker;
- (void)receiveSyncMarker:(NSString *)marker;
@end

@implementation LC32ThreadPerformProbe

- (void)receiveSameThreadMarker:(NSString *)marker {
    uint64_t currentThreadID = 0;
    (void)pthread_threadid_np(NULL, &currentThreadID);
    sameThreadAsyncCallbackPassed =
        sameThreadSchedulingReturned &&
        [marker isEqualToString:@"same-thread-marker"] &&
        [NSThread currentThread] == [NSThread mainThread] &&
        [NSThread isMainThread] &&
        currentThreadID == mainThreadID;
}

- (void)receiveSameThreadSyncMarker:(NSString *)marker {
    sameThreadSyncCallbackPassed =
        [marker isEqualToString:@"same-thread-sync-marker"] &&
        [NSThread currentThread] == [NSThread mainThread] &&
        [NSThread isMainThread];
}

- (void)runWorker:(id)unused {
    (void)unused;
    @autoreleasepool {
        /* Creating the run loop before publishing readiness avoids racing
         * performSelector:onThread: against the target run-loop setup. */
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        workerPthread = pthread_self();
        (void)pthread_threadid_np(NULL, &workerThreadID);
        workerEntryPassed =
            [NSThread currentThread] == expectedWorkerThread &&
            workerThreadID != 0 && workerThreadID != mainThreadID &&
            ![NSThread isMainThread];
        dispatch_semaphore_signal(workerReadySemaphore);

        while(!__atomic_load_n(&stopWorker, __ATOMIC_ACQUIRE)) {
            @autoreleasepool {
                NSDate *limit =
                    [NSDate dateWithTimeIntervalSinceNow:0.05];
                [runLoop runMode:NSDefaultRunLoopMode beforeDate:limit];
            }
        }
    }
}

- (void)receiveAsyncMarker:(NSString *)marker {
    asyncCallbackPassed = LC32CallbackArrivedOnWorker(
        marker, @"async-marker");
    dispatch_semaphore_signal(asyncCallbackSemaphore);
}

- (void)receiveSyncMarker:(NSString *)marker {
    /* If waitUntilDone is accidentally forwarded as false, the caller should
     * observe syncCallbackCompleted before this deliberately delayed method
     * reaches its completion store. */
    [NSThread sleepForTimeInterval:0.05];
    syncCallbackPassed = LC32CallbackArrivedOnWorker(
        marker, @"sync-marker");
    syncCallbackCompleted = YES;
    __atomic_store_n(&stopWorker, 1, __ATOMIC_RELEASE);
}

@end


static BOOL LC32WaitForWorkerToFinish(NSThread *thread) {
    for(unsigned int attempt = 0; attempt < 500; attempt++) {
        if(thread.isFinished && !thread.isExecuting) return YES;
        [NSThread sleepForTimeInterval:0.01];
    }
    return thread.isFinished && !thread.isExecuting;
}

int main(void) {
    @autoreleasepool {
        const char *nativeMode = getenv("NATIVE_GUEST_THREADS");
        if(!nativeMode || !nativeMode[0] || !strcmp(nativeMode, "0")) {
            fprintf(stderr,
                "thread-perform requires NATIVE_GUEST_THREADS=1\n");
            return 2;
        }

        (void)pthread_threadid_np(NULL, &mainThreadID);
        workerReadySemaphore = dispatch_semaphore_create(0);
        asyncCallbackSemaphore = dispatch_semaphore_create(0);

        LC32ThreadPerformProbe *probe =
            [LC32ThreadPerformProbe new];

        /* YTApiaryDeviceAuthenticator drains its pending authentication
         * queue with this exact same-thread, asynchronous selector shape.
         * It must return before invoking the callback, then deliver through
         * the guest run loop rather than a native NSThread mirror. */
        [probe performSelector:@selector(receiveSameThreadMarker:)
                     onThread:[NSThread currentThread]
                   withObject:@"same-thread-marker"
                waitUntilDone:NO];
        sameThreadSchedulingReturned = YES;
        for(unsigned int attempt = 0;
            attempt < 500 && !sameThreadAsyncCallbackPassed; attempt++) {
            @autoreleasepool {
                NSDate *limit =
                    [NSDate dateWithTimeIntervalSinceNow:0.01];
                [[NSRunLoop currentRunLoop]
                    runMode:NSDefaultRunLoopMode beforeDate:limit];
            }
        }
        printf("perform-selector-async-current-thread: %s\n",
            sameThreadAsyncCallbackPassed ? "PASS" : "FAIL");

        [probe performSelector:@selector(receiveSameThreadSyncMarker:)
                     onThread:[NSThread currentThread]
                   withObject:@"same-thread-sync-marker"
                waitUntilDone:YES];
        printf("perform-selector-sync-current-thread: %s\n",
            sameThreadSyncCallbackPassed ? "PASS" : "FAIL");

        NSThread *worker = [[NSThread alloc]
            initWithTarget:probe
                  selector:@selector(runWorker:)
                    object:nil];
        expectedWorkerThread = worker;
        [worker start];

        const long readyWait = dispatch_semaphore_wait(
            workerReadySemaphore,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        const BOOL readyPassed = readyWait == 0 && workerEntryPassed &&
            worker.isExecuting && !worker.isFinished;
        printf("perform-selector-worker-ready: %s\n",
            readyPassed ? "PASS" : "FAIL");

        BOOL asyncPassed = NO;
        BOOL syncPassed = NO;
        if(readyPassed) {
            [probe performSelector:@selector(receiveAsyncMarker:)
                         onThread:worker
                       withObject:@"async-marker"
                    waitUntilDone:NO];
            const long asyncWait = dispatch_semaphore_wait(
                asyncCallbackSemaphore,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            asyncPassed = asyncWait == 0 && asyncCallbackPassed;
            printf("perform-selector-async-target-thread: %s\n",
                asyncPassed ? "PASS" : "FAIL");

            if(asyncPassed) {
                [probe performSelector:@selector(receiveSyncMarker:)
                             onThread:worker
                           withObject:@"sync-marker"
                        waitUntilDone:YES];
                syncPassed = syncCallbackCompleted && syncCallbackPassed;
            } else {
                __atomic_store_n(&stopWorker, 1, __ATOMIC_RELEASE);
            }
        } else {
            __atomic_store_n(&stopWorker, 1, __ATOMIC_RELEASE);
            printf("perform-selector-async-target-thread: SKIP\n");
        }

        printf("perform-selector-sync-target-thread: %s\n",
            syncPassed ? "PASS" : "FAIL");
        printf("perform-selector-sync-wait: %s\n",
            syncCallbackCompleted ? "PASS" : "FAIL");

        const BOOL finishedPassed =
            LC32WaitForWorkerToFinish(worker);
        printf("perform-selector-worker-finished: %s\n",
            finishedPassed ? "PASS" : "FAIL");

        [worker release];
        [probe release];
        /* A timed-out worker might start late and still signal these. Leak
         * them on failure; the short-lived test process is about to exit. */
        if(finishedPassed) {
            dispatch_release(asyncCallbackSemaphore);
            dispatch_release(workerReadySemaphore);
        }

        return sameThreadAsyncCallbackPassed &&
            sameThreadSyncCallbackPassed &&
            readyPassed && asyncPassed && syncPassed &&
            finishedPassed ? 0 : 1;
    }
}
