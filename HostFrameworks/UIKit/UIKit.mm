@import Darwin;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"

#include <cmath>

/*
symbol = r0 + r1 << 32
r0 = r2
r1 = r3
r2 = sp
r3 = sp+4
...
*/

namespace {

UIViewController *LC32OwningViewController(UIView *view) {
    for(UIResponder *responder = view; responder;
            responder = responder.nextResponder) {
        if([responder isKindOfClass:UIViewController.class]) {
            return (UIViewController *)responder;
        }
        if([responder isKindOfClass:UIWindow.class]) break;
    }
    for(UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIViewController *controller = LC32OwningViewController(subview);
        if(controller) return controller;
    }
    return nil;
}

id LC32ObjectProperty(id object, const char *name) {
    SEL selector = sel_registerName(name);
    if(!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch(NSException *) {
        return nil;
    }
}

bool LC32ApproximatelyEqual(CGFloat lhs, CGFloat rhs) {
    return std::fabs(lhs - rhs) <= 0.5;
}

bool LC32ScreenSizesMatch(CGSize lhs, CGSize rhs) {
    const bool direct =
        LC32ApproximatelyEqual(lhs.width, rhs.width) &&
        LC32ApproximatelyEqual(lhs.height, rhs.height);
    const bool rotated =
        LC32ApproximatelyEqual(lhs.width, rhs.height) &&
        LC32ApproximatelyEqual(lhs.height, rhs.width);
    return direct || rotated;
}

UIWindow *LC32ActiveGuestWindow(UIScreen *screen) {
    UIApplication *application = UIApplication.sharedApplication;

    UIWindow *delegateWindow = LC32ObjectProperty(application.delegate,
                                                   "window");
    if([delegateWindow isKindOfClass:UIWindow.class] &&
       delegateWindow.screen == screen) {
        return delegateWindow;
    }

    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if(windowScene.screen != screen) continue;
        for(UIWindow *window in windowScene.windows) {
            if(window.isKeyWindow) return window;
        }
    }

    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if(windowScene.screen != screen) continue;
        for(UIWindow *window in windowScene.windows) {
            if(!window.hidden && window.alpha > 0) return window;
        }
    }
    return nil;
}

void LC32AdoptLegacyRootViewController(UIWindow *window) {
    if(!window || window.rootViewController) return;

    UIViewController *controller = nil;
    for(UIView *subview in [window.subviews reverseObjectEnumerator]) {
        controller = LC32OwningViewController(subview);
        if(controller) break;
    }

    id delegate = UIApplication.sharedApplication.delegate;
    UIWindow *delegateWindow = LC32ObjectProperty(delegate, "window");
    if(!controller && (!delegateWindow || delegateWindow == window)) {
        static const char *const candidateProperties[] = {
            "rootViewController", "viewController", "mainViewController",
            "navigationController",
        };
        for(const char *property : candidateProperties) {
            id candidate = LC32ObjectProperty(delegate, property);
            if([candidate isKindOfClass:UIViewController.class]) {
                controller = candidate;
                break;
            }
        }
    }

    if(controller) {
        window.rootViewController = controller;
        fprintf(stderr, "LC32: adopted legacy root view controller %s\n",
                object_getClassName(controller));
    }
}

void LC32AdoptLegacyRootViewControllers(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *delegateWindow = LC32ObjectProperty(application.delegate,
                                                   "window");
    if(delegateWindow) {
        LC32AdoptLegacyRootViewController(delegateWindow);
        return;
    }
    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            LC32AdoptLegacyRootViewController(window);
        }
    }
}

} // namespace

@interface UIWindow (LC32LegacyRootViewController)
- (void)lc32_makeKeyAndVisible;
@end

@implementation UIWindow (LC32LegacyRootViewController)

+ (void)load {
    Method original = class_getInstanceMethod(self,
                                               @selector(makeKeyAndVisible));
    Method compatibility = class_getInstanceMethod(
        self, @selector(lc32_makeKeyAndVisible));
    if(original && compatibility) {
        method_exchangeImplementations(original, compatibility);
    }
}

- (void)lc32_makeKeyAndVisible {
    LC32AdoptLegacyRootViewController(self);
    [self lc32_makeKeyAndVisible];
}

@end

__BEGIN_DECLS

