#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <LC32/LC32.h>
#import <CoreGraphics/CoreGraphics+LC32.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Rootless pre-controller canvas fixture. Package in a phone-only .app with
 * Default.png, no tall launch image, UIStatusBarHidden=YES, and initial
 * UIInterfaceOrientationLandscapeRight; omit the supported-orientation array.
 * To exercise SDK zero, run vtool -set-version-min ios 7.0 0.0 -replace on
 * the guest executable before injecting the ordinary arm64 shim with lipo.
 * No test-only host hook is used.
 *
 * Like early GL engines, a controller owns the content view without becoming
 * UIWindow.rootViewController. The portrait renderer is nested, not a direct
 * window child. Its drawable and its sibling views must not be resized or
 * reparented while reproducing the old window compositor in presentation.
 */

static int failures;
static BOOL checkingSynchronousLayout;
static NSUInteger synchronousLayouts;

static void report(const char *name, BOOL passed) {
    printf("legacy-nested-renderer-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static BOOL closeScalar(CGFloat a, CGFloat b) {
    return isfinite(a) && isfinite(b) && fabs(a - b) < 0.01;
}

static BOOL closePoint(CGPoint a, CGPoint b) {
    return closeScalar(a.x, b.x) && closeScalar(a.y, b.y);
}

static BOOL identityTransform(CGAffineTransform value) {
    return closeScalar(value.a, 1) && closeScalar(value.b, 0) &&
        closeScalar(value.c, 0) && closeScalar(value.d, 1) &&
        closeScalar(value.tx, 0) && closeScalar(value.ty, 0);
}

static UIInterfaceOrientation nativeSceneOrientation(UIWindow *window) {
    NSString *key = @"windowScene.interfaceOrientation";
    NSNumber *result = LC32InvokeHostObjectSelector([window host_self],
        LC32GetHostSelector(@selector(valueForKeyPath:)),
        [key host_self], (uint64_t)0);
    return (UIInterfaceOrientation)[result integerValue];
}

static CGRect nativeScreenBounds(UIWindow *window) {
    UIScreen *screen = [window screen];
    static uint64_t selector __attribute__((aligned(8)));
    const uint64_t hostSelector = LC32CachedHostSelector(
        &selector, @selector(bounds), YES);
    LC32Floats4_64 bounds;
    LC32InvokeHostSelector([screen host_self], hostSelector,
        &bounds, sizeof(bounds), (uint64_t)0);
    CGRect result;
    LC32Guest4Floats(&bounds, &result);
    return result;
}

@interface LC32NestedRendererView : UIView
@end
@implementation LC32NestedRendererView
+ (Class)layerClass {
    return [CAEAGLLayer class];
}
- (void)layoutSubviews {
    if(checkingSynchronousLayout) ++synchronousLayouts;
    [super layoutSubviews];
}
@end

@interface LC32RootlessController : UIViewController
@end
@implementation LC32RootlessController
- (void)loadView {
    /* The engine assigns its already-created surface through setView:. */
}
@end

@interface LC32NestedRendererDelegate : NSObject <UIApplicationDelegate> {
    LC32RootlessController *_controller;
    UIView *_content;
    UIView *_touchSurface;
    LC32NestedRendererView *_renderer;
    UIView *_overlay;
    NSUInteger _waitCount;
    NSUInteger _stableCount;
    CGRect _lastBounds;
    BOOL _configuredWindow;
}
@property(nonatomic, retain) UIWindow *window;
@end

@implementation LC32NestedRendererDelegate
@synthesize window = _window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    const CGRect canvas = CGRectMake(0, 0, 320, 480);
    self.window = [[[UIWindow alloc] initWithFrame:canvas] autorelease];
    _content = [[UIView alloc] initWithFrame:canvas];
    _touchSurface = [[UIView alloc] initWithFrame:canvas];
    _overlay = [[UIView alloc] initWithFrame:CGRectMake(13, 17, 60, 30)];
    [_content addSubview:_touchSurface];
    [_content addSubview:_overlay];
    [self.window addSubview:_content];
    [self.window makeKeyAndVisible];
    /* The window initially has no controller. The engine creates its view
     * owner later; that must not promote it over the installed inert root. */
    _controller = [LC32RootlessController new];
    [_controller setView:_content];
    [application setStatusBarOrientation:UIInterfaceOrientationLandscapeRight];
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
        selector:@selector(waitForLandscape:) userInfo:nil repeats:YES];
}

