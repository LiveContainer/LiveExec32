@import Darwin;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"
#include "crash_exception.h"
#include "../CoreGraphics/LC32CoreGraphicsHost.h"

#include <atomic>
#include <dispatch/dispatch.h>
#include <stdio.h>

typedef NS_ENUM(NSUInteger, LC32LegacyIPadGeometryMode) {
    /* Pre-root-controller applications added their portrait iPad view
     * directly to UIWindow and relied on UIKit's compositor quarter-turn. */
    LC32LegacyIPadGeometryModePreservePortraitCanvas,
    /* Applications using UIWindow.rootViewController expect UIKit to resize
     * the controller hierarchy into the requested interface orientation. */
    LC32LegacyIPadGeometryModeReflowRootController,
};

@interface LC32LegacyIPadContainerController : UIViewController {
@private
    UIViewController *_guestContentController;
    UIView *_guestContentView;
    UIView *_canvasView;
    CGRect _canonicalGuestBounds;
    LC32LegacyIPadGeometryMode _geometryMode;
    BOOL _fittingGuestContent;
    BOOL _guestLayoutPending;
    NSUInteger _guestContentGeneration;
}
@property(nonatomic, readonly) UIViewController *guestContentController;
- (instancetype)initWithGuestContentController:
    (UIViewController *)controller
                          geometryMode:(LC32LegacyIPadGeometryMode)mode;
- (void)setGuestContentController:(UIViewController *)controller
                      geometryMode:(LC32LegacyIPadGeometryMode)mode;
- (void)fitGuestContentForViewport:(CGRect)viewport
                   hostOrientation:(UIInterfaceOrientation)orientation;
- (void)scheduleGuestLayout;
@end

/*
 * UIWindow.rootViewController did not exist before iOS 4.  Main-nib games
 * from that era commonly archive their drawable view directly under the
 * window and leave the root controller nil.  Modern UIKit rejects such a
 * window at the end of application launch, so give the host a controller
 * whose inert view sits behind the untouched guest hierarchy.  The guest
 * rootViewController accessor deliberately hides this implementation detail.
 */
@interface LC32LegacyWindowRootController : UIViewController
@end

/*
symbol = r0 + r1 << 32
r0 = r2
r1 = r3
r2 = sp
r3 = sp+4
...
*/

namespace {

const void *LC32LegacyOrientationMaskKey =
    &LC32LegacyOrientationMaskKey;

struct LC32GuestUIKitPolicy {
    UIInterfaceOrientationMask declaredOrientations;
    UIInterfaceOrientation preferredOrientation;
    bool statusBarHidden;
};

const LC32GuestUIKitPolicy& LC32GuestInterfacePolicy(void);

std::atomic<NSInteger> LC32LegacyRequestedOrientation{
    UIInterfaceOrientationUnknown};
thread_local bool LC32SuppressGuestOrientationQuery = false;

/*
 * Do not replace these calls with ordinary Objective-C messages. A view can
 * be an instance of a synthesized guest subclass whose override is backed by
 * LC32InvokeGuestSelector. UIKit invokes the compatibility layout code from
 * native scene callbacks, where dynamically dispatching into ARM32 guest code
 * is unsafe (and may run on a host thread that is not registered for guest
 * execution). Calling UIView's typed IMP directly deliberately applies only
 * the native base implementation while preserving the arm64 aggregate ABI.
 */
CGRect LC32NativeViewBounds(UIView *view) {
    using Getter = CGRect (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(bounds)));
    return view ? getter(view, @selector(bounds)) : CGRectZero;
}

void LC32NativeSetViewBounds(UIView *view, CGRect bounds) {
    using Setter = void (*)(id, SEL, CGRect);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(UIView.class, @selector(setBounds:)));
    if(view) setter(view, @selector(setBounds:), bounds);
}

void LC32NativeSetViewCenter(UIView *view, CGPoint center) {
    using Setter = void (*)(id, SEL, CGPoint);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(UIView.class, @selector(setCenter:)));
    if(view) setter(view, @selector(setCenter:), center);
}

void LC32NativeSetViewAutoresizingMask(
        UIView *view, UIViewAutoresizing mask) {
    using Setter = void (*)(id, SEL, UIViewAutoresizing);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(
            UIView.class, @selector(setAutoresizingMask:)));
    if(view) setter(view, @selector(setAutoresizingMask:), mask);
}

void LC32NativeSetViewNeedsLayout(UIView *view) {
    using Setter = void (*)(id, SEL);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(UIView.class,
                                      @selector(setNeedsLayout)));
    if(view) setter(view, @selector(setNeedsLayout));
}

void LC32NativeLayoutViewIfNeeded(UIView *view) {
    using Layout = void (*)(id, SEL);
    static Layout layout = reinterpret_cast<Layout>(
        class_getMethodImplementation(UIView.class,
                                      @selector(layoutIfNeeded)));
    if(view) layout(view, @selector(layoutIfNeeded));
}

void LC32NativeSendSubviewToBack(UIView *view, UIView *subview) {
    using SendSubviewToBack = void (*)(id, SEL, UIView *);
    static SendSubviewToBack sendSubviewToBack =
        reinterpret_cast<SendSubviewToBack>(
            class_getMethodImplementation(
                UIView.class, @selector(sendSubviewToBack:)));
    if(view && subview) {
        sendSubviewToBack(view, @selector(sendSubviewToBack:), subview);
    }
}

UIInterfaceOrientationMask LC32CachedGuestOrientationMask(
        UIViewController *controller) {
    NSNumber *cached = controller ? objc_getAssociatedObject(
        controller, LC32LegacyOrientationMaskKey) : nil;
    return cached ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
                  : LC32GuestInterfacePolicy().declaredOrientations;
}

