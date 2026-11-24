#import <UIKit/UIKit.h>
#import "../LC32/host_selector_hooks.h"
#include "LC32UIKitCompatibilityConfig.h"

#if LC32_UIKIT_COMPATIBILITY
@interface UIApplication (LC32GuestStatusBar)
- (id)lc32_guestApplicationValueForKey:(NSString *)key;
@end

@interface NSObject (LC32GuestStatusBarPlaceholder)
- (id)lc32_guestStatusBarValueForKey:(NSString *)key;
@end

@implementation UIApplication (LC32GuestStatusBar)
+ (void)load {
    LC32RegisterHostSelectorHook(self, @selector(valueForKey:),
        {@selector(lc32_guestApplicationValueForKey:), nullptr});
    LC32RegisterHostSelectorHook(NSClassFromString(@"UIStatusBar_Placeholder"),
        @selector(valueForKey:), {@selector(lc32_guestStatusBarValueForKey:), nullptr});
}

- (id)lc32_guestApplicationValueForKey:(NSString *)key {
    const SEL original = @selector(valueForKey:);
    using Getter = id (*)(id, SEL, NSString *);
    Getter getter = (Getter)LC32NativeHostMethod(self, original);
    if(NSThread.isMainThread || ![key isEqualToString:@"statusBar"])
        return getter(self, original, key);

    // Old analytics SDKs read the status bar from worker threads. Even this
    // getter can create a UIWindow and attach it to a modern UIKit scene.
    // Marshal only guest status-bar reads, not native UIKit or other KVC.
    __block id value = nil;
    __block NSException *exception = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            value = getter(self, original, key);
        } @catch(NSException *caught) {
            exception = caught;
        }
    });
    // ARC keeps both results alive across the main queue's autorelease pool.
    // A native rejection must still be thrown on the requesting guest thread.
    if(exception) @throw exception;
    return value;
}
@end

@implementation NSObject (LC32GuestStatusBarPlaceholder)
- (id)lc32_guestStatusBarValueForKey:(NSString *)key {
    const SEL original = @selector(valueForKey:);
    using Getter = id (*)(id, SEL, NSString *);
    @try {
        return ((Getter)LC32NativeHostMethod(self, original))(self, original, key);
    } @catch(NSException *exception) {
        // Legacy network-type probes enumerate foregroundView.subviews.
        // Modern placeholders have no such hierarchy: expose its absence,
        // without inventing network state or suppressing unrelated KVC errors.
        if([key isEqualToString:@"foregroundView"] &&
                [exception.name isEqualToString:NSUndefinedKeyException])
            return nil;
        @throw;
    }
}
@end
#endif
