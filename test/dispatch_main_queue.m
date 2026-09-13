#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* No UIApplicationMain or guest dispatch_main: these run loops are native
 * when the executable runs under LiveExec32. Pending callbacks use only static
 * state, so a timeout cannot leave a callback pointing into an expired frame. */
typedef struct {
    unsigned count;
    unsigned events[8];
    BOOL wrongThread;
} Events;

static pthread_t mainThread;
static pthread_mutex_t stateLock = PTHREAD_MUTEX_INITIALIZER;
static Events fifoEvents, nestedRunLoopEvents, workerEvents, assetEvents;
static BOOL workerWasBackground, assetTracksFailed, assetPlayableFailed;
static BOOL nestedRunLoopDidNotReenter;
static unsigned assetCompletions;
static int failures, checks;

static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static void watchdog(int sig) {
    (void)sig;
    const char message[] = "dispatch-main-queue-watchdog: FAIL\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(2);
}

static Events snapshot(Events *events) {
    pthread_mutex_lock(&stateLock);
    Events result = *events;
    pthread_mutex_unlock(&stateLock);
    return result;
}

static void record(Events *events, unsigned value) {
    BOOL onMain = pthread_equal(pthread_self(), mainThread) &&
        [NSThread isMainThread];
    pthread_mutex_lock(&stateLock);
    events->wrongThread |= !onMain;
    if(events->count < sizeof(events->events) / sizeof(events->events[0]))
        events->events[events->count] = value;
    ++events->count;
    pthread_mutex_unlock(&stateLock);
}

static BOOL pumpUntil(Events *events, unsigned count, BOOL useNSRunLoop) {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 2.0;
    while(snapshot(events).count < count &&
          CFAbsoluteTimeGetCurrent() < deadline) {
        @autoreleasepool {
            if(useNSRunLoop) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            } else {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
            }
        }
    }
    return snapshot(events).count >= count;
}

static void sourcePerform(void *info) {
    (void)info; /* The keepalive source is deliberately never signalled. */
}

static void recordFIFOFunction(void *context) {
    record((Events *)context, 2);
}

static void recordWorkerFunction(void *context) {
    record((Events *)context, 2);
}