UIInterfaceOrientation LC32InterfaceOrientationFromName(NSString *name) {
    if([name isEqualToString:@"UIInterfaceOrientationPortrait"]) {
        return UIInterfaceOrientationPortrait;
    }
    if([name isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) {
        return UIInterfaceOrientationPortraitUpsideDown;
    }
    if([name isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) {
        return UIInterfaceOrientationLandscapeLeft;
    }
    if([name isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) {
        return UIInterfaceOrientationLandscapeRight;
    }
    return UIInterfaceOrientationUnknown;
}

UIInterfaceOrientationMask LC32MaskForInterfaceOrientation(
        UIInterfaceOrientation orientation) {
    switch(orientation) {
        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationPortraitUpsideDown:
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
            return (UIInterfaceOrientationMask)1 << orientation;
        default:
            return 0;
    }
}

const LC32GuestUIKitPolicy& LC32GuestInterfacePolicy(void) {
    static LC32GuestUIKitPolicy policy = {
        UIInterfaceOrientationMaskPortrait,
        UIInterfaceOrientationPortrait,
        false,
    };
    /* UIKit can query native controller policy while the shim dylib is
     * loading. Do not permanently cache the fallback until LC32RunGuest has
     * published the selected guest executable. */
    const char *guestExecutable = getenv("LC32_GUEST_EXECUTABLE");
    if(!guestExecutable || !guestExecutable[0]) return policy;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSString stringWithUTF8String:
            getenv("LC32_GUEST_EXECUTABLE")];
        NSBundle *bundle = [NSBundle bundleWithPath:
            path.stringByDeletingLastPathComponent];
        NSDictionary *info = bundle.infoDictionary;
        if(!info) return;

        bool supportsPhone = false;
        bool supportsPad = false;
        for(id value in info[@"UIDeviceFamily"]) {
            if(![value respondsToSelector:@selector(integerValue)]) continue;
            supportsPhone |= [value integerValue] == 1;
            supportsPad |= [value integerValue] == 2;
        }
        const bool usesIPadPolicy = supportsPad && !supportsPhone;
        NSArray *orientationNames = usesIPadPolicy
            ? info[@"UISupportedInterfaceOrientations~ipad"] : nil;
        if(![orientationNames isKindOfClass:NSArray.class]) {
            orientationNames = info[@"UISupportedInterfaceOrientations"];
        }

        UIInterfaceOrientationMask declared = 0;
        for(id value in orientationNames) {
            if(![value isKindOfClass:NSString.class]) continue;
            declared |= LC32MaskForInterfaceOrientation(
                LC32InterfaceOrientationFromName(value));
        }

        const UIInterfaceOrientation preferred =
            LC32InterfaceOrientationFromName(info[@"UIInterfaceOrientation"]);
        if(!declared) {
            declared = LC32MaskForInterfaceOrientation(preferred);
        }
        if(!declared) declared = UIInterfaceOrientationMaskPortrait;

        policy.declaredOrientations = declared;
        policy.preferredOrientation =
            LC32MaskForInterfaceOrientation(preferred) & declared
            ? preferred
            : UIInterfaceOrientationUnknown;
        policy.statusBarHidden = [info[@"UIStatusBarHidden"] boolValue];
    });
    return policy;
}

Method LC32ClassOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = nullptr;
    for(unsigned int index = 0; index < count; index++) {
        if(method_getName(methods[index]) == selector) {
            result = methods[index];
            break;
        }
    }
    free(methods);
    return result;
}

bool LC32ClassIsUIViewController(Class cls) {
    const Class viewControllerClass = UIViewController.class;
    for(Class current = cls; current;
            current = class_getSuperclass(current)) {
        if(current == viewControllerClass) return true;
    }
    return false;
}

bool LC32GuestClassHierarchyDefinesSelector(Class cls, SEL selector) {
    for(Class current = cls; current && current != UIViewController.class;
            current = class_getSuperclass(current)) {
        if(LC32ClassOwnMethod(current, selector)) return true;
        /* The class currently being registered is not marked until after
         * objc_registerClassPair. Registered guest superclasses are marked,
         * while the first native superclass terminates this search. */
        if(current != cls && ![(id)current isGuestClass]) break;
    }
    return false;
}

UIInterfaceOrientation LC32FirstOrientationInMask(
        UIInterfaceOrientationMask mask) {
    static const UIInterfaceOrientation order[] = {
        UIInterfaceOrientationPortrait,
        UIInterfaceOrientationLandscapeLeft,
        UIInterfaceOrientationLandscapeRight,
        UIInterfaceOrientationPortraitUpsideDown,
    };
    for(UIInterfaceOrientation orientation : order) {
        if(mask & LC32MaskForInterfaceOrientation(orientation)) {
            return orientation;
        }
    }
    return UIInterfaceOrientationPortrait;
}

UIInterfaceOrientationMask LC32LegacySupportedInterfaceOrientations(
        UIViewController *controller, SEL) {
    if(LC32SuppressGuestOrientationQuery ||
            !Dynarmic_guest_thread_is_registered()) {
        NSNumber *cached = objc_getAssociatedObject(
            controller, LC32LegacyOrientationMaskKey);
        return cached ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
                      : LC32GuestInterfacePolicy().declaredOrientations;
    }

    UIInterfaceOrientationMask mask = 0;
    const SEL legacySelector =
        @selector(shouldAutorotateToInterfaceOrientation:);
    using LegacyAutorotation = BOOL (*)(id, SEL, UIInterfaceOrientation);
    LegacyAutorotation shouldAutorotate =
        reinterpret_cast<LegacyAutorotation>(objc_msgSend);
    static const UIInterfaceOrientation orientations[] = {
        UIInterfaceOrientationPortrait,
        UIInterfaceOrientationPortraitUpsideDown,
        UIInterfaceOrientationLandscapeLeft,
        UIInterfaceOrientationLandscapeRight,
    };
    for(UIInterfaceOrientation orientation : orientations) {
        if(shouldAutorotate(controller, legacySelector, orientation)) {
            mask |= LC32MaskForInterfaceOrientation(orientation);
        }
    }
    if(!mask) mask = LC32GuestInterfacePolicy().declaredOrientations;
    objc_setAssociatedObject(controller, LC32LegacyOrientationMaskKey,
        @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return mask;
}

UIInterfaceOrientation LC32LegacyPreferredInterfaceOrientation(
        UIViewController *controller, SEL) {
    const UIInterfaceOrientationMask mask =
        LC32LegacySupportedInterfaceOrientations(controller, nullptr);
    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested) & mask) return requested;
    const UIInterfaceOrientation declared =
        LC32GuestInterfacePolicy().preferredOrientation;
    if(LC32MaskForInterfaceOrientation(declared) & mask) return declared;
    return LC32FirstOrientationInMask(mask);
}

BOOL LC32LegacyPrefersStatusBarHidden(UIViewController *, SEL) {
    return LC32GuestInterfacePolicy().statusBarHidden;
}

void LC32ScaleLegacyIPadWindow(UIWindow *window);
CGRect LC32WindowSceneBounds(UIWindow *window);
bool LC32UsesClassicFullScreenViewport(UIWindow *window);
CGRect LC32LegacyViewportInView(UIWindow *window, UIView *view);
UIInterfaceOrientation LC32WindowSceneOrientation(
    UIWindow *window, CGRect sceneBounds);
UIInterfaceOrientationMask LC32SupportedOrientationsForController(
    UIViewController *controller);
bool LC32ObjectUsesGuestClass(id object);
UIViewController *LC32NativeWindowRootViewController(UIWindow *window);
void LC32NativeSetWindowRootViewController(
    UIWindow *window, UIViewController *controller);
UIViewController *LC32GuestWindowRootViewController(UIWindow *window);
void LC32InstallGuestWindowRootViewController(
    UIWindow *window, UIViewController *controller,
    LC32LegacyIPadGeometryMode geometryMode);
UIInterfaceOrientation LC32LegacyTargetOrientation(void);

LC32LegacyIPadContainerController *LC32LegacyContainerForWindow(
        UIWindow *window) {
    UIViewController *root = LC32NativeWindowRootViewController(window);
    return [root isKindOfClass:LC32LegacyIPadContainerController.class]
        ? (LC32LegacyIPadContainerController *)root : nil;
}

