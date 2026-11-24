#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "LC32UIKitCompatibilityConfig.h"
#include "LC32ClassicPresentation.h"
#include "LC32LegacyRotation.h"
#if LC32_UIKIT_COMPATIBILITY
#include "bridge.h"
#include "LC32NativeViewGeometry.h"
#include "LC32ClassicPresentationGeometry.h"
#include <atomic>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface UIScene (LC32ClassicScene)
- (id)_FBSScene;
- (BOOL)_canDynamicallySpecifySupportedInterfaceOrientations;
@end
@interface UIWindow (LC32ClassicPrivate)
- (void)_updateTransformLayer;
- (UIInterfaceOrientation)interfaceOrientation;
- (void)_updateToInterfaceOrientation:(UIInterfaceOrientation)orientation
    duration:(NSTimeInterval)duration force:(BOOL)force;
@end
@interface NSObject (LC32ClassicSettings)
- (id)settings;
- (id)clientSettings;
- (NSInteger)interfaceOrientationMode;
- (UIInterfaceOrientationMask)supportedInterfaceOrientations;
- (id)valueForProperty:(SEL)property expectedClass:(Class)cls;
- (CGRect)sceneFrameInKeyboardReferenceSpace;
@end
@interface NSUserDefaults (LC32ClassicHostBundle)
+ (NSBundle *)lcMainBundle;
@end
@interface _LSOpenConfiguration : NSObject
@property(nonatomic, copy) NSDictionary *frontBoardOptions;
@end
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (void)openApplicationWithBundleIdentifier:(NSString *)identifier
    configuration:(_LSOpenConfiguration *)configuration
    completionHandler:(void (^)(BOOL, NSError *))completion;
@end

@interface LC32ClassicWindowState : NSObject
@property(nonatomic, weak) UIWindowScene *scene;
@property(nonatomic) LC32ClassicWindowGeometry geometry;
@property(nonatomic) CGFloat contentScale;
@property(nonatomic) LC32ClassicScreenGeometry screenGeometry;
@property(nonatomic) CGRect sceneBounds;
@property(nonatomic) BOOL restoring;
@end
@implementation LC32ClassicWindowState
@end

