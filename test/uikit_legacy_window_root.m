#import <UIKit/UIKit.h>

#include <stdio.h>
#include <stdlib.h>

@interface LC32LegacyWindowContentView : UIView
@end

@implementation LC32LegacyWindowContentView
@end

static int failures;

static void report(const char *name, BOOL passed) {
    printf("legacy-window-root-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    failures += !passed;
}

@interface LC32LegacyWindowDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, retain) UIWindow *window;
@end

@implementation LC32LegacyWindowDelegate

@synthesize window = _window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    (void)application;

    @autoreleasepool {
        const CGRect archivedFrame = CGRectMake(0, 0, 320, 480);
        self.window = [[UIWindow alloc] initWithFrame:archivedFrame];
#if !__has_feature(objc_arc)
        [self.window release];
#endif
        LC32LegacyWindowContentView *content =
            [[LC32LegacyWindowContentView alloc]
                initWithFrame:archivedFrame];
        LC32LegacyWindowContentView *background =
            [[LC32LegacyWindowContentView alloc]
                initWithFrame:CGRectMake(10, 20, 100, 120)];
        [self.window addSubview:background];
        [self.window addSubview:content];

        const NSUInteger originalSubviewCount = self.window.subviews.count;
        const BOOL initialPassed =
            self.window.rootViewController == nil &&
            originalSubviewCount == 2 &&
            self.window.subviews.firstObject == background &&
            self.window.subviews.lastObject == content;

        [self.window makeKeyAndVisible];

        const BOOL rootHiddenPassed = self.window.rootViewController == nil;
        NSArray<UIView *> *installedSubviews = self.window.subviews;
        const BOOL hierarchyPassed =
            content.superview == self.window &&
            background.superview == self.window &&
            installedSubviews.count >= 2 &&
            installedSubviews[installedSubviews.count - 2] == background &&
            installedSubviews.lastObject == content;
        const NSUInteger installedSubviewCount = installedSubviews.count;
        [self.window makeKeyAndVisible];
        NSArray<UIView *> *repeatedSubviews = self.window.subviews;
        const BOOL idempotencePassed =
            self.window.rootViewController == nil &&
            repeatedSubviews.count == installedSubviewCount &&
            repeatedSubviews.count >= 2 &&
            repeatedSubviews[repeatedSubviews.count - 2] == background &&
            repeatedSubviews.lastObject == content;
        const BOOL geometryPassed =
            CGRectEqualToRect(content.bounds,
                              CGRectMake(0, 0, 320, 480)) &&
            CGRectEqualToRect(background.frame,
                              CGRectMake(10, 20, 100, 120));

        report("initial-shape", initialPassed);
        report("guest-root-remains-nil", rootHiddenPassed);
        report("direct-subview-preserved", hierarchyPassed);
        report("repeated-make-key-is-idempotent", idempotencePassed);
        report("archived-geometry-preserved", geometryPassed);

#if !__has_feature(objc_arc)
        [background release];
        [content release];
#endif
    }
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self
                                   selector:@selector(finish:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)finish:(NSTimer *)timer {
    (void)timer;
    self.window.hidden = YES;
    printf("legacy-window-root-regression: %s\n",
        failures ? "FAIL" : "PASS");
    exit(failures != 0);
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_window release];
    [super dealloc];
#endif
}

@end


int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass(LC32LegacyWindowDelegate.class));
    }
}