bool LC32GuestIsIPadOnly(void) {
    const char *guestExecutable = getenv("LC32_GUEST_EXECUTABLE");
    /* UIKit can create internal windows while the shim dylib is loading.
     * Do not consume the cache until LC32RunGuest has published the guest. */
    if(!guestExecutable || !guestExecutable[0]) return false;

    static bool result = false;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSString stringWithUTF8String:
            getenv("LC32_GUEST_EXECUTABLE")];
        NSBundle *bundle = [NSBundle bundleWithPath:
            path.stringByDeletingLastPathComponent];
        NSArray *families = [bundle objectForInfoDictionaryKey:
            @"UIDeviceFamily"];
        bool supportsPhone = false;
        bool supportsPad = false;
        if([families isKindOfClass:NSArray.class]) {
            for(id family in families) {
                if(![family respondsToSelector:@selector(integerValue)]) {
                    continue;
                }
                const NSInteger value = [family integerValue];
                supportsPhone |= value == 1;
                supportsPad |= value == 2;
            }
        }
        result = supportsPad && !supportsPhone;
    });
    return result;
}

Class LC32NativeWindowDispatchClass(UIWindow *window) {
    Class dispatchClass = object_getClass(window);
    while(dispatchClass && [(id)dispatchClass isGuestClass]) {
        dispatchClass = class_getSuperclass(dispatchClass);
    }
    return dispatchClass;
}

UIViewController *LC32NativeWindowRootViewController(UIWindow *window) {
    Class dispatchClass = LC32NativeWindowDispatchClass(window);
    if(!window || !dispatchClass) return nil;
    struct objc_super superInfo = {window, dispatchClass};
    using GetRootViewController =
        UIViewController *(*)(struct objc_super *, SEL);
    return reinterpret_cast<GetRootViewController>(objc_msgSendSuper)(
        &superInfo, @selector(rootViewController));
}

void LC32NativeSetWindowRootViewController(
        UIWindow *window, UIViewController *controller) {
    Class dispatchClass = LC32NativeWindowDispatchClass(window);
    if(!window || !dispatchClass) return;
    struct objc_super superInfo = {window, dispatchClass};
    using SetRootViewController =
        void (*)(struct objc_super *, SEL, UIViewController *);
    reinterpret_cast<SetRootViewController>(objc_msgSendSuper)(
        &superInfo, @selector(setRootViewController:), controller);
}

bool LC32WindowNeedsLegacyIPadContainer(UIWindow *window) {
    if(!window || !LC32GuestIsIPadOnly()) return false;
    const CGRect hostBounds = LC32WindowSceneBounds(window);
    const CGFloat shortEdge = MIN(hostBounds.size.width,
                                  hostBounds.size.height);
    return shortEdge > 0 && shortEdge < 600;
}

UIInterfaceOrientation LC32LegacyTargetOrientation(void) {
    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested)) return requested;
    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    if(LC32MaskForInterfaceOrientation(policy.preferredOrientation)) {
        return policy.preferredOrientation;
    }
    return LC32FirstOrientationInMask(policy.declaredOrientations);
}

UIViewController *LC32GuestWindowRootViewController(UIWindow *window) {
    UIViewController *root = LC32NativeWindowRootViewController(window);
    if([root isKindOfClass:LC32LegacyIPadContainerController.class]) {
        root = ((LC32LegacyIPadContainerController *)root)
            .guestContentController;
    }
    return [root isKindOfClass:LC32LegacyWindowRootController.class]
        ? nil : root;
}

void LC32InstallGuestWindowRootViewController(
        UIWindow *window, UIViewController *controller,
        LC32LegacyIPadGeometryMode geometryMode) {
    if(!window || !window.guest_selfOrNull) return;
    LC32LegacyIPadContainerController *container =
        LC32LegacyContainerForWindow(window);
    const bool needsContainer =
        controller && LC32WindowNeedsLegacyIPadContainer(window);

    if(!needsContainer) {
        /* nil uninstalls the compatibility root. If the scene no longer
         * needs classic-iPad virtualization, detach the child before
         * promoting it back to UIWindow.rootViewController. */
#if !__has_feature(objc_arc)
        [controller retain];
#endif
        if(container) {
            [container setGuestContentController:nil
                                     geometryMode:geometryMode];
        }
        LC32NativeSetWindowRootViewController(window, controller);
#if !__has_feature(objc_arc)
        [controller release];
#endif
        return;
    }

    if(!container) {
        /* Retain across replacing UIWindow's old root: UIKit is allowed to
         * release that controller as part of the assignment. Install an
         * empty native container first so addChildViewController: never sees
         * a controller which is simultaneously UIWindow's root. */
#if !__has_feature(objc_arc)
        [controller retain];
#endif
        container = [[LC32LegacyIPadContainerController alloc]
            initWithGuestContentController:nil geometryMode:geometryMode];
        LC32NativeSetWindowRootViewController(window, container);
        [container setGuestContentController:controller
                                 geometryMode:geometryMode];
#if !__has_feature(objc_arc)
        [controller release];
        [container release];
#endif
    } else {
        [container setGuestContentController:controller
                                 geometryMode:geometryMode];
    }
    LC32ScaleLegacyIPadWindow(window);
}

CGRect LC32WindowSceneBounds(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;
    /* Keep this helper in scene coordinates for eligibility and orientation
     * policy. Canvas placement uses LC32LegacyViewportInView below, which
     * preserves the source coordinate space instead of copying raw numbers. */
    id<UICoordinateSpace> coordinateSpace = nil;
    if(@available(iOS 26.0, *)) {
        coordinateSpace =
            scene.effectiveGeometry.coordinateSpace;
        if(coordinateSpace) return coordinateSpace.bounds;
    }
    coordinateSpace = scene.coordinateSpace;
    if(coordinateSpace) return coordinateSpace.bounds;
    return (window.screen ?: UIScreen.mainScreen).bounds;
}

bool LC32UsesClassicFullScreenViewport(UIWindow *window) {
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    const CGRect screenBounds = screen.bounds;
    const CGFloat screenShortEdge = MIN(
        screenBounds.size.width, screenBounds.size.height);
    return LC32GuestIsIPadOnly() &&
           LC32GuestInterfacePolicy().statusBarHidden &&
           screenShortEdge > 0 && screenShortEdge < 600;
}

