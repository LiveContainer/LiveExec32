#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xpc/xpc.h>
#include "LC32LegacyRotation.h"

@interface NSObject (LC32SceneFixture)
@property(nonatomic, copy) id settings;
@property(nonatomic, copy) id clientSettings;
@property(nonatomic) UIInterfaceOrientation interfaceOrientation;
@property(nonatomic) CGRect frame;
- (void)encodeWithXPCDictionary:(xpc_object_t)dictionary;
- (instancetype)initWithXPCDictionary:(xpc_object_t)dictionary;
@end

static id sceneParametersRoundTrip(UIInterfaceOrientation orientation) {
    id parameters = [objc_getClass("FBSMutableSceneParameters") new];
    id settings = [objc_getClass("UIMutableApplicationSceneSettings") new];
    id client = [objc_getClass("UIMutableApplicationSceneClientSettings") new];
    [settings setInterfaceOrientation:orientation];
    [settings setFrame:CGRectMake(11, 13, 101, 203)];
    [client setInterfaceOrientation:orientation];
    [parameters setSettings:settings];
    [parameters setClientSettings:client];
    xpc_object_t dictionary = xpc_dictionary_create(NULL, NULL, 0);
    [parameters encodeWithXPCDictionary:dictionary];
    return [[objc_getClass("FBSSceneParameters") alloc] initWithXPCDictionary:dictionary];
}

/* Native-only fixture: compile the actual LegacyRotation.mm implementation,
 * not the emulator or guest selector bridge. Explicit registration stands in
 * for the bridge's classification of guest-created controller classes. */
static BOOL guestCallsAllowed = YES;
BOOL LC32NativeLegacyRotationCanCallGuest(void) { return guestCallsAllowed; }
/* Stand in for UIKit.mm's native iPad-on-phone container. The production
 * rotation unit must resolve its guest without registering the wrapper class. */
@interface RootlessRotationCanvasController : UIViewController
@property(nonatomic, strong) UIViewController *guestContentController;
@end
@implementation RootlessRotationCanvasController
- (BOOL)shouldAutomaticallyForwardRotationMethods { return NO; }
@end
UIViewController *LC32NativeLegacyRotationContentController(UIViewController *controller) {
    if([controller isKindOfClass:RootlessRotationCanvasController.class])
        return ((RootlessRotationCanvasController *)controller).guestContentController;
    return controller;
}

static int failures;
static unsigned legacyQueries;
static unsigned legacyLandscapeQueries;
static unsigned willRotateCalls;
static unsigned didRotateCalls;
static unsigned modernMaskQueries;
static UIInterfaceOrientation lastLegacyOrientation;
static BOOL manualRotation;
static BOOL explicitRootCase;
static BOOL expectedEnabled;
static BOOL originalNativeRotationPolicy;
static NSString *testCase;
static UIDeviceOrientation requestedDeviceOrientation;
static UIDeviceOrientation deviceOrientationProbe(id device, SEL selector) {
    (void)device; (void)selector;
    return requestedDeviceOrientation;
}

static BOOL startupDeviceGenerating;
static unsigned startupDeviceSetterCalls;
static BOOL startupDeviceAnimated;
static BOOL startupDeviceGeneratingProbe(id object, SEL selector) {
    (void)object; (void)selector;
    return startupDeviceGenerating;
}
static void startupDeviceSetterProbe(id device, SEL selector,
        UIDeviceOrientation orientation, BOOL animated) {
    (void)selector;
    ++startupDeviceSetterCalls;
    startupDeviceAnimated |= animated;
    if(!startupDeviceGenerating || requestedDeviceOrientation == orientation) return;
    requestedDeviceOrientation = orientation;
    [NSNotificationCenter.defaultCenter postNotificationName:
        UIDeviceOrientationDidChangeNotification object:device];
}

static NSDictionary *orientationProbeInfo;
static id orientationInfoProbe(id object, SEL selector) {
    (void)object; (void)selector;
    return orientationProbeInfo;
}
static UIInterfaceOrientation portraitStatusBarProbe(id object, SEL selector) {
    (void)object; (void)selector;
    return UIInterfaceOrientationPortrait;
}
static UIInterfaceOrientation startupSceneOrientation;
// A controllable refresh clock; the production adapter still owns target
// selection, delivery, timeout and the identity of the callback's sender.
@interface StartupLinkFixture : NSObject
@property(nonatomic, strong) id target;
@property(nonatomic) SEL action;
@property(nonatomic) CFTimeInterval timestamp;
@property(nonatomic, weak) id lastSender;
@property(nonatomic) unsigned calls;
@end
@implementation StartupLinkFixture
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)action {
    StartupLinkFixture *link = [self new];
    link.target = target;
    link.action = action;
    return link;
}
- (void)fire {
    ((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
}
- (void)record:(id)sender {
    self.calls++;
    self.lastSender = sender;
}
@end

static UIInterfaceOrientation startupSceneOrientationProbe(id object, SEL selector) {
    (void)object; (void)selector;
    return startupSceneOrientation;
}

/* The production original-method aliases are replaced only during the
 * synchronous ownership probe. No UIKit work runs with these stubs installed.
 * A false native answer makes the scoped override observable on every runtime. */
static __unsafe_unretained UIWindow *ownershipOtherWindow;
static __unsafe_unretained CALayer *ownershipExpectedRoot;
static __unsafe_unretained CALayer *ownershipExpectedScene;
static __unsafe_unretained CALayer *ownershipExpectedTransform;
static BOOL ownershipThrow;
static BOOL ownershipObservedOrientation;
static BOOL ownershipObservedTransform;
static BOOL ownershipObservedOtherOrientation;
static BOOL ownershipObservedOtherTransform;
static BOOL ownershipArgumentsPreserved;
static unsigned ownershipCalls;

static void check(const char *name, BOOL passed) {
    printf("rootless-rotation-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static void checkSceneOrientationPreference(UIViewController *controller, UIWindow *window) {
    UIInterfaceOrientation sceneOrientation = window.windowScene.interfaceOrientation;
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    NSString *opposite = sceneOrientation == UIInterfaceOrientationLandscapeRight
        ? @"UIInterfaceOrientationLandscapeLeft" : @"UIInterfaceOrientationLandscapeRight";
    info[@"UIInterfaceOrientation"] = opposite;
    info[@"UISupportedInterfaceOrientations"] = @[@"UIInterfaceOrientationLandscapeLeft",
        @"UIInterfaceOrientationLandscapeRight"];
    [info removeObjectForKey:@"UISupportedInterfaceOrientations~ipad"];
    orientationProbeInfo = info;
    Method bundleInfo = class_getInstanceMethod(NSBundle.class, @selector(infoDictionary));
    Method statusBar = class_getInstanceMethod(UIApplication.class, @selector(statusBarOrientation));
    IMP savedInfo = method_setImplementation(bundleInfo, (IMP)orientationInfoProbe);
    IMP savedStatus = method_setImplementation(statusBar, (IMP)portraitStatusBarProbe);
    @try {
        check("rootless-prefers-active-scene-over-stale-launch-orientation",
            UIInterfaceOrientationIsLandscape(sceneOrientation) &&
            controller.preferredInterfaceOrientationForPresentation == sceneOrientation);
    } @finally {
        method_setImplementation(bundleInfo, savedInfo);
        method_setImplementation(statusBar, savedStatus);
        orientationProbeInfo = nil;
    }
}

static BOOL frameProbeHidden, frameProbeIgnore;
static UIInterfaceOrientation frameProbeOrientation;
static CGFloat frameProbeHeight;
static unsigned frameProbeCalls;
static BOOL statusBarHiddenProbe(id object, SEL selector) {
    (void)object; (void)selector;
    return frameProbeHidden;
}
static CGRect applicationFrameProbe(id object, SEL selector,
        UIInterfaceOrientation orientation, CGFloat height, BOOL ignore) {
    (void)object; (void)selector;
    ++frameProbeCalls;
    frameProbeOrientation = orientation;
    frameProbeHeight = height;
    frameProbeIgnore = ignore;
    return CGRectMake(1, 2, 345, 678);
}
static void checkHiddenStatusBarFrame(void) {
    SEL policySelector = sel_registerName("_viewControllerBasedStatusBarAppearance");
    Method policyMethod = class_getInstanceMethod(UIApplication.class, policySelector);
    NSNumber *explicitPolicy = [NSBundle.mainBundle objectForInfoDictionaryKey:
        @"UIViewControllerBasedStatusBarAppearance"];
    const uint32_t sdk = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"LC32ExpectedSDK"] unsignedIntValue];
    const BOOL applicationDefault = expectedEnabled && sdk < 0x70000 && !explicitPolicy;
    Dl_info policyInfo = {0};
    check("statusbar-policy-entrypoint", policyMethod != NULL);
    if(policyMethod) {
        BOOL resolved = dladdr((const void *)method_getImplementation(policyMethod), &policyInfo) != 0;
        check("statusbar-policy-hook-scope", resolved &&
            (policyInfo.dli_fbase == _dyld_get_image_header(0)) == applicationDefault);
        if(applicationDefault || explicitPolicy) {
            BOOL controllerManaged = ((BOOL (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, policySelector);
            check("statusbar-policy-default-or-explicit", controllerManaged ==
                (explicitPolicy ? explicitPolicy.boolValue : NO));
        }
        if(applicationDefault) {
            UIApplication *application = UIApplication.sharedApplication;
            check("statusbar-initial-hidden", application.isStatusBarHidden);
            [application setStatusBarHidden:NO];
            check("statusbar-legacy-show", !application.isStatusBarHidden);
            [application setStatusBarHidden:YES];
            check("statusbar-legacy-hide", application.isStatusBarHidden);
        }
    }
    SEL selector = sel_registerName("_applicationFrameForInterfaceOrientation:usingStatusbarHeight:ignoreStatusBar:");
    SEL savedSelector = sel_registerName("lc32_applicationFrameForInterfaceOrientation:usingStatusbarHeight:ignoreStatusBar:");
    Method native = class_getInstanceMethod(UIScreen.class, expectedEnabled ? savedSelector : selector);
    Method hidden = class_getInstanceMethod(UIApplication.class, @selector(isStatusBarHidden));
    check("statusbar-native-entrypoints-present", native && hidden);
    if(!native || !hidden) return;
    // Replace only the saved native method while making synchronous probes.
    // SDK 11 must bypass the wrapper; legacy SDKs must preserve all arguments
    // except the hidden-bar inset. Restore both methods before yielding.
    IMP originalNative = method_setImplementation(native, (IMP)applicationFrameProbe);
    IMP originalHidden = method_setImplementation(hidden, (IMP)statusBarHiddenProbe);
    @try {
        for(unsigned isHidden = 0; isHidden < 2; ++isHidden) {
            frameProbeHidden = isHidden;
            for(unsigned ignore = 0; ignore < 2; ++ignore) {
                for(UIInterfaceOrientation orientation = 1; orientation <= 4; ++orientation) {
                    frameProbeCalls = 0;
                    CGRect frame = ((CGRect (*)(id, SEL, UIInterfaceOrientation, CGFloat, BOOL))objc_msgSend)(
                        UIScreen.mainScreen, selector, orientation, 23.5, ignore);
                    check("statusbar-original-called-once", frameProbeCalls == 1);
                    check("statusbar-arguments-preserved", frameProbeOrientation == orientation &&
                        frameProbeHeight == 23.5);
                    check("statusbar-hidden-inset-matches-sdk", frameProbeIgnore ==
                        (ignore || (expectedEnabled && isHidden)));
                    check("statusbar-native-frame-preserved", CGRectEqualToRect(frame, CGRectMake(1, 2, 345, 678)));
                }
            }
        }
    } @finally {
        method_setImplementation(native, originalNative);
        method_setImplementation(hidden, originalHidden);
    }
    check("statusbar-original-methods-restored", method_getImplementation(native) == originalNative &&
        method_getImplementation(hidden) == originalHidden);
}

static id nativeObjectGetter(id object, const char *name) {
    SEL selector = sel_registerName(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static BOOL nativeBoolGetter(id object, const char *name) {
    SEL selector = sel_registerName(name);
    return [object respondsToSelector:selector]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) : NO;
}

static NSInteger nativeIntegerGetter(id object, const char *name) {
    SEL selector = sel_registerName(name);
    return [object respondsToSelector:selector]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector) : -1;
}

static BOOL nativeDoesNotOwnOrientation(id object, SEL selector) {
    (void)object;
    (void)selector;
    return NO;
}

static CGFloat animationProbeAngle;
static void nativeConfigureAnimationProbe(id window, SEL selector,
        CALayer *root, CALayer *scene, CALayer *transform) {
    (void)window; (void)selector; (void)transform;
    // Native configuration installs portrait backing without actions. The
    // production hook then rebases it below the CAContext boundary.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    root.bounds = CGRectMake(0, 0, 317, 509);
    root.position = CGPointMake(254.5, 158.5);
    root.affineTransform = CGAffineTransformMakeRotation(animationProbeAngle);
    scene.position = CGPointMake(158.5, 254.5);
    scene.affineTransform = CGAffineTransformIdentity;
    [CATransaction commit];
}

@interface BackingAnimationProbe : NSObject <CALayerDelegate>
@property(nonatomic) CGAffineTransform fromTransform;
@property(nonatomic) unsigned transformActions;
@end
@implementation BackingAnimationProbe
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)key {
    if([key isEqualToString:@"transform"]) {
        self.fromTransform = layer.affineTransform;
        ++self.transformActions;
    }
    return (id)NSNull.null;
}
@end

static void nativeConfigureOwnershipProbe(id window, SEL selector,
        CALayer *root, CALayer *scene, CALayer *transform) {
    (void)selector;
    ++ownershipCalls;
    ownershipArgumentsPreserved = root == ownershipExpectedRoot &&
        scene == ownershipExpectedScene && transform == ownershipExpectedTransform;
    ownershipObservedOrientation = nativeBoolGetter(window, "_windowOwnsInterfaceOrientation");
    ownershipObservedTransform = nativeBoolGetter(window, "_windowOwnsInterfaceOrientationTransform");
    ownershipObservedOtherOrientation = nativeBoolGetter(ownershipOtherWindow,
        "_windowOwnsInterfaceOrientation");
    ownershipObservedOtherTransform = nativeBoolGetter(ownershipOtherWindow,
        "_windowOwnsInterfaceOrientationTransform");
    if(ownershipThrow)
        @throw [NSException exceptionWithName:@"LC32OwnershipProbe"
            reason:@"Exercise the production TLS restoration path" userInfo:nil];
}

/* A deterministic native allowance makes the production wrapper's refusal
 * branch observable even when this simulator's compositor rejects rotation
 * before consulting its controller. This replaces only the saved original
 * alias during a synchronous call, then restores it before yielding to UIKit. */
static BOOL nativeAllowsRotation(id window, SEL selector,
        UIInterfaceOrientation orientation, BOOL checkForDismissal, BOOL *disabled) {
    (void)window;
    (void)selector;
    (void)orientation;
    (void)checkForDismissal;
    if(disabled) *disabled = NO;
    return YES;
}

static BOOL nativeDisallowsRotation(id window, SEL selector,
        UIInterfaceOrientation orientation, BOOL checkForDismissal, BOOL *disabled) {
    (void)window;
    (void)selector;
    (void)orientation;
    (void)checkForDismissal;
    if(disabled) *disabled = YES;
    return NO;
}

static void nativeViewMoveNoop(id controller, SEL selector, UIWindow *window, BOOL appear) {
    (void)controller;
    (void)selector;
    (void)window;
    (void)appear;
}

static BOOL nativeRotationPolicy(void) {
    SEL selector = sel_registerName("_transformLayerRotationsAreEnabled");
    return [[UIWindow class] respondsToSelector:selector]
        ? ((BOOL (*)(id, SEL))objc_msgSend)([UIWindow class], selector) : NO;
}

static uint32_t executableSDK(void) {
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    if(header->magic != MH_MAGIC_64) return UINT32_MAX;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for(uint32_t index = 0; index < header->ncmds; ++index) {
        if((size_t)(end - cursor) < sizeof(struct load_command)) return UINT32_MAX;
        const struct load_command *command = (const void *)cursor;
        if(command->cmdsize < sizeof(*command) ||
                command->cmdsize > (size_t)(end - cursor)) return UINT32_MAX;
        if(command->cmd == LC_BUILD_VERSION &&
                command->cmdsize >= sizeof(struct build_version_command)) {
            const struct build_version_command *build = (const void *)command;
            check("simulator-platform", build->platform == PLATFORM_IOSSIMULATOR);
            check("minimum-os-11", build->minos == 0x000b0000);
            return build->sdk;
        }
        cursor += command->cmdsize;
    }
    return UINT32_MAX;
}

@interface UIWindow (RootlessRotationClientProbe)
- (void)_setRotatableClient:(UIViewController *)client
    toOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)update
    duration:(NSTimeInterval)duration force:(BOOL)force isRotating:(BOOL)rotating;
@end

@interface RootlessRotationWindow : UIWindow
@property(nonatomic) unsigned clientTurns;
@property(nonatomic) NSTimeInterval clientDuration;
@end
@implementation RootlessRotationWindow
- (void)_setRotatableClient:(UIViewController *)client
        toOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)update
        duration:(NSTimeInterval)duration force:(BOOL)force isRotating:(BOOL)rotating {
    ++self.clientTurns;
    self.clientDuration = duration;
    [super _setRotatableClient:client toOrientation:orientation updateStatusBar:update
        duration:duration force:force isRotating:rotating];
}
@end

