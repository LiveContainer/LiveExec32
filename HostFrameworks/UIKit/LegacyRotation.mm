#import "LC32LegacyRotation.h"
#import "LC32ClassicPresentation.h"
#include "../../include/LC32UIKitCompatibilityConfig.h"
#if LC32_UIKIT_COMPATIBILITY
#import <objc/message.h>
#import <objc/runtime.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// This unit deliberately restores UIKit's deprecated pre-iOS-8 contract.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

enum class InitialBacking { Unseen, Provisional, Ready };
@interface LC32LegacyRotationState : NSObject
@property(nonatomic, weak) UIViewController *initializedController;
@property(nonatomic) InitialBacking initialBacking;
@property(nonatomic) CFTimeInterval initialPresentationDeadline;
@end
@implementation LC32LegacyRotationState
@end

@interface UIWindow (LC32LegacyRotationClient)
- (void)_setRotatableClient:(UIViewController *)client
    toOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)updateStatusBar
    duration:(NSTimeInterval)duration force:(BOOL)force isRotating:(BOOL)rotating;
@end

@interface UIDevice (LC32LegacyInitialOrientation)
- (void)setOrientation:(UIDeviceOrientation)orientation animated:(BOOL)animated;
@end

struct LC32RotationBuildVersion { uint32_t platform, version; };
extern "C" bool dyld_program_sdk_at_least(LC32RotationBuildVersion version);

namespace {
const void *RegisteredClassKey = &RegisteredClassKey;
const void *WindowStateKey = &WindowStateKey;
bool startupFinished;
using NativeRotationQuery = BOOL (*)(id, SEL, UIInterfaceOrientation, BOOL, BOOL *);
NativeRotationQuery nativeRotationQuery;
thread_local __unsafe_unretained UIWindow *configuringLegacyWindow;

struct BackingGeometry {
    CGRect bounds;
    CGPoint position;
    CATransform3D transform;
    explicit BackingGeometry(CALayer *layer)
        : bounds(layer.bounds), position(layer.position), transform(layer.transform) {}
    void apply(CALayer *layer) const {
        layer.bounds = bounds;
        layer.position = position;
        layer.transform = transform;
    }
};

LC32LegacyRotationState *WindowState(UIWindow *window) {
    LC32LegacyRotationState *state = objc_getAssociatedObject(window, WindowStateKey);
    if(!state) {
        state = [LC32LegacyRotationState new];
        objc_setAssociatedObject(window, WindowStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

UIInterfaceOrientationMask DeclaredOrientations();
UIInterfaceOrientation PreferredOrientation();

UIInterfaceOrientationMask LegacySupportedOrientations(id, SEL) {
    // This is a policy query, not a rotation request. In particular, old Unity
    // writes its pending orientation even when shouldAutorotate returns NO.
    // Probing all four directions here would leave an arbitrary pending turn.
    return DeclaredOrientations();
}

UIInterfaceOrientation LegacyPreferredOrientation(id, SEL) {
    return PreferredOrientation();
}

bool RegisteredClass(Class cls) {
    for(Class current = cls; current && current != UIViewController.class;
            current = class_getSuperclass(current)) {
        if(objc_getAssociatedObject((id)current, RegisteredClassKey)) return true;
    }
    return false;
}

bool UsesModernRotationPolicy(Class cls) {
    // Recheck the actual subclass: a guest can inherit the old callback but
    // deliberately replace its policy with the modern orientation API.
    IMP supported = class_getMethodImplementation(
        cls, @selector(supportedInterfaceOrientations));
    IMP should = class_getMethodImplementation(cls, @selector(shouldAutorotate));
    return (supported != (IMP)LegacySupportedOrientations &&
            supported != class_getMethodImplementation(UIViewController.class,
                @selector(supportedInterfaceOrientations))) ||
        should != class_getMethodImplementation(UIViewController.class,
            @selector(shouldAutorotate));
}

bool UsesLegacyRotationPolicy(Class cls) {
    return RegisteredClass(cls) &&
        class_getMethodImplementation(cls, @selector(shouldAutorotateToInterfaceOrientation:)) !=
            class_getMethodImplementation(UIViewController.class,
                @selector(shouldAutorotateToInterfaceOrientation:)) &&
        !UsesModernRotationPolicy(cls);
}

NSHashTable<UIViewController *> *Controllers() {
    static NSHashTable<UIViewController *> *controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSHashTable weakObjectsHashTable]; });
    return controllers;
}

UIView *NativeView(UIViewController *controller) {
    using Getter = UIView *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIViewController.class, @selector(viewIfLoaded));
    return getter(controller, @selector(viewIfLoaded));
}

UIView *NativeSuperview(UIView *view) {
    using Getter = UIView *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIView.class, @selector(superview));
    return getter(view, @selector(superview));
}

UIWindow *NativeWindow(UIView *view) {
    using Getter = UIWindow *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIView.class, @selector(window));
    return getter(view, @selector(window));
}