CGRect LC32LegacyViewportInView(UIWindow *window, UIView *view) {
    const CGRect fallback = LC32NativeViewBounds(view);
    if(!window || !view || !window.windowScene) return fallback;

    id<UICoordinateSpace> sourceSpace = nil;
    CGRect sourceBounds = CGRectZero;
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    const CGRect screenBounds = screen.bounds;
    if(LC32UsesClassicFullScreenViewport(window)) {
        /* Full-screen legacy games draw behind modern safe-area insets. The
         * compatibility root is translated relative to UIScreen, so convert
         * the complete display rect instead of copying its origin and size. */
        sourceSpace = screen.coordinateSpace;
        sourceBounds = screenBounds;
    } else {
        UIWindowScene *scene = window.windowScene;
        if(@available(iOS 26.0, *)) {
            sourceSpace = scene.effectiveGeometry.coordinateSpace;
        }
        if(!sourceSpace) sourceSpace = scene.coordinateSpace;
        sourceBounds = sourceSpace.bounds;
    }
    if(!sourceSpace || !(sourceBounds.size.width > 0) ||
            !(sourceBounds.size.height > 0)) {
        return fallback;
    }

    const CGRect viewport = [view convertRect:sourceBounds
                           fromCoordinateSpace:sourceSpace];
    return isfinite(viewport.origin.x) && isfinite(viewport.origin.y) &&
           isfinite(viewport.size.width) &&
           isfinite(viewport.size.height) &&
           viewport.size.width > 0 && viewport.size.height > 0
        ? viewport : fallback;
}

UIInterfaceOrientation LC32WindowSceneOrientation(
        UIWindow *window, CGRect sceneBounds) {
    UIWindowScene *scene = window.windowScene;
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    if(@available(iOS 26.0, *)) {
        orientation = scene.effectiveGeometry.interfaceOrientation;
    } else {
        orientation = scene.interfaceOrientation;
    }
    if(orientation == UIInterfaceOrientationUnknown) {
        orientation = sceneBounds.size.width > sceneBounds.size.height
            ? UIInterfaceOrientationLandscapeLeft
            : UIInterfaceOrientationPortrait;
    }
    return orientation;
}

void LC32ScaleLegacyIPadWindow(UIWindow *window) {
    /* UIKit owns keyboard, alert, and text-effects windows in the same
     * process. Virtualize only a UIWindow paired with a guest object. */
    if(!window || !window.guest_selfOrNull || !LC32GuestIsIPadOnly()) return;

    LC32LegacyIPadContainerController *container =
        LC32LegacyContainerForWindow(window);
    if(container && !LC32WindowNeedsLegacyIPadContainer(window)) {
        /* Scene resizing can leave classic mode at runtime. Unwrap promptly
         * instead of retaining a scaled compatibility hierarchy in a native
         * iPad viewport. The mode is irrelevant once no container is needed. */
        LC32InstallGuestWindowRootViewController(window,
            container.guestContentController,
            LC32LegacyIPadGeometryModeReflowRootController);
        return;
    }
    if(!container && LC32WindowNeedsLegacyIPadContainer(window)) {
        UIViewController *guestRoot =
            LC32GuestWindowRootViewController(window);
        if(LC32ObjectUsesGuestClass(guestRoot)) {
            /* Reaching this path means the guest never used the bridged
             * rootViewController setter. Preserve its pre-iOS-4 portrait
             * canvas and reproduce the legacy compositor rotation. */
            LC32InstallGuestWindowRootViewController(window, guestRoot,
                LC32LegacyIPadGeometryModePreservePortraitCanvas);
            return;
        }
    }
    if(!container) return;

    /* A pre-controller guest can construct its UIWindow and root view from
     * the virtual 768x1024 UIScreen bounds before a scene is attached. Keep
     * those guest-visible bounds intact, but fit the native child canvas to
     * the settled scene instead of the oversized archived root. */
    const CGRect sceneBounds = LC32WindowSceneBounds(window);
    const CGRect viewport = LC32LegacyViewportInView(
        window, container.view);
    [container fitGuestContentForViewport:viewport
        hostOrientation:LC32WindowSceneOrientation(
            window, sceneBounds)];
}

bool LC32ObjectUsesGuestClass(id object) {
    return object && [(id)object_getClass(object) isGuestClass];
}

UIViewController *LC32ActiveOrientationController(
        UIViewController *controller) {
    while(controller) {
        if(controller.presentedViewController) {
            controller = controller.presentedViewController;
            continue;
        }
        /* A guest root controller implements the legacy rotation policy
         * itself. Only descend through native UIKit containers. */
        if(LC32ObjectUsesGuestClass(controller)) return controller;
        if([controller isKindOfClass:UINavigationController.class]) {
            UIViewController *visible =
                ((UINavigationController *)controller).visibleViewController;
            if(visible) {
                controller = visible;
                continue;
            }
        }
        if([controller isKindOfClass:UITabBarController.class]) {
            UIViewController *selected =
                ((UITabBarController *)controller).selectedViewController;
            if(selected) {
                controller = selected;
                continue;
            }
        }
        return controller;
    }
    return nil;
}

UIInterfaceOrientationMask LC32SupportedOrientationsForController(
        UIViewController *controller) {
    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    if(!controller || !LC32ObjectUsesGuestClass(controller)) {
        return policy.declaredOrientations;
    }

    NSNumber *cached = objc_getAssociatedObject(
        controller, LC32LegacyOrientationMaskKey);
    if(LC32SuppressGuestOrientationQuery ||
            !Dynarmic_guest_thread_is_registered()) {
        return cached ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
                      : policy.declaredOrientations;
    }

    const Class cls = object_getClass(controller);
    if(!LC32GuestClassHierarchyDefinesSelector(
            cls, @selector(supportedInterfaceOrientations))) {
        return policy.declaredOrientations;
    }
    using SupportedOrientations =
        UIInterfaceOrientationMask (*)(id, SEL);
    UIInterfaceOrientationMask mask =
        reinterpret_cast<SupportedOrientations>(objc_msgSend)(
            controller, @selector(supportedInterfaceOrientations));
    if(!mask) mask = policy.declaredOrientations;
    objc_setAssociatedObject(controller, LC32LegacyOrientationMaskKey,
        @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return mask;
}

void LC32ApplyLegacyWindowPolicy(UIWindow *window) {
    if(!window || !window.guest_selfOrNull) return;
    if(!pthread_main_np()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            const bool previous = LC32SuppressGuestOrientationQuery;
            LC32SuppressGuestOrientationQuery = true;
            LC32ApplyLegacyWindowPolicy(window);
            LC32SuppressGuestOrientationQuery = previous;
        });
        return;
    }

    UIViewController *rootController =
        LC32NativeWindowRootViewController(window);
    UIViewController *guestRootController =
        LC32GuestWindowRootViewController(window);
    UIViewController *orientationController =
        LC32ActiveOrientationController(guestRootController);
    UIInterfaceOrientationMask orientations =
        LC32SupportedOrientationsForController(orientationController);
    if(!orientations) {
        orientations = LC32GuestInterfacePolicy().declaredOrientations;
    }

    [orientationController setNeedsUpdateOfSupportedInterfaceOrientations];
    [rootController setNeedsStatusBarAppearanceUpdate];

    UIWindowScene *scene = window.windowScene;
    if(!scene) return;
    const CGRect sceneBounds = LC32WindowSceneBounds(window);
    const UIInterfaceOrientation current =
        LC32WindowSceneOrientation(window, sceneBounds);
    UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    UIInterfaceOrientationMask requestedMask =
        LC32MaskForInterfaceOrientation(requested);
    UIInterfaceOrientationMask geometryOrientations =
        requestedMask & orientations ? requestedMask : orientations;
    /* A legacy controller which accepts exactly one orientation is a more
     * precise launch policy than a permissive Info.plist. Publish it before
     * the first post-makeKey scale, even if the old UIApplication setter has
     * not run yet. */
    if(!requestedMask && geometryOrientations &&
            !(geometryOrientations & (geometryOrientations - 1))) {
        requested = LC32FirstOrientationInMask(geometryOrientations);
        requestedMask = LC32MaskForInterfaceOrientation(requested);
        LC32LegacyRequestedOrientation.store(
            requested, std::memory_order_relaxed);
        geometryOrientations = requestedMask;
    }
    if(LC32MaskForInterfaceOrientation(current) & geometryOrientations) {
        return;
    }

    if(@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *preferences =
            [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:geometryOrientations];
        [scene requestGeometryUpdateWithPreferences:preferences
            errorHandler:^(NSError *error) {
                fprintf(stderr,
                    "LC32: legacy scene orientation update failed: %s\n",
                    error.localizedDescription.UTF8String ?: "unknown error");
            }];
#if !__has_feature(objc_arc)
        [preferences release];
#endif
    } else {
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

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
    } @catch(NSException *exception) {
        if(LC32IsGuestCrashException(exception)) @throw;
        return nil;
    }
}