@interface RootlessRotationGuestView : UIView
@end
@implementation RootlessRotationGuestView
@end

/* Marmalade-style owner: no old or modern rotation policy; the GL renderer
 * turns its own contents inside a portrait view attached directly to UIWindow. */
@interface RootlessRotationManualController : UIViewController
@end
@implementation RootlessRotationManualController
@end

/* Only hidden, dedicated probe windows use this subclass. Suppressing their
 * native update lets the deferred-work test count requests without asking the
 * compositor to rotate or modifying the visible fixture window. */
@interface RootlessRotationRefreshWindow : UIWindow
@property(nonatomic) BOOL recordRefreshes;
@property(nonatomic) unsigned refreshes;
@end
@implementation RootlessRotationRefreshWindow
- (void)_updateTransformLayer {
    if(self.recordRefreshes) ++self.refreshes;
    else {
        struct objc_super parent = {self, UIWindow.class};
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(
            &parent, sel_registerName("_updateTransformLayer"));
    }
}
@end

static unsigned updateProbeCalls;
static unsigned updateProbeRefreshes;
static BOOL updateProbeArguments;
static void nativeOrientationUpdateProbe(RootlessRotationRefreshWindow *window, SEL selector,
        UIInterfaceOrientation orientation, NSTimeInterval duration, BOOL force) {
    (void)selector;
    ++updateProbeCalls;
    updateProbeRefreshes = window.refreshes;
    updateProbeArguments = orientation == UIInterfaceOrientationLandscapeLeft &&
        duration == 0.375 && force;
}

static void nativeOrientationUpdateNoop(id window, SEL selector,
        UIInterfaceOrientation orientation, NSTimeInterval duration, BOOL force) {
    (void)window; (void)selector; (void)orientation; (void)duration; (void)force;
}

@interface RootlessRotationTrackingController : UIViewController
@property(nonatomic) unsigned recordedQueries;
@property(nonatomic) unsigned recordedWillCalls;
@property(nonatomic) unsigned recordedDidCalls;
@property(nonatomic) UIInterfaceOrientation recordedWillOrientation;
@property(nonatomic) UIInterfaceOrientation recordedDidOrientation;
@property(nonatomic) NSTimeInterval recordedDuration;
@end
@implementation RootlessRotationTrackingController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    ++self.recordedQueries;
    ++legacyQueries;
    lastLegacyOrientation = orientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    legacyLandscapeQueries += landscape;
    printf("rootless-rotation-legacy-query: orientation=%ld accepted=%d returned=%d\n",
        (long)orientation, landscape, landscape && !manualRotation);
    return landscape && !manualRotation;
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
        duration:(NSTimeInterval)duration {
    ++self.recordedWillCalls;
    self.recordedWillOrientation = orientation;
    self.recordedDuration = duration;
    ++willRotateCalls;
    printf("rootless-rotation-will-rotate: orientation=%ld duration=%g\n",
        (long)orientation, duration);
    [super willRotateToInterfaceOrientation:orientation duration:duration];
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    ++self.recordedDidCalls;
    self.recordedDidOrientation = orientation;
    ++didRotateCalls;
    printf("rootless-rotation-did-rotate: orientation=%ld\n", (long)orientation);
    [super didRotateFromInterfaceOrientation:orientation];
}
@end

@interface RootlessRotationLegacyController : RootlessRotationTrackingController
@end
@implementation RootlessRotationLegacyController
@end

/* An inherited registration must not replace a subclass's modern policy. */
@interface RootlessRotationModernController : RootlessRotationLegacyController
@end
@implementation RootlessRotationModernController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    ++modernMaskQueries;
    return UIInterfaceOrientationMaskLandscapeRight;
}
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
@end

/* Native UIKit controllers not registered by the bridge must be unaffected. */
@interface RootlessRotationUnregisteredController : RootlessRotationTrackingController
@end
@implementation RootlessRotationUnregisteredController
@end

/* Match a low-SDK game which implements both the deprecated query and modern
 * landscape policy. Only its registered subclass is guest-owned; the native
 * base must remain outside both compatibility paths. */
@interface RootlessRotationNativeModernController : RootlessRotationTrackingController
@end
@implementation RootlessRotationNativeModernController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    ++modernMaskQueries;
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
@end

@interface RootlessRotationRegisteredModernController : RootlessRotationNativeModernController
@end
@implementation RootlessRotationRegisteredModernController
@end

/* Active native containers, plus hidden-stack, unselected-tab, and arbitrary
 * containment negatives. Only the active registered content grants backing. */
static UIViewController *backingProbeContainer(UIViewController *content, unsigned layout) {
    if(layout == 2) {
        RootlessRotationCanvasController *canvas = [RootlessRotationCanvasController new];
        [canvas addChildViewController:content];
        [canvas.view addSubview:content.view];
        [content didMoveToParentViewController:canvas];
        canvas.guestContentController = content;
        return canvas;
    }
    if(layout == 3 || layout == 4 || layout == 5) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:content];
        nav.navigationBarHidden = YES;
        if(layout == 5) [nav setViewControllers:@[content, [RootlessRotationNativeModernController new]]];
        if(layout != 4) return nav;
        UITabBarController *tabs = [UITabBarController new];
        tabs.viewControllers = @[nav];
        return tabs;
    }
    if(layout == 6) {
        UITabBarController *tabs = [UITabBarController new];
        tabs.viewControllers = @[content, [RootlessRotationNativeModernController new]];
        tabs.selectedIndex = 1;
        return tabs;
    }
    if(layout == 7) {
        UIViewController *container = [UIViewController new];
        [container addChildViewController:content];
        [container.view addSubview:content.view];
        [content didMoveToParentViewController:container];
        return container;
    }
    return content;
}