UIViewController *NativeRoot(UIWindow *window) {
    using Getter = UIViewController *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIWindow.class, @selector(rootViewController));
    return getter(window, @selector(rootViewController));
}

UIViewController *NativeParent(UIViewController *controller) {
    using Getter = UIViewController *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIViewController.class, @selector(parentViewController));
    return getter(controller, @selector(parentViewController));
}

UIViewController *NativePresenting(UIViewController *controller) {
    using Getter = UIViewController *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIViewController.class, @selector(presentingViewController));
    return getter(controller, @selector(presentingViewController));
}

UIViewController *NativePresented(UIViewController *controller) {
    using Getter = UIViewController *(*)(id, SEL);
    static Getter getter = (Getter)class_getMethodImplementation(
        UIViewController.class, @selector(presentedViewController));
    return getter(controller, @selector(presentedViewController));
}

UIViewController *BackingContentController(UIViewController *controller) {
    // Native navigation/tab containers rotate their own root view on behalf
    // of the guest inside. They need the same portrait backing, but must keep
    // ownership of policy and lifecycle dispatch. Do not traverse guest
    // containers, inactive children, or arbitrary view-controller hierarchies.
    using Getter = UIViewController *(*)(id, SEL);
    while(controller && !RegisteredClass(object_getClass(controller))) {
        if([controller isKindOfClass:UINavigationController.class]) {
            static Getter getter = (Getter)class_getMethodImplementation(
                UINavigationController.class, @selector(topViewController));
            controller = getter(controller, @selector(topViewController));
        } else if([controller isKindOfClass:UITabBarController.class]) {
            static Getter getter = (Getter)class_getMethodImplementation(
                UITabBarController.class, @selector(selectedViewController));
            controller = getter(controller, @selector(selectedViewController));
        } else {
            return nil;
        }
    }
    return controller;
}

UIViewController *ControllerForWindow(UIWindow *window, bool forBacking = false) {
    if(!window) return nil;
    UIViewController *root = NativeRoot(window);
    if(root) {
        if(NativePresented(root) && !forBacking) return nil;
        root = LC32NativeLegacyRotationContentController(root);
        if(!root) return nil; // The native canvas is installed before its guest.
        // Low-SDK UIKit still rotates a modern-policy root's view in portrait
        // window coordinates. It needs the same inverse backing rotation, but
        // must retain its modern policy without deprecated policy queries.
        Class cls = object_getClass(root);
        return forBacking ? (BackingContentController(root) ? root : nil) :
            (!NativePresented(root) && UsesLegacyRotationPolicy(cls) ? root : nil);
    }
    UIViewController *candidate = nil;
    for(UIViewController *controller in Controllers().allObjects) {
        // A renderer-owned controller can omit every rotation-policy method.
        // It still needs portrait backing coordinates, without old queries.
        Class cls = object_getClass(controller);
        if(!(forBacking ? RegisteredClass(cls) : UsesLegacyRotationPolicy(cls))) continue;
        UIView *view = NativeView(controller);
        if(view && NativeSuperview(view) == window &&
                !NativeParent(controller) &&
                !NativePresenting(controller) &&
                (forBacking || !NativePresented(controller))) {
            // Two independent direct children do not establish one rotation
            // owner. Do not pick one based on weak-table enumeration order.
            if(candidate) return nil;
            candidate = controller;
        }
    }
    return candidate;
}

UIInterfaceOrientation OrientationNamed(id name) {
    if([name isEqual:@"UIInterfaceOrientationPortrait"]) return UIInterfaceOrientationPortrait;
    if([name isEqual:@"UIInterfaceOrientationPortraitUpsideDown"]) return UIInterfaceOrientationPortraitUpsideDown;
    if([name isEqual:@"UIInterfaceOrientationLandscapeLeft"]) return UIInterfaceOrientationLandscapeLeft;
    if([name isEqual:@"UIInterfaceOrientationLandscapeRight"]) return UIInterfaceOrientationLandscapeRight;
    return UIInterfaceOrientationUnknown;
}

UIInterfaceOrientationMask OrientationBit(UIInterfaceOrientation orientation) {
    return orientation >= UIInterfaceOrientationPortrait &&
        orientation <= UIInterfaceOrientationLandscapeLeft
        ? (UIInterfaceOrientationMask)(1UL << orientation) : 0;
}

NSArray *DeclaredOrientationNames() {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    id names;
    if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        names = info[@"UISupportedInterfaceOrientations~ipad"];
    if(![names isKindOfClass:NSArray.class]) names = info[@"UISupportedInterfaceOrientations"];
    return [names isKindOfClass:NSArray.class] ? names : nil;
}

UIInterfaceOrientationMask DeclaredOrientations() {
    UIInterfaceOrientationMask mask = 0;
    for(id name in DeclaredOrientationNames()) mask |= OrientationBit(OrientationNamed(name));
    return mask ?: UIInterfaceOrientationMaskAllButUpsideDown;
}