bool LC32InstallLegacyDirectSubviewRoot(UIWindow *window) {
    if(!window || LC32NativeWindowRootViewController(window)) return false;

    const NSUInteger existingSubviewCount = window.subviews.count;
    if(!existingSubviewCount) return false;

    UIViewController *controller =
        [[LC32LegacyWindowRootController alloc] initWithNibName:nil
                                                         bundle:nil];
    (void)controller.view;
    LC32NativeSetWindowRootViewController(window, controller);
    const bool installed =
        LC32NativeWindowRootViewController(window) == controller;
    if(installed) {
        /* Assigning a native root normally places its view above existing
         * direct children.  Move only that new implementation detail behind
         * the archived hierarchy so every preexisting child keeps its exact
         * relative order, including any private UIKit overlay. */
        LC32NativeSendSubviewToBack(window, controller.view);
        fprintf(stderr,
            "LC32: installed legacy direct-view window root (%lu subviews)\n",
            (unsigned long)existingSubviewCount);
    }
#if !__has_feature(objc_arc)
    [controller release];
#endif
    return installed;
}

void LC32AdoptLegacyRootViewController(UIWindow *window) {
    if(!window || !window.guest_selfOrNull) return;
    UIViewController *existing =
        LC32NativeWindowRootViewController(window);
    if(existing) {
        if(LC32WindowNeedsLegacyIPadContainer(window) &&
                ![existing isKindOfClass:
                    LC32LegacyIPadContainerController.class] &&
                LC32ObjectUsesGuestClass(existing)) {
            LC32InstallGuestWindowRootViewController(window, existing,
                LC32LegacyIPadGeometryModePreservePortraitCanvas);
        }
        LC32ApplyLegacyWindowPolicy(window);
        LC32ScaleLegacyIPadWindow(window);
        return;
    }

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

    if(!controller && LC32InstallLegacyDirectSubviewRoot(window)) {
        LC32ApplyLegacyWindowPolicy(window);
        LC32ScaleLegacyIPadWindow(window);
        return;
    }

    if(controller) {
        LC32InstallGuestWindowRootViewController(window, controller,
            LC32LegacyIPadGeometryModePreservePortraitCanvas);
        fprintf(stderr, "LC32: adopted legacy root view controller %s\n",
                object_getClassName(controller));
    }
    LC32ApplyLegacyWindowPolicy(window);
}

void LC32AdoptLegacyRootViewControllers(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *delegateWindow = LC32ObjectProperty(application.delegate,
                                                   "window");
    if(delegateWindow) {
        LC32AdoptLegacyRootViewController(delegateWindow);
        LC32ScaleLegacyIPadWindow(delegateWindow);
        return;
    }
    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            LC32AdoptLegacyRootViewController(window);
            LC32ScaleLegacyIPadWindow(window);
        }
    }
}

} // namespace

@implementation LC32LegacyWindowRootController

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    view.userInteractionEnabled = NO;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    self.view = view;
#if !__has_feature(objc_arc)
    [view release];
#endif
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return LC32GuestInterfacePolicy().declaredOrientations;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    const UIInterfaceOrientationMask mask =
        [self supportedInterfaceOrientations];
    const UIInterfaceOrientation target = LC32LegacyTargetOrientation();
    return LC32MaskForInterfaceOrientation(target) & mask
        ? target : LC32FirstOrientationInMask(mask);
}

- (BOOL)prefersStatusBarHidden {
    return LC32GuestInterfacePolicy().statusBarHidden;
}

- (BOOL)shouldAutomaticallyForwardRotationMethods {
    return NO;
}

@end

@implementation LC32LegacyIPadContainerController

@synthesize guestContentController = _guestContentController;

- (instancetype)initWithGuestContentController:
        (UIViewController *)controller
                                  geometryMode:
        (LC32LegacyIPadGeometryMode)mode {
    self = [super initWithNibName:nil bundle:nil];
    if(self) {
        _geometryMode = mode;
        if(controller) {
            [self setGuestContentController:controller geometryMode:mode];
        }
    }
    return self;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = UIColor.blackColor;
    view.clipsToBounds = YES;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    self.view = view;

    /* The wrapper is always a native UIView. Transforming a mirrored guest
     * subclass directly can invoke a guest setter from a host scene callback,
     * and also lets UIKit rewrite the guest EAGL view transform during modern
     * rotation. UIView hit testing automatically applies the inverse wrapper
     * transform before delivering touches to the guest hierarchy. */
    UIView *canvas = [[UIView alloc] initWithFrame:CGRectZero];
    canvas.backgroundColor = UIColor.clearColor;
    canvas.clipsToBounds = YES;
    canvas.autoresizingMask = UIViewAutoresizingNone;
    [view addSubview:canvas];
    _canvasView = canvas;
#if !__has_feature(objc_arc)
    [canvas release];
    [view release];
#endif
}