/* iOS 6 policy with the pre-iOS-8 lifecycle, but no deprecated policy query
 * anywhere in the hierarchy (the Unity controller shape). */
@interface RootlessRotationPolicyOnlyController : UIViewController
@end
@implementation RootlessRotationPolicyOnlyController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    ++modernMaskQueries;
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)shouldAutorotate { return YES; }
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
        duration:(NSTimeInterval)duration {
    ++willRotateCalls;
    [super willRotateToInterfaceOrientation:orientation duration:duration];
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    ++didRotateCalls;
    [super didRotateFromInterfaceOrientation:orientation];
}
@end

/* A class can inherit a custom preference without implementing the modern
 * supported/shouldAutorotate policy. Registration must not shadow it. */
@interface RootlessRotationPreferredBaseController : RootlessRotationTrackingController
@end
@implementation RootlessRotationPreferredBaseController
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeLeft;
}
@end

@interface RootlessRotationInheritedPreferredController : RootlessRotationPreferredBaseController
@end
@implementation RootlessRotationInheritedPreferredController
@end

@interface RootlessRotationDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) RootlessRotationWindow *window;
@property(nonatomic, strong) UIViewController *controller;
@property(nonatomic, strong) UIViewController *safetyRoot;
@property(nonatomic, strong) UIViewController *modalController;
@property(nonatomic, strong) UIView *content;
@property(nonatomic, strong) UIView *startupRenderer;
@property(nonatomic, weak) UIViewController *replacedController;
@property(nonatomic) CGRect initialContentFrame;
@property(nonatomic) CGRect initialContentBounds;
@property(nonatomic) NSUInteger visibleSubviewCount;
@property(nonatomic) unsigned queriesWhileModalPresented;
@property(nonatomic) BOOL completedRefreshProbe;
@end