bool SupportedScene(UIWindowScene *scene) {
    return (OrientationBit(scene.interfaceOrientation) & DeclaredOrientations()) != 0;
}

void PresentInitialBacking(UIWindow *window, CALayer *backing) {
    if(startupFinished || !window.windowScene) return;
    LC32LegacyRotationState *state = WindowState(window);
    InitialBacking previous = state.initialBacking;
    if(previous == InitialBacking::Ready && !state.initialPresentationDeadline) return;
    bool ready = previous == InitialBacking::Ready || SupportedScene(window.windowScene);
    InitialBacking next = ready ? InitialBacking::Ready : InitialBacking::Provisional;
    CFTimeInterval now = CACurrentMediaTime();

    // A rotating rectangular backing can cut off an upright client's corners
    // until the scene turn settles. Hold only its presentation, not the guest
    // window's model opacity, layout, key status or display-link clock. CA
    // removes the hold even if no scene update arrives or the guest blocks.
    if(previous != next) {
        state.initialBacking = next;
        if(previous == InitialBacking::Unseen && ready) return;
        CFTimeInterval duration = [backing animationForKey:@"transform"].duration
            ?: UIView.inheritedAnimationDuration ?: UIApplication.sharedApplication.statusBarOrientationAnimationDuration;
        state.initialPresentationDeadline = isfinite(duration) ? now + duration : 0;
    }
    CFTimeInterval remaining = state.initialPresentationDeadline - now;
    if(remaining <= 0) {
        state.initialPresentationDeadline = 0;
        return;
    }
    NSString *key = @"lc32.initialPresentation";
    if(previous == next && [backing animationForKey:key]) return;
    // UIKit may replace or clear the provisional layer when ordering the
    // window front. Restore only the remaining interval, never restart it.
    CABasicAnimation *hold = [CABasicAnimation animationWithKeyPath:@"opacity"];
    hold.fromValue = hold.toValue = @0;
    hold.duration = remaining;
    [backing addAnimation:hold forKey:key];
}

UIInterfaceOrientation PreferredOrientation() {
    UIInterfaceOrientationMask mask = DeclaredOrientations();
    UIInterfaceOrientation current = UIApplication.sharedApplication.statusBarOrientation;
    if(OrientationBit(current) & mask) return current;
    // A rootless legacy window may still report portrait while its scene has
    // already launched landscape. Prefer that actual turn over plist order.
    current = UIApplication.sharedApplication.keyWindow.windowScene.interfaceOrientation;
    if(OrientationBit(current) & mask) return current;
    current = OrientationNamed(NSBundle.mainBundle.infoDictionary[@"UIInterfaceOrientation"]);
    if(OrientationBit(current) & mask) return current;
    for(id name in DeclaredOrientationNames()) {
        current = OrientationNamed(name);
        if(OrientationBit(current) & mask) return current;
    }
    return UIInterfaceOrientationPortrait;
}

struct RotationRequest {
    __unsafe_unretained UIWindow *window;
    __unsafe_unretained UIViewController *controller;
    UIInterfaceOrientation orientation;
    BOOL accepted;
    RotationRequest *previous;
};
thread_local RotationRequest *activeRequest;

BOOL QueryRotation(UIWindow *window, UIViewController *controller,
        UIInterfaceOrientation orientation) {
    if(!(OrientationBit(orientation) & DeclaredOrientations())) return NO;
    if(activeRequest && activeRequest->window == window && activeRequest->controller == controller &&
            activeRequest->orientation == orientation) return activeRequest->accepted;
    if(!startupFinished || !LC32NativeLegacyRotationCanCallGuest()) return NO;
    return ((BOOL (*)(id, SEL, UIInterfaceOrientation))objc_msgSend)(controller,
        @selector(shouldAutorotateToInterfaceOrientation:), orientation);
}