- (void)waitForLandscape:(NSTimer *)timer {
    const CGRect bounds = [self.window bounds];
    const UIInterfaceOrientation orientation = nativeSceneOrientation(self.window);
    if(!_configuredWindow && orientation == UIInterfaceOrientationLandscapeRight) {
        /* Model the settled 480x320 Classic Mode viewport explicitly. This
         * does not change any guest child or its locked 320x480 drawable. */
        const CGRect viewport = CGRectMake(0, 0, 480, 320);
        [self.window setTransform:CGAffineTransformIdentity];
        [self.window setFrame:viewport];
        [self.window setBounds:viewport];
        _lastBounds = viewport;
        _configuredWindow = YES;
        return;
    }
    const BOOL ready = _configuredWindow &&
        orientation == UIInterfaceOrientationLandscapeRight &&
        closeScalar(bounds.size.width, 480) &&
        closeScalar(bounds.size.height, 320) &&
        identityTransform([self.window transform]);
    _stableCount = ready && CGRectEqualToRect(bounds, _lastBounds)
        ? _stableCount + 1 : 0;
    _lastBounds = bounds;
    if(_stableCount >= 2) {
        [timer invalidate];
        report("landscape-ready", YES);
        /* Attach the renderer only after startup and scene geometry settle.
         * No makeKey/status-bar call follows: the ordinary nested insertion
         * must trigger a deferred compositor fit by itself. */
        checkingSynchronousLayout = YES;
        _renderer = [[LC32NestedRendererView alloc]
            initWithFrame:CGRectMake(0, 0, 320, 480)];
        [_content addSubview:_renderer];
        [_content addSubview:_overlay];
        checkingSynchronousLayout = NO;
        report("no-synchronous-renderer-layout", synchronousLayouts == 0);
        [NSTimer scheduledTimerWithTimeInterval:0.2 target:self
            selector:@selector(finish:) userInfo:nil repeats:NO];
    } else if(++_waitCount >= 100) {
        [timer invalidate];
        report("landscape-ready", NO);
        [self finish:nil];
    }
}