- (void)setGuestContentController:(UIViewController *)controller
                      geometryMode:(LC32LegacyIPadGeometryMode)mode {
    if(controller == _guestContentController) {
        if(_geometryMode != mode) {
            _geometryMode = mode;
            [self fitGuestContentForViewport:self.view.bounds
                hostOrientation:UIInterfaceOrientationUnknown];
        }
        return;
    }

    ++_guestContentGeneration;
    _guestLayoutPending = NO;
    UIViewController *oldController = _guestContentController;
    UIView *oldView = _guestContentView;
    if(oldController) [oldController willMoveToParentViewController:nil];
    [oldView removeFromSuperview];
    [oldController removeFromParentViewController];
    _guestContentController = nil;
    _guestContentView = nil;
    _canonicalGuestBounds = CGRectZero;
    _geometryMode = mode;

    if(!controller) return;

    /* Loading is deliberately done while the guest assigns or exposes its
     * root on a registered guest thread. Later refits use only retained views
     * and native UIView IMPs; they never ask the controller to load. */
    (void)self.view;
    UIView *contentView = controller.view;
    CGRect canonicalBounds = LC32NativeViewBounds(contentView);
    const CGFloat shortEdge = MIN(canonicalBounds.size.width,
                                  canonicalBounds.size.height);
    const CGFloat longEdge = MAX(canonicalBounds.size.width,
                                 canonicalBounds.size.height);
    if(!isfinite(shortEdge) || !isfinite(longEdge) ||
            shortEdge < 700 || longEdge < 900) {
        canonicalBounds = CGRectMake(0, 0, 768, 1024);
    }

    _guestContentController = controller;
    _guestContentView = contentView;
    _canonicalGuestBounds = canonicalBounds;
    [self addChildViewController:controller];
    [_canvasView addSubview:contentView];
    [controller didMoveToParentViewController:self];
    LC32NativeSetViewAutoresizingMask(contentView, UIViewAutoresizingNone);
    [self fitGuestContentForViewport:self.view.bounds
        hostOrientation:UIInterfaceOrientationUnknown];
    [self scheduleGuestLayout];
}

- (void)fitGuestContentForViewport:(CGRect)viewport
                   hostOrientation:(UIInterfaceOrientation)orientation {
    UIView *contentView = _guestContentView;
    UIView *canvasView = _canvasView;
    if(!contentView || !canvasView || _fittingGuestContent) return;
    /* Layout callbacks can still report the archived 768x1024 root bounds
     * even after the window is attached to a smaller compatibility scene.
     * For settled refits, always prefer that scene's visible extent. The
     * transition callback supplies a concrete future size and is retained as
     * the pre-settlement fallback until its completion runs. */
    if(orientation == UIInterfaceOrientationUnknown) {
        UIWindow *window = self.view.window;
        if(window.windowScene) {
            viewport = LC32LegacyViewportInView(window, self.view);
        }
    }
    if(!(viewport.size.width > 0) || !(viewport.size.height > 0)) {
        viewport = self.view.bounds;
    }
    const CGSize viewportSize = viewport.size;
    if(!(viewportSize.width > 0) || !(viewportSize.height > 0)) return;

    _fittingGuestContent = YES;
    (void)orientation;
    const UIInterfaceOrientation target = LC32LegacyTargetOrientation();
    CGRect canonicalBounds = _canonicalGuestBounds;
    if(!(canonicalBounds.size.width > 0) ||
            !(canonicalBounds.size.height > 0)) {
        canonicalBounds = CGRectMake(0, 0, 768, 1024);
    }

    CGSize logicalSize = canonicalBounds.size;
    CGFloat compositorAngle = 0;
    if(_geometryMode == LC32LegacyIPadGeometryModeReflowRootController) {
        /* The bridged rootViewController setter is the observable lifecycle
         * boundary between old resize-aware apps and pre-controller window
         * composition. In this mode UIKit historically resized the hierarchy
         * to the requested orientation, so resize-aware engines receive a
         * real 1024x768 EAGL drawable in landscape. The already-oriented scene
         * then displays it with an identity compositor. */
        const CGFloat shortEdge = MIN(logicalSize.width, logicalSize.height);
        const CGFloat longEdge = MAX(logicalSize.width, logicalSize.height);
        logicalSize = UIInterfaceOrientationIsLandscape(target)
            ? CGSizeMake(longEdge, shortEdge)
            : CGSizeMake(shortEdge, longEdge);
    } else {
        /* Pre-iOS-4 applications can add a portrait 768x1024 EAGL view
         * directly to UIWindow. Preserve that drawable contract and recreate
         * the old root compositor on this native wrapper only. */
        switch(target) {
            case UIInterfaceOrientationLandscapeLeft:
                compositorAngle = M_PI_2;
                break;
            case UIInterfaceOrientationLandscapeRight:
                compositorAngle = -M_PI_2;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                compositorAngle = M_PI;
                break;
            default:
                break;
        }
    }

    const CGAffineTransform rotation =
        CGAffineTransformMakeRotation(compositorAngle);
    const CGRect transformedBounds = CGRectApplyAffineTransform(
        CGRectMake(0, 0, logicalSize.width, logicalSize.height), rotation);
    const CGFloat transformedWidth = fabs(transformedBounds.size.width);
    const CGFloat transformedHeight = fabs(transformedBounds.size.height);
    const CGFloat scale = transformedWidth > 0 && transformedHeight > 0
        ? MIN(viewportSize.width / transformedWidth,
              viewportSize.height / transformedHeight)
        : 0;
    if(scale > 0 && isfinite(scale)) {
        const CGRect desiredContentBounds = CGRectMake(
            canonicalBounds.origin.x, canonicalBounds.origin.y,
            logicalSize.width, logicalSize.height);
        const BOOL contentBoundsChanged = !CGRectEqualToRect(
            LC32NativeViewBounds(contentView), desiredContentBounds);

        canvasView.transform = CGAffineTransformIdentity;
        canvasView.bounds = CGRectMake(
            0, 0, logicalSize.width, logicalSize.height);
        canvasView.center = CGPointMake(
            CGRectGetMidX(viewport), CGRectGetMidY(viewport));
        canvasView.transform = CGAffineTransformScale(rotation, scale, scale);

        /* Use UIView's native implementations so a mirrored guest subclass
         * cannot turn a host geometry callback into a nested guest call. Keep
         * any application-authored transform on the content view itself. */
        LC32NativeSetViewBounds(contentView, desiredContentBounds);
        LC32NativeSetViewCenter(contentView, CGPointMake(
            logicalSize.width * 0.5, logicalSize.height * 0.5));
        LC32NativeSetViewAutoresizingMask(contentView, UIViewAutoresizingNone);
        if(contentBoundsChanged) {
            LC32NativeSetViewNeedsLayout(contentView);
            [self scheduleGuestLayout];
        }
    }
    _fittingGuestContent = NO;
}