void UpdateWindow(UIWindow *window, UIInterfaceOrientation orientation,
        bool initialOnly) {
    if(!pthread_main_np() || !startupFinished) return;
    UIViewController *controller = ControllerForWindow(window, true);
    if(!controller || !(OrientationBit(orientation) & DeclaredOrientations())) return;
    UIView *view = NativeView(controller);
    if(!view || NativeWindow(view) != window) return;
    // Synchronize the portrait window extent before a guest rotation callback
    // sizes its renderer from UIScreen. Resizing afterwards applies the same
    // scene-size delta a second time through the view's autoresizing mask.
    ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("_updateTransformLayer"));
    if(!LC32NativeLegacyRotationCanCallGuest()) return;
    if(NativePresented(controller)) return;
    LC32LegacyRotationState *state = WindowState(window);
    const bool initializing = state.initializedController != controller;
    if(initialOnly && !initializing) return;
    // Rootless legacy windows have no native rotation client yet. Once one is
    // registered, respect UIKit's presentation and rotation-lock decisions.
    if(NativeRoot(window) && nativeRotationQuery) {
        BOOL disabled = NO;
        if(!nativeRotationQuery(window,
                sel_registerName("_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:"),
                orientation, YES, &disabled) || disabled) return;
    }

    BOOL accepted = !UsesLegacyRotationPolicy(object_getClass(controller)) ||
        QueryRotation(window, controller, orientation);
    if(ControllerForWindow(window, true) != controller) return;
    state.initializedController = controller;
    if(!NativeRoot(window)) {
        // A direct-window controller that accepts UIKit rotation still needs
        // the old rotatable-client path. The scene-era window updater ignores
        // it without a root controller. Keep the hierarchy intact, and leave
        // NO-returning/manual renderers in charge of their own transforms.
        if(accepted && UsesLegacyRotationPolicy(object_getClass(controller)) &&
                [window respondsToSelector:@selector(_setRotatableClient:toOrientation:
                    updateStatusBar:duration:force:isRotating:)]) {
            RotationRequest request{window, controller, orientation, accepted, activeRequest};
            activeRequest = &request;
            @try {
                const bool sameOrientation =
                    ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(window,
                        @selector(interfaceOrientation)) == orientation;
                // Repeated device notifications are not layout requests. A
                // forced same-orientation turn can restart UIKit's animation.
                if(sameOrientation && !initializing) return;
                const bool initialSync = initializing && sameOrientation;
                if(initialSync) [controller willRotateToInterfaceOrientation:orientation duration:0];
                NSTimeInterval duration = initializing ? 0 :
                    UIApplication.sharedApplication.statusBarOrientationAnimationDuration;
                [window _setRotatableClient:controller toOrientation:orientation
                    updateStatusBar:YES duration:duration force:sameOrientation isRotating:YES];
                if(initialSync) [controller didRotateFromInterfaceOrientation:orientation];
            } @finally {
                activeRequest = request.previous;
            }
        }
        ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("_updateTransformLayer"));
        return;
    }
    // A NO may still have queued a renderer-owned turn. Do not rotate the
    // controller before giving the game that choice.
    if(!accepted) {
        ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("_updateTransformLayer"));
        return;
    }
    RotationRequest request{window, controller, orientation, accepted, activeRequest};
    activeRequest = &request;
    @try {
        // Synchronize the newly registered rotation client with the window.
        // Unlike the old force-rotation API this is also valid for a window
        // whose scene owns orientation. It leaves Classic Mode to UIKit.
        SEL rotate = sel_registerName("_updateToInterfaceOrientation:duration:force:");
        if([window respondsToSelector:rotate]) {
            // A window may already have the scene's orientation before the
            // game attaches its controller. UIKit then only lays out the new
            // client, without a will/did pair. Supply that initial lifecycle
            // before the next guest frame can perform a competing manual turn.
            // Native containers already dispatch their children's lifecycle.
            SEL current = sel_registerName("interfaceOrientation");
            const bool sameOrientation =
                ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(window, current) == orientation;
            bool initialSync = initializing && RegisteredClass(object_getClass(controller)) &&
                sameOrientation;
            if(initialSync) [controller willRotateToInterfaceOrientation:orientation duration:0];
            // Force only a same-orientation layout refresh. For an actual turn,
            // UIKit's forced path skips the client's rotation lifecycle, leaving
            // renderer layout and touch coordinates in the previous orientation.
            ((void (*)(id, SEL, UIInterfaceOrientation, NSTimeInterval, BOOL))objc_msgSend)(
                window, rotate, orientation, 0, sameOrientation);
            if(initialSync) [controller didRotateFromInterfaceOrientation:orientation];
        } else {
            [UIViewController attemptRotationToDeviceOrientation];
        }
    } @finally {
        activeRequest = request.previous;
    }
}

void UpdateWindows(UIInterfaceOrientation orientation, bool initialOnly) {
    NSMutableSet<UIWindow *> *windows = [NSMutableSet set];
    for(UIViewController *controller in Controllers().allObjects) {
        UIView *view = NativeView(controller);
        UIWindow *window = view ? NativeWindow(view) : nil;
        if(window) [windows addObject:window];
    }
    for(UIWindow *window in windows) UpdateWindow(window, orientation, initialOnly);
}

void InitializeDeviceOrientation() {
    // A scene can launch landscape while the sensor is flat (or portrait in
    // a landscape-only app). Old notification-driven renderers then never
    // receive an initial supported orientation. Bootstrap from the actual
    // scene after their deferred launch work and controller layout finish.
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *controller = ControllerForWindow(window, true);
    if(!controller || NativePresented(controller) || !LC32NativeLegacyRotationCanCallGuest()) return;
    UIInterfaceOrientation initial = window.windowScene.interfaceOrientation;
    UIInterfaceOrientationMask supported = DeclaredOrientations();
    UIDevice *device = UIDevice.currentDevice;
    UIDeviceOrientation physical = device.orientation;
    if(!(OrientationBit(initial) & supported) ||
            (OrientationBit((UIInterfaceOrientation)physical) & supported) ||
            !device.generatesDeviceOrientationNotifications ||
            ![device respondsToSelector:@selector(setOrientation:animated:)]) return;
    @try {
        // Native setter only updates the cached reading and posts the normal
        // notification. Device/interface enum values match, not their names.
        [device setOrientation:(UIDeviceOrientation)initial animated:NO];
    } @finally {
        // This is an initial presentation event, not a sensor override. Leave
        // face-up/down readings and all subsequent physical events intact.
        [device setOrientation:physical animated:NO];
    }
}