@implementation RootlessRotationDelegate
- (void)dumpState:(const char *)stage {
    printf("rootless-rotation-state: %s case=%s root=%p delegate=%p clients=%s "
        "queries=%u landscape=%u will=%u did=%u frame=%s transform=%s\n",
        stage, testCase.UTF8String, (__bridge void *)self.window.rootViewController,
        (__bridge void *)nativeObjectGetter(self.window, "_delegateViewController"),
        [nativeObjectGetter(self.window, "_clientsForRotation") description].UTF8String ?: "nil",
        legacyQueries, legacyLandscapeQueries, willRotateCalls, didRotateCalls,
        NSStringFromCGRect(self.content.frame).UTF8String,
        NSStringFromCGAffineTransform(self.content.transform).UTF8String);
    printf("rootless-rotation-native-state: %s owns-orientation=%d autorotates=%d "
        "window-orientation=%ld app-orientation=%ld scene-orientation=%ld "
        "controller-orientation=%ld device-orientation=%ld window-frame=%s "
        "window-transform=%s presented=%p\n", stage,
        nativeBoolGetter(self.window, "_windowOwnsInterfaceOrientation"),
        nativeBoolGetter(self.window, "autorotates"),
        (long)nativeIntegerGetter(self.window, "_windowInterfaceOrientation"),
        (long)UIApplication.sharedApplication.statusBarOrientation,
        (long)self.window.windowScene.interfaceOrientation,
        (long)self.controller.interfaceOrientation,
        (long)UIDevice.currentDevice.orientation,
        NSStringFromCGRect(self.window.frame).UTF8String,
        NSStringFromCGAffineTransform(self.window.transform).UTF8String,
        (__bridge void *)self.controller.presentedViewController);
    unsigned depth = 0;
    for(CALayer *layer = self.window.layer; layer && depth < 4;
            layer = layer.superlayer, ++depth) {
        printf("rootless-rotation-backing-layer: %s depth=%u class=%s bounds=%s "
            "position=%s affine=%s\n", stage, depth, class_getName(layer.class),
            NSStringFromCGRect(layer.bounds).UTF8String,
            NSStringFromCGPoint(layer.position).UTF8String,
            NSStringFromCGAffineTransform(layer.affineTransform).UTF8String);
    }
}
- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    const uint32_t sdk = executableSDK();
    const uint32_t expectedSDK = [[NSBundle.mainBundle objectForInfoDictionaryKey:
        @"LC32ExpectedSDK"] unsignedIntValue];
    expectedEnabled = expectedSDK < 0x00080000;
    check("actual-sdk", sdk == expectedSDK);
    check("sdk-gate", LC32NativeLegacyRotationEnabled() == expectedEnabled);
    originalNativeRotationPolicy = nativeRotationPolicy();
    SEL maskSelector = @selector(supportedInterfaceOrientations);
    SEL preferredSelector = @selector(preferredInterfaceOrientationForPresentation);
    IMP originalMask = class_getMethodImplementation(
        RootlessRotationLegacyController.class, maskSelector);
    IMP originalPreferred = class_getMethodImplementation(
        RootlessRotationLegacyController.class, preferredSelector);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationLegacyController.class);
    IMP preparedMask = class_getMethodImplementation(
        RootlessRotationLegacyController.class, maskSelector);
    IMP preparedPreferred = class_getMethodImplementation(
        RootlessRotationLegacyController.class, preferredSelector);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationLegacyController.class);
    check("class-registration-is-idempotent",
        preparedMask == class_getMethodImplementation(
            RootlessRotationLegacyController.class, maskSelector) &&
        preparedPreferred == class_getMethodImplementation(
            RootlessRotationLegacyController.class, preferredSelector));
    if(!expectedEnabled)
        check("modern-sdk-class-policy-unchanged",
            preparedMask == originalMask && preparedPreferred == originalPreferred);

    NSArray<NSString *> *modernSelectors = @[@"supportedInterfaceOrientations", @"shouldAutorotate",
            @"preferredInterfaceOrientationForPresentation",
            @"shouldAutorotateToInterfaceOrientation:",
            @"willRotateToInterfaceOrientation:duration:", @"didRotateFromInterfaceOrientation:"];
    IMP modernBefore[6];
    for(NSUInteger index = 0; index < modernSelectors.count; ++index)
        modernBefore[index] = class_getMethodImplementation(
            RootlessRotationRegisteredModernController.class, NSSelectorFromString(modernSelectors[index]));
    LC32PrepareNativeLegacyRotationClass(RootlessRotationRegisteredModernController.class);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationRegisteredModernController.class);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationPolicyOnlyController.class);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationManualController.class);
    for(NSUInteger index = 0; index < modernSelectors.count; ++index) {
        check("registered-modern-method-implementation-preserved",
            class_getMethodImplementation(RootlessRotationRegisteredModernController.class,
                NSSelectorFromString(modernSelectors[index])) == modernBefore[index]);
    }

    IMP inheritedPreferred = class_getMethodImplementation(
        RootlessRotationInheritedPreferredController.class, preferredSelector);
    check("preferred-override-is-inherited",
        inheritedPreferred == class_getMethodImplementation(
            RootlessRotationPreferredBaseController.class, preferredSelector));
    LC32PrepareNativeLegacyRotationClass(RootlessRotationInheritedPreferredController.class);
    LC32PrepareNativeLegacyRotationClass(RootlessRotationInheritedPreferredController.class);
    check("inherited-preferred-implementation-preserved",
        class_getMethodImplementation(RootlessRotationInheritedPreferredController.class,
            preferredSelector) == inheritedPreferred);
    RootlessRotationInheritedPreferredController *preferred =
        [[RootlessRotationInheritedPreferredController alloc] init];
    check("inherited-preferred-result-preserved",
        preferred.preferredInterfaceOrientationForPresentation ==
            UIInterfaceOrientationLandscapeLeft);

    Class controllerClass = RootlessRotationLegacyController.class;
    if([testCase isEqualToString:@"modern"])
        controllerClass = RootlessRotationModernController.class;
    if([testCase isEqualToString:@"modern-explicit"] ||
            [testCase isEqualToString:@"modern-startup"])
        controllerClass = RootlessRotationRegisteredModernController.class;
    if([testCase isEqualToString:@"modern-only"])
        controllerClass = RootlessRotationPolicyOnlyController.class;
    if([testCase isEqualToString:@"unregistered"] ||
            [testCase isEqualToString:@"device-unregistered"])
        controllerClass = RootlessRotationUnregisteredController.class;
    if([testCase isEqualToString:@"manual-controller"])
        controllerClass = RootlessRotationManualController.class;
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[RootlessRotationWindow alloc] initWithFrame:bounds];
    self.controller = [[controllerClass alloc] init];
    if(expectedEnabled && self.controller && controllerClass == RootlessRotationLegacyController.class) {
        check("legacy-supported-mask", self.controller.supportedInterfaceOrientations ==
            UIInterfaceOrientationMaskLandscape);
        check("policy-query-does-not-probe-legacy-callback", legacyQueries == 0);
    }
    self.content = [[UIView alloc] initWithFrame:bounds];
    if([testCase isEqualToString:@"manual-controller"])
        [self.content addSubview:[[RootlessRotationGuestView alloc] initWithFrame:bounds]];
    self.initialContentFrame = self.content.frame;
    self.initialContentBounds = self.content.bounds;
    self.content.backgroundColor = UIColor.blueColor;
    [self.controller setView:self.content];
    if([testCase isEqualToString:@"modern-explicit"] ||
            ([testCase isEqualToString:@"modern-startup"] && !expectedEnabled)) {
        /* First let native UIKit configure a visible window with a non-guest
         * root, then attach the registered modern root after that setup. */
        self.safetyRoot = [[RootlessRotationNativeModernController alloc] init];
        self.window.rootViewController = self.safetyRoot;
    } else if(explicitRootCase && ![testCase isEqualToString:@"modern-startup"])
        self.window.rootViewController = self.controller;
    else
        [self.window addSubview:self.content];
    [self dumpState:"before-visible"];
    [self.window makeKeyAndVisible];
    if([testCase isEqualToString:@"modern-startup"]) {
        // iOS 6 engines attach the view, show the window, assign the root,
        // then immediately create a fixed-size renderer from its bounds.
        guestCallsAllowed = NO;
        self.window.rootViewController = self.controller;
        self.startupRenderer = [[UIView alloc] initWithFrame:self.content.bounds];
        [self.content addSubview:self.startupRenderer];
        RootlessRotationTrackingController *subject = (id)self.controller;
        check("startup-does-not-deliver-legacy-callbacks", subject.recordedQueries == 0 &&
            subject.recordedWillCalls == 0 && subject.recordedDidCalls == 0);
        if(expectedEnabled)
            check("startup-root-is-landscape-before-renderer-creation",
                self.content.bounds.size.width > self.content.bounds.size.height);
        guestCallsAllowed = YES;
    }
    if([testCase isEqualToString:@"modern-explicit"]) {
        check("modern-explicit-native-root-was-present", self.window.rootViewController == self.safetyRoot);
        self.window.rootViewController = self.controller;
    }
    [self dumpState:"after-visible"];
    self.visibleSubviewCount = self.window.subviews.count;
    [self.window makeKeyAndVisible];
    check("repeated-visible-is-idempotent",
        self.window.subviews.count == self.visibleSubviewCount);
    if(explicitRootCase)
        check("explicit-root-preserved", self.window.rootViewController == self.controller);
    if(!expectedEnabled && !explicitRootCase) {
        check("modern-sdk-no-adoption", self.window.rootViewController == nil);
        /* SDK8+ deliberately keeps production compatibility disabled. Supply
         * an unrelated native root only after checking that negative case, so
         * UIKit's modern launch invariant does not obscure our gate test. */
        self.safetyRoot = [[UIViewController alloc] init];
        self.window.rootViewController = self.safetyRoot;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
            if([testCase isEqualToString:@"modal"]) {
                self.modalController = [[UIViewController alloc] init];
                self.modalController.modalPresentationStyle = UIModalPresentationFullScreen;
                self.modalController.view.backgroundColor = UIColor.greenColor;
                [self.controller presentViewController:self.modalController animated:NO completion:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(), ^{ [self finishStartupAndScheduleChecks]; });
            } else {
                [self finishStartupAndScheduleChecks];
            }
        });
    return YES;
}
- (void)checkInitialBackingPresentation {
    NSString *key = @"lc32.initialPresentation";
    SEL refresh = sel_registerName("_updateTransformLayer");
    for(NSNumber *initiallyReady in @[@NO, @YES]) {
        startupSceneOrientation = initiallyReady.boolValue
            ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait;
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:self.window.windowScene];
        window.rootViewController = [RootlessRotationLegacyController new];
        window.alpha = 0.75;
        window.hidden = NO;
        void (^configure)(void) = ^{
            ((void (*)(id, SEL))objc_msgSend)(window, refresh);
        };
        configure();
        CALayer *backing = window.layer.superlayer.superlayer;
        CAAnimation *hold = [backing animationForKey:key];
        BOOL shouldHold = expectedEnabled && !initiallyReady.boolValue;
        check("only-provisional-backing-held", backing && (hold != nil) == shouldHold);
        if(hold) check("backing-presentation-fails-open",
            isfinite(hold.duration) && hold.duration > 0 && hold.removedOnCompletion);
        [backing removeAnimationForKey:key];
        configure();
        CAAnimation *remaining = [backing animationForKey:key];
        check("provisional-refresh-does-not-extend-hold", shouldHold
            ? remaining && remaining.duration <= hold.duration : !remaining);
        startupSceneOrientation = UIInterfaceOrientationLandscapeRight;
        configure();
        check("corrected-backing-uses-settling-transition",
            ([backing animationForKey:key] != nil) == shouldHold);
        CAAnimation *settling = [backing animationForKey:key];
        startupSceneOrientation = UIInterfaceOrientationPortrait;
        configure();
        check("later-turn-cannot-restart-settling-hold",
            [backing animationForKey:key].duration <= settling.duration);
        check("guest-window-model-and-key-status-preserved",
            !window.hidden && window.alpha == 0.75 && backing.opacity == 1 && !window.isKeyWindow);
        window.hidden = YES;
    }
}
- (void)finishStartupAndScheduleChecks {
    if([testCase isEqualToString:@"startup-scene-race"]) {
        Method sceneGetter = class_getInstanceMethod(UIWindowScene.class,
            @selector(interfaceOrientation));
        IMP saved = method_setImplementation(sceneGetter, (IMP)startupSceneOrientationProbe);
        const unsigned queries = legacyQueries, will = willRotateCalls, did = didRotateCalls;
        StartupLinkFixture *target = [StartupLinkFixture new];
        StartupLinkFixture *(^makeLink)(void) = ^{
            SEL action = @selector(record:);
            id receiver = LC32LegacyStartupDisplayLinkTarget(target, &action);
            return [StartupLinkFixture displayLinkWithTarget:receiver selector:action];
        };
        @try {
            for(NSNumber *value in @[@(UIInterfaceOrientationUnknown),
                    @(UIInterfaceOrientationPortrait), @(UIInterfaceOrientationPortraitUpsideDown)]) {
                startupSceneOrientation = value.integerValue;
                check("startup-waits-for-supported-scene",
                    LC32NativeLegacyRotationStartupSceneReady() == !expectedEnabled);
                LC32FinishNativeLegacyRotationStartup();
                check("provisional-scene-does-not-initialize-guest",
                    legacyQueries == queries && willRotateCalls == will && didRotateCalls == did);
            }
            StartupLinkFixture *link = makeLink();
            check("only-provisional-legacy-links-are-wrapped",
                (link.target != target) == expectedEnabled);
            link.timestamp = CACurrentMediaTime();
            [link fire];
            BOOL boundedWait = expectedEnabled &&
                UIApplication.sharedApplication.statusBarOrientationAnimationDuration > 0;
            check("provisional-tick-yields-to-scene", target.calls == (boundedWait ? 0u : 1u));
            startupSceneOrientation = UIInterfaceOrientationLandscapeLeft;
            [link fire];
            check("scene-change-has-a-frame-to-commit", target.calls == (boundedWait ? 0u : 2u));
            [link fire];
            check("original-target-receives-original-link", target.lastSender == link &&
                target.calls == (boundedWait ? 1u : 3u));
            check("already-supported-scene-retains-original-target", makeLink().target == target);
            startupSceneOrientation = UIInterfaceOrientationPortrait;
            unsigned delivered = target.calls;
            [link fire];
            check("later-ticks-never-start-waiting-again", target.calls == delivered + 1);
            StartupLinkFixture *timeout = makeLink();
            timeout.timestamp = CACurrentMediaTime();
            [timeout fire];
            delivered = target.calls;
            timeout.timestamp += UIApplication.sharedApplication.statusBarOrientationAnimationDuration + 1;
            [timeout fire];
            check("unresolved-scene-cannot-starve-link",
                target.calls == delivered + 1 && target.lastSender == timeout);
            StartupLinkFixture *late = makeLink();
            late.timestamp = timeout.timestamp + 1;
            startupSceneOrientation = UIInterfaceOrientationLandscapeRight;
            [late fire];
            check("late-first-tick-is-not-delayed", target.lastSender == late);
            [self checkInitialBackingPresentation];
        } @finally {
            method_setImplementation(sceneGetter, saved);
        }
        check("supported-scene-releases-startup", LC32NativeLegacyRotationStartupSceneReady());
        LC32FinishNativeLegacyRotationStartup();
        check("delayed-scene-initializes-guest",
            expectedEnabled ? legacyQueries > queries : legacyQueries == queries);
        unsigned settledQueries = legacyQueries;
        LC32FinishNativeLegacyRotationStartup();
        check("delayed-initialization-is-once-only", legacyQueries == settledQueries);
        [self finishAndExit];
        return;
    }
    if([testCase isEqualToString:@"initial-scene-update"]) {
        [self checkRotationUpdateOrdering];
        CALayer *probe = [CALayer layer];
        probe.frame = self.window.layer.bounds;
        probe.backgroundColor = UIColor.blueColor.CGColor;
        [self.window.layer addSublayer:probe];
        [CATransaction flush];
        usleep(100000);
        [CATransaction setDisableActions:YES];
        probe.opacity = 0.375f;
        SEL update = sel_registerName("_updateToInterfaceOrientation:duration:force:");
        Method original = class_getInstanceMethod(UIWindow.class, expectedEnabled
            ? sel_registerName("lc32_updateToInterfaceOrientation:duration:force:") : update);
        // Scene-era UIKit can do nothing here for a rootless window. The
        // production wrapper must still refresh and publish native backing.
        IMP saved = method_setImplementation(original, (IMP)nativeOrientationUpdateNoop);
        @try {
            ((void (*)(id, SEL, UIInterfaceOrientation, NSTimeInterval, BOOL))objc_msgSend)(
                self.window, update, self.window.windowScene.interfaceOrientation, 0, NO);
        } @finally {
            method_setImplementation(original, saved);
        }
        usleep(100000);
        check("early-scene-publishes-before-guest-loading",
            probe.presentationLayer && fabs(probe.presentationLayer.opacity -
                (expectedEnabled ? 0.375f : 1.0f)) < 0.001);
        check("early-scene-does-not-call-guest-rotation",
            legacyQueries == 0 && willRotateCalls == 0 && didRotateCalls == 0);
        if(expectedEnabled) [self checkNativeBackingGeometry];
        [self finishAndExit];
        return;
    }
    if([testCase isEqualToString:@"initial-backing"]) {
        if(expectedEnabled) [self checkNativeBackingGeometry];
        check("initial-backing-does-not-call-guest-rotation",
            legacyQueries == 0 && willRotateCalls == 0 && didRotateCalls == 0);
        [self finishAndExit];
        return;
    }
    if([testCase isEqualToString:@"scene-parameters"]) {
        id initial = sceneParametersRoundTrip(UIInterfaceOrientationPortrait);
        // Scene settings describe the host's actual orientation, not the
        // guest's preferred side. Backing setup must not rewrite either copy.
        check("initial-scene-keeps-native-orientation",
            [[initial settings] interfaceOrientation] == UIInterfaceOrientationPortrait &&
            [[initial clientSettings] interfaceOrientation] == UIInterfaceOrientationPortrait);
        check("initial-scene-preserves-native-frame", CGRectEqualToRect(
            [[initial settings] frame], CGRectMake(11, 13, 101, 203)));
        id supported = sceneParametersRoundTrip(UIInterfaceOrientationLandscapeLeft);
        check("initial-scene-keeps-supported-orientation",
            [[supported settings] interfaceOrientation] == UIInterfaceOrientationLandscapeLeft &&
            [[supported clientSettings] interfaceOrientation] == UIInterfaceOrientationLandscapeLeft);
        LC32FinishNativeLegacyRotationStartup();
        id later = sceneParametersRoundTrip(UIInterfaceOrientationPortrait);
        check("initial-scene-does-not-override-later-scenes",
            [[later settings] interfaceOrientation] == UIInterfaceOrientationPortrait &&
            [[later clientSettings] interfaceOrientation] == UIInterfaceOrientationPortrait);
        [self finishAndExit];
        return;
    }
    if([testCase isEqualToString:@"startup-commit"]) {
        // Deliberately keep the main run loop busy after startup, as a game
        // loading assets does. Presentation must not wait for another idle.
        CALayer *probe = [CALayer layer];
        probe.frame = self.window.layer.bounds;
        probe.backgroundColor = UIColor.blueColor.CGColor;
        [self.window.layer addSublayer:probe];
        [CATransaction flush];
        usleep(100000);
        [CATransaction setDisableActions:YES];
        probe.opacity = 0.375f;
        LC32FinishNativeLegacyRotationStartup();
        usleep(100000);
        check("startup-publishes-before-next-run-loop-turn",
            probe.presentationLayer && fabs(probe.presentationLayer.opacity -
                (expectedEnabled ? 0.375f : 1.0f)) < 0.001);
        [CATransaction setDisableActions:YES];
        probe.opacity = 0.625f;
        LC32FinishNativeLegacyRotationStartup();
        usleep(100000);
        check("startup-publication-is-once-only",
            probe.presentationLayer && fabs(probe.presentationLayer.opacity -
                (expectedEnabled ? 0.375f : 1.0f)) < 0.001);
        [probe removeFromSuperlayer];
        [self finishAndExit];
        return;
    }
    if([testCase hasPrefix:@"device-"]) {
        [self checkInitialDeviceOrientation];
        [self finishAndExit];
        return;
    }
    if([testCase isEqualToString:@"modal"]) {
        check("modal-presented-before-startup",
            self.controller.presentedViewController == self.modalController &&
            self.modalController.presentingViewController == self.controller);
        self.queriesWhileModalPresented = legacyQueries;
    }
    LC32FinishNativeLegacyRotationStartup();
    LC32FinishNativeLegacyRotationStartup();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
            if([testCase isEqualToString:@"replacement"])
                [self replaceRootlessController];
            else
                [self finish];
        });
}
- (void)checkInitialDeviceOrientation {
    UIDeviceOrientation physical = UIDeviceOrientationFaceUp;
    if([testCase isEqualToString:@"device-face-down"]) physical = UIDeviceOrientationFaceDown;
    if([testCase isEqualToString:@"device-unknown"]) physical = UIDeviceOrientationUnknown;
    if([testCase isEqualToString:@"device-portrait"]) physical = UIDeviceOrientationPortrait;
    if([testCase isEqualToString:@"device-landscape"]) physical = UIDeviceOrientationLandscapeLeft;
    UIInterfaceOrientation scene = self.window.windowScene.interfaceOrientation;
    check("initial-device-scene-is-landscape", UIInterfaceOrientationIsLandscape(scene));
    startupDeviceGenerating = ![testCase isEqualToString:@"device-no-observers"];
    guestCallsAllowed = ![testCase isEqualToString:@"device-disabled"];
    requestedDeviceOrientation = physical;
    Method getter = class_getInstanceMethod(UIDevice.class, @selector(orientation));
    Method generating = class_getInstanceMethod(UIDevice.class,
        @selector(isGeneratingDeviceOrientationNotifications));
    Method setter = class_getInstanceMethod(UIDevice.class, sel_registerName("setOrientation:animated:"));
    check("initial-device-native-methods-present", getter && generating && setter);
    if(!getter || !generating || !setter) return;
    IMP oldGetter = method_setImplementation(getter, (IMP)deviceOrientationProbe);
    IMP oldGenerating = method_setImplementation(generating, (IMP)startupDeviceGeneratingProbe);
    IMP oldSetter = method_setImplementation(setter, (IMP)startupDeviceSetterProbe);
    NSMutableArray<NSNumber *> *events = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:
        UIDeviceOrientationDidChangeNotification object:UIDevice.currentDevice queue:nil
        usingBlock:^(NSNotification *note) {
            [events addObject:@([(UIDevice *)note.object orientation])];
        }];
    BOOL shouldInitialize = expectedEnabled && startupDeviceGenerating && guestCallsAllowed &&
        !UIDeviceOrientationIsLandscape(physical) &&
        ![testCase isEqualToString:@"device-unregistered"];
    @try {
        LC32FinishNativeLegacyRotationStartup();
        NSArray *expected = shouldInitialize ? @[@(scene), @(physical)] : @[];
        check("initial-device-scene-event-then-physical-reading", [events isEqual:expected]);
        check("initial-device-only-native-notification-path",
            startupDeviceSetterCalls == (shouldInitialize ? 2u : 0u));
        check("initial-device-no-startup-animation", !startupDeviceAnimated);
        check("initial-device-physical-reading-restored", UIDevice.currentDevice.orientation == physical);
        unsigned calls = startupDeviceSetterCalls;
        LC32FinishNativeLegacyRotationStartup();
        check("initial-device-bootstrap-is-once-only", startupDeviceSetterCalls == calls &&
            [events isEqual:expected]);
        if(shouldInitialize) {
            check("initial-device-controller-keeps-scene-orientation",
                self.controller.interfaceOrientation == scene);
            check("initial-device-layout-remains-landscape",
                self.content.bounds.size.width > self.content.bounds.size.height);
        }
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        method_setImplementation(getter, oldGetter);
        method_setImplementation(generating, oldGenerating);
        method_setImplementation(setter, oldSetter);
        guestCallsAllowed = YES;
    }
}
- (void)replaceRootlessController {
    RootlessRotationTrackingController *previous = (id)self.controller;
    check("replacement-first-controller-queried-once",
        previous.recordedQueries == (expectedEnabled ? 1U : 0U));
    if(expectedEnabled)
        check("replacement-first-controller-remains-rootless", self.window.rootViewController == nil);
    self.replacedController = previous;
    [self.content removeFromSuperview];
    RootlessRotationLegacyController *replacement = [[RootlessRotationLegacyController alloc] init];
    self.content = [[UIView alloc] initWithFrame:self.initialContentFrame];
    self.content.backgroundColor = UIColor.orangeColor;
    replacement.view = self.content;
    self.controller = replacement;
    /* No production reset seam or root setter: discovering a different direct
     * child must invalidate the prior controller's per-window startup state. */
    if(expectedEnabled)
        [self.window addSubview:self.content];
    else
        self.window.rootViewController = replacement;
    LC32FinishNativeLegacyRotationStartup();
    LC32FinishNativeLegacyRotationStartup();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ [self finish]; });
}
- (void)checkManualDisabledOutput {
    SEL originalSelector = sel_registerName(
        "lc32_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    SEL wrappedSelector = sel_registerName(
        "_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    Method original = class_getInstanceMethod(UIWindow.class, originalSelector);
    Method wrapped = class_getInstanceMethod(UIWindow.class, wrappedSelector);
    check("manual-disabled-production-adapter-present", original && wrapped);
    if(!original || !wrapped) return;
    IMP savedOriginal = method_setImplementation(original, (IMP)nativeAllowsRotation);
    @try {
        const unsigned queriesBefore = legacyQueries;
        BOOL disabled = YES;
        BOOL allowed = ((BOOL (*)(id, SEL, UIInterfaceOrientation, BOOL, BOOL *))objc_msgSend)(
            self.window, wrappedSelector, UIInterfaceOrientationLandscapeRight, NO, &disabled);
        check("manual-disabled-refusal-returned", !allowed);
        check("manual-disabled-native-output-preserved", !disabled);
        check("manual-disabled-exactly-one-query", legacyQueries == queriesBefore + 1);
        check("manual-disabled-exact-candidate",
            lastLegacyOrientation == UIInterfaceOrientationLandscapeRight);
    } @finally {
        method_setImplementation(original, savedOriginal);
    }
    check("manual-disabled-original-imp-restored",
        method_getImplementation(original) == savedOriginal);
}
- (void)checkModalNativePermission {
    SEL originalSelector = sel_registerName(
        "lc32_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    SEL wrappedSelector = sel_registerName(
        "_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    Method original = class_getInstanceMethod(UIWindow.class, originalSelector);
    Method wrapped = class_getInstanceMethod(UIWindow.class, wrappedSelector);
    check("modal-production-adapter-present", original && wrapped);
    if(!original || !wrapped) return;
    IMP savedOriginal = method_setImplementation(original, (IMP)nativeAllowsRotation);
    @try {
        const unsigned queriesBefore = legacyQueries;
        BOOL disabled = YES;
        BOOL allowed = ((BOOL (*)(id, SEL, UIInterfaceOrientation, BOOL, BOOL *))objc_msgSend)(
            self.window, wrappedSelector, UIInterfaceOrientationLandscapeRight, NO, &disabled);
        check("modal-native-allowance-preserved", allowed);
        check("modal-native-disabled-output-preserved", !disabled);
        check("modal-window-gate-does-not-query-covered-root", legacyQueries == queriesBefore);
    } @finally {
        method_setImplementation(original, savedOriginal);
    }
    check("modal-original-imp-restored", method_getImplementation(original) == savedOriginal);
}
- (void)checkDirectLifecycleForwarding {
    SEL willSelector = sel_registerName(
        "window:willRotateToInterfaceOrientation:duration:newSize:");
    SEL didSelector = sel_registerName(
        "window:didRotateFromInterfaceOrientation:oldSize:");
    Method willMethod = class_getInstanceMethod(UIViewController.class, willSelector);
    Method didMethod = class_getInstanceMethod(UIViewController.class, didSelector);
    check("lifecycle-native-entrypoints-present", willMethod && didMethod);
    if(!willMethod || !didMethod) return;
    const NSTimeInterval duration = 0.375000000123;
    const UIInterfaceOrientation newOrientation = UIInterfaceOrientationLandscapeLeft;
    const UIInterfaceOrientation oldOrientation = UIInterfaceOrientationLandscapeRight;
    NSArray<Class> *classes = @[RootlessRotationLegacyController.class,
        RootlessRotationModernController.class, RootlessRotationRegisteredModernController.class,
        RootlessRotationUnregisteredController.class, RootlessRotationNativeModernController.class];
    for(unsigned wrapped = 0; wrapped < 2; ++wrapped)
    for(Class cls in classes) {
        RootlessRotationTrackingController *subject = [[cls alloc] init];
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        subject.view = [[UIView alloc] initWithFrame:window.bounds];
        UIViewController *recipient = subject;
        if(wrapped) {
            RootlessRotationCanvasController *canvas = [RootlessRotationCanvasController new];
            // Exercise the real installation order: the root is briefly empty.
            window.rootViewController = canvas;
            [canvas addChildViewController:subject];
            [canvas.view addSubview:subject.view];
            [subject didMoveToParentViewController:canvas];
            canvas.guestContentController = subject;
            recipient = canvas;
        } else {
            window.rootViewController = subject;
        }
        const unsigned queriesBefore = subject.recordedQueries;
        const unsigned willBefore = subject.recordedWillCalls;
        const unsigned didBefore = subject.recordedDidCalls;
        ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, NSTimeInterval, CGSize))objc_msgSend)(
            recipient, willSelector, window, newOrientation, duration, CGSizeMake(480, 320));
        ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, CGSize))objc_msgSend)(
            recipient, didSelector, window, oldOrientation, CGSizeMake(320, 480));
        const unsigned expectedCalls = expectedEnabled &&
            (cls == RootlessRotationLegacyController.class ||
             cls == RootlessRotationModernController.class ||
             cls == RootlessRotationRegisteredModernController.class) ? 1 : 0;
        printf("rootless-rotation-direct-lifecycle: class=%s wrapped=%u expected=%u "
            "will-delta=%u did-delta=%u queries-delta=%u will-orientation=%ld "
            "did-orientation=%ld duration=%a\n", class_getName(cls), wrapped, expectedCalls,
            subject.recordedWillCalls - willBefore, subject.recordedDidCalls - didBefore,
            subject.recordedQueries - queriesBefore, (long)subject.recordedWillOrientation,
            (long)subject.recordedDidOrientation, subject.recordedDuration);
        check("lifecycle-exact-will-call-count",
            subject.recordedWillCalls == willBefore + expectedCalls);
        check("lifecycle-exact-did-call-count",
            subject.recordedDidCalls == didBefore + expectedCalls);
        check("lifecycle-no-orientation-policy-probes", subject.recordedQueries == queriesBefore);
        if(expectedCalls) {
            check("lifecycle-will-orientation-forwarded", subject.recordedWillOrientation == newOrientation);
            check("lifecycle-did-old-orientation-forwarded", subject.recordedDidOrientation == oldOrientation);
            check("lifecycle-double-duration-forwarded-exactly", subject.recordedDuration == duration);
        }
        const unsigned willAfter = subject.recordedWillCalls;
        const unsigned didAfter = subject.recordedDidCalls;
        guestCallsAllowed = NO;
        @try {
            ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, NSTimeInterval, CGSize))objc_msgSend)(
                recipient, willSelector, window, newOrientation, duration, CGSizeMake(480, 320));
            ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, CGSize))objc_msgSend)(
                recipient, didSelector, window, oldOrientation, CGSizeMake(320, 480));
        } @finally {
            guestCallsAllowed = YES;
        }
        check("lifecycle-retains-guest-context-guard", subject.recordedWillCalls == willAfter &&
            subject.recordedDidCalls == didAfter);
        window.hidden = YES;
    }
    puts("rootless-rotation-direct-lifecycle-scope: callback forwarding only; "
         "this case does not claim an automatic compositor rotation");
}
- (void)checkAcceptedTurnLifecycle:(unsigned)turn {
    // Exercise the production notification -> UpdateWindow -> UIKit path,
    // rather than invoking the lifecycle forwarding aliases directly.
    RootlessRotationTrackingController *subject = (id)self.controller;
    Method orientationMethod = class_getInstanceMethod(UIDevice.class, @selector(orientation));
    IMP saved = method_setImplementation(orientationMethod, (IMP)deviceOrientationProbe);
    UIInterfaceOrientation previous = subject.interfaceOrientation;
    UIInterfaceOrientation target = previous == UIInterfaceOrientationLandscapeLeft
        ? UIInterfaceOrientationLandscapeRight : UIInterfaceOrientationLandscapeLeft;
    requestedDeviceOrientation = (UIDeviceOrientation)target;
    unsigned willBefore = subject.recordedWillCalls;
    unsigned didBefore = subject.recordedDidCalls;
    unsigned turnsBefore = self.window.clientTurns;
    [NSNotificationCenter.defaultCenter postNotificationName:
        UIDeviceOrientationDidChangeNotification object:UIDevice.currentDevice];
    check("accepted-turn-updates-interface", subject.interfaceOrientation == target);
    check("accepted-turn-delivers-one-will", subject.recordedWillCalls == willBefore + 1);
    if(!self.window.rootViewController) {
        check("rootless-turn-uses-native-animation-duration", self.window.clientDuration ==
            UIApplication.sharedApplication.statusBarOrientationAnimationDuration);
        [NSNotificationCenter.defaultCenter postNotificationName:
            UIDeviceOrientationDidChangeNotification object:UIDevice.currentDevice];
        check("rootless-duplicate-does-not-restart-native-turn",
            self.window.clientTurns == turnsBefore + 1);
    }
    // Yield the main queue so UIKit can commit the animation and deliver its
    // completion. A nested run loop cannot drain this main-queue finish block.
    NSTimeInterval wait = fmin(2, fmax(0, subject.recordedDuration)) + 0.1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, wait * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        check("accepted-turn-delivers-one-did", subject.recordedDidCalls == didBefore + 1);
        check("accepted-turn-callback-orientations", subject.recordedWillOrientation == target &&
            subject.recordedDidOrientation == previous);
        [NSNotificationCenter.defaultCenter postNotificationName:
            UIDeviceOrientationDidChangeNotification object:UIDevice.currentDevice];
        check("same-orientation-refresh-does-not-repeat-lifecycle",
            subject.recordedWillCalls == willBefore + 1 &&
            subject.recordedDidCalls == didBefore + 1);
        if(!self.window.rootViewController)
            check("rootless-settled-duplicate-does-not-force-layout",
                self.window.clientTurns == turnsBefore + 1);
        method_setImplementation(orientationMethod, saved);
        if(turn == 0) [self checkAcceptedTurnLifecycle:1];
        else [self finishAndExit];
    });
}
- (void)checkRotationUpdateOrdering {
    SEL originalSelector = sel_registerName("lc32_updateToInterfaceOrientation:duration:force:");
    SEL selector = sel_registerName("_updateToInterfaceOrientation:duration:force:");
    Method update = class_getInstanceMethod(UIWindow.class, selector);
    Method original = class_getInstanceMethod(UIWindow.class, originalSelector);
    check("rotation-update-entrypoints-present", update && original);
    if(!update || !original) return;
    Dl_info updateInfo = {0};
    BOOL resolved = dladdr((const void *)method_getImplementation(update), &updateInfo) != 0;
    check("rotation-update-hook-matches-sdk-gate", resolved &&
        (updateInfo.dli_fbase == _dyld_get_image_header(0)) == expectedEnabled);
    if(!expectedEnabled) return;
    for(unsigned layout = 0; layout < 8; ++layout)
    for(Class cls in @[RootlessRotationLegacyController.class,
            RootlessRotationPolicyOnlyController.class, RootlessRotationNativeModernController.class]) {
        const BOOL rootless = layout == 1;
        RootlessRotationRefreshWindow *window = [[RootlessRotationRefreshWindow alloc]
            initWithFrame:CGRectMake(0, 0, 320, 480)];
        UIViewController *controller = [[cls alloc] init];
        controller.view = [[RootlessRotationGuestView alloc] initWithFrame:window.bounds];
        if(layout >= 2) {
            window.rootViewController = backingProbeContainer(controller, layout);
        } else {
            if(!rootless) window.rootViewController = controller;
            if(controller.view.superview != window) [window addSubview:controller.view];
        }
        window.recordRefreshes = YES;
        window.refreshes = 0;
        updateProbeCalls = 0;
        IMP saved = method_setImplementation(original, (IMP)nativeOrientationUpdateProbe);
        @try {
            ((void (*)(id, SEL, UIInterfaceOrientation, NSTimeInterval, BOOL))objc_msgSend)(
                window, selector, UIInterfaceOrientationLandscapeLeft, 0.375, YES);
        } @finally {
            method_setImplementation(original, saved);
        }
        BOOL guest = layout < 5 && cls != RootlessRotationNativeModernController.class &&
            (!rootless || cls == RootlessRotationPolicyOnlyController.class ||
                [testCase isEqualToString:@"initial-scene-update"]);
        check("rotation-update-original-called-once", updateProbeCalls == 1);
        check("rotation-update-arguments-preserved", updateProbeArguments);
        check("rotation-update-backing-before-client", updateProbeRefreshes == (guest ? 1u : 0u));
        check("rotation-update-backing-after-client", window.refreshes == (guest ? 2u : 0u));
        window.recordRefreshes = NO;
        window.hidden = YES;
    }
}
- (void)checkModernNativePermission {
    SEL originalSelector = sel_registerName(
        "lc32_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    SEL wrappedSelector = sel_registerName(
        "_shouldAutorotateToInterfaceOrientation:checkForDismissal:isRotationDisabled:");
    Method original = class_getInstanceMethod(UIWindow.class, originalSelector);
    check("modern-production-policy-adapter-present", original != NULL);
    if(!original || !expectedEnabled) return;
    IMP saved = method_getImplementation(original);
    @try {
        for(Class cls in @[RootlessRotationModernController.class,
                RootlessRotationRegisteredModernController.class,
                RootlessRotationNativeModernController.class]) {
            UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
            RootlessRotationTrackingController *subject = [[cls alloc] init];
            subject.view = [[UIView alloc] initWithFrame:window.bounds];
            window.rootViewController = subject;
            for(unsigned allows = 0; allows < 2; ++allows) {
                method_setImplementation(original,
                    allows ? (IMP)nativeAllowsRotation : (IMP)nativeDisallowsRotation);
                unsigned before = subject.recordedQueries;
                BOOL disabled = allows;
                /* The old query rejects portrait. An accidental legacy-policy
                 * check would therefore turn the native YES into NO. */
                BOOL result = ((BOOL (*)(id, SEL, UIInterfaceOrientation, BOOL, BOOL *))objc_msgSend)(
                    window, wrappedSelector, UIInterfaceOrientationPortrait, NO, &disabled);
                printf("rootless-rotation-modern-policy: class=%s native=%u result=%d disabled=%d\n",
                    class_getName(cls), allows, result, disabled);
                check("modern-native-rotation-result-preserved", result == (BOOL)allows);
                check("modern-native-disabled-output-preserved", disabled == !allows);
                check("modern-policy-does-not-query-legacy-callback", subject.recordedQueries == before);
            }
            method_setImplementation(original, saved);
            window.hidden = YES;
        }
    } @finally {
        method_setImplementation(original, saved);
    }
    check("modern-native-policy-imp-restored", method_getImplementation(original) == saved);
}
- (void)checkQueuedModernBackingRefresh {
    SEL move = sel_registerName("viewDidMoveToWindow:shouldAppearOrDisappear:");
    SEL originalMove = sel_registerName("lc32_rotationViewDidMoveToWindow:shouldAppearOrDisappear:");
    Method original = class_getInstanceMethod(UIViewController.class, originalMove);
    check("modern-refresh-move-entrypoint-present", original &&
        class_getInstanceMethod(UIViewController.class, move));
    if(!original || !expectedEnabled) {
        self.completedRefreshProbe = YES;
        [self finish];
        return;
    }
    NSArray<NSString *> *labels = @[@"attached", @"replaced", @"detached", @"native", @"rootless", @"unloaded",
        @"navigation", @"navigation-replaced"];
    NSMutableArray<RootlessRotationRefreshWindow *> *windows = [NSMutableArray array];
    NSMutableArray<RootlessRotationTrackingController *> *controllers = [NSMutableArray array];
    for(NSUInteger index = 0; index < labels.count; ++index) {
        RootlessRotationRefreshWindow *window = [[RootlessRotationRefreshWindow alloc]
            initWithFrame:CGRectMake(0, 0, 320, 480)];
        Class cls = index == 3 ? RootlessRotationNativeModernController.class :
            RootlessRotationRegisteredModernController.class;
        RootlessRotationTrackingController *controller = [[cls alloc] init];
        controller.view = [[UIView alloc] initWithFrame:window.bounds];
        if(index >= 6) window.rootViewController = backingProbeContainer(controller, 3);
        else if(index == 4) [window addSubview:controller.view];
        else window.rootViewController = controller;
        /* Hidden windows need explicit attachment on some UIKit versions. */
        if(index >= 6) {
            [window addSubview:window.rootViewController.view];
            [window.rootViewController.view addSubview:controller.view];
        } else if(controller.view.superview != window) [window addSubview:controller.view];
        [windows addObject:window];
        [controllers addObject:controller];
    }
    /* Drain any work from fixture setup before counting the deliberately
     * queued production requests. None of these windows is made visible. */
    dispatch_async(dispatch_get_main_queue(), ^{
        IMP saved = method_setImplementation(original, (IMP)nativeViewMoveNoop);
        @try {
            for(NSUInteger index = 0; index < windows.count; ++index)
                ((void (*)(id, SEL, UIWindow *, BOOL))objc_msgSend)(
                    controllers[index], move, windows[index], YES);
        } @finally {
            method_setImplementation(original, saved);
        }
        check("modern-refresh-original-move-imp-restored", method_getImplementation(original) == saved);
        windows[1].rootViewController = [[RootlessRotationNativeModernController alloc] init];
        [(UINavigationController *)windows[7].rootViewController
            setViewControllers:@[[RootlessRotationNativeModernController new]]];
        [controllers[2].view removeFromSuperview];
        [controllers[5] setView:nil];
        for(RootlessRotationRefreshWindow *window in windows) {
            window.refreshes = 0;
            window.recordRefreshes = YES;
        }
        unsigned queries = legacyQueries, will = willRotateCalls, did = didRotateCalls;
        guestCallsAllowed = NO;
        @try {
            LC32FinishNativeLegacyRotationStartup();
        } @finally {
            guestCallsAllowed = YES;
        }
        for(NSUInteger index = 0; index < windows.count; ++index) {
            printf("rootless-rotation-modern-settled-refresh: state=%s requests=%u guest-calls=disabled\n",
                labels[index].UTF8String, windows[index].refreshes);
            check("modern-settled-backing-refresh-independent-of-guest-callback-permission",
                windows[index].refreshes == (index == 0 || index == 4 || index == 6 ? 1u : 0u));
            windows[index].refreshes = 0;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            for(NSUInteger index = 0; index < windows.count; ++index) {
                printf("rootless-rotation-modern-refresh: state=%s requests=%u\n",
                    labels[index].UTF8String, windows[index].refreshes);
                check("modern-refresh-only-current-attached-guest-root",
                    windows[index].refreshes == (index == 0 || index == 4 || index == 6 ? 1u : 0u));
                windows[index].recordRefreshes = NO;
            }
            check("modern-refresh-does-not-query-or-synthesize-legacy-callbacks",
                legacyQueries == queries && willRotateCalls == will && didRotateCalls == did);
            check("modern-refresh-replacement-root-preserved",
                windows[1].rootViewController != controllers[1]);
            check("modern-refresh-detached-view-not-reattached", controllers[2].view.window == nil);
            check("modern-refresh-rootless-controller-not-adopted", windows[4].rootViewController == nil);
            check("modern-refresh-unloaded-view-not-reloaded", controllers[5].viewIfLoaded == nil);
            self.completedRefreshProbe = YES;
            [self finish];
        });
    });
}
- (void)checkScopedOwnership {
    SEL configure = sel_registerName("_configureRootLayer:sceneTransformLayer:transformLayer:");
    SEL originalConfigure = sel_registerName("lc32_configureRootLayer:sceneTransformLayer:transformLayer:");
    SEL originalOrientation = sel_registerName("lc32_windowOwnsInterfaceOrientation");
    SEL originalTransform = sel_registerName("lc32_windowOwnsInterfaceOrientationTransform");
    Method configureMethod = class_getInstanceMethod(UIWindow.class, configure);
    Method savedConfigureMethod = class_getInstanceMethod(UIWindow.class, originalConfigure);
    Method savedOrientationMethod = class_getInstanceMethod(UIWindow.class, originalOrientation);
    Method savedTransformMethod = class_getInstanceMethod(UIWindow.class, originalTransform);
    check("ownership-production-entrypoints-present", configureMethod && savedConfigureMethod &&
        savedOrientationMethod && savedTransformMethod);
    if(!configureMethod || !savedConfigureMethod || !savedOrientationMethod || !savedTransformMethod) return;
    Dl_info configureInfo = {0};
    BOOL resolvedConfigure = dladdr((const void *)method_getImplementation(configureMethod),
        &configureInfo) != 0;
    BOOL usesProductionHook = resolvedConfigure &&
        configureInfo.dli_fbase == _dyld_get_image_header(0);
    check("ownership-configure-hook-matches-sdk-gate",
        resolvedConfigure && usesProductionHook == expectedEnabled);
    if(!expectedEnabled) {
        /* No aliases are replaced in SDK8+ processes. Calling an uninstalled
         * category method directly would not test the production SDK gate. */
        return;
    }
    NSArray<Class> *classes = @[RootlessRotationLegacyController.class,
        RootlessRotationModernController.class, RootlessRotationRegisteredModernController.class,
        RootlessRotationUnregisteredController.class, RootlessRotationNativeModernController.class];
    for(unsigned layout = 0; layout < 8; ++layout) for(Class cls in classes) {
        const BOOL rootless = layout == 1;
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        UIWindow *otherWindow = [[UIWindow alloc] initWithFrame:window.frame];
        UIViewController *controller = [[cls alloc] init];
        controller.view = [[UIView alloc] initWithFrame:window.bounds];
        if(rootless) [window addSubview:controller.view];
        else window.rootViewController = backingProbeContainer(controller, layout);
        const BOOL nativeOrientation = nativeBoolGetter(window, "_windowOwnsInterfaceOrientation");
        const BOOL nativeTransform = nativeBoolGetter(window, "_windowOwnsInterfaceOrientationTransform");
        CALayer *root = CALayer.layer;
        CALayer *scene = CALayer.layer;
        CALayer *transform = CALayer.layer;
        [root addSublayer:scene];
        [scene addSublayer:transform];
        ownershipOtherWindow = otherWindow;
        ownershipExpectedRoot = root;
        ownershipExpectedScene = scene;
        ownershipExpectedTransform = transform;
        IMP savedConfigure = method_setImplementation(savedConfigureMethod, (IMP)nativeConfigureOwnershipProbe);
        IMP savedOrientation = method_setImplementation(savedOrientationMethod, (IMP)nativeDoesNotOwnOrientation);
        IMP savedTransform = method_setImplementation(savedTransformMethod, (IMP)nativeDoesNotOwnOrientation);
        @try {
            for(unsigned attempt = 0; attempt < 4; ++attempt) {
                ownershipThrow = (attempt & 1) != 0;
                ownershipCalls = 0;
                // Nonzero origins, an off-center anchor and a preexisting
                // child transform exercise composition, not a screen size.
                root.bounds = CGRectMake(7, 11, 317, 509);
                root.anchorPoint = CGPointMake(0.3, 0.6);
                root.position = CGPointMake(271, 199);
                root.affineTransform = CGAffineTransformMakeRotation(
                    attempt < 2 ? M_PI_2 : -M_PI_2);
                scene.bounds = CGRectMake(3, 5, 317, 509);
                scene.position = CGPointMake(171, 219);
                scene.affineTransform = CGAffineTransformMakeScale(0.8, 1.2);
                CGRect originalFrame = root.frame;
                CGPoint points[] = {{3, 5}, {89, 173}, {320, 514}};
                CGPoint expectedPoints[3];
                for(unsigned point = 0; point < 3; ++point)
                    expectedPoints[point] = [scene convertPoint:points[point] toLayer:nil];
                BOOL caught = NO;
                @try {
                    ((void (*)(id, SEL, CALayer *, CALayer *, CALayer *))objc_msgSend)(
                        window, configure, root, scene, transform);
                } @catch(NSException *exception) {
                    caught = [exception.name isEqualToString:@"LC32OwnershipProbe"];
                    if(!caught) @throw;
                }
                BOOL backingEligible = layout < 5 && (cls == RootlessRotationLegacyController.class ||
                    cls == RootlessRotationModernController.class ||
                    cls == RootlessRotationRegisteredModernController.class);
                printf("rootless-rotation-ownership-probe: class=%s layout=%u exception=%d "
                    "orientation=%d transform=%d unrelated=%d/%d\n",
                    class_getName(cls), layout, ownershipThrow, ownershipObservedOrientation,
                    ownershipObservedTransform, ownershipObservedOtherOrientation,
                    ownershipObservedOtherTransform);
                check("ownership-original-called-once", ownershipCalls == 1);
                check("ownership-layer-arguments-preserved", ownershipArgumentsPreserved);
                check("ownership-enabled-only-for-eligible-window",
                    ownershipObservedOrientation == backingEligible &&
                    ownershipObservedTransform == backingEligible);
                check("ownership-other-window-unchanged",
                    !ownershipObservedOtherOrientation && !ownershipObservedOtherTransform);
                check("ownership-original-exception-preserved", caught == ownershipThrow);
                check("backing-root-normalized-only-for-successful-legacy-call",
                    CGAffineTransformIsIdentity(root.affineTransform) ==
                        (backingEligible && !ownershipThrow));
                CGRect actualFrame = root.frame;
                check("backing-root-frame-preserved",
                    fabs(actualFrame.origin.x - originalFrame.origin.x) < 0.001 &&
                    fabs(actualFrame.origin.y - originalFrame.origin.y) < 0.001 &&
                    fabs(actualFrame.size.width - originalFrame.size.width) < 0.001 &&
                    fabs(actualFrame.size.height - originalFrame.size.height) < 0.001);
                for(unsigned point = 0; point < 3; ++point) {
                    CGPoint actual = [scene convertPoint:points[point] toLayer:nil];
                    check("backing-point-mapping-preserved",
                        fabs(actual.x - expectedPoints[point].x) < 0.001 &&
                        fabs(actual.y - expectedPoints[point].y) < 0.001);
                }
                check("ownership-restored-after-original-returns-or-throws",
                    !nativeBoolGetter(window, "_windowOwnsInterfaceOrientation") &&
                    !nativeBoolGetter(window, "_windowOwnsInterfaceOrientationTransform"));
            }
        } @finally {
            method_setImplementation(savedConfigureMethod, savedConfigure);
            method_setImplementation(savedOrientationMethod, savedOrientation);
            method_setImplementation(savedTransformMethod, savedTransform);
            ownershipOtherWindow = nil;
            ownershipExpectedRoot = nil;
            ownershipExpectedScene = nil;
            ownershipExpectedTransform = nil;
        }
        check("ownership-probe-original-methods-restored",
            method_getImplementation(savedConfigureMethod) == savedConfigure &&
            method_getImplementation(savedOrientationMethod) == savedOrientation &&
            method_getImplementation(savedTransformMethod) == savedTransform);
        check("ownership-native-outside-policy-preserved",
            nativeBoolGetter(window, "_windowOwnsInterfaceOrientation") == nativeOrientation &&
            nativeBoolGetter(window, "_windowOwnsInterfaceOrientationTransform") == nativeTransform);
        window.hidden = YES;
    }
}
- (void)checkBackingAnimation {
    if(!expectedEnabled) return;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 317, 509)];
    window.rootViewController = [RootlessRotationLegacyController new];
    CALayer *root = CALayer.layer, *scene = CALayer.layer, *transform = CALayer.layer;
    [root addSublayer:scene];
    [scene addSublayer:transform];
    BackingAnimationProbe *rootProbe = [BackingAnimationProbe new];
    BackingAnimationProbe *sceneProbe = [BackingAnimationProbe new];
    SEL configure = sel_registerName("_configureRootLayer:sceneTransformLayer:transformLayer:");
    Method original = class_getInstanceMethod(UIWindow.class,
        sel_registerName("lc32_configureRootLayer:sceneTransformLayer:transformLayer:"));
    IMP saved = method_setImplementation(original, (IMP)nativeConfigureAnimationProbe);
    @try {
        for(unsigned turn = 0; turn < 4; ++turn) {
            BOOL disabled = turn >= 2;
            animationProbeAngle = (turn & 1) ? -M_PI_2 : M_PI_2;
            CGAffineTransform previous = CGAffineTransformMakeRotation(-animationProbeAngle);
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            root.bounds = CGRectMake(0, 0, 509, 317);
            root.position = CGPointMake(254.5, 158.5);
            root.affineTransform = CGAffineTransformIdentity;
            scene.bounds = CGRectMake(0, 0, 317, 509);
            scene.position = CGPointMake(254.5, 158.5);
            scene.affineTransform = previous;
            [CATransaction commit];
            root.delegate = rootProbe;
            scene.delegate = sceneProbe;
            rootProbe.transformActions = sceneProbe.transformActions = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:disabled];
            [CATransaction setAnimationDuration:0.6];
            ((void (*)(id, SEL, CALayer *, CALayer *, CALayer *))objc_msgSend)(
                window, configure, root, scene, transform);
            check("backing-animation-preserves-transaction-policy",
                CATransaction.disableActions == disabled && CATransaction.animationDuration == 0.6);
            [CATransaction commit];
            check("backing-animation-root-remains-upright", CGAffineTransformIsIdentity(root.affineTransform));
            check("backing-animation-scene-final-transform", CGAffineTransformEqualToTransform(
                scene.affineTransform, CGAffineTransformMakeRotation(animationProbeAngle)));
            if(disabled) {
                check("backing-animation-disabled-actions-preserved",
                    !rootProbe.transformActions && !sceneProbe.transformActions);
            } else {
                check("backing-animation-no-temporary-root-start",
                    !rootProbe.transformActions || CGAffineTransformIsIdentity(rootProbe.fromTransform));
                check("backing-animation-starts-at-previous-scene-transform",
                    sceneProbe.transformActions == 1 &&
                    CGAffineTransformEqualToTransform(sceneProbe.fromTransform, previous));
            }
        }
    } @finally {
        method_setImplementation(original, saved);
        root.delegate = scene.delegate = nil;
    }
}
- (void)checkNativeBackingGeometry {
    /* These are UIKit's real configured layers, not freshly constructed probe
     * layers. Lifecycle counts alone cannot catch a sideways backing store. */
    CALayer *windowLayer = self.window.layer;
    CALayer *transform = windowLayer.superlayer;
    CALayer *scene = transform.superlayer;
    CALayer *root = scene.superlayer;
    check("native-backing-layer-chain-present", root && scene && transform);
    if(!root || !scene || !transform) return;
    const CGFloat epsilon = 0.001;
    CGAffineTransform rotation = scene.affineTransform;
    CGRect bounds = scene.bounds;
    check("native-backing-scene-has-portrait-bounds",
        isfinite(bounds.size.width) && isfinite(bounds.size.height) &&
        bounds.size.width > 0 && bounds.size.width < bounds.size.height);
    check("native-backing-child-carries-quarter-turn",
        fabs(rotation.a) < epsilon && fabs(rotation.d) < epsilon &&
        fabs(fabs(rotation.b) - 1) < epsilon &&
        fabs(rotation.b + rotation.c) < epsilon &&
        fabs(rotation.tx) < epsilon && fabs(rotation.ty) < epsilon);
    check("native-backing-layer-bounds-match",
        CGRectEqualToRect(bounds, transform.bounds) &&
        CGRectEqualToRect(bounds, windowLayer.bounds));
    check("native-backing-inner-layers-identity",
        CGAffineTransformIsIdentity(root.affineTransform) &&
        CGAffineTransformIsIdentity(transform.affineTransform) &&
        CGAffineTransformIsIdentity(windowLayer.affineTransform));
    check("native-backing-root-position-matches-landscape-extent",
        fabs(root.position.x - bounds.size.height * 0.5) < epsilon &&
        fabs(root.position.y - bounds.size.width * 0.5) < epsilon);
    const CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    check("native-backing-inner-layers-centered",
        CGPointEqualToPoint(scene.position, CGPointMake(
            CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds))) &&
        CGPointEqualToPoint(transform.position, center) &&
        CGPointEqualToPoint(windowLayer.position, center));
    check("native-backing-root-extent-contains-rotated-scene",
        CGRectEqualToRect(scene.frame, root.bounds));
}
- (void)finish {
    BOOL checkAcceptedTurns = NO;
    if([testCase isEqualToString:@"modern-refresh"] && !self.completedRefreshProbe) {
        [self checkQueuedModernBackingRefresh];
        return;
    }
    [self dumpState:"settled"];
    check("native-compositor-policy-unchanged",
        nativeRotationPolicy() == originalNativeRotationPolicy);
    if([testCase isEqualToString:@"manual-controller"]) {
        check("manual-controller-no-rotation-callbacks", legacyQueries == 0 &&
            willRotateCalls == 0 && didRotateCalls == 0);
        if(expectedEnabled) {
            check("manual-controller-no-root-adoption", self.window.rootViewController == nil);
            check("manual-controller-renderer-transform-preserved",
                CGAffineTransformIsIdentity(self.content.transform));
            check("manual-controller-renderer-bounds-preserved",
                CGRectEqualToRect(self.content.bounds, self.initialContentBounds));
            [self checkNativeBackingGeometry];
        }
    } else if([testCase isEqualToString:@"statusbar"]) {
        checkHiddenStatusBarFrame();
    } else if([testCase isEqualToString:@"lifecycle"]) {
        [self checkDirectLifecycleForwarding];
    } else if([testCase isEqualToString:@"ownership"]) {
        [self checkScopedOwnership];
        [self checkBackingAnimation];
        [self checkModernNativePermission];
        [self checkRotationUpdateOrdering];
    } else if([testCase isEqualToString:@"modern-refresh"]) {
        check("modern-refresh-probe-completed", self.completedRefreshProbe);
    } else if([testCase isEqualToString:@"modern-only"]) {
        check("modern-only-root-preserved", self.window.rootViewController == self.controller);
        check("modern-only-policy-preserved", self.controller.supportedInterfaceOrientations ==
            UIInterfaceOrientationMaskLandscape && self.controller.shouldAutorotate);
        check("modern-only-no-legacy-policy-query", legacyQueries == 0);
        if(expectedEnabled) {
            check("modern-only-legacy-lifecycle-delivered", willRotateCalls > 0 && didRotateCalls > 0);
            [self checkNativeBackingGeometry];
        }
    } else if([testCase isEqualToString:@"modern-startup"]) {
        check("startup-renderer-has-no-autoresizing", self.startupRenderer.autoresizingMask == 0);
        check("startup-fixed-renderer-still-fits-root",
            CGRectEqualToRect(self.startupRenderer.frame, self.content.bounds));
        check("startup-root-preserved", self.window.rootViewController == self.controller);
        if(expectedEnabled) [self checkNativeBackingGeometry];
    } else if([testCase isEqualToString:@"modern-explicit"]) {
        check("modern-explicit-root-preserved", self.window.rootViewController == self.controller);
        check("modern-explicit-mask-preserved", self.controller.supportedInterfaceOrientations ==
            UIInterfaceOrientationMaskLandscape);
        check("modern-explicit-autorotate-preserved", self.controller.shouldAutorotate);
        check("modern-explicit-preferred-preserved", self.controller.preferredInterfaceOrientationForPresentation ==
            UIInterfaceOrientationLandscapeRight);
        RootlessRotationTrackingController *subject = (id)self.controller;
        check("modern-explicit-no-legacy-policy-queries", subject.recordedQueries == 0);
        check("modern-explicit-legacy-lifecycle-matches-sdk",
            expectedEnabled ? (subject.recordedWillCalls > 0 && subject.recordedDidCalls > 0) :
                (subject.recordedWillCalls == 0 && subject.recordedDidCalls == 0));
        if(expectedEnabled) [self checkNativeBackingGeometry];
    } else if([testCase isEqualToString:@"modal"]) {
        check("modal-presented-root-preserved", self.window.rootViewController == self.controller);
        check("modal-presentation-chain-preserved",
            self.controller.presentedViewController == self.modalController &&
            self.modalController.presentingViewController == self.controller);
        check("modal-covered-root-not-queried", legacyQueries == self.queriesWhileModalPresented);
        if(expectedEnabled) [self checkModalNativePermission];
    } else if([testCase isEqualToString:@"manual-disabled"]) {
        check("manual-disabled-explicit-root-preserved", self.window.rootViewController == self.controller);
        if(expectedEnabled) [self checkManualDisabledOutput];
    } else if([testCase isEqualToString:@"modern"]) {
        check("modern-mask-preserved", self.controller.supportedInterfaceOrientations ==
            UIInterfaceOrientationMaskLandscapeRight);
        check("modern-autorotate-preserved", !self.controller.shouldAutorotate);
        check("modern-preferred-orientation-preserved",
            self.controller.preferredInterfaceOrientationForPresentation ==
                UIInterfaceOrientationLandscapeRight);
        check("modern-override-called", modernMaskQueries != 0);
        if(expectedEnabled) {
            check("modern-subclass-not-adopted", self.window.rootViewController == nil);
            check("modern-subclass-no-legacy-queries", legacyQueries == 0);
        }
    } else if([testCase isEqualToString:@"unregistered"]) {
        if(expectedEnabled) {
            check("unregistered-controller-not-adopted", self.window.rootViewController == nil);
            check("unregistered-controller-not-queried", legacyQueries == 0);
        }
    } else if(expectedEnabled && !explicitRootCase) {
        RootlessRotationTrackingController *controller = (id)self.controller;
        check("rootless-no-root-adoption", self.window.rootViewController == nil);
        check("rootless-exactly-one-startup-query", controller.recordedQueries == 1);
        check("rootless-received-landscape-candidate",
            UIInterfaceOrientationIsLandscape(lastLegacyOrientation));
        if(manualRotation) {
            check("rootless-no-forced-rotation-callbacks",
                willRotateCalls == 0 && didRotateCalls == 0);
            check("rootless-content-transform-unchanged",
                CGAffineTransformIsIdentity(self.content.transform));
            check("rootless-renderer-frame-and-bounds-preserved",
                CGRectEqualToRect(self.content.frame, self.initialContentFrame) &&
                CGRectEqualToRect(self.content.bounds, self.initialContentBounds));
        } else {
            check("rootless-accepted-controller-is-landscape",
                UIInterfaceOrientationIsLandscape(controller.interfaceOrientation));
            check("rootless-accepted-view-is-landscape",
                self.content.bounds.size.width > self.content.bounds.size.height);
            check("rootless-accepted-turn-delivers-lifecycle",
                willRotateCalls != 0 && didRotateCalls != 0);
            checkSceneOrientationPreference(controller, self.window);
            checkAcceptedTurns = YES;
        }
        [self checkNativeBackingGeometry];
    } else if(expectedEnabled) {
        id clients = nativeObjectGetter(self.window, "_clientsForRotation");
        BOOL found = [clients respondsToSelector:@selector(containsObject:)] &&
            [clients containsObject:self.controller];
        check("native-rotation-client-discovered", found);
        check("legacy-orientation-queried", legacyQueries != 0);
        check("legacy-landscape-queried", legacyLandscapeQueries != 0);
        /* The helper can synchronize an already-oriented explicit root with
         * an initial callback pair. Do not call that a native compositor turn:
         * the independent backing-layer checks verify the rendered geometry. */
        check("explicit-root-will-rotation-received", willRotateCalls != 0);
        check("explicit-root-did-rotation-received", didRotateCalls != 0);
        check("explicit-root-controller-is-landscape",
            UIInterfaceOrientationIsLandscape(self.controller.interfaceOrientation));
        check("explicit-root-still-preserved", self.window.rootViewController == self.controller);
        [self checkNativeBackingGeometry];
        if([testCase isEqualToString:@"explicit"]) checkAcceptedTurns = YES;
    }
    if([testCase isEqualToString:@"replacement"]) {
        check("replacement-startup-state-does-not-retain-previous-controller",
            self.replacedController == nil);
        if(!expectedEnabled) {
            check("replacement-modern-sdk-no-legacy-queries", legacyQueries == 0);
            check("replacement-modern-sdk-explicit-root-preserved",
                self.window.rootViewController == self.controller);
        }
    }
    check("native-compositor-policy-still-unchanged",
        nativeRotationPolicy() == originalNativeRotationPolicy);
    check("sdk-policy-stable", LC32NativeLegacyRotationEnabled() == expectedEnabled);
    if(checkAcceptedTurns) [self checkAcceptedTurnLifecycle:0];
    else [self finishAndExit];
}
- (void)finishAndExit {
    self.window.hidden = YES;
    printf("rootless-rotation-regression: %s\n", failures ? "FAIL" : "PASS");
    exit(failures != 0);
}
@end

