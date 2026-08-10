#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <mach/mach_traps.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static pthread_mutex_t threadLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t threadCondition = PTHREAD_COND_INITIALIZER;
static NSThread *escapedThread;
static BOOL detachedReady;
static BOOL detachedMayExit;
static BOOL detachedBridgePassed;
static uint64_t detachedThreadID;
static void (^LC32GlobalBlock)(void) = ^{};

static BOOL LC32BlockClassHasName(id block, const char *name) {
    Class blockClass = object_getClass(block);
    return blockClass && strcmp(class_getName(blockClass), name) == 0;
}

static BOOL LC32ExerciseBlockClasses(void) {
    __block int result = 0;
    int capturedValue = 42;
    void (^stackBlock)(void) = ^{
        result = capturedValue;
    };

    id globalCopy = [(id)LC32GlobalBlock copy];
    id mallocCopy = [(id)stackBlock copy];
    const BOOL classesPassed =
        LC32BlockClassHasName((id)LC32GlobalBlock, "__NSGlobalBlock__") &&
        LC32BlockClassHasName((id)stackBlock, "__NSStackBlock__") &&
        LC32BlockClassHasName(mallocCopy, "__NSMallocBlock__") &&
        globalCopy == (id)LC32GlobalBlock;

    ((void (^)(void))mallocCopy)();
    const BOOL passed = classesPassed && result == capturedValue;
    [mallocCopy release];
    [globalCopy release];
    return passed;
}

static BOOL LC32ExerciseBridgeOnCurrentThread(void) {
    NSString *text = [NSString stringWithFormat:@"%d", 1234];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSInteger value = 0;
    return [scanner scanInteger:&value] && value == 1234 &&
           scanner.isAtEnd;
}

static void LC32RunDetachedThread(void) {
    @autoreleasepool {
        NSThread *current = [[NSThread currentThread] retain];
        uint64_t threadID = 0;
        (void)pthread_threadid_np(NULL, &threadID);
        const BOOL bridgePassed =
            LC32ExerciseBridgeOnCurrentThread();

        pthread_mutex_lock(&threadLock);
        escapedThread = current;
        detachedThreadID = threadID;
        detachedBridgePassed = bridgePassed;
        detachedReady = YES;
        pthread_cond_broadcast(&threadCondition);
        while(!detachedMayExit) {
            pthread_cond_wait(&threadCondition, &threadLock);
        }
        pthread_mutex_unlock(&threadLock);
    }
}

int main(void) {
    @autoreleasepool {
        const BOOL blockClassesPassed = LC32ExerciseBlockClasses();
        printf("block-classes: %s\n", blockClassesPassed ? "PASS" : "FAIL");

        uint64_t mainThreadID = 0;
        (void)pthread_threadid_np(NULL, &mainThreadID);

        [NSThread detachNewThreadWithBlock:^{
            LC32RunDetachedThread();
        }];

        pthread_mutex_lock(&threadLock);
        while(!detachedReady) {
            pthread_cond_wait(&threadCondition, &threadLock);
        }
        NSThread *thread = escapedThread;
        const BOOL detachedRunningPassed = detachedBridgePassed &&
            detachedThreadID != 0 && detachedThreadID != mainThreadID &&
            thread.isExecuting && !thread.isFinished &&
            !thread.isMainThread && [NSThread isMultiThreaded];
        detachedMayExit = YES;
        pthread_cond_broadcast(&threadCondition);
        pthread_mutex_unlock(&threadLock);

        BOOL detachedFinishedPassed = NO;
        for(unsigned int attempt = 0; attempt < 100000; attempt++) {
            if([thread retainCount] == 1) {
                detachedFinishedPassed = thread.isFinished &&
                    !thread.isExecuting;
                break;
            }
            swtch();
        }

        printf("nsthread-running: %s\n",
            detachedRunningPassed ? "PASS" : "FAIL");
        printf("nsthread-finished: %s\n",
            detachedFinishedPassed ? "PASS" : "FAIL");
        [thread release];

        dispatch_semaphore_t semaphore =
            dispatch_semaphore_create(0);
        __block BOOL dispatchBridgePassed = NO;
        __block BOOL dispatchWorkerPassed = NO;
        dispatch_async(dispatch_get_global_queue(
                DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                dispatchBridgePassed =
                    LC32ExerciseBridgeOnCurrentThread();
                dispatchWorkerPassed = ![NSThread isMainThread];
                dispatch_semaphore_signal(semaphore);
            }
        });
        const long dispatchWait = dispatch_semaphore_wait(
            semaphore, dispatch_time(DISPATCH_TIME_NOW,
                                     5 * NSEC_PER_SEC));
        const BOOL dispatchPassed = dispatchWait == 0 &&
            dispatchBridgePassed && dispatchWorkerPassed;
        printf("dispatch-async: %s\n",
            dispatchPassed ? "PASS" : "FAIL");
        dispatch_release(semaphore);

        return !(blockClassesPassed && detachedRunningPassed &&
                 detachedFinishedPassed && dispatchPassed);
    }
}