int LC32_UIKit_UIApplicationMain(u32 r2, u32 r3, u32 sp) {
    int argc = r2;
    u32 guest_argv = r3;
    NSString *principalClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    NSString *delegateClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);

    NSLog(@"UIApplicationMain(%d, 0x%x, %@, %@)\n", argc, guest_argv, principalClassName, delegateClassName);
    static id launchObserver;
    launchObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:nil
                usingBlock:^(__unused NSNotification *notification) {
        LC32AdoptLegacyRootViewControllers();
    }];
    (void)launchObserver;
    char executableName[] = "exec";
    char *host_argv[] = {executableName, nullptr};
    return UIApplicationMain(argc, host_argv, principalClassName, delegateClassName);
}

u32 LC32_UIKit_NSStringFromCGSize(u32 widthBits, u32 heightBits, u32) {
    float width;
    float height;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    return NSStringFromCGSize(CGSizeMake(width, height)).guest_self;
}

u32 LC32_UIKit_CGSizeFromString(u32 stringLow, u32 stringHigh, u32 sp) {
    NSString *string = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(stringLow |
            (static_cast<u64>(stringHigh) << 32)));
    const u32 guestResult =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    if(!string || !guestResult || guestResult > UINT32_MAX - 7)
        return 0;

    const CGSize size = CGSizeFromString(string);
    const struct {
        float width;
        float height;
    } guestSize = {
        static_cast<float>(size.width),
        static_cast<float>(size.height),
    };
    return Dynarmic_mem_1write(guestResult, sizeof(guestSize),
        const_cast<char *>(reinterpret_cast<const char *>(&guestSize))) == 0;
}

u32 LC32_UIKit_CopyScreenGeometry(u32 screenLow, u32 screenHigh, u32 sp) {
    enum : u32 {
        LC32UIScreenBounds = 0,
        LC32UIScreenApplicationFrame = 1,
    };

    const u32 kind =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 guestResult =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + sizeof(u32));
    if(kind > LC32UIScreenApplicationFrame || !guestResult ||
       guestResult > UINT32_MAX - (sizeof(float) * 4 - 1)) {
        return 0;
    }

    UIScreen *screen = reinterpret_cast<UIScreen *>(
        static_cast<uintptr_t>(screenLow |
            (static_cast<u64>(screenHigh) << 32)));
    if(!screen) screen = UIScreen.mainScreen;

    const CGRect nativeBounds = screen.bounds;
    CGRect result = kind == LC32UIScreenApplicationFrame
        ? screen.applicationFrame
        : nativeBounds;

    /*
     * LiveContainer's classic presentation can give the guest window a
     * 320x480 coordinate space while the process-wide UIScreen continues to
     * report the physical device dimensions.  Use that window coordinate
     * space only for a genuine size mismatch.  Full-screen windows (including
     * a width/height swap caused by rotation) retain native UIScreen behavior.
     */
    UIWindow *window = LC32ActiveGuestWindow(screen);
    if(window) {
        const CGRect windowBounds = window.bounds;
        if(windowBounds.size.width > 0 && windowBounds.size.height > 0 &&
           !LC32ScreenSizesMatch(windowBounds.size, nativeBounds.size)) {
            result = windowBounds;
        }
    }

    const struct {
        float x;
        float y;
        float width;
        float height;
    } guestRect = {
        static_cast<float>(result.origin.x),
        static_cast<float>(result.origin.y),
        static_cast<float>(result.size.width),
        static_cast<float>(result.size.height),
    };
    return Dynarmic_mem_1write(guestResult, sizeof(guestRect),
        const_cast<char *>(reinterpret_cast<const char *>(&guestRect))) == 0;
}

void LC32_UIKit_UIGraphicsBeginImageContext(
        u32 widthBits, u32 heightBits, u32) {
    float width;
    float height;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
}

void LC32_UIKit_UIGraphicsEndImageContext(u32, u32, u32) {
    UIGraphicsEndImageContext();
}

u32 LC32_UIKit_UIGraphicsGetCurrentContext(u32, u32, u32) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    return context ? [(id)context guest_self] : 0;
}

u32 LC32_UIKit_UIGraphicsGetImageFromCurrentImageContext(u32, u32, u32) {
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    return image ? image.guest_self : 0;
}

__END_DECLS