void Swizzle(Class cls, SEL original, SEL replacement) {
    Method method = class_getInstanceMethod(cls, original);
    if(!method) {
        NSLog(@"LC32: %s not found", sel_getName(original));
        return;
    }
    method_exchangeImplementations(method, class_getInstanceMethod(cls, replacement));
}

BOOL LegacyApplicationStatusBarPolicy(id, SEL) { return NO; }
} // namespace

extern "C" bool LC32NativeLegacyRotationEnabled(void) {
    static const bool enabled = [] {
        const char *disabled = getenv("LC32_DISABLE_UIKIT_COMPATIBILITY");
        return !(disabled && strcmp(disabled, "1") == 0) &&
            !dyld_program_sdk_at_least({2, 0x00080000});
    }();
    return enabled;
}

extern "C" void LC32PrepareNativeLegacyRotationClass(Class cls) {
    if(!cls || !LC32NativeLegacyRotationEnabled()) return;
    // Modern rotation policy arrived in iOS 6, before the iOS 8 geometry
    // change. Those guest controllers still need portrait backing coordinates
    // and the deprecated will/did lifecycle, but not legacy policy queries.
    objc_setAssociatedObject((id)cls, RegisteredClassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!UsesLegacyRotationPolicy(cls)) return;
    class_addMethod(cls, @selector(supportedInterfaceOrientations),
        (IMP)LegacySupportedOrientations, method_getTypeEncoding(class_getInstanceMethod(
            UIViewController.class, @selector(supportedInterfaceOrientations))));
    SEL preferred = @selector(preferredInterfaceOrientationForPresentation);
    if(class_getMethodImplementation(cls, preferred) ==
            class_getMethodImplementation(UIViewController.class, preferred))
        class_addMethod(cls, preferred, (IMP)LegacyPreferredOrientation,
            method_getTypeEncoding(class_getInstanceMethod(UIViewController.class, preferred)));
}

extern "C" bool LC32NativeLegacyRotationStartupSceneReady(void) {
    if(!LC32NativeLegacyRotationEnabled() || startupFinished) return true;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if(!ControllerForWindow(window, true) || !window.windowScene) return true;
    // A scene can connect in an unsupported provisional orientation and
    // deliver its initial landscape update after the first idle boundary.
    // Do not initialize the renderer from plist order or consume its one-time
    // device notification until the host has supplied a supported orientation.
    return SupportedScene(window.windowScene);
}

// A guest can do synchronous loading in its first display-link callback. If
// the link was created against provisional geometry, let UIKit publish the
// supported scene before such a callback can monopolize the main thread.
@interface LC32StartupDisplayLinkTarget : NSObject {
@public
    id _target;
    SEL _action;
    CFTimeInterval _deadline;
}
@end
@implementation LC32StartupDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    if(pthread_main_np() && _deadline) {
        bool waiting = link.timestamp < _deadline;
        if(waiting && !LC32NativeLegacyRotationStartupSceneReady()) return;
        _deadline = 0;
        // The orientation can change in this very update cycle; give its
        // transaction one refresh. A late or previously paused link runs now.
        if(waiting) return;
    }
    ((void (*)(id, SEL, CADisplayLink *))objc_msgSend)(_target, _action, link);
}
@end

extern "C" id LC32LegacyStartupDisplayLinkTarget(id target, SEL *action) {
    if(!target || !*action || !NSThread.isMainThread || LC32NativeLegacyRotationStartupSceneReady())
        return target;
    LC32StartupDisplayLinkTarget *relay = [LC32StartupDisplayLinkTarget new];
    relay->_target = target;
    relay->_action = *action;
    relay->_deadline = CACurrentMediaTime() + UIApplication.sharedApplication.statusBarOrientationAnimationDuration;
    *action = @selector(tick:);
    return relay;
}

extern "C" void LC32FinishNativeLegacyRotationStartup(void) {
    if(!LC32NativeLegacyRotationEnabled() || !LC32NativeLegacyRotationStartupSceneReady()) return;
    const bool initializing = !startupFinished;
    startupFinished = true;
    UpdateWindows(PreferredOrientation(), true);
    if(initializing) {
        InitializeDeviceOrientation();
        // Startup finishes at the last BeforeWaiting observer, after Core
        // Animation's normal commit. Publish the matching client/backing
        // geometry now: the next guest callback can block on loading while
        // the scene host is already displaying its new orientation.
        [CATransaction flush];
    }
}

