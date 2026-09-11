@import Darwin;
@import QuartzCore;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"
#include "crash_exception.h"
#include "LiveExec32Shared.h"
#include "LC32LegacyCanvas.h"
#include "LC32LegacyRotation.h"
#include "../CoreGraphics/LC32CoreGraphicsHost.h"

#include <atomic>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef NS_ENUM(NSUInteger, LC32LegacyIPadGeometryMode) {
    /* Pre-root-controller applications and some early fixed-surface engines
     * keep a portrait iPad drawable and rely on UIKit's compositor turn. */
    LC32LegacyIPadGeometryModePreservePortraitCanvas,
    /* Applications using UIWindow.rootViewController expect UIKit to resize
     * the controller hierarchy into the requested interface orientation. */
    LC32LegacyIPadGeometryModeReflowRootController,
    /* Some legacy landscape phone applications deliberately render through
     * a portrait 320x480 surface and rotate in their projection matrix. Keep
     * that drawable contract and turn only the native wrapper. */
    LC32LegacyIPadGeometryModePreservePhonePortraitCanvas,
    /* Some 568-point phone applications advertise tall launch art but retain
     * a 480x320 game view. Keep that already-landscape drawable centered at
     * 1x inside the modern scene. */
    LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas,
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
@property(nonatomic, readonly) LC32LegacyIPadGeometryMode geometryMode;
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

@interface LC32LegacyRendererAutoresizingState : NSObject
@property(nonatomic) UIViewAutoresizing originalMask;
@property(nonatomic) BOOL yielded;
@end

@implementation LC32LegacyRendererAutoresizingState
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
const void *LC32GuestSupportedOrientationsIMPKey =
    &LC32GuestSupportedOrientationsIMPKey;
const void *LC32GuestPreferredOrientationIMPKey =
    &LC32GuestPreferredOrientationIMPKey;
const void *LC32SettledLegacyOrientationKey =
    &LC32SettledLegacyOrientationKey;
const void *LC32HideLegacyDirectGuestWindowRootKey =
    &LC32HideLegacyDirectGuestWindowRootKey;
const void *LC32LegacyDirectWindowSublayerTransformKey =
    &LC32LegacyDirectWindowSublayerTransformKey;
const void *LC32LegacyDirectWindowAppliedSublayerTransformKey =
    &LC32LegacyDirectWindowAppliedSublayerTransformKey;
const void *LC32LegacyWindowLayersLayoutPendingKey =
    &LC32LegacyWindowLayersLayoutPendingKey;
const void *LC32LegacyRootlessWindowPlacementKey =
    &LC32LegacyRootlessWindowPlacementKey;
const void *LC32LegacyRootlessRendererAutoresizingKey =
    &LC32LegacyRootlessRendererAutoresizingKey;
const void *LC32LegacyRootlessRendererAutoresizingStateKey =
    &LC32LegacyRootlessRendererAutoresizingStateKey;
const void *LC32LegacyOverlayLayoutPendingKey =
    &LC32LegacyOverlayLayoutPendingKey;
const void *LC32LegacyRootWindowGeometryKey =
    &LC32LegacyRootWindowGeometryKey;

struct LC32GuestUIKitPolicy {
    UIInterfaceOrientationMask declaredOrientations;
    UIInterfaceOrientation preferredOrientation;
    bool statusBarHidden;
    bool constrainsControllerOrientations;
    bool usesLegacyInitialOrientation;
};

const LC32GuestUIKitPolicy& LC32GuestInterfacePolicy(void);
UIInterfaceOrientation LC32FirstOrientationInMask(
    UIInterfaceOrientationMask mask);
id LC32ObjectProperty(id object, const char *name);

std::atomic<NSInteger> LC32LegacyRequestedOrientation{
    UIInterfaceOrientationUnknown};
thread_local bool LC32SuppressGuestOrientationQuery = false;
thread_local bool LC32AllowGuestOrientationQuery = false;
// A registered guest thread is not necessarily ready for renderer callbacks.
// Legacy engines can show their window before initializing the screen manager,
// sometimes in a zero-delay selector scheduled by the launch delegate.
std::atomic<bool> LC32GuestOrientationStartupComplete{true};
u32 LC32GuestOrientationStartupCallbackDepth = 0;

bool LC32CanQueryGuestOrientation(void) {
    return LC32GuestOrientationStartupComplete.load(std::memory_order_acquire) &&
        !LC32SuppressGuestOrientationQuery &&
        Dynarmic_guest_thread_is_registered();
}

class LC32GuestOrientationQueryScope {
public:
    LC32GuestOrientationQueryScope()
        : previous_(LC32AllowGuestOrientationQuery) {
        LC32AllowGuestOrientationQuery = true;
    }

    ~LC32GuestOrientationQueryScope() {
        LC32AllowGuestOrientationQuery = previous_;
    }

private:
    bool previous_;
};

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

UIView *LC32NativeViewSuperview(UIView *view) {
    using Getter = UIView *(*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(superview)));
    return view ? getter(view, @selector(superview)) : nil;
}

NSArray<UIView *> *LC32NativeViewSubviews(UIView *view) {
    using Getter = NSArray<UIView *> *(*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(subviews)));
    return view ? getter(view, @selector(subviews)) : nil;
}

UIWindow *LC32NativeViewWindow(UIView *view) {
    using Getter = UIWindow *(*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(window)));
    return view ? getter(view, @selector(window)) : nil;
}

BOOL LC32NativeViewHidden(UIView *view) {
    using Getter = BOOL (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(isHidden)));
    return view ? getter(view, @selector(isHidden)) : NO;
}

CALayer *LC32NativeViewLayer(UIView *view) {
    using Getter = CALayer *(*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(layer)));
    return view ? getter(view, @selector(layer)) : nil;
}

UIApplicationState LC32NativeApplicationState(void) {
    UIApplication *application = UIApplication.sharedApplication;
    using Getter = UIApplicationState (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(
            UIApplication.class, @selector(applicationState)));
    return application
        ? getter(application, @selector(applicationState))
        : UIApplicationStateInactive;
}

CGAffineTransform LC32NativeViewTransform(UIView *view) {
    using Getter = CGAffineTransform (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class,
                                      @selector(transform)));
    return view ? getter(view, @selector(transform))
                : CGAffineTransformIdentity;
}

CGPoint LC32NativeViewCenter(UIView *view) {
    using Getter = CGPoint (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class, @selector(center)));
    return view ? getter(view, @selector(center)) : CGPointZero;
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

void LC32NativeSetViewTransform(
        UIView *view, CGAffineTransform transform) {
    using Setter = void (*)(id, SEL, CGAffineTransform);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(UIView.class,
                                      @selector(setTransform:)));
    if(view) setter(view, @selector(setTransform:), transform);
}

void LC32NativeSetViewAutoresizingMask(
        UIView *view, UIViewAutoresizing mask) {
    using Setter = void (*)(id, SEL, UIViewAutoresizing);
    static Setter setter = reinterpret_cast<Setter>(
        class_getMethodImplementation(
            UIView.class, @selector(setAutoresizingMask:)));
    if(view) setter(view, @selector(setAutoresizingMask:), mask);
}

UIViewAutoresizing LC32NativeViewAutoresizingMask(UIView *view) {
    using Getter = UIViewAutoresizing (*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(UIView.class,
            @selector(autoresizingMask)));
    return view ? getter(view, @selector(autoresizingMask))
                : UIViewAutoresizingNone;
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

UIInterfaceOrientationMask LC32ConstrainGuestOrientationMask(
        UIInterfaceOrientationMask mask) {
    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    if(!mask) return policy.declaredOrientations;
    if(!policy.constrainsControllerOrientations) return mask;

    /* A real supported-orientations array is an outer constraint on every
     * controller. UIInterfaceOrientation is only an initial-side hint and is
     * handled later, where the active window scene is known. */
    const UIInterfaceOrientationMask constrained =
        mask & policy.declaredOrientations;
    return constrained ? constrained : policy.declaredOrientations;
}

const LC32GuestUIKitPolicy& LC32GuestInterfacePolicy(void) {
    static LC32GuestUIKitPolicy policy = {
        UIInterfaceOrientationMaskPortrait,
        UIInterfaceOrientationPortrait,
        false,
        false,
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

        const bool usesIPadPolicy = LC32BundleNeedsLegacyIPadCanvas(
            bundle, LC32GetGuestExecutableSDKVersion());
        NSArray *orientationNames = usesIPadPolicy
            ? info[@"UISupportedInterfaceOrientations~ipad"] : nil;
        if(![orientationNames isKindOfClass:NSArray.class]) {
            orientationNames = info[@"UISupportedInterfaceOrientations"];
        }
        const bool hasSupportedOrientationArray =
            [orientationNames isKindOfClass:NSArray.class];

        UIInterfaceOrientationMask declared = 0;
        for(id value in orientationNames) {
            if(![value isKindOfClass:NSString.class]) continue;
            declared |= LC32MaskForInterfaceOrientation(
                LC32InterfaceOrientationFromName(value));
        }

        const UIInterfaceOrientation preferred =
            LC32InterfaceOrientationFromName(info[@"UIInterfaceOrientation"]);
        const UIInterfaceOrientationMask preferredMask =
            LC32MaskForInterfaceOrientation(preferred);
        const bool usesLegacyInitialOrientation =
            !hasSupportedOrientationArray && preferredMask;
        if(!declared && usesLegacyInitialOrientation) {
            declared = preferredMask;
        }
        if(!declared) declared = UIInterfaceOrientationMaskPortrait;

        policy.declaredOrientations = declared;
        policy.preferredOrientation =
            preferredMask & declared
            ? preferred
            : UIInterfaceOrientationUnknown;
        policy.statusBarHidden = [info[@"UIStatusBarHidden"] boolValue];
        policy.constrainsControllerOrientations =
            hasSupportedOrientationArray;
        policy.usesLegacyInitialOrientation =
            usesLegacyInitialOrientation;
    });
    return policy;
}

