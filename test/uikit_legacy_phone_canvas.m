#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <LC32/LC32.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Run this SDK-7 guest in an SDK-11 arm64 launcher. The .app must be phone-only
 * (UIDeviceFamily = [1]), contain Default.png but no tall launch image, hide
 * the status bar, and declare initial LandscapeRight with landscape-only
 * supported orientations. These select the fixed 480x320 phone canvas rather
 * than the universal/iPad controller path tested by legacy-root-geometry.
 *
 * Each case installs a fresh, already loaded guest controller through the
 * public UIWindow root setter after startup. The portrait renderer models an
 * engine that rotates its GL projection and ignores UIKit's setTransform:.
 * Its layer must remain portrait BEFORE its first layout: older engines may
 * allocate drawable storage once and never resize it again. We record layer
 * bounds at first layout, not an actual GL renderbuffer allocation.
 */

static int failures;
static const char *caseNames[] = {
    "portrait-identity", "landscape-identity", "portrait-quarter-turn"
};

static void report(const char *name, BOOL passed) {
    printf("legacy-phone-canvas-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static void reportCase(NSUInteger index, const char *name, BOOL passed) {
    printf("legacy-phone-canvas-%s-%s: %s\n", caseNames[index], name,
        passed ? "PASS" : "FAIL");
    failures += !passed;
}

static BOOL closeScalar(CGFloat a, CGFloat b) {
    return isfinite(a) && isfinite(b) && fabs(a - b) < 0.01;
}

static BOOL closeSize(CGSize a, CGSize b) {
    return closeScalar(a.width, b.width) && closeScalar(a.height, b.height);
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

@interface LC32PhoneCanvasRenderer : UIView {
    NSUInteger _layoutCount;
    CGSize _firstLayerSize;
}
@property(nonatomic, readonly) NSUInteger layoutCount;
@property(nonatomic, readonly) CGSize firstLayerSize;
@end

@implementation LC32PhoneCanvasRenderer
@synthesize layoutCount = _layoutCount;
@synthesize firstLayerSize = _firstLayerSize;
+ (Class)layerClass {
    return [CAEAGLLayer class];
}
- (void)layoutSubviews {
    if(_layoutCount++ == 0) _firstLayerSize = [[self layer] bounds].size;
    [super layoutSubviews];
}
@end

@interface LC32PhoneProjectionRenderer : LC32PhoneCanvasRenderer
@end
@implementation LC32PhoneProjectionRenderer
- (void)setTransform:(CGAffineTransform)transform {
    /* The engine owns its projection. Native containment must not depend on
     * this setter applying a UIKit-authored rotation to the drawable view. */
    (void)transform;
}
@end

@interface LC32PhoneCanvasController : UIViewController
@end
@implementation LC32PhoneCanvasController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
@end

@interface LC32PhoneCanvasDelegate : NSObject <UIApplicationDelegate> {
    NSMutableArray *_caseWindows;
    LC32PhoneCanvasController *_controller;
    LC32PhoneCanvasRenderer *_renderer;
    NSUInteger _caseIndex;
    NSUInteger _waitCount;
    NSUInteger _stableCount;
    BOOL _runningCase;
}
@property(nonatomic, retain) UIWindow *window;
@end

@implementation LC32PhoneCanvasDelegate
@synthesize window = _window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    _caseWindows = [NSMutableArray new];
    self.window = [[[UIWindow alloc] initWithFrame:
        CGRectMake(0, 0, 320, 480)] autorelease];
    UIViewController *bootstrap = [UIViewController new];
    [self.window setRootViewController:bootstrap];
    [bootstrap release];
    [self.window makeKeyAndVisible];
    [application setStatusBarOrientation:UIInterfaceOrientationLandscapeRight];
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
        selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)beginCase {
    [self.window setHidden:YES];
    const CGSize initialSize = _caseIndex == 1
        ? CGSizeMake(480, 320) : CGSizeMake(320, 480);
    UIWindow *window = [[UIWindow alloc] initWithFrame:
        CGRectMake(0, 0, 480, 320)];
    [_caseWindows addObject:window];
    self.window = window;
    [window release];
    [_controller release];
    [_renderer release];
    _controller = [LC32PhoneCanvasController new];
    Class rendererClass = _caseIndex == 0
        ? [LC32PhoneProjectionRenderer class] : [LC32PhoneCanvasRenderer class];
    _renderer = [[rendererClass alloc] initWithFrame:
        CGRectMake(0, 0, initialSize.width, initialSize.height)];
    [_renderer setAutoresizingMask:UIViewAutoresizingNone];
    if(_caseIndex == 2) {
        [_renderer setTransform:CGAffineTransformMake(0, 1, -1, 0, 0, 0)];
    } else if(_caseIndex == 0) {
        /* Establish that the portrait renderer really rejects this setter,
         * rather than merely happening to start with an identity transform. */
        [_renderer setTransform:CGAffineTransformMake(0, 1, -1, 0, 0, 0)];
    }
    [_controller setView:_renderer];
    const CGAffineTransform initialTransform = [_renderer transform];
    reportCase(_caseIndex, "initial-layer-contract",
        closeSize([_renderer bounds].size, initialSize) &&
        closeSize([[_renderer layer] bounds].size, initialSize) &&
        (_caseIndex == 2
            ? closeScalar(initialTransform.a, 0) &&
                closeScalar(initialTransform.b, 1) &&
                closeScalar(initialTransform.c, -1) &&
                closeScalar(initialTransform.d, 0)
            : identityTransform(initialTransform)));
    reportCase(_caseIndex, "not-laid-out-before-install",
        [_renderer layoutCount] == 0);

    /* This public setter must classify the existing native view before any
     * layout can allocate its drawable. Do not correct geometry afterwards. */
    [self.window setRootViewController:_controller];
    [self.window makeKeyAndVisible];
    _runningCase = YES;
    _waitCount = 0;
    _stableCount = 0;
}

- (void)checkCase {
    const CGSize expectedSize = _caseIndex == 0
        ? CGSizeMake(320, 480) : CGSizeMake(480, 320);
    UIView *canvas = [_renderer superview];
    UIView *viewport = [canvas superview];
    CGAffineTransform transform = [canvas transform];
    const BOOL quarterTurn = _caseIndex == 0;
    const BOOL expectedTransform = quarterTurn
        ? closeScalar(transform.a, 0) && closeScalar(transform.d, 0) &&
            transform.b < 0 && transform.c > 0 &&
            closeScalar(-transform.b, transform.c)
        : transform.a > 0 && closeScalar(transform.a, transform.d) &&
            closeScalar(transform.b, 0) && closeScalar(transform.c, 0);
    reportCase(_caseIndex, "guest-root-visible",
        [self.window rootViewController] == _controller);
    reportCase(_caseIndex, "wrapped-native-hierarchy",
        canvas != nil && canvas != self.window && viewport != nil &&
        [_renderer window] == self.window);
    reportCase(_caseIndex, "drawable-size",
        closeSize([_renderer bounds].size, expectedSize) &&
        closeSize([[_renderer layer] bounds].size, expectedSize));
    reportCase(_caseIndex, "first-layout-drawable-size",
        [_renderer layoutCount] > 0 &&
        closeSize([_renderer firstLayerSize], expectedSize));
    reportCase(_caseIndex, "content-transform-normalized",
        identityTransform([_renderer transform]));
    reportCase(_caseIndex, "native-wrapper-orientation", expectedTransform);

    const CGPoint origin = [_renderer convertPoint:CGPointZero toView:viewport];
    const CGPoint x = [_renderer convertPoint:CGPointMake(1, 0) toView:viewport];
    const CGPoint y = [_renderer convertPoint:CGPointMake(0, 1) toView:viewport];
    const CGPoint dx = CGPointMake(x.x - origin.x, x.y - origin.y);
    const CGPoint dy = CGPointMake(y.x - origin.x, y.y - origin.y);
    reportCase(_caseIndex, "presentation-axis-contract", quarterTurn
        ? closeScalar(dx.x, 0) && dx.y < 0 && dy.x > 0 &&
            closeScalar(dy.y, 0) && closeScalar(-dx.y, dy.x)
        : dx.x > 0 && closeScalar(dx.y, 0) && closeScalar(dy.x, 0) &&
            dy.y > 0 && closeScalar(dx.x, dy.y));
    const CGPoint guestPoint = CGPointMake(71, 129);
    const CGPoint presented = [_renderer convertPoint:guestPoint toView:viewport];
    reportCase(_caseIndex, "touch-conversion-roundtrip", closePoint(
        [_renderer convertPoint:presented fromView:viewport], guestPoint));
    fprintf(stderr, "Phone canvas %s: layer=%gx%g first-layout=%gx%g "
        "layouts=%lu wrapper=(%g,%g,%g,%g)\n", caseNames[_caseIndex],
        (double)[[_renderer layer] bounds].size.width,
        (double)[[_renderer layer] bounds].size.height,
        (double)[_renderer firstLayerSize].width,
        (double)[_renderer firstLayerSize].height,
        (unsigned long)[_renderer layoutCount],
        (double)transform.a, (double)transform.b,
        (double)transform.c, (double)transform.d);
}

- (void)tick:(NSTimer *)timer {
    const BOOL landscape = nativeSceneOrientation(self.window) ==
        UIInterfaceOrientationLandscapeRight;
    if(!_runningCase) {
        if(landscape) {
            report("bootstrap-landscape-ready", YES);
            [self beginCase];
        } else if(++_waitCount >= 100) {
            report("bootstrap-landscape-ready", NO);
            [timer invalidate];
            exit(1);
        }
        return;
    }
    _stableCount = landscape && [_renderer layoutCount] > 0
        ? _stableCount + 1 : 0;
    if(_stableCount < 2 && ++_waitCount < 100) return;
    reportCase(_caseIndex, "landscape-layout-ready", _stableCount >= 2);
    [self checkCase];
    if(++_caseIndex < sizeof(caseNames) / sizeof(caseNames[0])) {
        [self beginCase];
    } else {
        [timer invalidate];
        printf("legacy-phone-canvas: %s (%d failures)\n",
            failures ? "FAIL" : "PASS", failures);
        fflush(stdout);
        exit(failures ? 1 : 0);
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass([LC32PhoneCanvasDelegate class]));
    }
}
