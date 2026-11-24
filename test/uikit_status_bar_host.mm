// Compile the actual guest-only adapter and registry against a recording app.
#import <UIKit/UIKit.h>
#import "../HostFrameworks/LC32/host_selector_hooks.h"
#include "LC32UIKitCompatibilityConfig.h"
#include <atomic>
#include <cstdio>

static unsigned checks, failures;
static BOOL lastCallOnMain, throwOnStatusBar, nilStatusBar;
static id statusBar;
static NSException *failure;
static SEL lastSelector;
static BOOL hasForeground, otherForegroundError;

@implementation NSObject (LC32StatusBarTestBridge)
- (BOOL)isGuestClass { return NO; }
@end

@interface UIStatusBar_Placeholder : NSObject
@end
@implementation UIStatusBar_Placeholder
- (id)valueForKey:(NSString *)key {
    if([key isEqual:@"foregroundView"]) {
        if(otherForegroundError) @throw failure;
        if(hasForeground) return @"native-foreground";
    }
    return [super valueForKey:key];
}
@end

@implementation UIApplication
- (id)valueForKey:(NSString *)key {
    lastCallOnMain = NSThread.isMainThread;
    lastSelector = _cmd;
    if([key isEqualToString:@"statusBar"]) {
        if(throwOnStatusBar) @throw failure;
        // A fresh autoreleased result also checks ownership across queues.
        if(nilStatusBar) return nil;
        return statusBar ? statusBar : [NSMutableString stringWithString:@"bar"];
    }
    if([key isEqualToString:@"ordinary"]) return @"ordinary-value";
    return [super valueForKey:key];
}
@end

@interface GuestApplication : UIApplication
@end
@implementation GuestApplication
+ (BOOL)isGuestClass { return YES; }
- (id)valueForKey:(NSString *)key { (void)key; return @"guest-override"; }
@end

static void check(const char *name, bool passed) {
    ++checks;
    failures += !passed;
    std::printf("status-bar-%s: %s\n", name, passed ? "PASS" : "FAIL");
}

static id guestRead(id app, NSString *key) {
    SEL selector = @selector(valueForKey:);
    auto hook = LC32FindHostSelectorHook(object_getClass(app), selector);
    using Getter = id (*)(id, SEL, NSString *);
    if(hook.replacement) selector = hook.replacement;
    return ((Getter)[app methodForSelector:selector])(app, selector, key);
}

int main() {
    @autoreleasepool {
        UIApplication *app = [UIApplication new];
        auto hook = LC32FindHostSelectorHook(UIApplication.class, @selector(valueForKey:));
        check("compatibility-gate", !!hook.replacement == !!LC32_UIKIT_COMPATIBILITY);
        check("other-class-unmodified", !LC32FindHostSelectorHook(NSObject.class,
            @selector(valueForKey:)).replacement);
        check("other-selector-unmodified", !LC32FindHostSelectorHook(UIApplication.class,
            @selector(description)).replacement);
        statusBar = [NSObject new];
        check("main-read-identity", guestRead(app, @"statusBar") == statusBar && lastCallOnMain);
        check("original-selector", lastSelector == @selector(valueForKey:));
        std::atomic<bool> done{false};
        auto *completion = &done;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            @autoreleasepool {
                check("worker-read-identity", guestRead(app, @"statusBar") == statusBar &&
                    lastCallOnMain == !!LC32_UIKIT_COMPATIBILITY);
                check("worker-original-selector", lastSelector == @selector(valueForKey:));
                check("native-read-unchanged", [app valueForKey:@"statusBar"] == statusBar &&
                    !lastCallOnMain);
                check("unrelated-key-stays-worker",
                    [guestRead(app, @"ordinary") isEqual:@"ordinary-value"] && !lastCallOnMain);
                statusBar = nil;
                check("autoreleased-result-survives",
                    [guestRead(app, @"statusBar") isEqual:@"bar"]);
                nilStatusBar = YES;
                check("nil-result", guestRead(app, @"statusBar") == nil);
                nilStatusBar = NO;
                failure = [NSException exceptionWithName:@"ExpectedStatusBarFailure"
                    reason:@"test" userInfo:nil];
                throwOnStatusBar = YES;
                BOOL caughtOnWorker = NO;
                @try {
                    guestRead(app, @"statusBar");
                } @catch(NSException *caught) {
                    caughtOnWorker = caught == failure && !NSThread.isMainThread;
                }
                check("exception-returns-to-caller", caughtOnWorker);
                throwOnStatusBar = NO;
                check("lookup-after-exception", [guestRead(app, @"statusBar") isEqual:@"bar"]);
                BOOL unknownKeyRaised = NO;
                @try {
                    guestRead(app, @"unknown-key");
                } @catch(NSException *caught) {
                    unknownKeyRaised = [caught.name isEqual:NSUndefinedKeyException];
                }
                check("undefined-key-unchanged", unknownKeyRaised && !lastCallOnMain);
                GuestApplication *guest = [GuestApplication new];
                check("guest-super-dispatch",
                    [guestRead(guest, @"statusBar") isEqual:
                        LC32_UIKIT_COMPATIBILITY ? @"bar" : @"guest-override"]);
                UIStatusBar_Placeholder *placeholder = [UIStatusBar_Placeholder new];
                BOOL missingRaised = NO;
                id foreground = @"unchanged";
                @try {
                    foreground = guestRead(placeholder, @"foregroundView");
                } @catch(NSException *caught) {
                    missingRaised = [caught.name isEqual:NSUndefinedKeyException];
                }
                check("missing-foreground", LC32_UIKIT_COMPATIBILITY ?
                    !missingRaised && foreground == nil : missingRaised);
                hasForeground = YES;
                check("existing-foreground-preserved",
                    [guestRead(placeholder, @"foregroundView") isEqual:@"native-foreground"]);
                hasForeground = NO;
                BOOL nativeRaised = NO, unrelatedRaised = NO, otherErrorRaised = NO;
                @try {
                    [placeholder valueForKey:@"foregroundView"];
                } @catch(NSException *caught) {
                    nativeRaised = [caught.name isEqual:NSUndefinedKeyException];
                }
                @try {
                    guestRead(placeholder, @"unknown-key");
                } @catch(NSException *caught) {
                    unrelatedRaised = [caught.name isEqual:NSUndefinedKeyException];
                }
                otherForegroundError = YES;
                @try {
                    guestRead(placeholder, @"foregroundView");
                } @catch(NSException *caught) {
                    otherErrorRaised = caught == failure;
                }
                check("native-foreground-unchanged", nativeRaised);
                check("unrelated-placeholder-error-preserved", unrelatedRaised);
                check("other-foreground-error-preserved", otherErrorRaised);
            }
            completion->store(true, std::memory_order_release);
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while(!done.load(std::memory_order_acquire) && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if(!done.load(std::memory_order_acquire)) {
            std::fprintf(stderr, "status-bar-worker: TIMEOUT\n");
            return 1;
        }
    }
    std::printf("status-bar: %u/%u checks passed (mode=%d)\n",
        checks - failures, checks, LC32_UIKIT_COMPATIBILITY);
    return failures != 0;
}