static void *enqueueFromWorker(void *unused) {
    (void)unused;
    @autoreleasepool {
        workerWasBackground = !pthread_equal(pthread_self(), mainThread) &&
            ![NSThread isMainThread];
        dispatch_async(dispatch_get_main_queue(), ^{
            record(&workerEvents, 1);
        });
        dispatch_async_f(dispatch_get_main_queue(), &workerEvents,
            recordWorkerFunction);
    }
    return NULL;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGALRM, watchdog);
    alarm(20);
    mainThread = pthread_self();
    @autoreleasepool {
        check("entry-main-thread", [NSThread isMainThread]);
        check("main-queue-available", dispatch_get_main_queue() != NULL);
        if(!dispatch_get_main_queue()) return 1;
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceContext context = {0};
        context.perform = sourcePerform;
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        check("native-run-loop-keepalive", source != NULL);
        if(!source) return 1;
        CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);

        dispatch_async(dispatch_get_main_queue(), ^{
            record(&fifoEvents, 1);
            /* Enqueue during the drain: this must run after the two callbacks
             * already waiting, not inline or only on a later external wakeup. */
            dispatch_async(dispatch_get_main_queue(), ^{
                record(&fifoEvents, 4);
            });
        });
        dispatch_async_f(dispatch_get_main_queue(), &fifoEvents,
            recordFIFOFunction);
        dispatch_async(dispatch_get_main_queue(), ^{
            record(&fifoEvents, 3);
        });
        check("main-async-not-inline", snapshot(&fifoEvents).count == 0);
        check("cf-run-loop-drains-main-and-nested", pumpUntil(&fifoEvents, 4, NO));
        Events fifo = snapshot(&fifoEvents);
        const unsigned expectedFIFO[] = {1, 2, 3, 4};
        check("main-block-function-nested-fifo", fifo.count == 4 &&
            !memcmp(fifo.events, expectedFIFO, sizeof(expectedFIFO)));
        check("cf-main-callback-thread", fifo.count == 4 && !fifo.wrongThread);

        dispatch_async(dispatch_get_main_queue(), ^{
            record(&nestedRunLoopEvents, 1);
            dispatch_async(dispatch_get_main_queue(), ^{
                record(&nestedRunLoopEvents, 3);
            });
            /* A nested native loop may consume a wakeup, but the serial main
             * queue must not reenter its drain or strand the pending block. */
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.03, false);
            unsigned count = snapshot(&nestedRunLoopEvents).count;
            pthread_mutex_lock(&stateLock);
            nestedRunLoopDidNotReenter = count == 1;
            pthread_mutex_unlock(&stateLock);
            record(&nestedRunLoopEvents, 2);
        });
        check("nested-run-loop-pending-main-completes",
            pumpUntil(&nestedRunLoopEvents, 3, NO));
        pthread_mutex_lock(&stateLock);
        BOOL didNotReenter = nestedRunLoopDidNotReenter;
        pthread_mutex_unlock(&stateLock);
        check("nested-run-loop-does-not-reenter-main", didNotReenter);
        Events nested = snapshot(&nestedRunLoopEvents);
        const unsigned expectedNested[] = {1, 2, 3};
        check("nested-run-loop-main-after-outer-once", nested.count == 3 &&
            !memcmp(nested.events, expectedNested, sizeof(expectedNested)));
        check("nested-run-loop-main-callback-thread", nested.count == 3 &&
            !nested.wrongThread);

        pthread_t worker;
        int created = pthread_create(&worker, NULL, enqueueFromWorker, NULL);
        check("create-guest-worker", created == 0);
        if(created == 0) {
            /* The worker only enqueues; it never waits for main. The watchdog
             * also bounds a regression that mistakenly makes async blocking. */
            check("join-guest-worker", pthread_join(worker, NULL) == 0);
            check("worker-is-background", workerWasBackground);
            check("worker-main-async-not-inline", snapshot(&workerEvents).count == 0);
            check("ns-run-loop-drains-worker-main", pumpUntil(&workerEvents, 2, YES));
            Events workerResult = snapshot(&workerEvents);
            check("worker-block-function-fifo", workerResult.count == 2 &&
                workerResult.events[0] == 1 && workerResult.events[1] == 2);
            check("worker-main-callback-thread", workerResult.count == 2 &&
                !workerResult.wrongThread);
        }

        /* /dev/null is a file, so its child cannot exist. No media fixture,
         * network access, file creation, or hardware decoder is needed. */
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:
            [NSURL fileURLWithPath:@"/dev/null/lc32-dispatch-main-queue-missing.caf"]
            options:nil];
        check("asset-created", asset != nil);
        [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"playable"]
            completionHandler:^{
                pthread_mutex_lock(&stateLock);
                ++assetCompletions;
                pthread_mutex_unlock(&stateLock);
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *tracksError = nil, *playableError = nil;
                    AVKeyValueStatus tracks = [asset statusOfValueForKey:@"tracks"
                        error:&tracksError];
                    AVKeyValueStatus playable = [asset statusOfValueForKey:@"playable"
                        error:&playableError];
                    pthread_mutex_lock(&stateLock);
                    assetTracksFailed = tracks == AVKeyValueStatusFailed && tracksError != nil;
                    assetPlayableFailed = playable == AVKeyValueStatusFailed && playableError != nil;
                    pthread_mutex_unlock(&stateLock);
                    record(&assetEvents, 1);
                });
            }];
        check("asset-completion-main-hop", pumpUntil(&assetEvents, 1, YES));
        pthread_mutex_lock(&stateLock);
        unsigned completions = assetCompletions;
        BOOL tracksFailed = assetTracksFailed, playableFailed = assetPlayableFailed;
        pthread_mutex_unlock(&stateLock);
        check("asset-native-completion-once", completions == 1);
        check("asset-tracks-failed-with-error", tracksFailed);
        check("asset-playable-failed-with-error", playableFailed);
        Events assetResult = snapshot(&assetEvents);
        check("asset-main-hop-once-on-main", assetResult.count == 1 &&
            !assetResult.wrongThread);
        [asset cancelLoading];
        [asset release];

        CFRunLoopRemoveSource(runLoop, source, kCFRunLoopDefaultMode);
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
    }
    alarm(0);
    printf("dispatch-main-queue: %d checks, %d failures\n", checks, failures);
    return failures != 0;
}