@interface UIViewController (LC32NativeLegacyRotation)
- (void)lc32_rotationViewDidMoveToWindow:(UIWindow *)window shouldAppearOrDisappear:(BOOL)appear;
- (void)lc32_rotationWindow:(UIWindow *)window willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
    duration:(NSTimeInterval)duration newSize:(CGSize)size;
- (void)lc32_rotationWindow:(UIWindow *)window didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation
    oldSize:(CGSize)size;
@end

@implementation UIViewController (LC32NativeLegacyRotation)
- (void)lc32_rotationViewDidMoveToWindow:(UIWindow *)window shouldAppearOrDisappear:(BOOL)appear {
    [self lc32_rotationViewDidMoveToWindow:window shouldAppearOrDisappear:appear];
    if(!window || !pthread_main_np() || !RegisteredClass(object_getClass(self))) return;
    [Controllers() addObject:self];
    if(!startupFinished) {
        // The window can configure its backing before this controller is
        // registered. Refresh that native geometry now, before the first
        // visible frame; only guest rotation callbacks need deferred startup.
        ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("_updateTransformLayer"));
        return;
    }
    // Revalidate deferred attachment work; a replaced or detached controller
    // must not initialize the next owner of its old window.
    __weak UIViewController *pendingController = self;
    __weak UIWindow *pendingWindow = window;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = pendingController;
        UIWindow *target = pendingWindow;
        if(controller && target &&
                BackingContentController(ControllerForWindow(target, true)) == controller)
            UpdateWindow(target, PreferredOrientation(), true);
    });
}

- (void)lc32_rotationWindow:(UIWindow *)window willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
        duration:(NSTimeInterval)duration newSize:(CGSize)size {
    [self lc32_rotationWindow:window willRotateToInterfaceOrientation:orientation duration:duration newSize:size];
    UIViewController *controller = LC32NativeLegacyRotationContentController(self);
    if(RegisteredClass(object_getClass(controller)) && startupFinished && LC32NativeLegacyRotationCanCallGuest())
        [controller willRotateToInterfaceOrientation:orientation duration:duration];
}

- (void)lc32_rotationWindow:(UIWindow *)window didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation
        oldSize:(CGSize)size {
    [self lc32_rotationWindow:window didRotateFromInterfaceOrientation:orientation oldSize:size];
    UIViewController *controller = LC32NativeLegacyRotationContentController(self);
    if(RegisteredClass(object_getClass(controller)) && startupFinished && LC32NativeLegacyRotationCanCallGuest())
        [controller didRotateFromInterfaceOrientation:orientation];
}
@end

@interface UIScreen (LC32NativeLegacyRotation)
- (CGRect)lc32_applicationFrameForInterfaceOrientation:(UIInterfaceOrientation)orientation
    usingStatusbarHeight:(CGFloat)height ignoreStatusBar:(BOOL)ignore;
@end

@implementation UIScreen (LC32NativeLegacyRotation)
- (CGRect)lc32_applicationFrameForInterfaceOrientation:(UIInterfaceOrientation)orientation
        usingStatusbarHeight:(CGFloat)height ignoreStatusBar:(BOOL)ignore {
    // Legacy controller bounds/center still use the default status-bar height
    // when the bar is hidden. Keep that nonexistent inset out of both queries;
    // shrinking just the renderer desynchronizes its projection and touches.
    CGRect frame = [self lc32_applicationFrameForInterfaceOrientation:orientation
        usingStatusbarHeight:height ignoreStatusBar:ignore || UIApplication.sharedApplication.statusBarHidden];
    LC32ClassicScreenGeometry saved;
    if(LC32GetClassicScreenGeometry(self, &saved)) {
        // Legacy controller rotation derives its renderer size and center
        // from this screen query, not UIWindow.bounds. Retain UIKit's insets
        // but use the captured logical extent after the host leaves Classic.
        CGRect native = self.bounds;
        frame.size.width += saved.bounds.size.width - native.size.width;
        frame.size.height += saved.bounds.size.height - native.size.height;
    }
    return frame;
}
@end

@interface UIWindow (LC32NativeLegacyRotation)
- (void)lc32_rotationSetRootViewController:(UIViewController *)controller;
- (void)lc32_updateToInterfaceOrientation:(UIInterfaceOrientation)orientation
    duration:(NSTimeInterval)duration force:(BOOL)force;
- (void)lc32_configureRootLayer:(CALayer *)root sceneTransformLayer:(CALayer *)scene
    transformLayer:(CALayer *)transform;
- (BOOL)lc32_windowOwnsInterfaceOrientation;
- (BOOL)lc32_windowOwnsInterfaceOrientationTransform;
- (BOOL)lc32_shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
    checkForDismissal:(BOOL)check isRotationDisabled:(BOOL *)disabled;
+ (void)lc32_nativeLegacyDeviceOrientationChanged:(NSNotification *)notification;
@end

