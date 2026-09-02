#import <UIKit/UIKit.h>

#include <stdio.h>

static NSUInteger primaryLoadCount;
static NSUInteger nestedLoadCount;
static BOOL primarySawUnloadedView;
static BOOL nestedSawUnloadedView;
static UIViewController *nestedController;

@interface LC32LoadViewReplacement : UIView
@end

@implementation LC32LoadViewReplacement
@end

@interface LC32NestedLoadViewController : UIViewController
@end

@implementation LC32NestedLoadViewController

- (void)loadView {
    nestedLoadCount++;
    nestedSawUnloadedView = self.view == nil;

    LC32LoadViewReplacement *replacement = [[LC32LoadViewReplacement alloc]
        initWithFrame:CGRectMake(0, 0, 120, 80)];
    replacement.tag = 202;
    self.view = replacement;
#if !__has_feature(objc_arc)
    [replacement release];
#endif
}

@end

@interface LC32PrimaryLoadViewController : UIViewController
@end

@implementation LC32PrimaryLoadViewController

- (void)loadView {
    primaryLoadCount++;

    /* Loading another guest controller must remain legal while this receiver
     * is active. Each override then reproduces the legacy self.view access
     * which used to bounce indefinitely through native loadViewIfRequired. */
    (void)nestedController.view;
    primarySawUnloadedView = self.view == nil;
    (void)NSBundle.mainBundle.bundlePath;

    LC32LoadViewReplacement *replacement = [[LC32LoadViewReplacement alloc]
        initWithFrame:CGRectMake(0, 0, 320, 200)];
    replacement.tag = 101;
    self.view = replacement;
#if !__has_feature(objc_arc)
    [replacement release];
#endif
}

@end

static int report(const char *name, BOOL passed) {
    printf("uikit-view-load-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    @autoreleasepool {
        LC32NestedLoadViewController *nested =
            [LC32NestedLoadViewController new];
        LC32PrimaryLoadViewController *primary =
            [LC32PrimaryLoadViewController new];
        nestedController = nested;

        UIView *primaryView = primary.view;
        UIView *nestedView = nested.view;
        const BOOL firstLoadPassed =
            primaryLoadCount == 1 && nestedLoadCount == 1 &&
            primarySawUnloadedView && nestedSawUnloadedView &&
            [primaryView isKindOfClass:LC32LoadViewReplacement.class] &&
            [nestedView isKindOfClass:LC32LoadViewReplacement.class] &&
            primaryView.tag == 101 && nestedView.tag == 202;

        const BOOL repeatedAccessPassed =
            primary.view == primaryView && nested.view == nestedView &&
            primaryLoadCount == 1 && nestedLoadCount == 1;

        int passed = report("per-receiver-reentrancy", firstLoadPassed);
        passed &= report("repeated-access", repeatedAccessPassed);
        printf("uikit-view-load-reentrancy-regression: %s\n",
            passed ? "PASS" : "FAIL");

        nestedController = nil;
#if !__has_feature(objc_arc)
        [primary release];
        [nested release];
#endif
        return !passed;
    }
}