- (void)finish:(NSTimer *)timer {
    (void)timer;
    const CGRect canvas = CGRectMake(0, 0, 320, 480);
    report("guest-root-remains-nil", [self.window rootViewController] == nil);
    report("controller-not-reparented", [_controller parentViewController] == nil);
    report("direct-content-preserved", [_content superview] == self.window);
    report("nested-siblings-preserved",
        [_touchSurface superview] == _content &&
        [_renderer superview] == _content && [_overlay superview] == _content &&
        [[_content subviews] count] == 3 &&
        [[_content subviews] objectAtIndex:0] == _touchSurface &&
        [[_content subviews] objectAtIndex:1] == _renderer &&
        [[_content subviews] objectAtIndex:2] == _overlay);
    report("portrait-drawable-preserved",
        CGRectEqualToRect([_renderer bounds], canvas) &&
        CGRectEqualToRect([_content bounds], canvas) &&
        CGRectEqualToRect([_touchSurface bounds], canvas) &&
        closePoint([_renderer center], CGPointMake(160, 240)) &&
        identityTransform([_renderer transform]) &&
        identityTransform([_content transform]));
    report("overlay-geometry-preserved",
        CGRectEqualToRect([_overlay frame], CGRectMake(13, 17, 60, 30)) &&
        identityTransform([_overlay transform]));
    report("guest-window-bounds-preserved", CGRectEqualToRect(
        [self.window bounds], CGRectMake(0, 0, 480, 320)));
    const CGRect viewport = nativeScreenBounds(self.window);
    const CGFloat expectedScale = MIN(
        viewport.size.width / 480, viewport.size.height / 320);
    const CGRect windowFrame = [self.window frame];
    report("native-window-fits-viewport",
        closeScalar(windowFrame.size.width, 480 * expectedScale) &&
        closeScalar(windowFrame.size.height, 320 * expectedScale) &&
        closeScalar(CGRectGetMidX(windowFrame), CGRectGetMidX(viewport)) &&
        closeScalar(CGRectGetMidY(windowFrame), CGRectGetMidY(viewport)));

    const CGPoint origin = [_renderer convertPoint:CGPointZero toView:self.window];
    const CGPoint x = [_renderer convertPoint:CGPointMake(1, 0) toView:self.window];
    const CGPoint y = [_renderer convertPoint:CGPointMake(0, 1) toView:self.window];
    fprintf(stderr, "Portrait canvas in landscape window: origin=(%g,%g) "
        "x-axis=(%g,%g) y-axis=(%g,%g)\n", (double)origin.x,
        (double)origin.y, (double)(x.x - origin.x), (double)(x.y - origin.y),
        (double)(y.x - origin.x), (double)(y.y - origin.y));
    /* LandscapeRight's pre-scene compositor takes portrait (x,y) to
     * landscape (y,320-x). This is a quarter-turn, never a 180-degree
     * renderer patch. Touch conversion must use that same presentation. */
    report("right-compositor-coordinate-contract",
        closePoint(origin, CGPointMake(0, 320)) &&
        closePoint(x, CGPointMake(0, 319)) &&
        closePoint(y, CGPointMake(1, 320)));
    const CGPoint touch = [_renderer convertPoint:CGPointMake(120, 280)
        fromView:self.window];
    report("touch-conversion-contract", closePoint(touch, CGPointMake(40, 120)));
    const CGAffineTransform fittedWindowTransform = [self.window transform];
    const CGPoint fittedWindowCenter = [self.window center];
    [self.window makeKeyAndVisible];
    report("window-placement-idempotent",
        CGAffineTransformEqualToTransform(
            [self.window transform], fittedWindowTransform) &&
        closePoint([self.window center], fittedWindowCenter) &&
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointMake(0, 320)));

    /* An ambiguous second renderer must restore the original compositor,
     * without changing either drawable. Removing it permits the same
     * idempotent presentation transform to be installed again. */
    LC32NestedRendererView *second =
        [[LC32NestedRendererView alloc] initWithFrame:canvas];
    [_touchSurface addSubview:second];
    [self.window makeKeyAndVisible];
    report("multiple-renderers-not-rotated",
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointZero) && CGRectEqualToRect([second bounds], canvas));
    [second removeFromSuperview];
    [second release];
    [self.window makeKeyAndVisible];
    report("single-renderer-compositor-restored",
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointMake(0, 320)));

    const CGAffineTransform authored = CGAffineTransformMakeTranslation(7, 9);
    [_content setTransform:authored];
    [self.window makeKeyAndVisible];
    report("authored-ancestor-transform-preserved",
        CGAffineTransformEqualToTransform([_content transform], authored) &&
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointMake(7, 9)));
    [_content setTransform:CGAffineTransformIdentity];
    [self.window makeKeyAndVisible];
    report("identity-ancestor-compositor-restored",
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointMake(0, 320)));

    const CGPoint authoredCenter = CGPointMake(123, 157);
    [self.window setCenter:authoredCenter];
    [self.window makeKeyAndVisible];
    [self.window makeKeyAndVisible];
    report("authored-window-center-preserved",
        closePoint([self.window center], authoredCenter) &&
        identityTransform([self.window transform]));
    const CGAffineTransform authoredWindowTransform =
        CGAffineTransformMakeScale(0.75, 0.75);
    [self.window setTransform:authoredWindowTransform];
    [self.window makeKeyAndVisible];
    report("authored-window-transform-preserved",
        CGAffineTransformEqualToTransform(
            [self.window transform], authoredWindowTransform) &&
        closePoint([self.window center], authoredCenter) &&
        CGRectEqualToRect([self.window bounds], CGRectMake(0, 0, 480, 320)) &&
        CGRectEqualToRect([_renderer bounds], canvas) &&
        closePoint([_renderer convertPoint:CGPointZero toView:self.window],
                   CGPointZero));
    printf("legacy-nested-renderer-regression: %s\n", failures ? "FAIL" : "PASS");
    exit(failures != 0);
}
@end

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass([LC32NestedRendererDelegate class]));
    }
}
