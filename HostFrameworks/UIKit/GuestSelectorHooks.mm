#import <UIKit/UIKit.h>
#import "../LC32/bridge.h"
#import "../LC32/host_selector_hooks.h"
#import "LegacyNibLoading.h"

@interface NSBundle (LC32GuestNibLoading)
- (NSArray *)lc32_guestLoadNibNamed:(NSString *)name owner:(id)owner
    options:(NSDictionary *)options;
@end

@implementation NSBundle (LC32GuestNibLoading)
+ (void)load {
    LC32RegisterHostSelectorHook(self, @selector(loadNibNamed:owner:options:),
        {@selector(lc32_guestLoadNibNamed:owner:options:), nullptr});
}

- (NSArray *)lc32_guestLoadNibNamed:(NSString *)name owner:(id)owner
        options:(NSDictionary *)options {
    if(![(id)object_getClass(self) isGuestClass])
        return LC32LoadGuestNib(self, name, owner, options);
    // Preserve the old guest-subclass/super dispatch and its exception policy.
    const SEL original = @selector(loadNibNamed:owner:options:);
    using LoadNib = NSArray *(*)(id, SEL, NSString *, id, NSDictionary *);
    return ((LoadNib)LC32NativeHostMethod(self, original))(self, original,
        name, owner, options);
}
@end

@interface UIViewController (LC32GuestViewLoading)
- (UIView *)lc32_guestView;
@end

@implementation UIViewController (LC32GuestViewLoading)
+ (void)load {
    LC32RegisterHostSelectorHook(self, @selector(view), {@selector(lc32_guestView), nullptr});
}

- (UIView *)lc32_guestView {
    id loadedView = nil;
    if(LC32UIKitGetViewDuringGuestLoad(self, &loadedView)) return loadedView;
    const SEL original = @selector(view);
    using GetView = UIView *(*)(id, SEL);
    return ((GetView)LC32NativeHostMethod(self, original))(self, original);
}
@end

@interface UIAlertView (LC32GuestAlertPresentation)
- (void)lc32_guestShow;
@end

@implementation UIAlertView (LC32GuestAlertPresentation)
+ (void)load {
    LC32RegisterHostSelectorHook(self, @selector(show), {@selector(lc32_guestShow), nullptr});
}

- (void)lc32_guestShow {
    // Some legacy games report loading/network errors from a worker thread.
    // Modern alert windows must attach to their scene on the main thread.
    // Schedule only guest show requests; native UIKit calls remain untouched.
    void (^show)(void) = ^{
        const SEL original = @selector(show);
        ((void (*)(id, SEL))LC32NativeHostMethod(self, original))(self, original);
    };
    if(NSThread.isMainThread) show();
    else dispatch_async(dispatch_get_main_queue(), show);
}
@end

#if LC32_UIKIT_COMPATIBILITY
@interface LC32GuestViewMutationHooks : NSObject
@end
@implementation LC32GuestViewMutationHooks
+ (void)load {
    // Run after the complete guest setter (including native subclass overrides),
    // never for setters issued by UIKit's own layout or compatibility code.
    auto geometryChanged = [](id view, const uint64_t *) {
        LC32UIKitScheduleLegacyOverlayLayout(view, nil);
    };
    const SEL geometry[] = {@selector(setTransform:), @selector(setBounds:),
        @selector(setCenter:), @selector(setFrame:)};
    for(SEL selector : geometry)
        LC32RegisterHostSelectorHook(UIView.class, selector, {nullptr, geometryChanged});
    LC32RegisterHostSelectorHook(UIView.class, @selector(addSubview:),
        {nullptr, [](id view, const uint64_t *args) {
            LC32UIKitScheduleLegacyOverlayLayout(view, (__bridge id)(void *)(uintptr_t)args[0]);
        }});
    LC32RegisterHostSelectorHook(UIView.class, @selector(setAutoresizingMask:),
        {nullptr, [](id view, const uint64_t *) {
            LC32UIKitDidSetGuestAutoresizingMask(view);
        }});
}
@end
#endif