void LC32CacheSettledLegacyOrientation(
        id object, UIInterfaceOrientation orientation) {
    if(!object || !LC32GuestInterfacePolicy().usesLegacyInitialOrientation ||
            !LC32MaskForInterfaceOrientation(orientation)) {
        return;
    }
    objc_setAssociatedObject(object, LC32SettledLegacyOrientationKey,
        @((NSInteger)orientation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

UIInterfaceOrientation LC32SettledLegacyOrientation(
        id object, UIInterfaceOrientationMask mask) {
    if(!LC32GuestInterfacePolicy().usesLegacyInitialOrientation) {
        return UIInterfaceOrientationUnknown;
    }
    NSNumber *cached = object ? objc_getAssociatedObject(
        object, LC32SettledLegacyOrientationKey) : nil;
    const UIInterfaceOrientation settled = cached
        ? (UIInterfaceOrientation)cached.integerValue
        : UIInterfaceOrientationUnknown;
    return LC32MaskForInterfaceOrientation(settled) & mask
        ? settled : UIInterfaceOrientationUnknown;
}

IMP LC32GuestOrientationImplementation(id object, const void *key) {
    for(Class cls = object_getClass(object); cls;
            cls = class_getSuperclass(cls)) {
        NSNumber *value = objc_getAssociatedObject((id)cls, key);
        if(value) return reinterpret_cast<IMP>(
            static_cast<uintptr_t>(value.unsignedLongLongValue));
        if(cls == UIViewController.class) break;
    }
    return nullptr;
}

UIInterfaceOrientationMask LC32GuestSupportedInterfaceOrientations(
        UIViewController *controller, SEL selector) {
    NSNumber *cached = objc_getAssociatedObject(
        controller, LC32LegacyOrientationMaskKey);
    if(!LC32AllowGuestOrientationQuery || !LC32CanQueryGuestOrientation()) {
        return cached
            ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
            : LC32GuestInterfacePolicy().declaredOrientations;
    }

    using SupportedOrientations =
        UIInterfaceOrientationMask (*)(id, SEL);
    SupportedOrientations original =
        reinterpret_cast<SupportedOrientations>(
            LC32GuestOrientationImplementation(
                controller, LC32GuestSupportedOrientationsIMPKey));
    UIInterfaceOrientationMask mask = original
        ? original(controller, selector) : 0;
    mask = LC32ConstrainGuestOrientationMask(mask);
    objc_setAssociatedObject(controller, LC32LegacyOrientationMaskKey,
        @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return mask;
}

UIInterfaceOrientationMask LC32ControllerSupportedInterfaceOrientations(
        UIViewController *controller) {
    using SupportedOrientations =
        UIInterfaceOrientationMask (*)(id, SEL);
    UIInterfaceOrientationMask mask = controller
        ? reinterpret_cast<SupportedOrientations>(objc_msgSend)(
            controller, @selector(supportedInterfaceOrientations))
        : 0;
    mask = LC32ConstrainGuestOrientationMask(mask);
    if(controller) {
        objc_setAssociatedObject(controller, LC32LegacyOrientationMaskKey,
            @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return mask;
}

UIInterfaceOrientation LC32GuestPreferredInterfaceOrientation(
        UIViewController *controller, SEL selector) {
    using PreferredOrientation = UIInterfaceOrientation (*)(id, SEL);
    PreferredOrientation original =
        reinterpret_cast<PreferredOrientation>(
            LC32GuestOrientationImplementation(
                controller, LC32GuestPreferredOrientationIMPKey));
    const UIInterfaceOrientation guestPreferred =
        original && LC32AllowGuestOrientationQuery &&
                LC32CanQueryGuestOrientation()
            ? original(controller, selector)
            : UIInterfaceOrientationUnknown;

    const UIInterfaceOrientationMask mask =
        LC32ControllerSupportedInterfaceOrientations(controller);
    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested) & mask) {
        return requested;
    }
    const UIInterfaceOrientation settled =
        LC32SettledLegacyOrientation(controller, mask);
    if(settled != UIInterfaceOrientationUnknown) {
        return settled;
    }
    if(LC32MaskForInterfaceOrientation(guestPreferred) & mask) {
        return guestPreferred;
    }
    const UIInterfaceOrientation bundlePreferred =
        LC32GuestInterfacePolicy().preferredOrientation;
    if(LC32MaskForInterfaceOrientation(bundlePreferred) & mask) {
        return bundlePreferred;
    }
    return LC32FirstOrientationInMask(mask);
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

struct LC32GuestLoadViewFrame {
    __unsafe_unretained UIViewController *controller;
    LC32GuestLoadViewFrame *previous;
};

thread_local LC32GuestLoadViewFrame *LC32GuestLoadViewFrames = nullptr;

bool LC32GuestLoadViewIsActive(UIViewController *controller) {
    for(LC32GuestLoadViewFrame *frame = LC32GuestLoadViewFrames;
            frame; frame = frame->previous) {
        if(frame->controller == controller) return true;
    }
    return false;
}

class LC32GuestLoadViewScope {
public:
    explicit LC32GuestLoadViewScope(UIViewController *controller)
        : frame{controller, LC32GuestLoadViewFrames} {
        LC32GuestLoadViewFrames = &frame;
    }

    ~LC32GuestLoadViewScope() {
        LC32GuestLoadViewFrames = frame.previous;
    }

private:
    LC32GuestLoadViewFrame frame;
};

void LC32GuestLoadView(UIViewController *controller, SEL selector) {
    if(LC32GuestLoadViewIsActive(controller)) {
        /* LC32InvokeHostSelector normally intercepts the reentrant -view read
         * before native UIKit reaches this callback. Keep a no-op backstop for
         * any other same-controller native load path; installing a generic
         * UIView here would make the legacy override believe loading finished. */
        return;
    }

    LC32GuestLoadViewScope scope(controller);
    (void)LC32InvokeGuestSelector(
        controller, selector, 0, 0, 0, 0, 0, 0);
}

void LC32GuestWillRotate(UIViewController *controller, SEL selector,
        UIInterfaceOrientation orientation, NSTimeInterval duration) {
    if(!LC32CanQueryGuestOrientation()) return;

    // A typed native IMP receives duration in d0. Darwin ARMv7 uses four-byte
    // argument alignment here: self/cmd/orientation occupy r0-r2, the double's
    // low word is r3, and its high word is the first stack argument. Do not
    // insert the eight-byte alignment padding used by generic AAPCS examples.
    // Verified with Clang's armv7-apple-ios Objective-C caller and callee.
    static_assert(sizeof(duration) == sizeof(u64));
    u64 durationBits;
    memcpy(&durationBits, &duration, sizeof(durationBits));
    u32 arguments[] = {
        [controller guest_self],
        guest_sel_registerName(sel_getName(selector)),
        static_cast<u32>(orientation),
        static_cast<u32>(durationBits),
        static_cast<u32>(durationBits >> 32),
    };
    (void)guest_objc_msgSend(sizeof(arguments) / sizeof(*arguments), arguments);
}

bool LC32NativeViewIfLoaded(UIViewController *controller, UIView **view) {
    if(!view) return false;
    using Getter = UIView *(*)(id, SEL);
    static Getter getter = reinterpret_cast<Getter>(
        class_getMethodImplementation(
            UIViewController.class, @selector(viewIfLoaded)));
    *view = controller ? getter(controller, @selector(viewIfLoaded)) : nil;
    return true;
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
    if(!LC32AllowGuestOrientationQuery || !LC32CanQueryGuestOrientation()) {
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
    mask = LC32ConstrainGuestOrientationMask(mask);
    objc_setAssociatedObject(controller, LC32LegacyOrientationMaskKey,
        @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return mask;
}

UIInterfaceOrientation LC32LegacyPreferredInterfaceOrientation(
        UIViewController *controller, SEL) {
    const UIInterfaceOrientationMask mask =
        LC32ControllerSupportedInterfaceOrientations(controller);
    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested) & mask) return requested;
    const UIInterfaceOrientation settled =
        LC32SettledLegacyOrientation(controller, mask);
    if(settled != UIInterfaceOrientationUnknown) return settled;
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
void LC32NativeSetWindowFrame(UIWindow *window, CGRect frame);
UIViewController *LC32GuestWindowRootViewController(UIWindow *window);
void LC32InstallGuestWindowRootViewController(
    UIWindow *window, UIViewController *controller,
    LC32LegacyIPadGeometryMode geometryMode);
UIInterfaceOrientation LC32LegacyTargetOrientation(
    UIViewController *controller);
bool LC32WindowNeedsLegacyPhoneCanvas(
    UIWindow *window, UIViewController *controller);
bool LC32WindowNeedsImmediateLegacyPhoneCanvas(
    UIWindow *window, UIViewController *controller);
bool LC32FitLegacyDirectWindowLayers(UIWindow *window);
void LC32RestoreRootlessRendererAutoresizing(UIWindow *window);
bool LC32TransformNearlyEquals(
    CGAffineTransform left, CGAffineTransform right);
UIInterfaceOrientation LC32LegacyRootWindowGeometry(
    UIView *view, bool requireGuestLandscapeBounds,
    UIWindow *installingWindow = nil, UIViewController *installingRoot = nil);
void LC32FitLegacyControllerRoot(UIView *view);

bool LC32GeometryModePreservesPhoneCanvas(
        LC32LegacyIPadGeometryMode geometryMode) {
    return geometryMode ==
            LC32LegacyIPadGeometryModePreservePhonePortraitCanvas ||
        geometryMode ==
            LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas;
}

LC32LegacyIPadContainerController *LC32LegacyContainerForWindow(
        UIWindow *window) {
    UIViewController *root = LC32NativeWindowRootViewController(window);
    return [root isKindOfClass:LC32LegacyIPadContainerController.class]
        ? (LC32LegacyIPadContainerController *)root : nil;
}

struct LC32LegacyCanvasPolicy {
    LC32LegacyIPadCanvasKind kind;
    bool usesFixedLandscapeIPadCanvas;
    bool usesFixedLandscapePhoneCanvas;
    bool mayRetainLegacyLandscapePhoneCanvas;
};

const LC32LegacyCanvasPolicy& LC32GuestLegacyCanvasPolicy(void) {
    static LC32LegacyCanvasPolicy result = {
        LC32LegacyIPadCanvasNone,
        false,
        false,
        false,
    };
    const char *guestExecutable = getenv("LC32_GUEST_EXECUTABLE");
    /* UIKit can create internal windows while the shim dylib is loading.
     * Do not consume the cache until LC32RunGuest has published the guest. */
    if(!guestExecutable || !guestExecutable[0]) return result;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSString stringWithUTF8String:
            getenv("LC32_GUEST_EXECUTABLE")];
        NSBundle *bundle = [NSBundle bundleWithPath:
            path.stringByDeletingLastPathComponent];
        result.kind = LC32BundleLegacyIPadCanvasKind(
            bundle, LC32GetGuestExecutableSDKVersion());
        result.usesFixedLandscapeIPadCanvas =
            LC32BundleUsesFixedLandscapeIPadCanvas(bundle, result.kind);
        result.usesFixedLandscapePhoneCanvas =
            LC32BundleUsesFixedLandscapePhoneCanvas(
                bundle, LC32GetGuestExecutableSDKVersion());
        result.mayRetainLegacyLandscapePhoneCanvas =
            LC32BundleMayRetainLegacyLandscapePhoneCanvas(
                bundle, LC32GetGuestExecutableSDKVersion());
    });
    return result;
}

LC32LegacyIPadCanvasKind LC32GuestLegacyIPadCanvasKind(void) {
    return LC32GuestLegacyCanvasPolicy().kind;
}

bool LC32GuestNeedsLegacyIPadCanvas(void) {
    return LC32GuestLegacyIPadCanvasKind() != LC32LegacyIPadCanvasNone;
}

bool LC32GuestUsesFixedLandscapeIPadCanvas(void) {
    return LC32GuestLegacyCanvasPolicy().usesFixedLandscapeIPadCanvas;
}

bool LC32GuestUsesFixedLandscapePhoneCanvas(void) {
    return LC32GuestLegacyCanvasPolicy()
        .usesFixedLandscapePhoneCanvas;
}

bool LC32GuestMayRetainLegacyLandscapePhoneCanvas(void) {
    return LC32GuestLegacyCanvasPolicy()
        .mayRetainLegacyLandscapePhoneCanvas;
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
    if(LC32UIKitLegacyCompatibilityEnabled() &&
            ![controller isKindOfClass:LC32LegacyWindowRootController.class]) {
        LC32RestoreRootlessRendererAutoresizing(window);
    }
    struct objc_super superInfo = {window, dispatchClass};
    using SetRootViewController =
        void (*)(struct objc_super *, SEL, UIViewController *);
    reinterpret_cast<SetRootViewController>(objc_msgSendSuper)(
        &superInfo, @selector(setRootViewController:), controller);
}

void LC32NativeSetWindowFrame(UIWindow *window, CGRect frame) {
    Class dispatchClass = LC32NativeWindowDispatchClass(window);
    if(!window || !dispatchClass) return;
    using SetFrame = void (*)(id, SEL, CGRect);
    SetFrame setter = reinterpret_cast<SetFrame>(
        class_getMethodImplementation(dispatchClass, @selector(setFrame:)));
    setter(window, @selector(setFrame:), frame);
}

bool LC32WindowNeedsLegacyIPadContainer(UIWindow *window) {
    if(!window || !LC32GuestNeedsLegacyIPadCanvas()) return false;
    const CGRect hostBounds = LC32WindowSceneBounds(window);
    const CGFloat shortEdge = MIN(hostBounds.size.width,
                                  hostBounds.size.height);
    return shortEdge > 0 && shortEdge < 600;
}

UIInterfaceOrientation LC32LegacyTargetOrientation(
        UIViewController *controller) {
    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested)) return requested;
    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    const UIInterfaceOrientation settled =
        LC32SettledLegacyOrientation(
            controller, UIInterfaceOrientationMaskAll);
    if(settled != UIInterfaceOrientationUnknown) return settled;
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
    const bool requestsPhoneCanvas =
        LC32GeometryModePreservesPhoneCanvas(geometryMode);
    const bool preservesInstalledPhoneCanvas = container &&
        LC32GeometryModePreservesPhoneCanvas(container.geometryMode);
    const bool needsPhoneCanvas = requestsPhoneCanvas &&
        (preservesInstalledPhoneCanvas ||
         LC32WindowNeedsLegacyPhoneCanvas(window, controller));
    const bool needsContainer = controller &&
        (LC32WindowNeedsLegacyIPadContainer(window) || needsPhoneCanvas);

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
        UIView *rootView = nil;
        LC32NativeViewIfLoaded(controller, &rootView);
        const UIInterfaceOrientation oldRootOrientation = rootView
            ? LC32LegacyRootWindowGeometry(rootView, true, window, controller)
            : UIInterfaceOrientationUnknown;
        LC32NativeSetWindowRootViewController(window, controller);
        if(oldRootOrientation) {
            /* Capture before UIKit's initial root layout can transpose the
             * guest's already-landscape bounds. Unattached renderers perform
             * their old orientation setup before setRootViewController:. */
            objc_setAssociatedObject(rootView, LC32LegacyRootWindowGeometryKey,
                @(oldRootOrientation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dispatch_async(dispatch_get_main_queue(), ^{
                LC32FitLegacyControllerRoot(rootView);
            });
        }
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
        coordinateSpace = (id<UICoordinateSpace>)LC32ObjectProperty(
            scene.effectiveGeometry, "coordinateSpace");
        if(coordinateSpace) return coordinateSpace.bounds;
    }
    coordinateSpace = scene.coordinateSpace;
    if(coordinateSpace) return coordinateSpace.bounds;
    return (window.screen ?: UIScreen.mainScreen).bounds;
}

bool LC32WindowNeedsLegacyPhoneCanvas(
        UIWindow *window, UIViewController *controller) {
    if(!window || !window.guest_selfOrNull || !controller ||
            !LC32ObjectUsesGuestClass(controller) ||
            LC32GuestNeedsLegacyIPadCanvas()) {
        return false;
    }

    if(LC32GuestUsesFixedLandscapePhoneCanvas()) {
        /* The bundle classifier already restricts this to pre-iPhone-5,
         * landscape-only phone apps without tall launch art. They need the
         * legacy compositor even when Classic Mode exposes exactly 480x320. */
        return true;
    }

    if(!LC32GuestMayRetainLegacyLandscapePhoneCanvas()) {
        return false;
    }

    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    if(!policy.usesLegacyInitialOrientation ||
            !UIInterfaceOrientationIsLandscape(
                policy.preferredOrientation)) {
        return false;
    }

    UIView *contentView = nil;
    if(!LC32NativeViewIfLoaded(controller, &contentView) || !contentView) {
        return false;
    }
    const CGRect sceneBounds = LC32WindowSceneBounds(window);
    const CGRect contentBounds = LC32NativeViewBounds(contentView);
    const CGFloat sceneShort = MIN(sceneBounds.size.width,
                                   sceneBounds.size.height);
    const CGFloat sceneLong = MAX(sceneBounds.size.width,
                                  sceneBounds.size.height);
    const CGFloat contentShort = MIN(contentBounds.size.width,
                                     contentBounds.size.height);
    const CGFloat contentLong = MAX(contentBounds.size.width,
                                    contentBounds.size.height);
    constexpr CGFloat epsilon = 0.5;

    /* A few 568-point games include the tall launch image but deliberately
     * retain their old 480x320 drawable. Newer hosts can expose the physical
     * scene (for example 956x440) even when LiveContainer's Classic Mode is
     * enabled, so accept a larger scene while keeping the distinctive legacy
     * content dimensions and initial-orientation policy exact. */
    return sceneShort >= 320 - epsilon &&
           sceneLong >= 568 - epsilon &&
           fabs(contentShort - 320) < epsilon &&
           fabs(contentLong - 480) < epsilon;
}

bool LC32WindowNeedsImmediateLegacyPhoneCanvas(
        UIWindow *window, UIViewController *controller) {
    if(!window || !window.guest_selfOrNull || !controller ||
            !LC32ObjectUsesGuestClass(controller) ||
            LC32GuestNeedsLegacyIPadCanvas()) {
        return false;
    }

    if(!LC32GuestUsesFixedLandscapePhoneCanvas()) return false;

    UIView *contentView = nil;
    if(LC32NativeViewIfLoaded(controller, &contentView) &&
            LC32NativeViewHidden(contentView) &&
            LC32NativeViewSuperview(contentView) == window) return false;

    /* Unattached roots still need their fixed portrait surface isolated
     * before UIKit creates and lays out the renderer. */
    return true;
}

NSNumber *LC32LegacyDirectGuestRootStateForAssignment(
        UIWindow *window, UIViewController *controller) {
    if(!window || !window.guest_selfOrNull || !controller ||
            !LC32ObjectUsesGuestClass(controller) ||
            !LC32GuestUsesFixedLandscapePhoneCanvas()) {
        return nil;
    }
    UIViewController *currentController =
        LC32GuestWindowRootViewController(window);
    if(currentController) {
        if(currentController != controller) return nil;
        return objc_getAssociatedObject(
            window, LC32HideLegacyDirectGuestWindowRootKey);
    }
    if(LC32NativeApplicationState() == UIApplicationStateActive) return nil;

    UIView *contentView = nil;
    if(!LC32NativeViewIfLoaded(controller, &contentView) ||
            !LC32NativeViewHidden(contentView) ||
            LC32NativeViewSuperview(contentView) != window) return nil;

    /* Main-nib games can archive a hidden bookkeeping controller alongside
     * their real renderer as direct UIWindow children, then assign that
     * controller as root during launch. Old UIKit left rootViewController nil
     * through the first renderer layouts. Modern UIKit exposes it immediately,
     * which can enter post-launch guest UI before engine-owned buffers exist.
     * Keep the native root for scene policy, but preserve the old
     * guest-visible nil for the lifetime of this direct hierarchy. Exposing
     * or reparenting it can synchronously force layout before engine-owned
     * buffers have finished initializing. */
    return @YES;
}

void LC32RestoreLegacyDirectWindowSublayerTransform(
        UIWindow *window, CALayer *windowLayer, NSValue *savedTransform) {
    if(!window || !windowLayer || !savedTransform) return;

    CATransform3D originalTransform;
    [savedTransform getValue:&originalTransform
                        size:sizeof(originalTransform)];
    NSValue *appliedValue = objc_getAssociatedObject(
        window, LC32LegacyDirectWindowAppliedSublayerTransformKey);
    CATransform3D appliedTransform = CATransform3DIdentity;
    if(appliedValue) {
        [appliedValue getValue:&appliedTransform
                          size:sizeof(appliedTransform)];
    }
    const CATransform3D currentTransform = windowLayer.sublayerTransform;
    const bool stillOwnsTransform = appliedValue &&
        CATransform3DEqualToTransform(currentTransform, appliedTransform);
    if(stillOwnsTransform && !CATransform3DEqualToTransform(
            currentTransform, originalTransform)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        windowLayer.sublayerTransform = originalTransform;
        [CATransaction commit];
    }
    objc_setAssociatedObject(
        window, LC32LegacyDirectWindowSublayerTransformKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(
        window, LC32LegacyDirectWindowAppliedSublayerTransformKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

bool LC32LegacyLayerPreservesPortraitCanvas(CALayer *layer) {
    const CGRect bounds = layer.bounds;
    const CGPoint position = layer.position;
    const CGPoint anchor = layer.anchorPoint;
    constexpr CGFloat epsilon = 0.5;
    return fabs(bounds.origin.x) < epsilon &&
        fabs(bounds.origin.y) < epsilon &&
        fabs(bounds.size.width - 320) < epsilon &&
        fabs(bounds.size.height - 480) < epsilon &&
        fabs(position.x - anchor.x * bounds.size.width) < epsilon &&
        fabs(position.y - anchor.y * bounds.size.height) < epsilon &&
        CATransform3DIsIdentity(layer.transform) &&
        CATransform3DIsIdentity(layer.sublayerTransform);
}

bool LC32FindLegacyNestedPortraitRenderer(
        CALayer *layer, Class rendererClass, bool portraitAncestors,
        unsigned depth, unsigned &remainingLayers, CALayer *&renderer) {
    /* Inspect native backing layers only. Guest CALayer overrides can enter
     * the emulator even for a getter; an unfamiliar or overly deep tree is
     * not evidence that its compositor is missing. */
    if(!layer || !remainingLayers || depth > 32 ||
            LC32ObjectUsesGuestClass(layer)) return false;
    --remainingLayers;
    const bool portraitChain = portraitAncestors &&
        LC32LegacyLayerPreservesPortraitCanvas(layer);
    if([layer isKindOfClass:rendererClass]) {
        if(!portraitChain || renderer) return false;
        renderer = layer;
    }
    for(CALayer *child in layer.sublayers) {
        if(!LC32FindLegacyNestedPortraitRenderer(child, rendererClass,
                portraitChain, depth + 1, remainingLayers, renderer)) {
            return false;
        }
    }
    return true;
}

bool LC32LegacyWindowHasAncestorCompositor(
        CALayer *windowLayer, CATransform3D allowedWindowTransform) {
    if(!CATransform3DEqualToTransform(
            windowLayer.transform, allowedWindowTransform)) return true;
    unsigned remainingLayers = 32;
    for(CALayer *layer = windowLayer.superlayer; layer;
            layer = layer.superlayer) {
        if(!remainingLayers-- || LC32ObjectUsesGuestClass(layer) ||
                !CATransform3DIsIdentity(layer.transform) ||
                !CATransform3DIsIdentity(layer.sublayerTransform)) {
            return true;
        }
    }
    return false;
}

bool LC32WindowUsesRootlessPhoneCanvas(UIWindow *window) {
    return window && window.guest_selfOrNull &&
        LC32GetGuestExecutableSDKVersion() < 0x80000 &&
        LC32GuestUsesFixedLandscapePhoneCanvas() &&
        [LC32NativeWindowRootViewController(window)
            isKindOfClass:LC32LegacyWindowRootController.class];
}

void LC32RestoreRootlessRendererAutoresizing(UIWindow *window) {
    NSMapTable<UIView *, LC32LegacyRendererAutoresizingState *> *saved =
        objc_getAssociatedObject(
            window, LC32LegacyRootlessRendererAutoresizingKey);
    for(UIView *view in saved.keyEnumerator) {
        LC32LegacyRendererAutoresizingState *state = [saved objectForKey:view];
        if(objc_getAssociatedObject(view,
                LC32LegacyRootlessRendererAutoresizingStateKey) != state) continue;
        if(!state.yielded &&
                LC32NativeViewAutoresizingMask(view) == UIViewAutoresizingNone) {
            LC32NativeSetViewAutoresizingMask(view, state.originalMask);
        }
        objc_setAssociatedObject(view,
            LC32LegacyRootlessRendererAutoresizingStateKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(window, LC32LegacyRootlessRendererAutoresizingKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LC32PreserveRootlessRendererAutoresizing(
        UIWindow *window, bool installingSyntheticRoot = false) {
    if(!window || !window.guest_selfOrNull ||
            LC32GetGuestExecutableSDKVersion() >= 0x80000 ||
            !LC32GuestUsesFixedLandscapePhoneCanvas()) return;
    UIViewController *root = LC32NativeWindowRootViewController(window);
    if(installingSyntheticRoot ? root != nil
            : ![root isKindOfClass:LC32LegacyWindowRootController.class]) return;

    NSMapTable<UIView *, LC32LegacyRendererAutoresizingState *> *saved =
        objc_getAssociatedObject(
            window, LC32LegacyRootlessRendererAutoresizingKey);
    bool alreadyPreserved = false;
    for(UIView *view in saved.keyEnumerator) {
        LC32LegacyRendererAutoresizingState *state = [saved objectForKey:view];
        if(state.yielded || objc_getAssociatedObject(view,
                LC32LegacyRootlessRendererAutoresizingStateKey) != state) continue;
        if(LC32NativeViewAutoresizingMask(view) != UIViewAutoresizingNone) {
            /* A later guest setting takes ownership. Remember that decision
             * while this window remains rootless instead of freezing it again. */
            state.yielded = YES;
        } else if(LC32NativeViewSuperview(view) != window) {
            LC32NativeSetViewAutoresizingMask(view, state.originalMask);
            state.yielded = YES;
            objc_setAssociatedObject(view,
                LC32LegacyRootlessRendererAutoresizingStateKey, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            alreadyPreserved = true;
        }
    }
    if(alreadyPreserved) return;

    CALayer *windowLayer = LC32NativeViewLayer(window);
    if(!windowLayer || LC32ObjectUsesGuestClass(windowLayer) ||
            !LC32TransformNearlyEquals(LC32NativeViewTransform(window),
                CGAffineTransformIdentity) ||
            !CATransform3DIsIdentity(windowLayer.sublayerTransform)) return;
    static Class rendererClass = NSClassFromString(@"CAEAGLLayer");
    if(!rendererClass) return;
    CALayer *renderer = nil;
    unsigned remainingLayers = 1024;
    for(CALayer *layer in windowLayer.sublayers) {
        if(!LC32FindLegacyNestedPortraitRenderer(layer, rendererClass,
                true, 0, remainingLayers, renderer)) return;
    }
    if(!renderer) return;

    for(UIView *view in LC32NativeViewSubviews(window)) {
        if(LC32NativeViewLayer(view) != renderer || !view.guest_selfOrNull ||
                [saved objectForKey:view]) continue;
        LC32LegacyRendererAutoresizingState *previous = objc_getAssociatedObject(
            view, LC32LegacyRootlessRendererAutoresizingStateKey);
        if(previous) {
            /* A renderer can move to a different rootless window before its
             * former window refits. Retire only that old preservation record;
             * its later cleanup must not alter this window's new ownership. */
            if(!previous.yielded &&
                    LC32NativeViewAutoresizingMask(view) ==
                        UIViewAutoresizingNone) {
                LC32NativeSetViewAutoresizingMask(view, previous.originalMask);
            }
            previous.yielded = YES;
            objc_setAssociatedObject(view,
                LC32LegacyRootlessRendererAutoresizingStateKey, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        const UIViewAutoresizing mask = LC32NativeViewAutoresizingMask(view);
        if(!(mask & (UIViewAutoresizingFlexibleWidth |
                     UIViewAutoresizingFlexibleHeight))) return;
        if(!saved) {
            /* Weak pointer-identity keys neither extend a removed renderer's
             * lifetime nor call guest -hash/-isEqual: implementations. */
            saved = [NSMapTable
                mapTableWithKeyOptions:NSPointerFunctionsWeakMemory |
                    NSPointerFunctionsObjectPointerPersonality
                valueOptions:NSPointerFunctionsStrongMemory];
            objc_setAssociatedObject(window,
                LC32LegacyRootlessRendererAutoresizingKey, saved,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        LC32LegacyRendererAutoresizingState *state =
            [LC32LegacyRendererAutoresizingState new];
        state.originalMask = mask;
        [saved setObject:state forKey:view];
        objc_setAssociatedObject(view,
            LC32LegacyRootlessRendererAutoresizingStateKey, state,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if !__has_feature(objc_arc)
        [state release];
#endif
        /* The synthetic root makes modern UIWindow adopt scene-oriented
         * bounds. A main-nib portrait drawable with flexible dimensions would
         * otherwise be resized before our compositor can recognize it.
         * Preserve only the proven direct renderer, without changing its
         * bounds, center, descendants, or parent or forcing guest layout. */
        LC32NativeSetViewAutoresizingMask(view, UIViewAutoresizingNone);
        return;
    }
}

struct LC32LegacyRootlessWindowPlacement {
    CGAffineTransform originalTransform;
    CGAffineTransform appliedTransform;
    CGPoint originalCenter;
    CGPoint appliedCenter;
    bool yielded;
};

void LC32SaveRootlessWindowPlacement(
        UIWindow *window, const LC32LegacyRootlessWindowPlacement &placement) {
    objc_setAssociatedObject(window, LC32LegacyRootlessWindowPlacementKey,
        [NSValue value:&placement
            withObjCType:@encode(LC32LegacyRootlessWindowPlacement)],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

bool LC32ReadRootlessWindowPlacement(
        UIWindow *window, LC32LegacyRootlessWindowPlacement &placement) {
    NSValue *value = objc_getAssociatedObject(
        window, LC32LegacyRootlessWindowPlacementKey);
    if(!value) return false;
    [value getValue:&placement size:sizeof(placement)];
    return true;
}

bool LC32ReconcileRootlessWindowPlacement(
        UIWindow *window, CALayer *layer, bool restore) {
    LC32LegacyRootlessWindowPlacement placement;
    if(!LC32ReadRootlessWindowPlacement(window, placement) ||
            placement.yielded || !layer || LC32ObjectUsesGuestClass(layer)) {
        return false;
    }
    const bool ownsTransform = CATransform3DEqualToTransform(
        layer.transform, CATransform3DMakeAffineTransform(
            placement.appliedTransform));
    const bool ownsCenter = CGPointEqualToPoint(
        LC32NativeViewCenter(window), placement.appliedCenter);
    if(ownsTransform && ownsCenter && !restore) return true;

    /* An application/scene can take over either component independently.
     * Restore only the pieces still ours, then stop fitting this window if
     * another owner intervened. Otherwise the next pass could silently
     * replace an authored center after restoring our scale to identity. */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if(ownsTransform) {
        LC32NativeSetViewTransform(window, placement.originalTransform);
    }
    if(ownsCenter) LC32NativeSetViewCenter(window, placement.originalCenter);
    [CATransaction commit];
    if(!ownsTransform || !ownsCenter) {
        placement.yielded = true;
        LC32SaveRootlessWindowPlacement(window, placement);
    } else {
        objc_setAssociatedObject(window, LC32LegacyRootlessWindowPlacementKey,
            nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return false;
}

void LC32FitRootlessWindowPlacement(UIWindow *window, CALayer *layer) {
    /* Do not resize the guest window: its local 480x320 bounds and every
     * locked 320x480 drawable must survive. Moving/scaling the native window
     * also keeps UIKit hit-testing aligned with the visible content, unlike
     * drawing enlarged sublayers beyond the original window hit region. */
    const CGRect bounds = layer.bounds;
    const CGPoint anchor = layer.anchorPoint;
    if(LC32ObjectUsesGuestClass(window) || !window.windowScene ||
            !CGRectEqualToRect(bounds, CGRectMake(0, 0, 480, 320)) ||
            !CGPointEqualToPoint(anchor, CGPointMake(0.5, 0.5))) {
        LC32ReconcileRootlessWindowPlacement(window, layer, true);
        return;
    }
    LC32LegacyRootlessWindowPlacement placement;
    const bool hasPlacement = LC32ReadRootlessWindowPlacement(window, placement);
    if(hasPlacement && placement.yielded) return;
    const CGAffineTransform current = LC32NativeViewTransform(window);
    if(!hasPlacement && !CGAffineTransformIsIdentity(current)) return;
    const CGPoint center = LC32NativeViewCenter(window);
    const CGRect viewport = LC32LegacyViewportInView(window, window);
    /* The window can reach landscape before its scene/source space settles.
     * Do not claim placement ownership in that provisional portrait space:
     * UIKit's subsequent ordinary recenter is not an application takeover. */
    if(!(viewport.size.width > viewport.size.height) ||
            !(viewport.size.height > 0) || !isfinite(viewport.size.width) ||
            !isfinite(viewport.size.height)) return;
    /* Coordinate conversion removes our existing scale. Put the viewport
     * back into the native parent space before fitting, so repeated passes
     * neither compound nor cancel the previous placement. */
    const CGFloat scale = MIN(viewport.size.width / bounds.size.width,
                              viewport.size.height / bounds.size.height) *
        current.a;
    const CGPoint targetCenter = {
        center.x + (CGRectGetMidX(viewport) - CGRectGetMidX(bounds)) * current.a,
        center.y + (CGRectGetMidY(viewport) - CGRectGetMidY(bounds)) * current.d,
    };
    if(!(scale > 0) || !isfinite(scale) || !isfinite(targetCenter.x) ||
            !isfinite(targetCenter.y)) return;
    const CGAffineTransform target = CGAffineTransformMakeScale(scale, scale);
    if(!hasPlacement && CGAffineTransformEqualToTransform(current, target) &&
            CGPointEqualToPoint(center, targetCenter)) return;
    if(!hasPlacement) {
        placement.originalTransform = current;
        placement.originalCenter = center;
        placement.yielded = false;
    }
    placement.appliedTransform = target;
    placement.appliedCenter = targetCenter;
    LC32SaveRootlessWindowPlacement(window, placement);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if(!CGAffineTransformEqualToTransform(current, target)) {
        LC32NativeSetViewTransform(window, target);
    }
    if(!CGPointEqualToPoint(center, targetCenter)) {
        LC32NativeSetViewCenter(window, targetCenter);
    }
    [CATransaction commit];
}

bool LC32FitLegacyDirectWindowLayers(UIWindow *window) {
    if(!window) return false;

    NSNumber *directRootState = objc_getAssociatedObject(
        window, LC32HideLegacyDirectGuestWindowRootKey);
    NSValue *savedTransform = objc_getAssociatedObject(
        window, LC32LegacyDirectWindowSublayerTransformKey);
    CALayer *windowLayer = LC32NativeViewLayer(window);
    UIViewController *nativeRoot = LC32NativeWindowRootViewController(window);
    const bool rootlessPhoneCanvas = LC32WindowUsesRootlessPhoneCanvas(window);
    if(rootlessPhoneCanvas) LC32PreserveRootlessRendererAutoresizing(window);
    else LC32RestoreRootlessRendererAutoresizing(window);
    const bool ownsWindowPlacement = LC32ReconcileRootlessWindowPlacement(
        window, windowLayer, !rootlessPhoneCanvas);
    if(!directRootState.boolValue && !rootlessPhoneCanvas) {
        LC32RestoreLegacyDirectWindowSublayerTransform(
            window, windowLayer, savedTransform);
        return false;
    }

    /* This path emulates the pre-scene UIWindow compositor for main-nib
     * games whose renderer and hidden bookkeeping root are direct siblings,
     * or rootless engines with a nested, fixed portrait drawable.
     * Changing UIView geometry or reparenting either object synchronously
     * invokes the guest EAGLView's layoutSubviews before engine-owned state
     * is initialized. A parent-layer transform changes presentation and
     * coordinate conversion without invalidating that 320x480 drawable. */
    if(!windowLayer) return true;
    if(rootlessPhoneCanvas && LC32ObjectUsesGuestClass(windowLayer))
        return true;
    static const bool isCoreSimulator =
        getenv("SIMULATOR_UDID") != nullptr ||
        getenv("SIMULATOR_DEVICE_NAME") != nullptr;
    if(!isCoreSimulator && !rootlessPhoneCanvas) {
        LC32RestoreLegacyDirectWindowSublayerTransform(
            window, windowLayer, savedTransform);
        return true;
    }

    NSValue *appliedValue = objc_getAssociatedObject(
        window, LC32LegacyDirectWindowAppliedSublayerTransformKey);
    if(savedTransform && appliedValue) {
        CATransform3D originalTransform;
        CATransform3D appliedTransform;
        [savedTransform getValue:&originalTransform
                            size:sizeof(originalTransform)];
        [appliedValue getValue:&appliedTransform
                          size:sizeof(appliedTransform)];
        const CATransform3D currentTransform = windowLayer.sublayerTransform;
        if(!CATransform3DEqualToTransform(
                currentTransform, originalTransform) &&
                !CATransform3DEqualToTransform(
                    currentTransform, appliedTransform)) {
            /* UIKit or another owner replaced our compositor transform.
             * Preserve it and discard the stale restore point instead of
             * overwriting it on this pass or during later cleanup. */
            objc_setAssociatedObject(
                window, LC32LegacyDirectWindowSublayerTransformKey,
                nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                window,
                LC32LegacyDirectWindowAppliedSublayerTransformKey,
                nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            savedTransform = nil;
        }
    }
    const CGRect windowBounds = windowLayer.bounds;
    const CATransform3D allowedWindowTransform = ownsWindowPlacement
        ? windowLayer.transform : CATransform3DIdentity;
    const bool alreadyHasNativeCompositor =
        (!ownsWindowPlacement && !LC32TransformNearlyEquals(
            LC32NativeViewTransform(window), CGAffineTransformIdentity)) ||
        (rootlessPhoneCanvas &&
         LC32LegacyWindowHasAncestorCompositor(
             windowLayer, allowedWindowTransform)) ||
        (!savedTransform &&
         !CATransform3DIsIdentity(windowLayer.sublayerTransform));
    if(alreadyHasNativeCompositor ||
            !(windowBounds.size.width > windowBounds.size.height)) {
        LC32ReconcileRootlessWindowPlacement(window, windowLayer, true);
        LC32RestoreLegacyDirectWindowSublayerTransform(
            window, windowLayer, savedTransform);
        return true;
    }

    Class eaglLayerClass = NSClassFromString(@"CAEAGLLayer");
    CALayer *portraitRenderer = nil;
    if(rootlessPhoneCanvas && eaglLayerClass) {
        unsigned remainingLayers = 1024;
        for(CALayer *layer in windowLayer.sublayers) {
            if(!LC32FindLegacyNestedPortraitRenderer(layer, eaglLayerClass,
                    true, 0, remainingLayers, portraitRenderer)) {
                LC32ReconcileRootlessWindowPlacement(window, windowLayer, true);
                LC32RestoreLegacyDirectWindowSublayerTransform(
                    window, windowLayer, savedTransform);
                return true;
            }
        }
    } else {
        for(CALayer *layer in windowLayer.sublayers) {
            if(eaglLayerClass && [layer isKindOfClass:eaglLayerClass]) {
                const CGRect bounds = layer.bounds;
                if(fabs(bounds.size.width - 320) < 0.5 &&
                        fabs(bounds.size.height - 480) < 0.5) {
                    if(portraitRenderer) {
                        LC32RestoreLegacyDirectWindowSublayerTransform(
                            window, windowLayer, savedTransform);
                        return true;
                    }
                    portraitRenderer = layer;
                }
            }
        }
    }
    if(!portraitRenderer || !LC32TransformNearlyEquals(
            portraitRenderer.affineTransform,
            CGAffineTransformIdentity)) {
        LC32ReconcileRootlessWindowPlacement(window, windowLayer, true);
        LC32RestoreLegacyDirectWindowSublayerTransform(
            window, windowLayer, savedTransform);
        return true;
    }

    const UIInterfaceOrientation orientation =
        rootlessPhoneCanvas ? LC32LegacyTargetOrientation(nativeRoot)
                            : LC32GuestInterfacePolicy().preferredOrientation;
    CGFloat angle;
    if(orientation == UIInterfaceOrientationLandscapeLeft) {
        angle = M_PI_2;
    } else if(orientation == UIInterfaceOrientationLandscapeRight) {
        angle = -M_PI_2;
    } else {
        LC32ReconcileRootlessWindowPlacement(window, windowLayer, true);
        LC32RestoreLegacyDirectWindowSublayerTransform(
            window, windowLayer, savedTransform);
        return true;
    }

    if(!savedTransform) {
        const CATransform3D originalTransform =
            windowLayer.sublayerTransform;
        savedTransform = [NSValue value:&originalTransform
                           withObjCType:@encode(CATransform3D)];
        objc_setAssociatedObject(
            window, LC32LegacyDirectWindowSublayerTransformKey,
            savedTransform, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    constexpr CGSize logicalSize = {320, 480};
    const CGSize turnedSize = {logicalSize.height, logicalSize.width};
    const CGFloat scale = MIN(
        windowBounds.size.width / turnedSize.width,
        windowBounds.size.height / turnedSize.height);
    if(!(scale > 0) || !isfinite(scale)) return true;

    CGAffineTransform transform = CGAffineTransformScale(
        CGAffineTransformMakeRotation(angle), scale, scale);
    const CGPoint layerAnchor = windowLayer.anchorPoint;
    const CGPoint anchor = {
        windowBounds.origin.x +
            layerAnchor.x * windowBounds.size.width,
        windowBounds.origin.y +
            layerAnchor.y * windowBounds.size.height,
    };
    const CGPoint viewportCenter = {
        CGRectGetMidX(windowBounds), CGRectGetMidY(windowBounds),
    };
    const CGPoint canvasCenter = {
        logicalSize.width * 0.5, logicalSize.height * 0.5,
    };
    const CGFloat anchorDeltaX = anchor.x - canvasCenter.x;
    const CGFloat anchorDeltaY = anchor.y - canvasCenter.y;
    transform.tx = viewportCenter.x - anchor.x +
        transform.a * anchorDeltaX + transform.c * anchorDeltaY;
    transform.ty = viewportCenter.y - anchor.y +
        transform.b * anchorDeltaX + transform.d * anchorDeltaY;

    const CATransform3D desiredTransform =
        CATransform3DMakeAffineTransform(transform);
    if(!CATransform3DEqualToTransform(
            windowLayer.sublayerTransform, desiredTransform)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        windowLayer.sublayerTransform = desiredTransform;
        [CATransaction commit];
    }
    NSValue *desiredValue = [NSValue value:&desiredTransform
                               withObjCType:@encode(CATransform3D)];
    objc_setAssociatedObject(
        window, LC32LegacyDirectWindowAppliedSublayerTransformKey,
        desiredValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(rootlessPhoneCanvas) LC32FitRootlessWindowPlacement(window, windowLayer);
    return true;
}

void LC32ScheduleRootlessWindowLayerLayout(UIWindow *window) {
    if(!LC32WindowUsesRootlessPhoneCanvas(window) ||
            objc_getAssociatedObject(
                window, LC32LegacyWindowLayersLayoutPendingKey)) return;
    objc_setAssociatedObject(window, LC32LegacyWindowLayersLayoutPendingKey,
        @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    /* Early engines add their renderer to an existing nested canvas after
     * the initial makeKeyAndVisible/orientation calls. Coalesce insertions
     * and inspect the settled native layer hierarchy without forcing guest
     * layout or scanning on display frames/global UIView layout callbacks. */
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(window, LC32LegacyWindowLayersLayoutPendingKey,
            nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LC32FitLegacyDirectWindowLayers(window);
    });
}

LC32LegacyIPadGeometryMode LC32LegacyPhoneCanvasGeometryMode(
        UIViewController *controller) {
    UIView *contentView = nil;
    if(LC32NativeViewIfLoaded(controller, &contentView) && contentView) {
        const CGRect bounds = LC32NativeViewBounds(contentView);
        const CGFloat shortEdge = MIN(
            bounds.size.width, bounds.size.height);
        const CGFloat longEdge = MAX(
            bounds.size.width, bounds.size.height);
        constexpr CGFloat epsilon = 0.5;
        if(fabs(shortEdge - 320) < epsilon &&
                fabs(longEdge - 480) < epsilon) {
            static Class eaglLayerClass = NSClassFromString(@"CAEAGLLayer");
            if(LC32GuestUsesFixedLandscapePhoneCanvas() &&
                    bounds.size.width < bounds.size.height &&
                    LC32TransformNearlyEquals(
                        LC32NativeViewTransform(contentView),
                        CGAffineTransformIdentity) &&
                    [LC32NativeViewLayer(contentView)
                        isKindOfClass:eaglLayerClass]) {
                /* An unturned portrait GL surface can rotate in the engine's
                 * projection matrix. Preserve it before the first drawable
                 * allocation; some old renderers never reallocate storage.
                 * Matching only the short/long edges loses this contract. */
                return LC32LegacyIPadGeometryModePreservePhonePortraitCanvas;
            }
            /* Old applications often follow setRootViewController: with a
             * redundant addSubview:. Modern controller containment makes
             * that reparent invalid, so normalize either archived ordering
             * to the landscape canvas which that second call established. */
            return LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas;
        }
    }
    return LC32GuestUsesFixedLandscapePhoneCanvas()
        ? LC32LegacyIPadGeometryModePreservePhonePortraitCanvas
        : LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas;
}

bool LC32UsesClassicFullScreenViewport(UIWindow *window) {
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    const CGRect screenBounds = screen.bounds;
    const CGFloat screenShortEdge = MIN(
        screenBounds.size.width, screenBounds.size.height);
    return (LC32GuestNeedsLegacyIPadCanvas() ||
            LC32GuestUsesFixedLandscapePhoneCanvas()) &&
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
            sourceSpace = (id<UICoordinateSpace>)LC32ObjectProperty(
                scene.effectiveGeometry, "coordinateSpace");
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
    }
    if(orientation == UIInterfaceOrientationUnknown) {
        orientation = scene.interfaceOrientation;
    }
    if(LC32MaskForInterfaceOrientation(orientation)) {
        if([window isKeyWindow]) {
            LC32CacheSettledLegacyOrientation(window, orientation);
        }
    } else {
        orientation = LC32SettledLegacyOrientation(
            window, UIInterfaceOrientationMaskAll);
    }
    (void)sceneBounds;
    return orientation;
}

void LC32ScaleLegacyIPadWindow(UIWindow *window) {
    /* UIKit owns keyboard, alert, and text-effects windows in the same
     * process. Virtualize only a UIWindow paired with a guest object. */
    if(!window || !window.guest_selfOrNull) return;
    if(LC32FitLegacyDirectWindowLayers(window)) return;
    LC32LegacyIPadContainerController *container =
        LC32LegacyContainerForWindow(window);
    if(container && container.geometryMode ==
            LC32LegacyIPadGeometryModeReflowRootController &&
            LC32GuestUsesFixedLandscapeIPadCanvas() &&
            LC32WindowNeedsLegacyIPadContainer(window)) {
        const UIInterfaceOrientation orientation =
            LC32LegacyTargetOrientation(container.guestContentController);
        if(UIInterfaceOrientationIsLandscape(orientation)) {
            /* The host otherwise retains the archived 768x1024 UIWindow and
             * exposes only its bottom scene-height strip.  This inferred-iPad
             * class uses a fixed landscape GL drawable, so give UIKit the
             * native legacy frame before the renderer locks its surface. */
            CGRect canvasFrame = CGRectMake(0, 0, 1024, 768);
            const CGRect sceneBounds = LC32WindowSceneBounds(window);
            if(sceneBounds.size.width > 0 && sceneBounds.size.height > 0) {
                canvasFrame.origin.y =
                    (MIN(sceneBounds.size.width, sceneBounds.size.height) -
                     canvasFrame.size.height) * 0.5;
            }
            LC32NativeSetWindowFrame(window, canvasFrame);
            const CGRect viewportBounds = {
                CGPointZero,
                canvasFrame.size,
            };
            [container fitGuestContentForViewport:viewportBounds
                hostOrientation:orientation];
            return;
        }
    }
    if(container && container.geometryMode ==
            LC32LegacyIPadGeometryModePreservePhonePortraitCanvas) {
        UIScreen *screen = window.screen ?: UIScreen.mainScreen;
        CGRect viewportBounds = screen.bounds;
        if(!(viewportBounds.size.width > 0) ||
                !(viewportBounds.size.height > 0)) {
            viewportBounds = LC32WindowSceneBounds(window);
        }
        const UIInterfaceOrientation orientation =
            LC32WindowSceneOrientation(window, viewportBounds);
        if(UIInterfaceOrientationIsLandscape(orientation) &&
                viewportBounds.size.width < viewportBounds.size.height) {
            viewportBounds.size = CGSizeMake(
                viewportBounds.size.height, viewportBounds.size.width);
        }
        LC32NativeSetWindowFrame(window, viewportBounds);
        const CGRect viewport = LC32LegacyViewportInView(
            window, container.view);
        [container fitGuestContentForViewport:viewport
            hostOrientation:orientation];
        return;
    }
    if(container && container.geometryMode ==
            LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas) {
        CGRect sceneBounds = window.windowScene.coordinateSpace.bounds;
        if(!(sceneBounds.size.width > 0) ||
                !(sceneBounds.size.height > 0)) {
            sceneBounds = LC32WindowSceneBounds(window);
        }
        const UIInterfaceOrientation orientation =
            LC32WindowSceneOrientation(window, sceneBounds);
        if(UIInterfaceOrientationIsLandscape(orientation) &&
                sceneBounds.size.width < sceneBounds.size.height) {
            sceneBounds.size = CGSizeMake(
                sceneBounds.size.height, sceneBounds.size.width);
        }
        LC32NativeSetWindowFrame(window, sceneBounds);
        const CGRect viewport = LC32LegacyViewportInView(
            window, container.view);
        [container fitGuestContentForViewport:viewport
            hostOrientation:orientation];
        return;
    }
    if(!LC32GuestNeedsLegacyIPadCanvas()) return;

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

bool LC32TransformNearlyEquals(
        CGAffineTransform left, CGAffineTransform right) {
    constexpr CGFloat epsilon = 0.0001;
    return fabs(left.a - right.a) < epsilon &&
           fabs(left.b - right.b) < epsilon &&
           fabs(left.c - right.c) < epsilon &&
           fabs(left.d - right.d) < epsilon &&
           fabs(left.tx - right.tx) < epsilon &&
           fabs(left.ty - right.ty) < epsilon;
}

bool LC32LayerContainsRenderer(CALayer *layer) {
    static Class eaglLayer = NSClassFromString(@"CAEAGLLayer");
    static Class metalLayer = NSClassFromString(@"CAMetalLayer");
    if((eaglLayer && [layer isKindOfClass:eaglLayer]) ||
            (metalLayer && [layer isKindOfClass:metalLayer])) return true;
    for(CALayer *child in layer.sublayers) {
        if(LC32LayerContainsRenderer(child)) return true;
    }
    return false;
}

UIInterfaceOrientation LC32LegacyRootWindowGeometry(
        UIView *view, bool requireGuestLandscapeBounds,
        UIWindow *installingWindow, UIViewController *installingRoot) {
    const u32 sdk = LC32GetGuestExecutableSDKVersion();
    if(!sdk || sdk >= 0x80000) return UIInterfaceOrientationUnknown;
    UIView *superview = LC32NativeViewSuperview(view);
    UIWindow *window = installingWindow;
    if(window) {
        if(superview && superview != window) return UIInterfaceOrientationUnknown;
    } else {
        if(![superview isKindOfClass:UIWindow.class])
            return UIInterfaceOrientationUnknown;
        window = (UIWindow *)superview;
    }
    if(!view.guest_selfOrNull || !window.guest_selfOrNull ||
            LC32GuestUsesFixedLandscapePhoneCanvas() ||
            LC32GuestNeedsLegacyIPadCanvas()) return UIInterfaceOrientationUnknown;
    if(LC32LegacyContainerForWindow(window)) return UIInterfaceOrientationUnknown;
    UIViewController *root = installingRoot ?: LC32NativeWindowRootViewController(window);
    UIView *rootView = nil;
    if(!LC32ObjectUsesGuestClass(root) ||
            !LC32NativeViewIfLoaded(root, &rootView) || rootView != view)
        return UIInterfaceOrientationUnknown;
    /* This contract belongs to renderer-backed roots which size their own
     * drawable. Ordinary UIKit roots and overlays retain their existing
     * geometry behavior, even when they contain a transformed subview. */
    CALayer *layer = LC32NativeViewLayer(view);
    static Class eaglLayer = NSClassFromString(@"CAEAGLLayer");
    static Class metalLayer = NSClassFromString(@"CAMetalLayer");
    if(!((eaglLayer && [layer isKindOfClass:eaglLayer]) ||
            (metalLayer && [layer isKindOfClass:metalLayer])))
        return UIInterfaceOrientationUnknown;
    if(!LC32TransformNearlyEquals(LC32NativeViewTransform(window),
            CGAffineTransformIdentity) || !CATransform3DIsIdentity(
                LC32NativeViewLayer(window).sublayerTransform))
        return UIInterfaceOrientationUnknown;

    const CGRect viewport = LC32NativeViewBounds(window);
    const CGRect bounds = LC32NativeViewBounds(view);
    UIInterfaceOrientation orientation =
        LC32WindowSceneOrientation(window, viewport);
    if(!UIInterfaceOrientationIsLandscape(orientation) &&
            viewport.size.width > viewport.size.height && [window isKeyWindow]) {
        /* UIWindow can already have its final landscape geometry while
         * UIWindowScene still reports the launch-time portrait orientation.
         * Its identity transform was checked above; use the app's accepted
         * landscape side only for this already-turned primary window. */
        const UIInterfaceOrientation current =
            UIApplication.sharedApplication.statusBarOrientation;
        NSNumber *cached = objc_getAssociatedObject(root, LC32LegacyOrientationMaskKey);
        const UIInterfaceOrientationMask mask = cached
            ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
            : LC32GuestInterfacePolicy().declaredOrientations;
        if(UIInterfaceOrientationIsLandscape(current) &&
                (LC32MaskForInterfaceOrientation(current) & mask))
            orientation = current;
    }
    if(!UIInterfaceOrientationIsLandscape(orientation) ||
            !(viewport.size.width > viewport.size.height) ||
            !(viewport.size.height > 0)) return UIInterfaceOrientationUnknown;
    const CGAffineTransform oldWindowTurn =
        orientation == UIInterfaceOrientationLandscapeRight
            ? CGAffineTransformMake(0, 1, -1, 0, 0, 0)
            : CGAffineTransformMake(0, -1, 1, 0, 0, 0);
    if(!LC32TransformNearlyEquals(LC32NativeViewTransform(view), oldWindowTurn))
        return UIInterfaceOrientationUnknown;
    constexpr CGFloat epsilon = 0.5;
    const bool landscapeBounds =
        fabs(bounds.size.width - viewport.size.width) < epsilon &&
        fabs(bounds.size.height - viewport.size.height) < epsilon;
    const bool resizedByUIKit = !requireGuestLandscapeBounds &&
        fabs(bounds.size.width - viewport.size.height) < epsilon &&
        fabs(bounds.size.height - viewport.size.width) < epsilon;
    using GetCenter = CGPoint (*)(id, SEL);
    static GetCenter getCenter = reinterpret_cast<GetCenter>(
        class_getMethodImplementation(UIView.class, @selector(center)));
    const CGPoint center = getCenter(view, @selector(center));
    const bool windowCenter =
        fabs(center.x - viewport.size.width * 0.5) < epsilon &&
        fabs(center.y - viewport.size.height * 0.5) < epsilon;
    const bool portraitCenter =
        fabs(center.x - viewport.size.height * 0.5) < epsilon &&
        fabs(center.y - viewport.size.width * 0.5) < epsilon;
    if(!isfinite(viewport.size.width) || !isfinite(viewport.size.height) ||
            !(fabs(viewport.origin.x) < epsilon) ||
            !(fabs(viewport.origin.y) < epsilon) ||
            !(fabs(bounds.origin.x) < epsilon) ||
            !(fabs(bounds.origin.y) < epsilon) ||
            !(landscapeBounds || resizedByUIKit) ||
            !(windowCenter || portraitCenter)) return UIInterfaceOrientationUnknown;
    return orientation;
}

void LC32FitLegacyControllerRoot(UIView *view) {
    NSNumber *recorded = objc_getAssociatedObject(
        view, LC32LegacyRootWindowGeometryKey);
    objc_setAssociatedObject(view, LC32LegacyRootWindowGeometryKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!recorded || LC32LegacyRootWindowGeometry(view, false) !=
            recorded.integerValue) return;
    /* A pre-iOS-8 controller can explicitly rotate a landscape bounds rect
     * into the old portrait window. Modern UIWindow has already rotated;
     * its next root layout would transpose those bounds a second time.
     * Only act after observing that exact guest-authored landscape shape,
     * never infer it from an intentionally portrait rendering surface. */
    const CGRect viewport = LC32NativeViewBounds(LC32NativeViewSuperview(view));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    LC32NativeSetViewTransform(view, CGAffineTransformIdentity);
    LC32NativeSetViewBounds(view, viewport);
    LC32NativeSetViewCenter(view, CGPointMake(
        CGRectGetMidX(viewport), CGRectGetMidY(viewport)));
    [CATransaction commit];
}

void LC32FitLegacyControllerOverlay(UIView *view) {
    UIView *superview = LC32NativeViewSuperview(view);
    if(![superview isKindOfClass:UIWindow.class]) return;
    UIWindow *window = (UIWindow *)superview;
    if(!view.guest_selfOrNull || !window.guest_selfOrNull ||
            LC32LegacyContainerForWindow(window)) return;

    /* Only an independently added controller root uses this old window
     * contract. Ordinary rotated views, contained controllers, and the game
     * root/drawable must retain their application-authored transforms. */
    using NextResponder = UIResponder *(*)(id, SEL);
    static NextResponder nextResponder = reinterpret_cast<NextResponder>(
        class_getMethodImplementation(UIView.class, @selector(nextResponder)));
    UIResponder *owner = nextResponder(view, @selector(nextResponder));
    if(![owner isKindOfClass:UIViewController.class] ||
            !LC32ObjectUsesGuestClass(owner)) return;
    UIViewController *controller = (UIViewController *)owner;
    UIView *controllerView = nil;
    using GetController = UIViewController *(*)(id, SEL);
    static GetController getParent = reinterpret_cast<GetController>(
        class_getMethodImplementation(UIViewController.class,
            @selector(parentViewController)));
    static GetController getPresenter = reinterpret_cast<GetController>(
        class_getMethodImplementation(UIViewController.class,
            @selector(presentingViewController)));
    if(controller == LC32NativeWindowRootViewController(window) ||
            getParent(controller, @selector(parentViewController)) ||
            getPresenter(controller, @selector(presentingViewController)) ||
            !LC32NativeViewIfLoaded(controller, &controllerView) ||
            controllerView != view) return;

    CALayer *windowLayer = LC32NativeViewLayer(window);
    if(!LC32TransformNearlyEquals(LC32NativeViewTransform(window),
                CGAffineTransformIdentity) ||
            !CATransform3DIsIdentity(windowLayer.sublayerTransform)) return;

    const CGRect windowBounds = LC32NativeViewBounds(window);
    const CGRect bounds = LC32NativeViewBounds(view);
    const UIInterfaceOrientation orientation =
        LC32WindowSceneOrientation(window, windowBounds);
    if(!UIInterfaceOrientationIsLandscape(orientation) ||
            !(windowBounds.size.width > windowBounds.size.height) ||
            !(windowBounds.size.height > 0)) return;

    const CGAffineTransform oldWindowTurn =
        /* This is the view's old portrait-to-window transform, not the
         * inverse compositor transform used by the fixed-canvas adapters. */
        orientation == UIInterfaceOrientationLandscapeRight
            ? CGAffineTransformMake(0, 1, -1, 0, 0, 0)
            : CGAffineTransformMake(0, -1, 1, 0, 0, 0);
    if(!LC32TransformNearlyEquals(
            LC32NativeViewTransform(view), oldWindowTurn)) return;

    using GetCenter = CGPoint (*)(id, SEL);
    static GetCenter getCenter = reinterpret_cast<GetCenter>(
        class_getMethodImplementation(UIView.class, @selector(center)));
    const CGPoint center = getCenter(view, @selector(center));
    constexpr CGFloat epsilon = 0.5;
    /* Pre-iOS-8 helpers rotate an already-landscape bounds rect and place it
     * at the portrait screen midpoint. This exact full-screen shape rules
     * out partial overlays, deliberate scaling, and transition offsets. */
    if(!isfinite(windowBounds.origin.x) || !isfinite(windowBounds.origin.y) ||
            !isfinite(windowBounds.size.width) ||
            !isfinite(windowBounds.size.height) ||
            !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
            !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
            !isfinite(center.x) || !isfinite(center.y) ||
            fabs(windowBounds.origin.x) >= epsilon ||
            fabs(windowBounds.origin.y) >= epsilon ||
            fabs(bounds.origin.x) >= epsilon ||
            fabs(bounds.origin.y) >= epsilon ||
            fabs(bounds.size.width - windowBounds.size.width) >= epsilon ||
            fabs(bounds.size.height - windowBounds.size.height) >= epsilon ||
            fabs(center.x - windowBounds.size.height * 0.5) >= epsilon ||
            fabs(center.y - windowBounds.size.width * 0.5) >= epsilon ||
            LC32LayerContainsRenderer(LC32NativeViewLayer(view))) return;

    /* The scene has already performed this turn. Preserve the controller's
     * bounds and every descendant transform; only remove the duplicate
     * window-space turn/translation. Native setters cannot enter guest
     * geometry overrides from this deferred native main-thread callback. */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    LC32NativeSetViewTransform(view, CGAffineTransformIdentity);
    LC32NativeSetViewCenter(view, CGPointMake(
        CGRectGetMidX(windowBounds), CGRectGetMidY(windowBounds)));
    [CATransaction commit];
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
    if(LC32GuestUsesFixedLandscapePhoneCanvas()) {
        const UIInterfaceOrientation requested = (UIInterfaceOrientation)
            LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
        const UIInterfaceOrientationMask requestedMask =
            LC32MaskForInterfaceOrientation(requested);
        if(requestedMask & UIInterfaceOrientationMaskLandscape) {
            /* The bundle side is only a safe launch-time fallback. Once the
             * initialized renderer explicitly requests a landscape side,
             * keep the native wrapper and scene on that exact side. */
            return requestedMask;
        }
        /* Renderer-era shouldAutorotate implementations can consult GL state
         * which is not initialized while UIKit installs the root. */
        return policy.declaredOrientations;
    }

    NSNumber *cached = objc_getAssociatedObject(
        controller, LC32LegacyOrientationMaskKey);
    if(!LC32CanQueryGuestOrientation()) {
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
    LC32GuestOrientationQueryScope queryScope;
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

    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    UIWindowScene *scene = window.windowScene;
    const CGRect sceneBounds = scene
        ? LC32WindowSceneBounds(window) : CGRectZero;
    const UIInterfaceOrientation current = scene
        ? LC32WindowSceneOrientation(window, sceneBounds)
        : UIInterfaceOrientationUnknown;
    const UIInterfaceOrientationMask currentMask =
        LC32MaskForInterfaceOrientation(current);
    UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    UIInterfaceOrientationMask requestedMask =
        LC32MaskForInterfaceOrientation(requested);
    const UIInterfaceOrientationMask legacyAxis =
        UIInterfaceOrientationIsLandscape(policy.preferredOrientation)
            ? UIInterfaceOrientationMaskLandscape
            : UIInterfaceOrientationMaskPortrait |
              UIInterfaceOrientationMaskPortraitUpsideDown;
    const bool observesLegacyLaunchAxis =
        policy.usesLegacyInitialOrientation && !requestedMask &&
        (currentMask & legacyAxis);

    UIInterfaceOrientationMask orientations =
        LC32SupportedOrientationsForController(orientationController);
    if(!orientations) {
        orientations = policy.declaredOrientations;
    }
    /* CoreSimulator can expose the opposite provisional landscape side while
     * the key window is being attached. A fixed phone canvas has one exact
     * selected side, so widening that mask would let the native wrapper choose
     * the simulator side and display the guest output upside down. */
    const bool fixedPhoneOrientationConflictsWithCurrent =
        LC32GuestUsesFixedLandscapePhoneCanvas() && currentMask &&
        (orientations == UIInterfaceOrientationMaskLandscapeLeft ||
         orientations == UIInterfaceOrientationMaskLandscapeRight) &&
        !(orientations & currentMask);
    if(observesLegacyLaunchAxis && (orientations & legacyAxis) &&
            !fixedPhoneOrientationConflictsWithCurrent) {
        /* UIInterfaceOrientation selected an initial side, not a permanent
         * supported-orientation mask. If this active controller still uses
         * the same axis, retain the scene's settled side alongside its raw
         * policy. This prevents a late 180-degree flip without affecting a
         * later controller which deliberately switches axes. */
        LC32CacheSettledLegacyOrientation(window, current);
        LC32CacheSettledLegacyOrientation(rootController, current);
        LC32CacheSettledLegacyOrientation(guestRootController, current);
        LC32CacheSettledLegacyOrientation(orientationController, current);
        orientations |= currentMask;
    }
    if(orientationController) {
        objc_setAssociatedObject(orientationController,
            LC32LegacyOrientationMaskKey, @(orientations),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if(@available(iOS 16.0, *)) {
        [orientationController setNeedsUpdateOfSupportedInterfaceOrientations];
    }
    [rootController setNeedsStatusBarAppearanceUpdate];

    if(!scene) return;
    /* Before makeKeyAndVisible, a scene can report a provisional landscape
     * side. Let UIKit settle it before applying a legacy initial-orientation
     * hint; an explicit guest status-bar request remains authoritative. */
    if(policy.usesLegacyInitialOrientation && ![window isKeyWindow] &&
            !requestedMask) {
        return;
    }
    UIInterfaceOrientationMask geometryOrientations =
        requestedMask & orientations ? requestedMask : orientations;
    /* A legacy controller which accepts exactly one orientation is a more
     * precise local policy than a permissive Info.plist. Do not publish this
     * inference into the process-wide explicit-request state. */
    if(!requestedMask && geometryOrientations &&
            !(geometryOrientations & (geometryOrientations - 1))) {
        requested = LC32FirstOrientationInMask(geometryOrientations);
        requestedMask = LC32MaskForInterfaceOrientation(requested);
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

    LC32PreserveRootlessRendererAutoresizing(window, true);

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
    } else {
        LC32RestoreRootlessRendererAutoresizing(window);
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
        if(![existing isKindOfClass:
                LC32LegacyIPadContainerController.class] &&
                LC32ObjectUsesGuestClass(existing)) {
            const bool needsPhoneCanvas =
                LC32WindowNeedsImmediateLegacyPhoneCanvas(window, existing);
            if(LC32WindowNeedsLegacyIPadContainer(window) ||
                    needsPhoneCanvas) {
                LC32InstallGuestWindowRootViewController(window, existing,
                    needsPhoneCanvas
                        ? LC32LegacyPhoneCanvasGeometryMode(existing)
                        : LC32LegacyIPadGeometryModePreservePortraitCanvas);
            }
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
        const bool needsPhoneCanvas =
            LC32WindowNeedsImmediateLegacyPhoneCanvas(window, controller);
        LC32InstallGuestWindowRootViewController(window, controller,
            needsPhoneCanvas
                ? LC32LegacyPhoneCanvasGeometryMode(controller)
                : LC32LegacyIPadGeometryModePreservePortraitCanvas);
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

void LC32FinishGuestOrientationStartupAfterLaunch(void) {
    // FinishLaunching is posted after the launch delegate returns, but that
    // delegate may have queued the renderer's initialization on a zero-delay
    // timer. The first idle boundary lets that startup work run before any
    // compatibility-induced orientation callback. A dispatch_async from
    // makeKeyAndVisible could instead run inside a nested launch run loop.
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(
        kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true, LONG_MAX,
        ^(CFRunLoopObserverRef observer, CFRunLoopActivity) {
            // Deferred initialization can pump a nested run loop too. Only
            // the original UIApplicationMain callback depth is a safe idle.
            if(LC32GuestCallbackDepth() > LC32GuestOrientationStartupCallbackDepth)
                return;
            // BeforeWaiting can precede delivery of an already-signaled
            // timer port. Do not overtake a due zero-delay startup selector.
            CFRunLoopRef runLoop = CFRunLoopGetMain();
            CFStringRef mode = CFRunLoopCopyCurrentMode(runLoop);
            const CFAbsoluteTime nextTimer = mode
                ? CFRunLoopGetNextTimerFireDate(runLoop, mode) : 0;
            if(mode) CFRelease(mode);
            if(nextTimer > 0 && nextTimer <= CFAbsoluteTimeGetCurrent()) return;
            CFRunLoopObserverInvalidate(observer);
            LC32GuestOrientationStartupComplete.store(
                true, std::memory_order_release);
            // Recompute rather than permanently caching the Info.plist
            // fallback: initialized controllers can have narrower policies.
            if(LC32NativeLegacyRotationEnabled()) {
                LC32FinishNativeLegacyRotationStartup();
            } else {
                LC32AdoptLegacyRootViewControllers();
            }
        });
    if(observer) {
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
        CFRelease(observer);
    }
}

void LC32AdoptLegacyPhoneCanvases(UIApplication *application) {
    if(!application) return;
    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(!window.guest_selfOrNull || ![window isKeyWindow]) {
                continue;
            }
            if(objc_getAssociatedObject(
                    window, LC32HideLegacyDirectGuestWindowRootKey)) {
                /* The controller's hidden view is only bookkeeping; the
                 * renderer is a direct UIWindow sibling. Containerizing the
                 * controller would leave that renderer outside the canvas
                 * and let the scene resize its fixed 320x480 surface. */
                LC32ScaleLegacyIPadWindow(window);
                continue;
            }
            LC32LegacyIPadContainerController *container =
                LC32LegacyContainerForWindow(window);
            if(container) {
                if(LC32GeometryModePreservesPhoneCanvas(
                        container.geometryMode)) {
                    LC32ScaleLegacyIPadWindow(window);
                }
                continue;
            }
            UIViewController *guestController =
                LC32GuestWindowRootViewController(window);
            if(!LC32WindowNeedsLegacyPhoneCanvas(
                    window, guestController)) {
                continue;
            }

            /* UIKit asserts if a controller is reparented while it is still
             * completing the application's initial appearance transition.
             * This function runs one turn after didBecomeActive, when that
             * transition is complete. The native container then owns future
             * scene layout while the guest retains its legacy drawable. */
            LC32InstallGuestWindowRootViewController(
                window, guestController,
                LC32LegacyPhoneCanvasGeometryMode(guestController));
            LC32ApplyLegacyWindowPolicy(window);
            dispatch_async(dispatch_get_main_queue(), ^{
                LC32ScaleLegacyIPadWindow(window);
                /* Replacing a live root controller can enqueue one more
                 * UIWindow layout pass after this block. Reassert only the
                 * native scene frame once more; the child canvas is managed
                 * by the compatibility container itself. */
                dispatch_async(dispatch_get_main_queue(), ^{
                    LC32ScaleLegacyIPadWindow(window);
                });
            });
            fprintf(stderr,
                "LC32: isolated legacy phone canvas in landscape scene\n");
        }
    }
}

} // namespace

extern "C" BOOL LC32NativeLegacyRotationCanCallGuest(void) {
    return LC32CanQueryGuestOrientation();
}

extern "C" void LC32UIKitDidSetGuestAutoresizingMask(id object) {
    if(!LC32UIKitLegacyCompatibilityEnabled()) return;
    if(!pthread_main_np() || LC32GetGuestExecutableSDKVersion() >= 0x80000 ||
            ![object isKindOfClass:UIView.class]) return;
    LC32LegacyRendererAutoresizingState *state = objc_getAssociatedObject(
        object, LC32LegacyRootlessRendererAutoresizingStateKey);
    if(state) {
        /* This runs only after a guest setter, not our typed native setters.
         * Even an explicit None after detachment relinquishes ownership of
         * the frozen mask. The record retains neither its view nor window. */
        state.yielded = YES;
    }
}

extern "C" void LC32UIKitScheduleLegacyOverlayLayout(
        id object, id addedSubview) {
    if(!LC32UIKitLegacyCompatibilityEnabled()) return;
    if(!pthread_main_np() || LC32GetGuestExecutableSDKVersion() >= 0x80000) {
        return;
    }
    if(addedSubview) {
        /* A selector with this name on an unrelated class need not take an
         * object argument. Inspect only the known-valid receiver first. */
        if(![object isKindOfClass:UIView.class]) return;
        if([object isKindOfClass:UIWindow.class]) {
            LC32PreserveRootlessRendererAutoresizing((UIWindow *)object);
        }
        LC32ScheduleRootlessWindowLayerLayout(
            LC32NativeViewWindow((UIView *)object));
        if(![object isKindOfClass:UIWindow.class]) return;
        object = addedSubview;
    }
    if(![object isKindOfClass:UIView.class]) return;
    UIView *view = (UIView *)object;
    if([view isKindOfClass:UIWindow.class]) {
        LC32ScheduleRootlessWindowLayerLayout((UIWindow *)view);
        return;
    }
    if(![LC32NativeViewSuperview(view) isKindOfClass:UIWindow.class]) return;
    const UIInterfaceOrientation rootOrientation =
        LC32LegacyRootWindowGeometry(view, true);
    objc_setAssociatedObject(view, LC32LegacyRootWindowGeometryKey,
        rootOrientation ? @(rootOrientation) : nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(objc_getAssociatedObject(view, LC32LegacyOverlayLayoutPendingKey)) {
        return;
    }
    objc_setAssociatedObject(view, LC32LegacyOverlayLayoutPendingKey,
        @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(view, LC32LegacyOverlayLayoutPendingKey,
            nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LC32FitLegacyControllerRoot(view);
        LC32FitLegacyControllerOverlay(view);
    });
}

extern "C" bool LC32UIKitGetViewDuringGuestLoad(
        id object, id *view) {
    if(![object isKindOfClass:UIViewController.class] ||
            !LC32GuestLoadViewIsActive((UIViewController *)object)) {
        return false;
    }

    UIView *loadedView = nil;
    if(!LC32NativeViewIfLoaded((UIViewController *)object, &loadedView)) {
        return false;
    }
    if(view) *view = loadedView;
    return true;
}

@implementation LC32LegacyWindowRootController

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* Scene-driven window resizing can settle after makeKeyAndVisible.
     * Refit presentation from this inert native root without laying out the
     * guest renderer or intercepting ordinary guest view layout. */
    LC32ScheduleRootlessWindowLayerLayout(LC32NativeViewWindow(self.view));
}

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
    const UIInterfaceOrientation target = LC32LegacyTargetOrientation(self);
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
@synthesize geometryMode = _geometryMode;

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
    /* The guest rootViewController accessor unwraps this native container.
     * Publish the controller before forcing -view so loadView/viewDidLoad can
     * observe the root that the guest just assigned. */
    const NSUInteger generation = _guestContentGeneration;
    _guestContentController = controller;
    UIView *contentView = controller.view;
    if(generation != _guestContentGeneration ||
            controller != _guestContentController) {
        /* Loading the guest view can synchronously replace the window root.
         * Let that nested install own the container instead of resuming this
         * stale generation and overwriting its controller/view pair. */
        return;
    }
    CGRect canonicalBounds = LC32NativeViewBounds(contentView);
    const CGFloat shortEdge = MIN(canonicalBounds.size.width,
                                  canonicalBounds.size.height);
    const CGFloat longEdge = MAX(canonicalBounds.size.width,
                                 canonicalBounds.size.height);
    if(_geometryMode ==
            LC32LegacyIPadGeometryModePreservePhonePortraitCanvas) {
        const CGAffineTransform transform =
            LC32NativeViewTransform(contentView);
        const CGAffineTransform landscapeLeftTransform =
            CGAffineTransformMake(0, 1, -1, 0, 0, 0);
        const CGAffineTransform landscapeRightTransform =
            CGAffineTransformMake(0, -1, 1, 0, 0, 0);
        if(LC32TransformNearlyEquals(
                transform, landscapeLeftTransform) ||
                LC32TransformNearlyEquals(
                    transform, landscapeRightTransform)) {
            /* UIKit can already have applied the obsolete root-window turn
             * if this is the post-key fallback. It is redundant once the
             * portrait canvas is a child of the native scene container. */
            LC32NativeSetViewTransform(
                contentView, CGAffineTransformIdentity);
        }
        /* Old phone GL engines commonly allocate a portrait surface from
         * UIScreen.bounds and apply the selected landscape orientation in
         * their projection matrix. Preserve the full surface and reproduce
         * UIKit's old compositor turn on the native wrapper below. */
        canonicalBounds = CGRectMake(
            canonicalBounds.origin.x, canonicalBounds.origin.y,
            320, 480);
    } else if(_geometryMode ==
            LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas) {
        const CGAffineTransform transform =
            LC32NativeViewTransform(contentView);
        const CGAffineTransform landscapeLeftTransform =
            CGAffineTransformMake(0, 1, -1, 0, 0, 0);
        const CGAffineTransform landscapeRightTransform =
            CGAffineTransformMake(0, -1, 1, 0, 0, 0);
        if(LC32TransformNearlyEquals(
                transform, landscapeLeftTransform) ||
                LC32TransformNearlyEquals(
                    transform, landscapeRightTransform)) {
            /* UIKit may already have applied an obsolete root-window turn.
             * It is redundant once the landscape canvas is a child of the
             * native scene container. */
            LC32NativeSetViewTransform(
                contentView, CGAffineTransformIdentity);
        }
        if(!isfinite(shortEdge) || !isfinite(longEdge) ||
                shortEdge <= 0 || longEdge <= 0) {
            canonicalBounds = CGRectMake(0, 0, 480, 320);
        } else {
            /* The runtime probe deliberately matches by short/long edge: the
             * archived root may still be portrait-ordered while carrying the
             * obsolete UIKit quarter-turn cleared above. Once isolated in the
             * native wrapper, store its canonical drawable as 480x320. */
            canonicalBounds.size = CGSizeMake(longEdge, shortEdge);
        }
    } else if(!isfinite(shortEdge) || !isfinite(longEdge) ||
            shortEdge < 700 || longEdge < 900) {
        canonicalBounds = CGRectMake(0, 0, 768, 1024);
    }

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
        const bool preservesInferredIPadCanvas =
            _geometryMode ==
                LC32LegacyIPadGeometryModeReflowRootController &&
            LC32GuestUsesFixedLandscapeIPadCanvas() &&
            LC32WindowNeedsLegacyIPadContainer(window);
        if(preservesInferredIPadCanvas) {
            /* UIKit's scene conversion describes the visible phone viewport,
             * but the classic compositor scales this fixed iPad window again.
             * Preserve its 1x canvas here to avoid applying both scales. */
            viewport = LC32NativeViewBounds(self.view);
        } else if(window.windowScene) {
            viewport = LC32LegacyViewportInView(window, self.view);
        }
    }
    if(!(viewport.size.width > 0) || !(viewport.size.height > 0)) {
        viewport = self.view.bounds;
    }
    const CGSize viewportSize = viewport.size;
    if(!(viewportSize.width > 0) || !(viewportSize.height > 0)) return;

    _fittingGuestContent = YES;
    const UIInterfaceOrientation target =
        LC32LegacyTargetOrientation(_guestContentController);
    CGRect canonicalBounds = _canonicalGuestBounds;
    if(!(canonicalBounds.size.width > 0) ||
            !(canonicalBounds.size.height > 0)) {
        canonicalBounds = CGRectMake(0, 0, 768, 1024);
    }

    CGSize logicalSize = canonicalBounds.size;
    CGFloat compositorAngle = 0;
    if(_geometryMode ==
            LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas) {
        /* This drawable is already landscape. Center it without recreating
         * the portrait-canvas compositor turn. */
    } else if(_geometryMode ==
            LC32LegacyIPadGeometryModeReflowRootController) {
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
        /* Pre-controller iPad applications and legacy landscape phone games
         * both keep a portrait drawable. Preserve that contract and recreate
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
    CGFloat scale = transformedWidth > 0 && transformedHeight > 0
        ? MIN(viewportSize.width / transformedWidth,
              viewportSize.height / transformedHeight)
        : 0;
    if(_geometryMode ==
            LC32LegacyIPadGeometryModePreservePhoneLandscapeCanvas) {
        scale = MIN((CGFloat)1, scale);
    }
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
    const UIInterfaceOrientation target =
        LC32LegacyTargetOrientation(_guestContentController);
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
    UIInterfaceOrientation targetOrientation =
        LC32LegacyTargetOrientation(_guestContentController);
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

    /* Preserve native and inherited -loadView implementations. A synthesized
     * class's own void trampoline is the only method which needs the legacy
     * reentrancy guard; method_setImplementation retains its guest encoding.
     * Keep this bridge guard even when legacy UIKit adaptation is disabled:
     * it only intercepts recursive guest -view reads while -loadView is active,
     * without changing geometry, hierarchy, or orientation policy. */
    Method guestLoadView = LC32ClassOwnMethod(cls, @selector(loadView));
    if(guestLoadView && method_getImplementation(guestLoadView) ==
            (IMP)&LC32InvokeGuestSelector) {
        method_setImplementation(
            guestLoadView, (IMP)&LC32GuestLoadView);
    }

    if(LC32NativeLegacyRotationEnabled()) {
        Method guestWillRotate = LC32ClassOwnMethod(cls,
            @selector(willRotateToInterfaceOrientation:duration:));
        if(guestWillRotate && method_getImplementation(guestWillRotate) ==
                (IMP)&LC32InvokeGuestSelector) {
            method_setImplementation(guestWillRotate, (IMP)&LC32GuestWillRotate);
        }
        LC32PrepareNativeLegacyRotationClass(cls);
    }
    if(!LC32UIKitLegacyCompatibilityEnabled()) return;

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

    /* Guest implementations of the modern methods are ordinary JIT-backed
     * trampolines. Wrap class-owned methods so native UIKit callbacks can use
     * a cached result without entering ARM32 code, and so the application-wide
     * Info.plist policy remains the outer constraint. Keep the original IMPs
     * for guest-thread queries made from LC32ApplyLegacyWindowPolicy. */
    Method guestSupportedOrientations = LC32ClassOwnMethod(
        cls, @selector(supportedInterfaceOrientations));
    if(guestSupportedOrientations && method_getImplementation(
            guestSupportedOrientations) !=
            (IMP)&LC32GuestSupportedInterfaceOrientations) {
        objc_setAssociatedObject((id)cls,
            LC32GuestSupportedOrientationsIMPKey,
            @(reinterpret_cast<uintptr_t>(method_getImplementation(
                guestSupportedOrientations))),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        method_setImplementation(guestSupportedOrientations,
            (IMP)&LC32GuestSupportedInterfaceOrientations);
    }

    Method guestPreferredOrientation = LC32ClassOwnMethod(
        cls, @selector(preferredInterfaceOrientationForPresentation));
    if(guestPreferredOrientation && method_getImplementation(
            guestPreferredOrientation) !=
            (IMP)&LC32GuestPreferredInterfaceOrientation) {
        objc_setAssociatedObject((id)cls,
            LC32GuestPreferredOrientationIMPKey,
            @(reinterpret_cast<uintptr_t>(method_getImplementation(
                guestPreferredOrientation))),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        method_setImplementation(guestPreferredOrientation,
            (IMP)&LC32GuestPreferredInterfaceOrientation);
    }

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
    if(!LC32UIKitLegacyCompatibilityEnabled()) return 0;
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

extern "C" u32 LC32UIKitGetLegacyControllerOrientation(
        u32 low, u32 high, u32) {
    if(!LC32UIKitLegacyCompatibilityEnabled())
        return UIInterfaceOrientationUnknown;
    if(!pthread_main_np() || LC32GetGuestExecutableSDKVersion() >= 0x80000)
        return UIInterfaceOrientationUnknown;
    /* Those canvases already have a distinct logical orientation contract;
     * leave their existing controller getters unchanged. */
    if(LC32GuestUsesFixedLandscapePhoneCanvas() ||
            LC32GuestNeedsLegacyIPadCanvas())
        return UIInterfaceOrientationUnknown;
    UIViewController *controller = reinterpret_cast<UIViewController *>(
        static_cast<uintptr_t>(low | (static_cast<u64>(high) << 32)));
    if(![controller isKindOfClass:UIViewController.class])
        return UIInterfaceOrientationUnknown;

    using ControllerGetter = UIViewController *(*)(id, SEL);
    static ControllerGetter parentGetter = reinterpret_cast<ControllerGetter>(
        class_getMethodImplementation(UIViewController.class,
            @selector(parentViewController)));
    if(parentGetter(controller, @selector(parentViewController)))
        return UIInterfaceOrientationUnknown;
    static ControllerGetter presentingGetter =
        reinterpret_cast<ControllerGetter>(class_getMethodImplementation(
            UIViewController.class, @selector(presentingViewController)));
    if(presentingGetter(controller, @selector(presentingViewController)))
        return UIInterfaceOrientationUnknown;

    NSNumber *cached = objc_getAssociatedObject(
        controller, LC32LegacyOrientationMaskKey);
    const UIInterfaceOrientationMask mask = cached
        ? (UIInterfaceOrientationMask)cached.unsignedLongLongValue
        : LC32GuestInterfacePolicy().declaredOrientations;
    UIView *view = nil;
    LC32NativeViewIfLoaded(controller, &view);
    using WindowGetter = UIWindow *(*)(id, SEL);
    static WindowGetter windowGetter = reinterpret_cast<WindowGetter>(
        class_getMethodImplementation(UIView.class, @selector(window)));
    UIWindow *window = view ? windowGetter(view, @selector(window)) : nil;
    if(window) {
        if(!window.guest_selfOrNull)
            return UIInterfaceOrientationUnknown;
        if(LC32NativeWindowRootViewController(window) == controller) {
            using OrientationGetter = UIInterfaceOrientation (*)(id, SEL);
            static OrientationGetter orientationGetter =
                reinterpret_cast<OrientationGetter>(class_getMethodImplementation(
                    UIViewController.class, @selector(interfaceOrientation)));
            const UIInterfaceOrientation native = orientationGetter(
                controller, @selector(interfaceOrientation));
            /* Preserve an allowed native orientation, including an ongoing
             * transition. Old UIKit only applied its preferred/mask fallback
             * when the root's cached orientation was no longer supported. */
            if(LC32MaskForInterfaceOrientation(native) & mask)
                return UIInterfaceOrientationUnknown;
        } else {
            using ViewGetter = UIView *(*)(id, SEL);
            static ViewGetter superviewGetter = reinterpret_cast<ViewGetter>(
                class_getMethodImplementation(UIView.class, @selector(superview)));
            if(superviewGetter(view, @selector(superview)) != window)
                return UIInterfaceOrientationUnknown;
        }
    }

    /* iOS 10's _legacyInterfaceOrientation falls back to the application
     * orientation when a controller is not its window's root yet, including
     * when its view has already been added directly to that window. It also
     * corrects an attached root's stale orientation against its allowed mask.
     * Modern UIKit can instead report portrait during a landscape launch.
     * Do not load the view or invoke engine-owned orientation callbacks here. */
    const UIInterfaceOrientation current =
        UIApplication.sharedApplication.statusBarOrientation;
    return (LC32MaskForInterfaceOrientation(current) & mask)
        ? (u32)current : (u32)UIInterfaceOrientationUnknown;
}

extern "C" u32 LC32UIKitGetLegacyStatusBarOrientation(void) {
    if(!LC32UIKitLegacyCompatibilityEnabled())
        return (u32)UIInterfaceOrientationUnknown;
    const LC32GuestUIKitPolicy &policy = LC32GuestInterfacePolicy();
    if(LC32GuestUsesFixedLandscapePhoneCanvas()) {
        /* Keep the guest's projection orientation paired with the native
         * wrapper that turns its fixed portrait canvas into landscape. */
        return (u32)LC32LegacyTargetOrientation(nil);
    }

    if(!LC32GuestNeedsLegacyIPadCanvas()) {
        /* Ordinary phone applications should retain the generated shim's
         * direct UIApplication forwarding behavior. In particular, apps
         * supporting both landscape sides must not observe our pre-scene
         * fallback and then a different settled scene orientation. */
        return (u32)UIInterfaceOrientationUnknown;
    }

    UIApplication *application = UIApplication.sharedApplication;
    UIInterfaceOrientation current = UIInterfaceOrientationUnknown;
    bool foundKeyWindow = false;
    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        const UIInterfaceOrientation candidate =
            windowScene.interfaceOrientation;
        if(!LC32MaskForInterfaceOrientation(candidate)) continue;
        if(!LC32MaskForInterfaceOrientation(current)) current = candidate;
        for(UIWindow *window in windowScene.windows) {
            if(!window.isKeyWindow) continue;
            current = candidate;
            foundKeyWindow = true;
            break;
        }
        if(foundKeyWindow) break;
    }

    const UIInterfaceOrientationMask currentMask =
        LC32MaskForInterfaceOrientation(current);
    if(currentMask & policy.declaredOrientations) return (u32)current;

    const UIInterfaceOrientation requested = (UIInterfaceOrientation)
        LC32LegacyRequestedOrientation.load(std::memory_order_relaxed);
    if(LC32MaskForInterfaceOrientation(requested) &
            policy.declaredOrientations) {
        return (u32)requested;
    }
    if(LC32MaskForInterfaceOrientation(policy.preferredOrientation) &
            policy.declaredOrientations) {
        return (u32)policy.preferredOrientation;
    }
    return (u32)LC32FirstOrientationInMask(policy.declaredOrientations);
}

@interface UIWindow (LC32LegacyRootViewController)
- (void)lc32_makeKeyAndVisible;
+ (void)lc32_applicationDidBecomeActive:(NSNotification *)notification;
@end

@implementation UIWindow (LC32LegacyRootViewController)

+ (void)load {
    if(!LC32UIKitLegacyCompatibilityEnabled()) return;
    Method original = class_getInstanceMethod(self,
                                               @selector(makeKeyAndVisible));
    Method compatibility = class_getInstanceMethod(
        self, @selector(lc32_makeKeyAndVisible));
    if(original && compatibility) {
        method_exchangeImplementations(original, compatibility);
    }
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(lc32_applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification
        object:nil];
}

+ (void)lc32_applicationDidBecomeActive:(NSNotification *)notification {
    UIApplication *application =
        [notification.object isKindOfClass:UIApplication.class]
            ? (UIApplication *)notification.object
            : UIApplication.sharedApplication;
    dispatch_async(dispatch_get_main_queue(), ^{
        LC32AdoptLegacyPhoneCanvases(application);
    });
}

- (void)lc32_makeKeyAndVisible {
    LC32AdoptLegacyRootViewController(self);
    [self lc32_makeKeyAndVisible];
    /* UIWindowScene geometry is authoritative only after makeKeyAndVisible.
     * Refit the virtual child canvas against that settled viewport without
     * changing guest-visible UIWindow bounds. */
    LC32ApplyLegacyWindowPolicy(self);
    LC32ScaleLegacyIPadWindow(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        LC32ScaleLegacyIPadWindow(self);
    });
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

void LC32_UIKit_UIAccessibilityPostNotification(
        u32 notificationValue, u32 argumentLow, u32 sp) {
    const u32 argumentHigh =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    id argument = reinterpret_cast<id>(static_cast<uintptr_t>(
        argumentLow | (static_cast<u64>(argumentHigh) << 32)));
    UIAccessibilityPostNotification(
        (UIAccessibilityNotifications)notificationValue, argument);
}

static float LC32UIKitFloatFromBits(u32 bits) {
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static id LC32UIKitObjectFromWords(u32 low, u32 high) {
    return reinterpret_cast<id>(static_cast<uintptr_t>(
        low | (static_cast<u64>(high) << 32)));
}

u32 LC32_UIKit_UIAccessibilityConvertFrameToScreenCoordinates(
        u32 guestResult, u32 xBits, u32 sp) {
    if(!guestResult || guestResult > UINT32_MAX - 15) return 0;

    const u32 yBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 widthBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 4);
    const u32 heightBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 8);
    UIView *view = LC32UIKitObjectFromWords(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 12),
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 16));
    if(!view) return 0;

    const CGRect result = UIAccessibilityConvertFrameToScreenCoordinates(
        CGRectMake(LC32UIKitFloatFromBits(xBits),
            LC32UIKitFloatFromBits(yBits),
            LC32UIKitFloatFromBits(widthBits),
            LC32UIKitFloatFromBits(heightBits)),
        view);
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

u32 LC32_UIKit_UIAccessibilityConvertPathToScreenCoordinates(
        u32 pathLow, u32 pathHigh, u32 sp) {
    UIBezierPath *path = LC32UIKitObjectFromWords(pathLow, pathHigh);
    UIView *view = LC32UIKitObjectFromWords(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp),
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 4));
    if(!path || !view) return 0;
    UIBezierPath *result =
        UIAccessibilityConvertPathToScreenCoordinates(path, view);
    return result ? result.guest_self : 0;
}

u32 LC32_UIKit_UIAccessibilityFocusedElement(
        u32 identifierLow, u32 identifierHigh, u32) {
    NSString *identifier =
        LC32UIKitObjectFromWords(identifierLow, identifierHigh);
    id element = UIAccessibilityFocusedElement(identifier);
    return element ? [element guest_self] : 0;
}

void LC32_UIKit_UIAccessibilityZoomFocusChanged(
        u32 type, u32 xBits, u32 sp) {
    const u32 yBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 widthBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 4);
    const u32 heightBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 8);
    UIView *view = LC32UIKitObjectFromWords(
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 12),
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + 16));
    if(!view) return;
    UIAccessibilityZoomFocusChanged((UIAccessibilityZoomType)type,
        CGRectMake(LC32UIKitFloatFromBits(xBits),
            LC32UIKitFloatFromBits(yBits),
            LC32UIKitFloatFromBits(widthBits),
            LC32UIKitFloatFromBits(heightBits)),
        view);
}

u32 LC32_UIKit_UIGuidedAccessRestrictionStateForIdentifier(
        u32 identifierLow, u32 identifierHigh, u32) {
    NSString *identifier =
        LC32UIKitObjectFromWords(identifierLow, identifierHigh);
    return identifier
        ? (u32)UIGuidedAccessRestrictionStateForIdentifier(identifier)
        : (u32)UIGuidedAccessRestrictionStateAllow;
}

u32 LC32_UIKit_UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(
        u32 pathLow, u32 pathHigh, u32) {
    NSString *path = LC32UIKitObjectFromWords(pathLow, pathHigh);
    return path && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path);
}

int LC32_UIKit_UIApplicationMain(u32 r2, u32 r3, u32 sp) {
    static bool firstEntry = true;
    if(!firstEntry) {
        return LC32RunDebuggerAwareMainRunLoop();
    }
    firstEntry = false;
    if(LC32UIKitLegacyCompatibilityEnabled() || LC32NativeLegacyRotationEnabled()) {
        LC32GuestOrientationStartupCallbackDepth = LC32GuestCallbackDepth();
        LC32GuestOrientationStartupComplete.store(false, std::memory_order_release);
    }

    int argc = r2;
    u32 guest_argv = r3;
    NSString *principalClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    NSString *delegateClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);

    NSLog(@"UIApplicationMain(%d, 0x%x, %@, %@)\n", argc, guest_argv, principalClassName, delegateClassName);
    static id launchObserver;
    if(LC32UIKitLegacyCompatibilityEnabled() || LC32NativeLegacyRotationEnabled()) {
        launchObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
            if(LC32UIKitLegacyCompatibilityEnabled()) LC32AdoptLegacyRootViewControllers();
            LC32FinishGuestOrientationStartupAfterLaunch();
        }];
    }
    (void)launchObserver;
    char executableName[] = "exec";
    char *host_argv[] = {executableName, nullptr};

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
    UIViewController *controller;
    if(LC32UIKitLegacyCompatibilityEnabled()) {
        NSNumber *legacyDirectRootState = objc_getAssociatedObject(
            window, LC32HideLegacyDirectGuestWindowRootKey);
        if(legacyDirectRootState.boolValue) return 0;
        controller = LC32GuestWindowRootViewController(window);
    } else {
        controller = LC32NativeWindowRootViewController(window);
    }
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
    if(!LC32UIKitLegacyCompatibilityEnabled()) {
        LC32NativeSetWindowRootViewController(window, controller);
        return;
    }

    const bool suppressGuestCallbacks = !pthread_main_np();
    dispatch_block_t setRoot = ^{
        const bool previous = LC32SuppressGuestOrientationQuery;
        NSNumber *legacyDirectRootState =
            LC32LegacyDirectGuestRootStateForAssignment(window, controller);
        objc_setAssociatedObject(
            window, LC32HideLegacyDirectGuestWindowRootKey,
            legacyDirectRootState,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        const bool needsImmediatePhoneCanvas =
            LC32WindowNeedsImmediateLegacyPhoneCanvas(
                window, controller);
        if(suppressGuestCallbacks) {
            LC32SuppressGuestOrientationQuery = true;
        }
        LC32LegacyIPadGeometryMode geometryMode =
            LC32LegacyIPadGeometryModeReflowRootController;
        LC32LegacyIPadContainerController *container =
            LC32LegacyContainerForWindow(window);
        if(container && LC32GeometryModePreservesPhoneCanvas(
                container.geometryMode)) {
            /* Once runtime geometry has identified a legacy drawable, keep
             * that window policy stable if the guest replaces its root. The
             * replacement view may not be loaded yet, so probing it here
             * would otherwise unwrap the container until another activation. */
            geometryMode = container.geometryMode;
        } else if(needsImmediatePhoneCanvas) {
            geometryMode = LC32LegacyPhoneCanvasGeometryMode(controller);
        } else if(LC32GuestUsesFixedLandscapeIPadCanvas()) {
            /* This inferred-iPad class creates a 768x1024 EAGL surface and
             * rotates its projection from statusBarOrientation even though
             * it assigns a root controller. Preserve that old surface and
             * let the native wrapper perform UIKit's matching quarter-turn. */
            geometryMode =
                LC32LegacyIPadGeometryModePreservePortraitCanvas;
        }
        LC32InstallGuestWindowRootViewController(
            window, controller, geometryMode);
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
