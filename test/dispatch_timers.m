#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>

/* Native baseline: clang -fblocks -fno-objc-arc dispatch_timers.m
 *   -framework Foundation -framework CoreFoundation -o /tmp/dispatch-timers
 * Static callback state remains valid even when a bounded wait fails. */
typedef struct {
    unsigned mainAfter, globalAfter, globalHop, timerFires, cancellations;
    unsigned workersEntered, workersFinished, workersTimedOut, workerReleaseHops, exitRegistrations;
    BOOL wrongMainThread, globalWasMain, emptyTimerData;
    double mainAfterTime, globalAfterTime, firstTimerTime, lastTimerTime, lastTimerWallTime;
} TimerState;

typedef struct {
    BOOL wallClock, wrongThread;
    unsigned count;
    double fired;
} ClockAfter;

static TimerState state;
static ClockAfter absoluteAfter, wallAfter = {.wallClock = YES};
static pthread_mutex_t stateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t mainThread;
static mach_timebase_info_data_t timebase;
static dispatch_source_t timerSource;
static dispatch_source_t exitTimerSource;
static dispatch_semaphore_t workerRelease;
static int checks, failures;

static double now(void) {
    return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}

static double wallNow(void) {
    struct timeval value = {0};
    gettimeofday(&value, NULL);
    return (double)value.tv_sec + (double)value.tv_usec / 1e6;
}

static BOOL onMain(void) {
    return pthread_equal(pthread_self(), mainThread) && [NSThread isMainThread];
}

static TimerState snapshot(void) {
    pthread_mutex_lock(&stateLock);
    TimerState result = state;
    pthread_mutex_unlock(&stateLock);
    return result;
}

static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static void watchdog(int sig) {
    (void)sig;
    const char message[] = "dispatch-timers-watchdog: FAIL\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(2);
}

static void keepalive(void *context) {
    (void)context;
}

static void pumpOnce(void) {
    @autoreleasepool {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, false);
    }
}

static BOOL pumpUntil(unsigned afters, unsigned fires, unsigned cancellations) {
    double deadline = now() + 2.0;
    do {
        TimerState result = snapshot();
        if(result.mainAfter + result.globalHop >= afters &&
           result.timerFires >= fires && result.cancellations >= cancellations)
            return YES;
        pumpOnce();
    } while(now() < deadline);
    return NO;
}

static void pumpFor(double duration) {
    double deadline = now() + duration;
    do { pumpOnce(); } while(now() < deadline);
}

static ClockAfter clockSnapshot(ClockAfter *clock) {
    pthread_mutex_lock(&stateLock);
    ClockAfter result = *clock;
    pthread_mutex_unlock(&stateLock);
    return result;
}