- (void)scheduleGuestLayout {
    UIView *contentView = _guestContentView;
    if(!contentView || _guestLayoutPending) return;

    _guestLayoutPending = YES;
    const NSUInteger generation = _guestContentGeneration;
    LC32NativeSetViewNeedsLayout(contentView);
    dispatch_async(dispatch_get_main_queue(), ^{
        if(generation != _guestContentGeneration ||
                contentView != _guestContentView) {
            return;
        }
        _guestLayoutPending = NO;
        LC32NativeSetViewNeedsLayout(contentView);
        /* layoutIfNeeded can reach a guest EAGLView.layoutSubviews. Only force
         * it while the native main pthread owns a registered guest context;
         * otherwise leave the invalidation for UIKit's next safe transaction. */
        if(Dynarmic_guest_thread_is_registered()) {
            LC32NativeLayoutViewIfNeeded(contentView);
        }
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self fitGuestContentForViewport:self.view.bounds
        hostOrientation:UIInterfaceOrientationUnknown];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    /* UIKit can ask during a scene callback with no active guest JIT frame.
     * The root-install path already cached the guest policy when it was safe;
     * never enter guest code from this native container callback. */
    return LC32CachedGuestOrientationMask(_guestContentController);
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    const UIInterfaceOrientationMask mask =
        [self supportedInterfaceOrientations];
    const UIInterfaceOrientation target = LC32LegacyTargetOrientation();
    return LC32MaskForInterfaceOrientation(target) & mask
        ? target : LC32FirstOrientationInMask(mask);
}

- (BOOL)prefersStatusBarHidden {
    return LC32GuestInterfacePolicy().statusBarHidden;
}

- (BOOL)shouldAutomaticallyForwardRotationMethods {
    /* The legacy callbacks need a dedicated FP-aware guest ABI adapter.
     * Until then the native container owns rotation and must not cause UIKit
     * to invoke a guest callback from an arbitrary host transition stack. */
    return NO;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:
        (id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size
         withTransitionCoordinator:coordinator];
    UIInterfaceOrientation targetOrientation = LC32LegacyTargetOrientation();
    CGRect targetViewport = self.view.bounds;
    UIWindow *window = self.view.window;
    if(window.windowScene) {
        targetViewport = LC32LegacyViewportInView(window, self.view);
    }
    if(!window.windowScene ||
            !LC32UsesClassicFullScreenViewport(window)) {
        targetViewport.size = size;
    }
    [self fitGuestContentForViewport:targetViewport
        hostOrientation:targetOrientation];
    void (^refitActualBounds)(void) = ^{
        [self fitGuestContentForViewport:self.view.bounds
            hostOrientation:UIInterfaceOrientationUnknown];
    };
    BOOL scheduled = NO;
    if(coordinator) {
        scheduled = [coordinator animateAlongsideTransition:nil completion:
            ^(__unused id<UIViewControllerTransitionCoordinatorContext>
              context) {
                refitActualBounds();
            }];
    }
    if(!scheduled) {
        dispatch_async(dispatch_get_main_queue(), refitActualBounds);
    }
}

@end

extern "C" void LC32UIKitPrepareGuestClass(Class cls) {
    if(!cls || !LC32ClassIsUIViewController(cls)) return;

    auto addNativeAdapter = ^(SEL selector, IMP implementation) {
        Method declaration = class_getInstanceMethod(
            UIViewController.class, selector);
        if(!declaration) return false;
        return class_addMethod(cls, selector, implementation,
                               method_getTypeEncoding(declaration));
    };

    const bool hasLegacyRotation =
        LC32GuestClassHierarchyDefinesSelector(
            cls, @selector(shouldAutorotateToInterfaceOrientation:));
    if(hasLegacyRotation) {
        addNativeAdapter(@selector(supportedInterfaceOrientations),
            (IMP)&LC32LegacySupportedInterfaceOrientations);
        addNativeAdapter(
            @selector(preferredInterfaceOrientationForPresentation),
            (IMP)&LC32LegacyPreferredInterfaceOrientation);
    }

    /* UIStatusBarHidden and pre-iOS-7 UIApplication status-bar calls are no
     * longer consulted by modern UIKit. A guest implementation of the modern
     * method wins because class_addMethod leaves an existing method intact. */
    addNativeAdapter(@selector(prefersStatusBarHidden),
        (IMP)&LC32LegacyPrefersStatusBarHidden);

}

/* SVC 1002 forwards the first guest argument in r2, followed by r3 and the
 * guest stack pointer. Keep this exported entry point in that three-word
 * shape even though the UIKit adapter only needs the orientation. */
extern "C" u32 LC32UIKitHandleLegacyStatusBarOrientation(
        u32 orientationValue, u32, u32) {
    const UIInterfaceOrientation orientation =
        (UIInterfaceOrientation)orientationValue;
    if(!LC32MaskForInterfaceOrientation(orientation)) return 0;
    LC32LegacyRequestedOrientation.store(
        orientation, std::memory_order_relaxed);
    /* Early game engines can keep the native main thread inside their guest
     * loop indefinitely. Refit synchronously while this legacy setter is
     * already executing on that thread; queuing the only refit would leave
     * the old portrait placement in force forever. Scaling itself does not
     * enter guest code. */
    if(pthread_main_np()) {
        UIApplication *application = UIApplication.sharedApplication;
        UIWindow *keyWindow = application.keyWindow;
        if(keyWindow) LC32ScaleLegacyIPadWindow(keyWindow);
        for(UIScene *scene in application.connectedScenes) {
            if(![scene isKindOfClass:UIWindowScene.class]) continue;
            for(UIWindow *window in ((UIWindowScene *)scene).windows) {
                if(window != keyWindow) LC32ScaleLegacyIPadWindow(window);
            }
        }
    }

    /* Avoid entering guest shouldAutorotate... while its outgoing direct
     * UIKit host call is still on the JIT stack. */
    dispatch_async(dispatch_get_main_queue(), ^{
        LC32AdoptLegacyRootViewControllers();
    });
    return 0;
}

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
    /* UIWindowScene geometry is authoritative only after makeKeyAndVisible.
     * Refit the virtual child canvas against that settled viewport without
     * changing guest-visible UIWindow bounds. */
    LC32ApplyLegacyWindowPolicy(self);
    LC32ScaleLegacyIPadWindow(self);
}

@end

/*
 * Sentinel returned to the guest UIApplicationMain shim when the host run
 * loop was interrupted by a guest-debugger all-stop. The guest shim loops
 * back and re-enters this function, which then drives the run loop directly
 * (the app object and delegate already exist). Keep the value in sync with
 * GuestFrameworks/UIKit/UIKit.m.
 */
static const int LC32UIKITRunLoopDebuggerStop = 0x1C32DEAD;

/*
 * The guest debugger can request an all-stop (worker crash, ^C, breakpoint)
 * while the guest main thread is parked inside the host UIApplicationMain run
 * loop. That blocking mach_msg lives in CoreFoundation and is not tracked by
 * the coordinator's debuggerMachCalls, so it cannot be aborted like a guest
 * SVC wait. GSEventRunModal(0) also loops forever, so CFRunLoopStop alone
 * cannot make UIApplicationMain return. Instead the notifier below wakes the
 * main run loop and its armed block unwinds the run loop via a caught
 * Objective-C exception, returning control to the guest JIT so the stop
 * reply is delivered. Once the debugger resumes, the guest shim re-enters
 * this function and LC32RunDebuggerAwareMainRunLoop drives the run loop
 * directly with a poll, avoiding any further unwinding.
 */
@interface LC32DebuggerStopException : NSException
@end
@implementation LC32DebuggerStopException
@end

/* Non-zero only while UIApplicationMain's own run loop is executing, so the
 * notifier block only unwinds (throws) inside the @try below. */