@implementation UIWindow (LC32NativeLegacyRotation)
- (void)lc32_rotationSetRootViewController:(UIViewController *)controller {
    [self lc32_rotationSetRootViewController:controller];
    if(startupFinished || !pthread_main_np()) return;
    UIViewController *content = BackingContentController(controller);
    if(!content || !UsesModernRotationPolicy(object_getClass(content))) return;
    UIView *view = NativeView(controller);
    if(!view || NativeWindow(view) != self) return;
    // Modern-policy controllers already have the window's orientation, but
    // scene-era UIKit defers applying it to a newly installed legacy root's
    // view. Complete that same-orientation layout before the caller sizes a
    // fixed renderer from its bounds. Do not request a new orientation or
    // advance the deferred lifecycle of renderer-owned legacy controllers.
    SEL orientation = sel_registerName("interfaceOrientation");
    SEL update = sel_registerName("_updateToInterfaceOrientation:duration:force:");
    if([self respondsToSelector:update]) {
        UIInterfaceOrientation current =
            ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(self, orientation);
        ((void (*)(id, SEL, UIInterfaceOrientation, NSTimeInterval, BOOL))objc_msgSend)(
            self, update, current, 0, YES);
    }
}
- (void)lc32_updateToInterfaceOrientation:(UIInterfaceOrientation)orientation
        duration:(NSTimeInterval)duration force:(BOOL)force {
    // Scene-owned windows do not run the old backing update as part of their
    // view rotation. Sync its extent before resizing the client and its root
    // transform afterwards, including a same-orientation scene-size change.
    // During startup, rootless windows also need the incoming scene geometry
    // before a deferred loader can block the main thread. This refresh does
    // not advance their guest rotation lifecycle. Afterwards, old-policy
    // rootless controllers retain their renderer-owned turn ordering.
    UIViewController *backingController = ControllerForWindow(self, true);
    BOOL legacy = backingController && (!startupFinished || NativeRoot(self) ||
        !UsesLegacyRotationPolicy(object_getClass(backingController)));
    SEL refresh = sel_registerName("_updateTransformLayer");
    if(legacy) ((void (*)(id, SEL))objc_msgSend)(self, refresh);
    [self lc32_updateToInterfaceOrientation:orientation duration:duration force:force];
    if(legacy) ((void (*)(id, SEL))objc_msgSend)(self, refresh);
    // The scene host can present its new orientation while guest loading is
    // busy. Publish the matching backing in this native update, not at the
    // deferred guest-startup boundary or the next automatic CA commit.
    if(legacy && !startupFinished) [CATransaction flush];
}
- (void)lc32_configureRootLayer:(CALayer *)root sceneTransformLayer:(CALayer *)scene
        transformLayer:(CALayer *)transform {
    // A presented overlay suspends the renderer's rotation queries, not the
    // backing coordinate system of the window beneath it.
    if(!ControllerForWindow(self, true)) {
        [self lc32_configureRootLayer:root sceneTransformLayer:scene transformLayer:transform];
        return;
    }
    // The pre-iOS-8 compositor rotates the client in portrait window space.
    // Scene-owned windows now skip its inverse root-layer rotation and retain
    // landscape backing bounds, leaving that client sideways and clipped.
    // Select UIKit's original backing-layer setup only inside this operation;
    // the scene must still own orientation requests and events everywhere else.
    UIWindow *previous = configuringLegacyWindow;
    configuringLegacyWindow = self;
    @try {
        const BackingGeometry oldRoot(root), oldScene(scene);
        BackingGeometry newRoot(root), newScene(scene);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        @try {
            [self lc32_configureRootLayer:root sceneTransformLayer:scene transformLayer:transform];
            // A scene host may discard its CAContext root layer's transform.
            // Express the same mapping below that boundary instead: publish an
            // upright root extent and carry its transform on the existing child.
            // This preserves the legacy window/view coordinate system, including
            // hit testing, without depending on the host's root-transform policy.
            CGAffineTransform rotation = root.affineTransform;
            if(!CGAffineTransformIsIdentity(rotation)) {
                CGRect frame = root.frame;
                CGPoint position = [root convertPoint:scene.position toLayer:root.superlayer];
                scene.affineTransform = CGAffineTransformConcat(scene.affineTransform, rotation);
                root.affineTransform = CGAffineTransformIdentity;
                root.bounds = (CGRect){CGPointZero, frame.size};
                root.frame = frame;
                scene.position = CGPointMake(position.x - frame.origin.x,
                    position.y - frame.origin.y);
            }
            newRoot = BackingGeometry(root);
            newScene = BackingGeometry(scene);
            oldRoot.apply(root);
            oldScene.apply(scene);
        } @finally {
            [CATransaction commit];
        }
        // UIKit's intermediate root rotation is only a coordinate-system
        // change. Animate from the previously published geometry to the final
        // rebased geometry, never from that temporary portrait-layer setup.
        // Keep the caller's animation timing and disabled-actions policy.
        newRoot.apply(root);
        newScene.apply(scene);
        PresentInitialBacking(self, scene);
    } @finally {
        configuringLegacyWindow = previous;
    }
}
- (BOOL)lc32_windowOwnsInterfaceOrientation {
    return configuringLegacyWindow == self || [self lc32_windowOwnsInterfaceOrientation];
}
- (BOOL)lc32_windowOwnsInterfaceOrientationTransform {
    return configuringLegacyWindow == self || [self lc32_windowOwnsInterfaceOrientationTransform];
}
+ (void)load {
    if(!LC32NativeLegacyRotationEnabled()) return;
    Swizzle(self, @selector(setRootViewController:),
        @selector(lc32_rotationSetRootViewController:));
    // Controller-managed status bars were introduced in iOS 7. Modern UIKit
    // defaults to them even for older guests, losing UIStatusBarHidden and
    // UIApplication's setters. Preserve an explicit opt-in/out in the bundle.
    if(!dyld_program_sdk_at_least({2, 0x00070000}) &&
            ![NSBundle.mainBundle objectForInfoDictionaryKey:
                @"UIViewControllerBasedStatusBarAppearance"]) {
        Method method = class_getInstanceMethod(objc_getClass("UIApplication"),
            sel_registerName("_viewControllerBasedStatusBarAppearance"));
        if(method) method_setImplementation(method, (IMP)LegacyApplicationStatusBarPolicy);
    }
    // Do not initialize UIScreen while the runtime itself is being dlopened.
    Swizzle(objc_getClass("UIScreen"),
        sel_registerName("_applicationFrameForInterfaceOrientation:usingStatusbarHeight:ignoreStatusBar:"),
        @selector(lc32_applicationFrameForInterfaceOrientation:usingStatusbarHeight:ignoreStatusBar:));
    Swizzle(self, sel_registerName("_updateToInterfaceOrientation:duration:force:"),
        @selector(lc32_updateToInterfaceOrientation:duration:force:));
    Swizzle(self, sel_registerName("_configureRootLayer:sceneTransformLayer:transformLayer:"),
        @selector(lc32_configureRootLayer:sceneTransformLayer:transformLayer:));
    Swizzle(self, sel_registerName("_windowOwnsInterfaceOrientation"),
        @selector(lc32_windowOwnsInterfaceOrientation));
    Swizzle(self, sel_registerName("_windowOwnsInterfaceOrientationTransform"),
        @selector(lc32_windowOwnsInterfaceOrientationTransform));
    Swizzle(UIViewController.class,
        sel_registerName("viewDidMoveToWindow:shouldAppearOrDisappear:"),
        @selector(lc32_rotationViewDidMoveToWindow:shouldAppearOrDisappear:));
    // The scene-era callbacks retained native bookkeeping but dropped the
    // deprecated public callbacks expected by pre-iOS-6 guest controllers.
    Swizzle(UIViewController.class,
        sel_registerName("window:willRotateToInterfaceOrientation:duration:newSize:"),
        @selector(lc32_rotationWindow:willRotateToInterfaceOrientation:duration:newSize:));
    Swizzle(UIViewController.class,
        sel_registerName("window:didRotateFromInterfaceOrientation:oldSize:"),
        @selector(lc32_rotationWindow:didRotateFromInterfaceOrientation:oldSize:));
    nativeRotationQuery = (NativeRotationQuery)class_getMethodImplementation(self,
        sel_registerName("_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:"));
    Swizzle(self,
        sel_registerName("_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:"),
        @selector(lc32_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:));
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(lc32_nativeLegacyDeviceOrientationChanged:)
        name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (BOOL)lc32_shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
        checkForDismissal:(BOOL)check isRotationDisabled:(BOOL *)disabled {
    BOOL allowed = [self lc32_shouldAutorotateToInterfaceOrientation:orientation
        checkForDismissal:check isRotationDisabled:disabled];
    UIViewController *controller = ControllerForWindow(self);
    if(!allowed || !controller) return allowed;
    return QueryRotation(self, controller, orientation);
}

+ (void)lc32_nativeLegacyDeviceOrientationChanged:(NSNotification *)notification {
    (void)notification;
    // The enums use the same values (the landscape *names* are opposite).
    UIInterfaceOrientation orientation = (UIInterfaceOrientation)UIDevice.currentDevice.orientation;
    if(OrientationBit(orientation)) UpdateWindows(orientation, false);
}
@end
#else
extern "C" bool LC32NativeLegacyRotationEnabled(void) { return false; }
extern "C" void LC32PrepareNativeLegacyRotationClass(Class) {}
extern "C" bool LC32NativeLegacyRotationStartupSceneReady(void) { return true; }
extern "C" id LC32LegacyStartupDisplayLinkTarget(id target, SEL *) { return target; }
extern "C" void LC32FinishNativeLegacyRotationStartup(void) {}
#endif // LC32_UIKIT_COMPATIBILITY
