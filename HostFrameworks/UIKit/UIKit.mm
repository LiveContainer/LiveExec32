@import Darwin;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"

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
    return UIApplicationMain(argc, host_argv, principalClassName, delegateClassName);
}

__END_DECLS
