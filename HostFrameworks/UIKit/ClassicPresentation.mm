#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "LC32UIKitCompatibilityConfig.h"
#include "LC32ClassicPresentation.h"
#if LC32_UIKIT_COMPATIBILITY
#include "bridge.h"
#include "LC32NativeViewGeometry.h"
#include "LC32ClassicPresentationGeometry.h"
#include <atomic>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface UIScene (LC32ClassicScene)
- (id)_FBSScene;
@end
@interface UIWindow (LC32ClassicPrivate)
- (void)_updateTransformLayer;
@end
@interface NSObject (LC32ClassicSettings)
- (id)settings;
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

bool Presentation(UIWindow *window, CGRect *rectangle, CGFloat *scale) {
    *rectangle = CGRectZero;
    UIWindowScene *scene = window.windowScene;
    if(![scene respondsToSelector:@selector(_FBSScene)]) return false;
    id settings = [[scene _FBSScene] settings];
    if(![settings respondsToSelector:@selector(valueForProperty:expectedClass:)]) return false;
    NSValue *value = [settings valueForProperty:@selector(sceneFrameInKeyboardReferenceSpace)
                               expectedClass:NSValue.class];
    if(!value) return false;
    *rectangle = value.CGRectValue;
    return LC32ClassicPresentationScale(window.screen.fixedCoordinateSpace.bounds,
        *rectangle, scale);
}

void Capture(UIWindow *window) {
    // UIKit-owned alerts/keyboards must retain their native geometry.
    if(normalized || activationPending || !window.guest_selfOrNull ||
            !window.windowScene || window.screen != UIScreen.mainScreen) return;
    CGRect presentation;
    CGFloat scale;
    if(!Presentation(window, &presentation, &scale)) return;
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

void Restore(UIWindow *window) {
    LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
    if(!normalized || activationPending || !state.scene || state.restoring ||
            state.scene != window.windowScene) return;
    CGRect presentation;
    CGFloat scale;
    if(Presentation(window, &presentation, &scale) || !LC32ClassicValidRect(presentation)) return;
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
        if(!normalized && backgrounded && !activationPending && !attemptedActivation &&
                application.applicationState == UIApplicationStateActive) {
            for(UIWindow *window in windows.allObjects) {
                LC32ClassicWindowState *state = objc_getAssociatedObject(window, StateKey);
                CGRect rectangle;
                CGFloat scale;
                if(state.scene && state.scene == window.windowScene &&
                        !Presentation(window, &rectangle, &scale) && LC32ClassicValidRect(rectangle)) {
                    NormalizeScene();
                    break;
                }
            }
        }
        for(UIWindow *window in windows.allObjects) Restore(window);
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