static void uncaught(NSException *exception) {
    fprintf(stderr, "rootless-rotation-uncaught: %s: %s\n%s\n",
        exception.name.UTF8String, exception.reason.UTF8String,
        exception.callStackSymbols.description.UTF8String);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        testCase = @"rootless";
        for(int index = 1; index + 1 < argc; ++index) {
            if(!strcmp(argv[index], "--case")) testCase = @(argv[index + 1]);
        }
        if(![@[@"rootless", @"explicit", @"modern", @"modern-explicit", @"modern-startup", @"modern-only", @"modern-refresh", @"unregistered", @"manual", @"manual-controller",
                @"modal", @"manual-disabled", @"lifecycle", @"ownership", @"replacement", @"statusbar", @"startup-commit", @"startup-scene-race", @"scene-parameters", @"initial-backing", @"initial-scene-update",
                @"device-face-up", @"device-face-down", @"device-unknown", @"device-portrait",
                @"device-landscape", @"device-no-observers", @"device-unregistered", @"device-disabled"]
                containsObject:testCase]) return 2;
        manualRotation = [testCase isEqualToString:@"manual"] ||
            [testCase isEqualToString:@"manual-disabled"];
        explicitRootCase = [testCase isEqualToString:@"explicit"] ||
            [testCase isEqualToString:@"modern-startup"] ||
            [testCase isEqualToString:@"modern-explicit"] ||
            [testCase isEqualToString:@"modern-only"] ||
            [testCase isEqualToString:@"modern-refresh"] ||
            [testCase isEqualToString:@"modal"] ||
            [testCase isEqualToString:@"manual-disabled"] ||
            [testCase isEqualToString:@"ownership"];
        NSSetUncaughtExceptionHandler(uncaught);
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass(RootlessRotationDelegate.class));
    }
}