static void clockAfterFunction(void *context) {
    ClockAfter *clock = context;
    BOOL isMain = onMain();
    double fired = clock->wallClock ? wallNow() : now();
    pthread_mutex_lock(&stateLock);
    ++clock->count;
    clock->fired = fired;
    clock->wrongThread |= !isMain;
    pthread_mutex_unlock(&stateLock);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGALRM, watchdog);
    alarm(20);
    mainThread = pthread_self();
    check("timer-monotonic-clock", mach_timebase_info(&timebase) == KERN_SUCCESS &&
        timebase.numer != 0 && timebase.denom != 0);
    if(!timebase.numer || !timebase.denom) return 1;

    @autoreleasepool {
        check("timer-entry-main", onMain());
        CFRunLoopSourceContext context = {0};
        context.perform = keepalive;
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        check("timer-run-loop-keepalive", source != NULL);
        if(!source) return 1;
        CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);

        double mainDeadline = now() + 0.04;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC),
            dispatch_get_main_queue(), ^{
                BOOL isMain = onMain();
                double fired = now();
                pthread_mutex_lock(&stateLock);
                ++state.mainAfter;
                state.mainAfterTime = fired;
                state.wrongMainThread |= !isMain;
                pthread_mutex_unlock(&stateLock);
            });
        double globalDeadline = now() + 0.06;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                BOOL isMain = pthread_equal(pthread_self(), mainThread);
                double fired = now();
                pthread_mutex_lock(&stateLock);
                ++state.globalAfter;
                state.globalAfterTime = fired;
                state.globalWasMain |= isMain;
                pthread_mutex_unlock(&stateLock);
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL hopIsMain = onMain();
                    pthread_mutex_lock(&stateLock);
                    ++state.globalHop;
                    state.wrongMainThread |= !hopIsMain;
                    pthread_mutex_unlock(&stateLock);
                });
            });
        check("dispatch-after-both-complete", pumpUntil(2, 0, 0));
        TimerState after = snapshot();
        check("dispatch-after-main-once", after.mainAfter == 1);
        check("dispatch-after-global-hop-once", after.globalAfter == 1 && after.globalHop == 1);
        check("dispatch-after-global-background", after.globalAfter == 1 && !after.globalWasMain);
        check("dispatch-after-main-identity", after.mainAfter == 1 && after.globalHop == 1 &&
            !after.wrongMainThread);
        /* Allow 2ms of clock/measurement slack, but not immediate or materially
         * early delivery. No upper latency assumption beyond the watchdog. */
        check("dispatch-after-main-not-early", after.mainAfterTime >= mainDeadline - 0.002);
        check("dispatch-after-global-not-early", after.globalAfterTime >= globalDeadline - 0.002);

        /* Save a monotonic deadline before other work: it must remain an
         * absolute deadline, not be interpreted as a fresh relative delay. */
        double absoluteDeadline = now() + 0.08;
        dispatch_time_t savedDeadline = dispatch_time(DISPATCH_TIME_NOW,
            80 * NSEC_PER_MSEC);
        pumpFor(0.02);
        dispatch_after_f(savedDeadline, dispatch_get_main_queue(),
            &absoluteAfter, clockAfterFunction);
        struct timeval wallBase = {0};
        check("dispatch-walltime-read-clock", gettimeofday(&wallBase, NULL) == 0);
        struct timespec wallStart = {wallBase.tv_sec, wallBase.tv_usec * 1000};
        double wallDeadline = (double)wallBase.tv_sec + (double)wallBase.tv_usec / 1e6 + 0.06;
        dispatch_after_f(dispatch_walltime(&wallStart, 60 * NSEC_PER_MSEC),
            dispatch_get_main_queue(), &wallAfter, clockAfterFunction);
        double clockWaitDeadline = now() + 2.0;
        while((!clockSnapshot(&absoluteAfter).count || !clockSnapshot(&wallAfter).count) &&
              now() < clockWaitDeadline) pumpOnce();
        ClockAfter absoluteResult = clockSnapshot(&absoluteAfter);
        ClockAfter wallResult = clockSnapshot(&wallAfter);
        check("dispatch-after-f-absolute-once", absoluteResult.count == 1);
        check("dispatch-after-f-absolute-not-early", absoluteResult.fired >= absoluteDeadline - 0.002);
        check("dispatch-after-f-walltime-once", wallResult.count == 1);
        check("dispatch-after-f-walltime-not-early", wallResult.fired >= wallDeadline - 0.002);
        check("dispatch-after-f-clock-main-identity", absoluteResult.count == 1 &&
            wallResult.count == 1 && !absoluteResult.wrongThread && !wallResult.wrongThread);

        timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_main_queue());
        check("dispatch-timer-source-created", timerSource != NULL);
        if(timerSource) {
            dispatch_source_set_event_handler(timerSource, ^{
                BOOL isMain = onMain();
                double fired = now();
                double wallFired = wallNow();
                unsigned long data = dispatch_source_get_data(timerSource);
                pthread_mutex_lock(&stateLock);
                if(!state.timerFires) state.firstTimerTime = fired;
                ++state.timerFires;
                state.lastTimerTime = fired;
                state.lastTimerWallTime = wallFired;
                state.wrongMainThread |= !isMain;
                state.emptyTimerData |= data == 0;
                pthread_mutex_unlock(&stateLock);
            });
            dispatch_source_set_cancel_handler(timerSource, ^{
                BOOL isMain = onMain();
                pthread_mutex_lock(&stateLock);
                ++state.cancellations;
                state.wrongMainThread |= !isMain;
                pthread_mutex_unlock(&stateLock);
            });
            double firstDeadline = now() + 0.04;
            dispatch_source_set_timer(timerSource,
                dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC),
                30 * NSEC_PER_MSEC, 0);
            dispatch_resume(timerSource);
            check("dispatch-timer-periodic-fires", pumpUntil(0, 3, 0));
            TimerState periodic = snapshot();
            check("dispatch-timer-first-not-early", periodic.firstTimerTime >= firstDeadline - 0.002);
            check("dispatch-timer-data-nonzero", periodic.timerFires >= 3 && !periodic.emptyTimerData);
            check("dispatch-timer-main-identity", periodic.timerFires >= 3 && !periodic.wrongMainThread);

            /* set_timer clears pending data from the previous schedule. */
            dispatch_source_set_timer(timerSource, DISPATCH_TIME_FOREVER,
                DISPATCH_TIME_FOREVER, 0);
            unsigned beforeRearm = snapshot().timerFires;
            pumpFor(0.08);
            check("dispatch-timer-disarmed-stays-quiet", snapshot().timerFires == beforeRearm);

            double rearmDeadline = now() + 0.06;
            dispatch_source_set_timer(timerSource,
                dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
                DISPATCH_TIME_FOREVER, 0);
            check("dispatch-timer-rearmed-fires", pumpUntil(0, beforeRearm + 1, 0));
            TimerState rearmed = snapshot();
            check("dispatch-timer-rearmed-not-early", rearmed.timerFires == beforeRearm + 1 &&
                rearmed.lastTimerTime >= rearmDeadline - 0.002);
            pumpFor(0.08);
            check("dispatch-timer-rearmed-one-shot", snapshot().timerFires == beforeRearm + 1);

            unsigned beforeWallRearm = snapshot().timerFires;
            double wallRearmDeadline = wallNow() + 0.06;
            dispatch_source_set_timer(timerSource,
                dispatch_walltime(NULL, 60 * NSEC_PER_MSEC),
                DISPATCH_TIME_FOREVER, 0);
            check("dispatch-timer-walltime-rearm-fires", pumpUntil(0, beforeWallRearm + 1, 0));
            TimerState wallRearmed = snapshot();
            check("dispatch-timer-walltime-rearm-not-early",
                wallRearmed.timerFires == beforeWallRearm + 1 &&
                wallRearmed.lastTimerWallTime >= wallRearmDeadline - 0.002);
            pumpFor(0.08);
            check("dispatch-timer-walltime-rearm-one-shot", snapshot().timerFires == beforeWallRearm + 1);

            dispatch_source_set_timer(timerSource,
                dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                20 * NSEC_PER_MSEC, 0);
            dispatch_source_cancel(timerSource);
            check("dispatch-timer-cancel-handler", pumpUntil(0, 0, 1));
            check("dispatch-timer-testcancel", dispatch_source_testcancel(timerSource) != 0);
            unsigned atCancel = snapshot().timerFires;
            /* Setting a canceled timer must not resurrect it. */
            dispatch_source_set_timer(timerSource, DISPATCH_TIME_NOW,
                10 * NSEC_PER_MSEC, 0);
            pumpFor(0.14);
            TimerState canceled = snapshot();
            check("dispatch-timer-no-events-after-cancel", canceled.timerFires == atCancel);
            check("dispatch-timer-cancel-once-on-main", canceled.cancellations == 1 &&
                !canceled.wrongMainThread);
            /* On failure retain the static source until exit, since a callback
             * may still be queued. Successful cancellation balances ownership. */
            if(canceled.cancellations == 1) dispatch_release(timerSource);
        }

        /* Four ordinary guest workers exhaust the normal worker allowance.
         * Timer management must still run in its separately reserved slot. */
        workerRelease = dispatch_semaphore_create(0);
        check("dispatch-timer-worker-release-created", workerRelease != NULL);
        if(workerRelease) {
            for(unsigned index = 0; index < 4; ++index) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    pthread_mutex_lock(&stateLock);
                    ++state.workersEntered;
                    pthread_mutex_unlock(&stateLock);
                    long waited = dispatch_semaphore_wait(workerRelease,
                        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                    pthread_mutex_lock(&stateLock);
                    ++state.workersFinished;
                    state.workersTimedOut += waited != 0;
                    pthread_mutex_unlock(&stateLock);
                });
            }
            double workersDeadline = now() + 2.0;
            while(snapshot().workersEntered < 4 && now() < workersDeadline) pumpOnce();
            check("dispatch-timer-four-workers-entered", snapshot().workersEntered == 4);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{
                    BOOL isMain = onMain();
                    pthread_mutex_lock(&stateLock);
                    ++state.workerReleaseHops;
                    state.wrongMainThread |= !isMain;
                    pthread_mutex_unlock(&stateLock);
                    for(unsigned index = 0; index < 4; ++index)
                        dispatch_semaphore_signal(workerRelease);
                });
            workersDeadline = now() + 2.0;
            while(snapshot().workersFinished < 4 && now() < workersDeadline) pumpOnce();
            TimerState workers = snapshot();
            check("dispatch-timer-progress-with-four-waiters", workers.workersFinished == 4 &&
                workers.workersTimedOut == 0 && workers.workerReleaseHops == 1);
            check("dispatch-timer-worker-release-on-main", workers.workerReleaseHops == 1 &&
                !workers.wrongMainThread);
            if(workers.workersFinished == 4 && workers.workerReleaseHops == 1) {
                dispatch_release(workerRelease);
            } else {
                /* Release blocked workers on failure, keeping the static
                 * semaphore alive for a delayed callback until process exit. */
                for(unsigned index = 0; index < 4; ++index)
                    dispatch_semaphore_signal(workerRelease);
            }
        }

        /* Deliberately leave one far-future timer registered: process teardown
         * must wake and join the native timer waiter, not wait for this fire. */
        exitTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_main_queue());
        check("dispatch-timer-future-source-for-exit", exitTimerSource != NULL);
        if(exitTimerSource) {
            dispatch_source_set_registration_handler(exitTimerSource, ^{
                pthread_mutex_lock(&stateLock);
                ++state.exitRegistrations;
                pthread_mutex_unlock(&stateLock);
            });
            dispatch_source_set_event_handler(exitTimerSource, ^{
                check("dispatch-timer-future-fired-before-exit", NO);
            });
            dispatch_source_set_timer(exitTimerSource,
                dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                DISPATCH_TIME_FOREVER, 0);
            dispatch_resume(exitTimerSource);
            double registrationDeadline = now() + 2.0;
            while(!snapshot().exitRegistrations && now() < registrationDeadline) pumpOnce();
            check("dispatch-timer-future-registered-before-exit", snapshot().exitRegistrations == 1);
            pumpFor(0.02);
        }

        CFRunLoopRemoveSource(runLoop, source, kCFRunLoopDefaultMode);
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
    }
    alarm(0);
    printf("dispatch-timers: %d checks, %d failures\n", checks, failures);
    return failures != 0;
}