static bool LC32RunLoopExceptionArmed = false;

static void LC32DebuggerStopRunLoopBlock(void) {
    if((LC32DebuggerAllStopRequested() ||
            LC32DebuggerSessionUnwindRequested()) &&
            LC32RunLoopExceptionArmed) {
        @throw [LC32DebuggerStopException
            exceptionWithName:@"LC32DebuggerStopException"
                       reason:@"Guest debugger requested an all-stop"
                     userInfo:nil];
    }
}

static void LC32DebuggerStopRunLoopNotify(void) {
    CFRunLoopRef runLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
        LC32DebuggerStopRunLoopBlock();
    });
    CFRunLoopWakeUp(runLoop);
}

static int LC32RunDebuggerAwareMainRunLoop(void) {
    /* Re-entry after a debugger stop: the app object and delegate already
     * exist, so drive the run loop directly. The short timeout bounds stop
     * latency even if the wake-up is missed. */
    for(;;) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        if(LC32DebuggerAllStopRequested() ||
                LC32DebuggerSessionUnwindRequested()) {
            return LC32UIKITRunLoopDebuggerStop;
        }
    }
}

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

    static bool firstEntry = true;
    if(!firstEntry) {
        return LC32RunDebuggerAwareMainRunLoop();
    }
    firstEntry = false;
    if(!LC32DebuggerActive()) {
        return UIApplicationMain(
            argc, host_argv, principalClassName, delegateClassName);
    }

    LC32SetDebuggerStopRunLoopNotifier(
        LC32DebuggerStopRunLoopNotify);
    LC32RunLoopExceptionArmed = true;
    int result;
    @try {
        result = UIApplicationMain(
            argc, host_argv, principalClassName, delegateClassName);
    } @catch(LC32DebuggerStopException *exception) {
        LC32RunLoopExceptionArmed = false;
        fprintf(stderr,
            "LC32: host run loop interrupted by guest debugger stop\n");
        fflush(stderr);
        return LC32UIKITRunLoopDebuggerStop;
    }
    LC32RunLoopExceptionArmed = false;
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

u32 LC32_UIKit_NSStringFromCGPoint(u32 xBits, u32 yBits, u32) {
    float x;
    float y;
    memcpy(&x, &xBits, sizeof(x));
    memcpy(&y, &yBits, sizeof(y));
    return NSStringFromCGPoint(CGPointMake(x, y)).guest_self;
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

u32 LC32_UIKit_CGRectFromString(u32 stringLow, u32 stringHigh, u32 sp) {
    NSString *string = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(stringLow |
            (static_cast<u64>(stringHigh) << 32)));
    const u32 guestResult =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    if(!string || !guestResult || guestResult > UINT32_MAX - 15)
        return 0;

    const CGRect rect = CGRectFromString(string);
    const struct {
        float x;
        float y;
        float width;
        float height;
    } guestRect = {
        static_cast<float>(rect.origin.x),
        static_cast<float>(rect.origin.y),
        static_cast<float>(rect.size.width),
        static_cast<float>(rect.size.height),
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

void LC32_UIKit_UIGraphicsPushContext(
        u32 contextLow, u32 contextHigh, u32) {
    CGContextRef context = reinterpret_cast<CGContextRef>(
        static_cast<uintptr_t>(contextLow |
            (static_cast<u64>(contextHigh) << 32)));
    if(context) UIGraphicsPushContext(context);
}

void LC32_UIKit_UIGraphicsPopContext(u32, u32, u32) {
    LC32CoreGraphicsSyncBitmapBacking(UIGraphicsGetCurrentContext());
    UIGraphicsPopContext();
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

u32 LC32_UIKit_UIImagePNGRepresentation(u32 imageLow, u32 imageHigh, u32) {
    UIImage *image = reinterpret_cast<UIImage *>(static_cast<uintptr_t>(
        imageLow | (static_cast<u64>(imageHigh) << 32)));
    NSData *data = image ? UIImagePNGRepresentation(image) : nil;
    return data ? data.guest_self : 0;
}

void LC32_UIKit_UIImageWriteToSavedPhotosAlbum(
        u32 imageLow, u32 imageHigh, u32 sp) {
    UIImage *image = reinterpret_cast<UIImage *>(static_cast<uintptr_t>(
        imageLow | (static_cast<u64>(imageHigh) << 32)));
    id completionTarget = reinterpret_cast<id>(static_cast<uintptr_t>(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp) |
        (static_cast<u64>(
            Dynarmic_current_user_callbacks()->MemoryRead32(sp + 4))
            << 32)));
    SEL completionSelector = reinterpret_cast<SEL>(static_cast<uintptr_t>(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 8) |
        (static_cast<u64>(
            Dynarmic_current_user_callbacks()->MemoryRead32(sp + 12))
            << 32)));
    void *contextInfo = reinterpret_cast<void *>(static_cast<uintptr_t>(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 16)));
    if(image) UIImageWriteToSavedPhotosAlbum(
        image, completionTarget, completionSelector, contextInfo);
}

u32 LC32_UIKit_NSStringFromCGRect(
        u32 xBits, u32 yBits, u32 sp) {
    float x;
    float y;
    float width;
    float height;
    memcpy(&x, &xBits, sizeof(x));
    memcpy(&y, &yBits, sizeof(y));
    const u32 widthBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 heightBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + sizeof(u32));
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    return NSStringFromCGRect(CGRectMake(x, y, width, height)).guest_self;
}

u32 LC32_UIKit_GetWindowRootViewController(
        u32 windowLow, u32 windowHigh, u32) {
    UIWindow *window = reinterpret_cast<UIWindow *>(static_cast<uintptr_t>(
        windowLow | (static_cast<u64>(windowHigh) << 32)));
    UIViewController *controller =
        LC32GuestWindowRootViewController(window);
    if(!controller) return 0;
    u32 guestController = controller.guest_selfOrNull;
    if(!guestController && Dynarmic_guest_thread_is_registered()) {
        guestController = controller.guest_self;
    }
    return guestController;
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

    const bool suppressGuestCallbacks = !pthread_main_np();
    dispatch_block_t setRoot = ^{
        const bool previous = LC32SuppressGuestOrientationQuery;
        if(suppressGuestCallbacks) {
            LC32SuppressGuestOrientationQuery = true;
        }
        LC32InstallGuestWindowRootViewController(window, controller,
            LC32LegacyIPadGeometryModeReflowRootController);
        LC32ApplyLegacyWindowPolicy(window);
        LC32ScaleLegacyIPadWindow(window);
        LC32SuppressGuestOrientationQuery = previous;
    };
    if(pthread_main_np()) {
        setRoot();
    } else {
        /* Guest callback pthreads can wait on the main guest loop, so a
         * synchronous hop can deadlock. The copied dispatch block retains the
         * window/controller until UIKit performs the assignment. Suppression
         * keeps that foreign native-main callback from entering guest code. */
        dispatch_async(dispatch_get_main_queue(), setRoot);
    }
}

__END_DECLS
