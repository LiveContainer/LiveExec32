#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>

static int failures;
static int unexpectedReleases;
static CFRunLoopTimerRef expectedTimer;
static CFRunLoopTimerContext *contextBeingRetained;

typedef struct {
    int retains;
    int releases;
    int callbacks;
    Boolean sawExpectedTimer;
    Boolean sawRetainedInfo;
} TimerInfo;

static TimerInfo originalInfo;
static TimerInfo retainedInfo;

static void check(const char *name, Boolean condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void unexpectedRelease(const void *rawInfo) {
    (void)rawInfo;
    unexpectedReleases++;
}

static const void *retainTimerInfo(const void *rawInfo) {
    TimerInfo *info = (TimerInfo *)rawInfo;
    info->retains++;
    if(contextBeingRetained) {
        /* The implementation must snapshot all callbacks before retain is
         * allowed to mutate the caller-owned structure. */
        contextBeingRetained->release = unexpectedRelease;
        contextBeingRetained->copyDescription = NULL;
        contextBeingRetained = NULL;
    }
    return &retainedInfo;
}

static void releaseTimerInfo(const void *rawInfo) {
    if(rawInfo == &retainedInfo) {
        retainedInfo.releases++;
    } else {
        unexpectedReleases++;
    }
}

static CFStringRef copyTimerInfoDescription(const void *rawInfo) {
    (void)rawInfo;
    return CFStringCreateCopy(kCFAllocatorDefault,
                              CFSTR("run-loop-timer-context"));
}

static void timerCallback(CFRunLoopTimerRef timer, void *rawInfo) {
    retainedInfo.callbacks++;
    retainedInfo.sawExpectedTimer |= timer == expectedTimer;
    retainedInfo.sawRetainedInfo |= rawInfo == &retainedInfo;
    CFRunLoopTimerInvalidate(timer);
    CFRunLoopStop(CFRunLoopGetCurrent());
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFRunLoopTimerContext context = {
        0,
        &originalInfo,
        retainTimerInfo,
        releaseTimerInfo,
        copyTimerInfoDescription,
    };
    contextBeingRetained = &context;
    const CFAbsoluteTime fireDate = CFAbsoluteTimeGetCurrent() + 0.02;
    const CFTimeInterval interval = 0.125;
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, fireDate, interval, 0, -1234567,
        timerCallback, &context);
    expectedTimer = timer;

    check("create", timer != NULL);
    check("context-retained-once",
        originalInfo.retains == 1 && retainedInfo.releases == 0);
    check("context-snapshotted-before-retain",
        contextBeingRetained == NULL && context.release == unexpectedRelease);
    if(timer) {
        NSTimer *nativeTimer = (NSTimer *)timer;
        check("fire-date-double-bits", fabs(
            nativeTimer.fireDate.timeIntervalSinceReferenceDate -
            fireDate) < 0.01);
        check("interval-double-bits",
            fabs(nativeTimer.timeInterval - interval) < 0.000001);

        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer,
                          kCFRunLoopDefaultMode);
        CFRunLoopRun();
        check("guest-c-callback",
            retainedInfo.callbacks == 1 &&
            retainedInfo.sawExpectedTimer &&
            retainedInfo.sawRetainedInfo);
        CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer,
                             kCFRunLoopDefaultMode);
        CFRunLoopTimerInvalidate(timer);
        CFRelease(timer);
    }
    expectedTimer = NULL;
    check("context-released-once",
        retainedInfo.releases == 1 && unexpectedReleases == 0);

    TimerInfo rejectedInfo = {};
    CFRunLoopTimerContext rejectedContext = {
        1,
        &rejectedInfo,
        retainTimerInfo,
        releaseTimerInfo,
        copyTimerInfoDescription,
    };
    check("reject-context-version",
        CFRunLoopTimerCreate(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 60.0, 0.0, 0, 0,
            timerCallback, &rejectedContext) == NULL &&
        rejectedInfo.retains == 0);
    check("reject-null-callback-before-retain",
        CFRunLoopTimerCreate(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 60.0, 0.0, 0, 0,
            NULL, &rejectedContext) == NULL &&
        rejectedInfo.retains == 0);

    CFRunLoopTimerRef contextlessTimer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 60.0,
        0.0, 0, INT32_MIN, timerCallback, NULL);
    check("null-context", contextlessTimer != NULL);
    if(contextlessTimer) {
        CFRunLoopTimerInvalidate(contextlessTimer);
        CFRelease(contextlessTimer);
    }

    [pool drain];
    return failures != 0;
}
