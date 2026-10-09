#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static UIView *view;
static pthread_t worker;
static unsigned draws;
static BOOL correctThread, hasContext, correctRect;

@interface LC32ThreadExitDrawingView : UIView
@end

@implementation LC32ThreadExitDrawingView
- (void)drawRect:(CGRect)rect {
    ++draws;
    correctThread = pthread_equal(pthread_self(), worker);
    hasContext = UIGraphicsGetCurrentContext() != NULL;
    correctRect = CGRectEqualToRect(rect, CGRectMake(0, 0, 32, 24));
    CGContextSetRGBFillColor(UIGraphicsGetCurrentContext(), 1, 0, 0, 1);
    CGContextFillRect(UIGraphicsGetCurrentContext(), rect);
}
@end

static void *drawAtExit(void *unused) {
    (void)unused;
    worker = pthread_self();
    /* No run loop or explicit flush: the implicit transaction is committed
     * as this pthread exits. Its drawRect: must keep the worker's CGContext. */
    [view.layer setNeedsDisplay];
    return NULL;
}

@interface LC32ThreadExitDrawingDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, retain) UIWindow *window;
@end

@implementation LC32ThreadExitDrawingDelegate
@synthesize window = _window;
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    (void)application;
    self.window = [[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    UIViewController *controller = [[[UIViewController alloc] init] autorelease];
    self.window.rootViewController = controller;
    view = [[LC32ThreadExitDrawingView alloc] initWithFrame:CGRectMake(0, 0, 32, 24)];
    [controller.view addSubview:view];
    [self.window makeKeyAndVisible];
    [CATransaction flush];
    draws = 0;
    @autoreleasepool {
        pthread_t thread;
        if(pthread_create(&thread, NULL, drawAtExit, NULL) || pthread_join(thread, NULL))
            exit(1);
        const BOOL passed = draws == 1 && correctThread && hasContext && correctRect;
        printf("thread-exit-drawing: %s (draws=%u thread=%d context=%d rect=%d)\n",
            passed ? "PASS" : "FAIL", draws, correctThread, hasContext, correctRect);
        [view release];
        exit(!passed);
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"LC32ThreadExitDrawingDelegate");
    }
}