namespace {
const void *StateKey = &StateKey;
const void *OrientationRequestKey = &OrientationRequestKey;
NSHashTable<UIWindow *> *windows;
bool backgrounded, activationPending, attemptedActivation, updatePending;
std::atomic<bool> normalized{false};

void WithoutWindowAutoresizing(UIWindow *window, void (^update)(void)) {
    const BOOL autoresizes = window.autoresizesSubviews;
    window.autoresizesSubviews = NO;
    @try {
        update();
    } @finally {
        window.autoresizesSubviews = autoresizes;
    }
}

bool Presentation(UIWindowScene *scene, CGRect *rectangle, CGFloat *scale) {
    *rectangle = CGRectZero;
    if(![scene respondsToSelector:@selector(_FBSScene)]) return false;
    id settings = [[scene _FBSScene] settings];
    if(![settings respondsToSelector:@selector(valueForProperty:expectedClass:)]) return false;
    NSValue *value = [settings valueForProperty:@selector(sceneFrameInKeyboardReferenceSpace)
                               expectedClass:NSValue.class];
    if(!value) return false;
    *rectangle = value.CGRectValue;
    return LC32ClassicPresentationScale(scene.screen.fixedCoordinateSpace.bounds,
        *rectangle, scale);
}

// The multitasking host's "always all" mode ignores controller policy.
// Other modes (including an explicit orientation lock) stay with UIKit.
bool UsesHostOrientationMask(UIWindowScene *scene) {
    if(![scene respondsToSelector:@selector(_FBSScene)]) return false;
    id settings = [[scene _FBSScene] settings];
    constexpr NSInteger alwaysAll = 2;
    return [settings respondsToSelector:@selector(interfaceOrientationMode)] &&
        [settings interfaceOrientationMode] == alwaysAll;
}

using SceneOrientationPolicy = BOOL (*)(UIWindowScene *, SEL);
SceneOrientationPolicy nativeOrientationPolicy;

BOOL CanSpecifySupportedOrientations(UIWindowScene *scene, SEL selector) {
    if(nativeOrientationPolicy(scene, selector)) return YES;
    if(scene.screen != UIScreen.mainScreen || !UsesHostOrientationMask(scene)) return NO;
    LC32ClassicWindowState *saved = objc_getAssociatedObject(scene.screen, StateKey);
    CGRect rectangle;
    CGFloat scale;
    return (normalized && saved.scene == scene) || Presentation(scene, &rectangle, &scale);
}

void RequestSupportedOrientation(UIWindowScene *scene) {
    if(@available(iOS 16.0, *)) {
        if(scene.activationState != UISceneActivationStateForegroundActive ||
                !nativeOrientationPolicy || !UsesHostOrientationMask(scene)) return;
        id fbs = [scene _FBSScene];
        if(![fbs respondsToSelector:@selector(clientSettings)]) return;
        id settings = [fbs clientSettings];
        if(![settings respondsToSelector:@selector(supportedInterfaceOrientations)]) return;
        // This is the policy UIKit has published for the active window,
        // including its delegate and controllers, not the broader Info.plist.
        UIInterfaceOrientationMask mask = [settings supportedInterfaceOrientations];
        UIInterfaceOrientation current = scene.interfaceOrientation;
        if(!mask || current == UIInterfaceOrientationUnknown) return;
        if(mask & (1UL << current)) {
            objc_setAssociatedObject(scene, OrientationRequestKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        if([objc_getAssociatedObject(scene, OrientationRequestKey) unsignedIntegerValue] == mask) return;
        objc_setAssociatedObject(scene, OrientationRequestKey, @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:mask] errorHandler:nil];
    }
}

void Capture(UIWindow *window) {
    // UIKit-owned alerts/keyboards must retain their native geometry.
    if(normalized || activationPending || !window.guest_selfOrNull ||
            !window.windowScene || window.screen != UIScreen.mainScreen) return;
    CGRect presentation;
    CGFloat scale;
    if(!Presentation(window.windowScene, &presentation, &scale)) return;
    CALayer *layer = LC32NativeViewLayer(window);
    LC32ClassicWindowGeometry geometry = {LC32NativeViewBounds(window),
        LC32NativeViewCenter(window), LC32NativeViewTransform(window),
        layer.superlayer.bounds, scale};
    CGPoint center;
    CGAffineTransform transform;
    if(!LC32ClassicWindowPlacement(geometry, geometry.parentBounds, &center, &transform)) return;
    LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
    if(!state) {
        state = [LC32ClassicWindowState new];
        objc_setAssociatedObject(window, StateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!windows) windows = [NSHashTable weakObjectsHashTable];
        [windows addObject:window];
    }
    state.scene = window.windowScene;
    state.geometry = geometry;
    state.contentScale = layer.contentsScale;
    UIScreen *screen = window.screen;
    state.screenGeometry = LC32CaptureGuestScreenGeometry(screen);
    state.sceneBounds = window.windowScene.coordinateSpace.bounds;
    objc_setAssociatedObject(screen, StateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void Restore(UIWindow *window, bool refreshLayout = false) {
    LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
    if(!normalized || activationPending || !state.scene || state.restoring ||
            state.scene != window.windowScene) return;
    CGRect presentation;
    CGFloat scale;
    if(Presentation(window.windowScene, &presentation, &scale) || !LC32ClassicValidRect(presentation)) return;
    CALayer *layer = LC32NativeViewLayer(window);
    CGPoint center;
    CGAffineTransform transform;
    if(!LC32ClassicWindowPlacement(state.geometry, layer.superlayer.bounds, &center, &transform)) return;
    state.restoring = YES;
    @try {
        [UIView performWithoutAnimation:^{
            WithoutWindowAutoresizing(window, ^{
                LC32NativeSetViewBounds(window, state.geometry.bounds);
                LC32NativeSetViewTransform(window, transform);
                LC32NativeSetViewCenter(window, center);
                layer.contentsScale = state.contentScale;
                // The turn that exposed Classic loss may already have sized
                // the native rotation client from the physical screen. Once
                // activation finishes, reflow that client using the saved
                // metrics without sending the guest another rotation pair.
                if(refreshLayout && LC32NativeLegacyRotationEnabled() &&
                        [window respondsToSelector:@selector(_updateToInterfaceOrientation:duration:force:)])
                    [window _updateToInterfaceOrientation:window.interfaceOrientation duration:0 force:YES];
            });
        }];
    } @finally {
        state.restoring = NO;
    }
}

void ScheduleUpdate();

void NormalizeScene() {
    Class configurationClass = NSClassFromString(@"_LSOpenConfiguration");
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    NSBundle *host = [NSUserDefaults respondsToSelector:@selector(lcMainBundle)]
        ? NSUserDefaults.lcMainBundle : NSBundle.mainBundle;
    if(!host.bundleIdentifier.length ||
            ![configurationClass instancesRespondToSelector:@selector(setFrontBoardOptions:)] ||
            ![workspaceClass instancesRespondToSelector:
                @selector(openApplicationWithBundleIdentifier:configuration:completionHandler:)]) return;
    attemptedActivation = true;
    activationPending = true;
    // Native controller layout during activation must already use the saved
    // reference size; the completion runs after those scene callbacks.
    normalized = true;
    _LSOpenConfiguration *configuration = [configurationClass new];
    configuration.frontBoardOptions = @{@"__ActivateAsClassic": @0};
    // Clear the stale host clipping boundary, not the guest's logical canvas.
    // This activates the existing process; it does not relaunch the game.
    [[workspaceClass defaultWorkspace] openApplicationWithBundleIdentifier:host.bundleIdentifier
        configuration:configuration completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                activationPending = false;
                normalized = success;
                if(!success) NSLog(@"LC32: Classic presentation restore failed: %@", error);
                if(success) {
                    for(UIWindow *window in windows.allObjects) Restore(window, true);
                }
                ScheduleUpdate();
            });
        }];
}

void ScheduleUpdate() {
    if(updatePending) return;
    updatePending = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        updatePending = false;
        UIApplication *application = UIApplication.sharedApplication;
        if(!backgrounded) {
            for(UIWindow *window in application.windows) Capture(window);
        }
        // A scene can leave Classic during rotation or overlay dismissal too,
        // without backgrounding the application. The verified saved state and
        // live presentation metadata, not a lifecycle event, establish loss.
        if(!normalized && !activationPending && !attemptedActivation &&
                application.applicationState == UIApplicationStateActive) {
            for(UIWindow *window in windows.allObjects) {
                LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
                CGRect rectangle;
                CGFloat scale;
                if(state.scene && state.scene == window.windowScene &&
                        !Presentation(window.windowScene, &rectangle, &scale) && LC32ClassicValidRect(rectangle)) {
                    NormalizeScene();
                    break;
                }
            }
        }
        for(UIWindow *window in windows.allObjects) {
            LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
            if(!activationPending && state.scene && state.scene == window.windowScene)
                RequestSupportedOrientation(state.scene);
            Restore(window);
        }
    });
}
}

