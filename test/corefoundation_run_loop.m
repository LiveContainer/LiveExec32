#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

@interface LC32RunLoopProbe : NSObject {
    BOOL _fired;
}
@property(nonatomic, readonly) BOOL fired;
- (void)stopRunLoop:(NSTimer *)timer;
@end

@implementation LC32RunLoopProbe

- (BOOL)fired {
    return _fired;
}

- (void)stopRunLoop:(NSTimer *)timer {
    (void)timer;
    _fired = YES;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    check("get-current", runLoop != NULL);
    check("get-main", CFRunLoopGetMain() != NULL);

    CFRunLoopMode mode = CFSTR("LC32RunLoopBridgeTestMode");
    LC32RunLoopProbe *probe = [LC32RunLoopProbe new];
    NSTimer *futureTimer = [NSTimer timerWithTimeInterval:3600.0
        target:probe selector:@selector(stopRunLoop:)
        userInfo:nil repeats:NO];
    check("create-host-timer", futureTimer != nil);

    CFRunLoopAddTimer(runLoop, (CFRunLoopTimerRef)futureTimer, mode);
    CFArrayRef modes = CFRunLoopCopyAllModes(runLoop);
    const BOOL copiedMode = modes && CFArrayContainsValue(modes,
        CFRangeMake(0, CFArrayGetCount(modes)), mode);
    check("copy-all-modes-owned", copiedMode);
    if(modes) CFRelease(modes);

    const CFAbsoluteTime requestedFireDate =
        CFAbsoluteTimeGetCurrent() + 1234.125;
    CFRunLoopTimerSetNextFireDate(
        (CFRunLoopTimerRef)futureTimer, requestedFireDate);
    const CFAbsoluteTime observedFireDate =
        [[futureTimer fireDate] timeIntervalSinceReferenceDate];
    check("timer-fire-date-double-bits",
        fabs(observedFireDate - requestedFireDate) < 0.01);

    const CFRunLoopRunResult result =
        CFRunLoopRunInMode(mode, 0.002, true);
    check("run-in-mode-double-bits", result == kCFRunLoopRunTimedOut);
    CFRunLoopWakeUp(runLoop);
    CFRunLoopRemoveTimer(runLoop, (CFRunLoopTimerRef)futureTimer, mode);
    CFRunLoopTimerInvalidate((CFRunLoopTimerRef)futureTimer);
    check("timer-invalidate", !futureTimer.valid);

    /* Exercise CFRunLoopRun itself with a bounded one-shot timer. */
    NSTimer *stopTimer = [NSTimer timerWithTimeInterval:0.01
        target:probe selector:@selector(stopRunLoop:)
        userInfo:nil repeats:NO];
    CFRunLoopAddTimer(runLoop, (CFRunLoopTimerRef)stopTimer,
        kCFRunLoopDefaultMode);
    CFRunLoopRun();
    check("run-and-stop", probe.fired);
    CFRunLoopRemoveTimer(runLoop, (CFRunLoopTimerRef)stopTimer,
        kCFRunLoopDefaultMode);

    /* NULL is rejected in the guest before native CF sees it. */
    CFRunLoopAddSource(runLoop, NULL, mode);
    CFRunLoopRemoveSource(runLoop, NULL, mode);
    CFRunLoopSourceSignal(NULL);
    CFRunLoopSourceInvalidate(NULL);
    check("source-null-safety", YES);

    [probe release];
    [pool drain];
    return failures != 0;
}
