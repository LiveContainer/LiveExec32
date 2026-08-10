#import <LC32/LC32.h>
#import <UIKit/UIKit+LC32.h>

#include <pthread.h>

const NSString *UIApplicationStatusBarHeightChangedNotification = @"UIApplicationStatusBarHeightChangedNotification";
NSNotificationName const UIApplicationDidEnterBackgroundNotification =
    @"UIApplicationDidEnterBackgroundNotification";
NSNotificationName const UIApplicationWillEnterForegroundNotification =
    @"UIApplicationWillEnterForegroundNotification";
NSNotificationName const UIApplicationWillTerminateNotification =
    @"UIApplicationWillTerminateNotification";

const UIEdgeInsets UIEdgeInsetsZero = {0,0,0,0};

int UIApplicationMain(int argc, char * argv[], NSString *
principalClassName, NSString *delegateClassName) {
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_UIKit_UIApplicationMain", YES);
    return LC32InvokeHostCRet32(hostPtr, argc, argv, principalClassName.host_self, delegateClassName.host_self);
}

static pthread_once_t LC32UIImageCGImageOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32UIImageCGImageSelector;

static void LC32UIImageResolveCGImageSelector(void) {
    LC32UIImageCGImageSelector = LC32GetHostSelector(@selector(CGImage));
}

@implementation UIImage (LC32CoreGraphics)

- (CGImageRef)CGImage {
    pthread_once(&LC32UIImageCGImageOnce,
        LC32UIImageResolveCGImageSelector);
    uint64_t hostImage = LC32InvokeHostSelector(
        self.host_self, LC32UIImageCGImageSelector);
    return hostImage
        ? (__bridge CGImageRef)LC32HostToGuestObject(hostImage)
        : NULL;
}

@end

@implementation UIView (LC32LegacyAnimationContext)

+ (void)beginAnimations:(NSString *)animationID context:(void *)context {
    static uint64_t hostSelector;
    if(!hostSelector) {
        hostSelector = LC32GetHostSelector(_cmd);
    }
    /*
     * The context is an opaque token, not a buffer for UIKit to dereference.
     * Preserve its 32-bit guest value so an animation-delegate callback can
     * receive the same token rather than exposing guest memory to the host.
     */
    LC32InvokeHostSelector(self.host_self, hostSelector,
                           animationID.host_self,
                           (uint64_t)(uint32_t)(uintptr_t)context,
                           (uint64_t)0);
}

@end