bool LC32GetClassicScreenGeometry(UIScreen *screen, LC32ClassicScreenGeometry *geometry) {
    if(!normalized.load()) return false;
    LC32ClassicWindowState *state = objc_getAssociatedObject(screen, StateKey);
    if(!state.scene) return false;
    *geometry = state.screenGeometry;
    return true;
}

bool LC32GetClassicWindowGeometry(UIWindow *window, CGRect *bounds, CGRect *sceneBounds) {
    if(!normalized.load()) return false;
    LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
    if(!state.scene || state.scene != window.windowScene) return false;
    *bounds = state.geometry.bounds;
    *sceneBounds = state.sceneBounds;
    return true;
}

@interface UIWindow (LC32ClassicPresentation)
- (void)lc32_classicUpdateTransformLayer;
+ (void)lc32_classicApplicationActive:(NSNotification *)notification;
+ (void)lc32_classicApplicationResigning:(NSNotification *)notification;
+ (void)lc32_classicApplicationBackgrounded:(NSNotification *)notification;
@end
@implementation UIWindow (LC32ClassicPresentation)
+ (void)load {
    const char *override = getenv("CLASSIC_OVERRIDE");
    // A launch hint only: Capture additionally verifies live host presentation.
    if(!override || strtol(override, nullptr, 10) <= 0) return;
    Method original = class_getInstanceMethod(self, @selector(_updateTransformLayer));
    if(!original) return;
    if(@available(iOS 16.0, *)) {
        SEL selector = @selector(_canDynamicallySpecifySupportedInterfaceOrientations);
        Method method = class_getInstanceMethod(UIWindowScene.class, selector);
        if(method && LC32NativeLegacyRotationEnabled()) {
            nativeOrientationPolicy = (SceneOrientationPolicy)method_getImplementation(method);
            // Exchanging an inherited Method would change UIScene itself; override only UIWindowScene.
            class_replaceMethod(UIWindowScene.class, selector,
                (IMP)CanSpecifySupportedOrientations, method_getTypeEncoding(method));
        }
    }
    method_exchangeImplementations(original,
        class_getInstanceMethod(self, @selector(lc32_classicUpdateTransformLayer)));
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(lc32_classicApplicationActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(lc32_classicApplicationResigning:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(lc32_classicApplicationBackgrounded:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)lc32_classicUpdateTransformLayer {
    LC32ClassicWindowState *state = objc_getAssociatedObject(self, StateKey);
    if(normalized && state.scene && state.scene == self.windowScene) {
        // The compositor temporarily sets a physical window frame. Do not
        // autoresize logical child views for that intermediate extent (or
        // resize them a second time when Restore puts the logical bounds back).
        WithoutWindowAutoresizing(self, ^{ [self lc32_classicUpdateTransformLayer]; });
    } else {
        [self lc32_classicUpdateTransformLayer];
    }
    // UIKit also updates these layers for system snapshots. Coalesce after
    // native layout; synchronously restoring here corrupts child-view layout.
    if((state && !state.restoring) || (!backgrounded && self.guest_selfOrNull)) ScheduleUpdate();
}
+ (void)lc32_classicApplicationActive:(NSNotification *)notification {
    for(UIWindow *window in windows.allObjects)
        objc_setAssociatedObject(window.windowScene, OrientationRequestKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ScheduleUpdate();
}
+ (void)lc32_classicApplicationResigning:(NSNotification *)notification {
    // Capture the settled orientation immediately before leaving Classic,
    // rather than freezing a portrait launch frame for a landscape game.
    for(UIWindow *window in UIApplication.sharedApplication.windows) Capture(window);
}
+ (void)lc32_classicApplicationBackgrounded:(NSNotification *)notification {
    backgrounded = true;
    attemptedActivation = false;
}
@end
#else
bool LC32GetClassicScreenGeometry(UIScreen *, LC32ClassicScreenGeometry *) { return false; }
bool LC32GetClassicWindowGeometry(UIWindow *, CGRect *, CGRect *) { return false; }
#endif
