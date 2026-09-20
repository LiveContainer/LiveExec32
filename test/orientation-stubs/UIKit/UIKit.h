#import <Foundation/Foundation.h>
#include <stdint.h>

typedef int32_t UIInterfaceOrientation;
enum {
    UIInterfaceOrientationUnknown = 0,
    UIInterfaceOrientationPortrait = 1,
    UIInterfaceOrientationPortraitUpsideDown = 2,
    UIInterfaceOrientationLandscapeRight = 3,
    UIInterfaceOrientationLandscapeLeft = 4,
};
@interface UIApplication : NSObject
- (UIInterfaceOrientation)statusBarOrientation;
@end
@interface UIApplication (OrientationAPI)
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation;
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation animated:(BOOL)animated;
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation animation:(int)animation duration:(NSTimeInterval)duration;
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation animationParameters:(id)parameters;
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation animationParameters:(id)parameters notifySpringBoardAndFence:(BOOL)notify;
- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation animationParameters:(id)parameters notifySpringBoardAndFence:(BOOL)notify updateBlock:(id)update;
@end
