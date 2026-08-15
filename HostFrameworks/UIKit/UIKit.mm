@import Darwin;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"

#include <dispatch/dispatch.h>

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
    const int result = UIApplicationMain(
        argc, host_argv, principalClassName, delegateClassName);
    fprintf(stderr,
        "LC32: host UIApplicationMain returned %d\n", result);
    fflush(stderr);
    return result;
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

void LC32_UIKit_UIGraphicsBeginImageContext(
        u32 widthBits, u32 heightBits, u32) {
    float width;
    float height;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
}

void LC32_UIKit_UIGraphicsBeginImageContextWithOptions(
        u32 widthBits, u32 heightBits, u32 sp) {
    float width;
    float height;
    float scale;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    const BOOL opaque = Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 scaleBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + sizeof(u32));
    memcpy(&scale, &scaleBits, sizeof(scale));
    UIGraphicsBeginImageContextWithOptions(
        CGSizeMake(width, height), opaque, scale);
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

u32 LC32_UIKit_UIImageJPEGRepresentation(
        u32 imageLow, u32 imageHigh, u32 sp) {
    UIImage *image = reinterpret_cast<UIImage *>(static_cast<uintptr_t>(
        imageLow | (static_cast<u64>(imageHigh) << 32)));
    const u32 qualityBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    float quality;
    memcpy(&quality, &qualityBits, sizeof(quality));
    NSData *data = image
        ? UIImageJPEGRepresentation(image, static_cast<CGFloat>(quality))
        : nil;
    return data ? data.guest_self : 0;
}

void LC32_UIKit_SetWindowRootViewController(
        u32 windowLow, u32 windowHigh, u32 sp) {
    UIWindow *window = reinterpret_cast<UIWindow *>(static_cast<uintptr_t>(
        windowLow | (static_cast<u64>(windowHigh) << 32)));
    const u64 controllerAddress =
        Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    UIViewController *controller = reinterpret_cast<UIViewController *>(
        static_cast<uintptr_t>(controllerAddress));
    if(!window) return;

    dispatch_block_t setRoot = ^{
        /* The host mirror may itself be a guest-defined UIWindow subclass.
         * An ordinary objc_msgSend would re-enter that class's guest
         * trampoline and eventually arrive back at this helper.  Start the
         * lookup at the first native superclass, just as the generic selector
         * bridge does for guest-super calls. */
        Class dispatchClass = object_getClass(window);
        while(dispatchClass && [(id)dispatchClass isGuestClass]) {
            dispatchClass = class_getSuperclass(dispatchClass);
        }
        if(!dispatchClass) return;

        struct objc_super superInfo = {window, dispatchClass};
        using SetRootViewController =
            void (*)(struct objc_super *, SEL, UIViewController *);
        reinterpret_cast<SetRootViewController>(objc_msgSendSuper)(
            &superInfo, @selector(setRootViewController:), controller);
    };
    if(pthread_main_np()) {
        setRoot();
    } else {
        /* Guest network/operation callbacks execute on LC32's registered
         * callback pthread. UIKit still requires window hierarchy mutations
         * on the native main queue; dispatch_sync also preserves the legacy
         * method's synchronous completion contract. Block captures retain
         * both objects until the main-thread assignment has finished. */
        dispatch_sync(dispatch_get_main_queue(), setRoot);
    }
}

__END_DECLS
