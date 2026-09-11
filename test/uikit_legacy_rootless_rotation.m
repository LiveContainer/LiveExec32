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
#include "LC32LegacyRotation.h"

/* Native-only fixture: compile the actual LegacyRotation.mm implementation,
 * not the emulator or guest selector bridge. Explicit registration stands in
 * for the bridge's classification of guest-created controller classes. */
BOOL LC32NativeLegacyRotationCanCallGuest(void) { return YES; }

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

@interface RootlessRotationWindow : UIWindow
@end
@implementation RootlessRotationWindow
@end

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
@property(nonatomic, weak) UIViewController *replacedController;
@property(nonatomic) CGRect initialContentFrame;
@property(nonatomic) CGRect initialContentBounds;
@property(nonatomic) NSUInteger visibleSubviewCount;
@property(nonatomic) unsigned queriesWhileModalPresented;
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
    if([testCase isEqualToString:@"unregistered"])
        controllerClass = RootlessRotationUnregisteredController.class;
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[RootlessRotationWindow alloc] initWithFrame:bounds];
    self.controller = [[controllerClass alloc] init];
    if(expectedEnabled && controllerClass == RootlessRotationLegacyController.class) {
        check("legacy-supported-mask", self.controller.supportedInterfaceOrientations ==
            UIInterfaceOrientationMaskLandscape);
        check("policy-query-does-not-probe-legacy-callback", legacyQueries == 0);
    }
    self.content = [[UIView alloc] initWithFrame:bounds];
    self.initialContentFrame = self.content.frame;
    self.initialContentBounds = self.content.bounds;
    self.content.backgroundColor = UIColor.blueColor;
    [self.controller setView:self.content];
    if(explicitRootCase)
        self.window.rootViewController = self.controller;
    else
        [self.window addSubview:self.content];
    [self dumpState:"before-visible"];
    [self.window makeKeyAndVisible];
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
- (void)finishStartupAndScheduleChecks {
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
        RootlessRotationModernController.class, RootlessRotationUnregisteredController.class];
    for(Class cls in classes) {
        RootlessRotationTrackingController *subject = [[cls alloc] init];
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        subject.view = [[UIView alloc] initWithFrame:window.bounds];
        window.rootViewController = subject;
        const unsigned queriesBefore = subject.recordedQueries;
        const unsigned willBefore = subject.recordedWillCalls;
        const unsigned didBefore = subject.recordedDidCalls;
        ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, NSTimeInterval, CGSize))objc_msgSend)(
            subject, willSelector, window, newOrientation, duration, CGSizeMake(480, 320));
        ((void (*)(id, SEL, UIWindow *, UIInterfaceOrientation, CGSize))objc_msgSend)(
            subject, didSelector, window, oldOrientation, CGSizeMake(320, 480));
        const unsigned expectedCalls = expectedEnabled &&
            cls == RootlessRotationLegacyController.class ? 1 : 0;
        printf("rootless-rotation-direct-lifecycle: class=%s expected=%u "
            "will-delta=%u did-delta=%u queries-delta=%u will-orientation=%ld "
            "did-orientation=%ld duration=%a\n", class_getName(cls), expectedCalls,
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
        window.hidden = YES;
    }
    puts("rootless-rotation-direct-lifecycle-scope: callback forwarding only; "
         "this case does not claim an automatic compositor rotation");
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
        RootlessRotationModernController.class, RootlessRotationUnregisteredController.class];
    for(Class cls in classes) {
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        UIWindow *otherWindow = [[UIWindow alloc] initWithFrame:window.frame];
        UIViewController *controller = [[cls alloc] init];
        controller.view = [[UIView alloc] initWithFrame:window.bounds];
        window.rootViewController = controller;
        const BOOL nativeOrientation = nativeBoolGetter(window, "_windowOwnsInterfaceOrientation");
        const BOOL nativeTransform = nativeBoolGetter(window, "_windowOwnsInterfaceOrientationTransform");
        CALayer *root = CALayer.layer;
        CALayer *scene = CALayer.layer;
        CALayer *transform = CALayer.layer;
        ownershipOtherWindow = otherWindow;
        ownershipExpectedRoot = root;
        ownershipExpectedScene = scene;
        ownershipExpectedTransform = transform;
        IMP savedConfigure = method_setImplementation(savedConfigureMethod, (IMP)nativeConfigureOwnershipProbe);
        IMP savedOrientation = method_setImplementation(savedOrientationMethod, (IMP)nativeDoesNotOwnOrientation);
        IMP savedTransform = method_setImplementation(savedTransformMethod, (IMP)nativeDoesNotOwnOrientation);
        @try {
            for(unsigned attempt = 0; attempt < 2; ++attempt) {
                ownershipThrow = attempt != 0;
                ownershipCalls = 0;
                BOOL caught = NO;
                @try {
                    ((void (*)(id, SEL, CALayer *, CALayer *, CALayer *))objc_msgSend)(
                        window, configure, root, scene, transform);
                } @catch(NSException *exception) {
                    caught = [exception.name isEqualToString:@"LC32OwnershipProbe"];
                    if(!caught) @throw;
                }
                BOOL legacy = cls == RootlessRotationLegacyController.class;
                printf("rootless-rotation-ownership-probe: class=%s exception=%d "
                    "orientation=%d transform=%d unrelated=%d/%d\n",
                    class_getName(cls), ownershipThrow, ownershipObservedOrientation,
                    ownershipObservedTransform, ownershipObservedOtherOrientation,
                    ownershipObservedOtherTransform);
                check("ownership-original-called-once", ownershipCalls == 1);
                check("ownership-layer-arguments-preserved", ownershipArgumentsPreserved);
                check("ownership-enabled-only-for-eligible-window",
                    ownershipObservedOrientation == legacy && ownershipObservedTransform == legacy);
                check("ownership-other-window-unchanged",
                    !ownershipObservedOtherOrientation && !ownershipObservedOtherTransform);
                check("ownership-original-exception-preserved", caught == ownershipThrow);
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
    CGAffineTransform rotation = root.affineTransform;
    CGRect bounds = root.bounds;
    check("native-backing-root-has-portrait-bounds",
        isfinite(bounds.size.width) && isfinite(bounds.size.height) &&
        bounds.size.width > 0 && bounds.size.width < bounds.size.height);
    check("native-backing-root-quarter-turn",
        fabs(rotation.a) < epsilon && fabs(rotation.d) < epsilon &&
        fabs(fabs(rotation.b) - 1) < epsilon &&
        fabs(rotation.b + rotation.c) < epsilon &&
        fabs(rotation.tx) < epsilon && fabs(rotation.ty) < epsilon);
    check("native-backing-layer-bounds-match",
        CGRectEqualToRect(bounds, scene.bounds) &&
        CGRectEqualToRect(bounds, transform.bounds) &&
        CGRectEqualToRect(bounds, windowLayer.bounds));
    check("native-backing-inner-layers-identity",
        CGAffineTransformIsIdentity(scene.affineTransform) &&
        CGAffineTransformIsIdentity(transform.affineTransform) &&
        CGAffineTransformIsIdentity(windowLayer.affineTransform));
    check("native-backing-root-position-matches-landscape-extent",
        fabs(root.position.x - bounds.size.height * 0.5) < epsilon &&
        fabs(root.position.y - bounds.size.width * 0.5) < epsilon);
    const CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    check("native-backing-inner-layers-centered",
        CGPointEqualToPoint(scene.position, center) &&
        CGPointEqualToPoint(transform.position, center) &&
        CGPointEqualToPoint(windowLayer.position, center));
}
- (void)finish {
    [self dumpState:"settled"];
    check("native-compositor-policy-unchanged",
        nativeRotationPolicy() == originalNativeRotationPolicy);
    if([testCase isEqualToString:@"lifecycle"]) {
        [self checkDirectLifecycleForwarding];
    } else if([testCase isEqualToString:@"ownership"]) {
        [self checkScopedOwnership];
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
        check("rootless-no-forced-rotation-callbacks",
            willRotateCalls == 0 && didRotateCalls == 0);
        check("rootless-content-transform-unchanged",
            CGAffineTransformIsIdentity(self.content.transform));
        check("rootless-renderer-frame-and-bounds-preserved",
            CGRectEqualToRect(self.content.frame, self.initialContentFrame) &&
            CGRectEqualToRect(self.content.bounds, self.initialContentBounds));
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
        if(![@[@"rootless", @"explicit", @"modern", @"unregistered", @"manual",
                @"modal", @"manual-disabled", @"lifecycle", @"ownership", @"replacement"]
                containsObject:testCase]) return 2;
        manualRotation = [testCase isEqualToString:@"manual"] ||
            [testCase isEqualToString:@"manual-disabled"];
        explicitRootCase = [testCase isEqualToString:@"explicit"] ||
            [testCase isEqualToString:@"modal"] ||
            [testCase isEqualToString:@"manual-disabled"] ||
            [testCase isEqualToString:@"ownership"];
        NSSetUncaughtExceptionHandler(uncaught);
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass(RootlessRotationDelegate.class));
    }
}
