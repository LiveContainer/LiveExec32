#import <LC32/LC32.h>
#import <UIKit/UIKit+LC32.h>
#import <objc/runtime.h>

#include <pthread.h>
#include <stdio.h>

const NSString *UIApplicationStatusBarHeightChangedNotification = @"UIApplicationStatusBarHeightChangedNotification";
UIAccessibilityTraits UIAccessibilityTraitNone = 0;
UIAccessibilityTraits UIAccessibilityTraitButton = UINT64_C(1);
UIAccessibilityTraits UIAccessibilityTraitSelected = UINT64_C(8);

NSNotificationName const UIApplicationDidBecomeActiveNotification =
    @"UIApplicationDidBecomeActiveNotification";
NSNotificationName const UIApplicationDidChangeStatusBarOrientationNotification =
    @"UIApplicationDidChangeStatusBarOrientationNotification";
NSNotificationName const UIApplicationDidFinishLaunchingNotification =
    @"UIApplicationDidFinishLaunchingNotification";
NSNotificationName const UIApplicationDidEnterBackgroundNotification =
    @"UIApplicationDidEnterBackgroundNotification";
NSNotificationName const UIApplicationDidReceiveMemoryWarningNotification =
    @"UIApplicationDidReceiveMemoryWarningNotification";
NSNotificationName const UIApplicationSignificantTimeChangeNotification =
    @"UIApplicationSignificantTimeChangeNotification";
NSNotificationName const UIApplicationWillResignActiveNotification =
    @"UIApplicationWillResignActiveNotification";
NSNotificationName const UIApplicationWillEnterForegroundNotification =
    @"UIApplicationWillEnterForegroundNotification";
NSNotificationName const UIApplicationWillTerminateNotification =
    @"UIApplicationWillTerminateNotification";
NSNotificationName const UIDeviceOrientationDidChangeNotification =
    @"UIDeviceOrientationDidChangeNotification";

NSString *const UIImagePickerControllerEditedImage =
    @"UIImagePickerControllerEditedImage";
NSString *const UIImagePickerControllerOriginalImage =
    @"UIImagePickerControllerOriginalImage";

NSString *const UIKeyboardAnimationCurveUserInfoKey =
    @"UIKeyboardAnimationCurveUserInfoKey";
NSString *const UIKeyboardAnimationDurationUserInfoKey =
    @"UIKeyboardAnimationDurationUserInfoKey";
NSNotificationName const UIKeyboardDidHideNotification =
    @"UIKeyboardDidHideNotification";
NSNotificationName const UIKeyboardDidShowNotification =
    @"UIKeyboardDidShowNotification";
NSString *const UIKeyboardFrameBeginUserInfoKey =
    @"UIKeyboardFrameBeginUserInfoKey";
NSString *const UIKeyboardFrameEndUserInfoKey =
    @"UIKeyboardFrameEndUserInfoKey";
NSNotificationName const UIKeyboardWillHideNotification =
    @"UIKeyboardWillHideNotification";
NSNotificationName const UIKeyboardWillShowNotification =
    @"UIKeyboardWillShowNotification";

NSNotificationName const UIScreenDidConnectNotification =
    @"UIScreenDidConnectNotification";
NSNotificationName const UIScreenDidDisconnectNotification =
    @"UIScreenDidDisconnectNotification";

NSString *const UITextAttributeFont = @"NSFont";
NSString *const UITextAttributeTextColor = @"NSColor";
NSString *const UITextAttributeTextShadowColor = @"TextShadowColor";
NSString *const UITextAttributeTextShadowOffset = @"TextShadowOffset";
NSNotificationName const UITextFieldTextDidChangeNotification =
    @"UITextFieldTextDidChangeNotification";
NSNotificationName const UITextViewTextDidChangeNotification =
    @"UITextViewTextDidChangeNotification";

NSNotificationName const UIWindowDidBecomeVisibleNotification =
    @"UIWindowDidBecomeVisibleNotification";

const UIEdgeInsets UIEdgeInsetsZero = {0,0,0,0};
const UIOffset UIOffsetZero = {0,0};
const UIWindowLevel UIWindowLevelAlert = 2000.0f;

static pthread_once_t LC32LegacyAdMobOnce = PTHREAD_ONCE_INIT;
static pthread_once_t LC32VoiceOverOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32HostUIAccessibilityIsVoiceOverRunning;

static void LC32ResolveVoiceOverFunction(void) {
    LC32HostUIAccessibilityIsVoiceOverRunning =
        LC32Dlsym("UIAccessibilityIsVoiceOverRunning", YES);
}

BOOL UIAccessibilityIsVoiceOverRunning(void) {
    pthread_once(&LC32VoiceOverOnce, LC32ResolveVoiceOverFunction);
    if(!LC32HostUIAccessibilityIsVoiceOverRunning) return NO;
    return (BOOL)LC32InvokeHostCRet32(
        LC32HostUIAccessibilityIsVoiceOverRunning);
}

static void LC32NoopLegacyGADBannerLoadRequest(id self, SEL _cmd,
                                               id request) {
    (void)self;
    (void)_cmd;
    (void)request;
}

static void LC32DisableLegacyAdMobNetworking(void) {
    /*
     * A few old games statically embedded a Google Mobile Ads release whose
     * HTTP/UIWebView stack no longer interoperates with current iOS.  Let the
     * banner remain a normal UIView, but do not start its obsolete request
     * machinery.  Resolve this at UIApplicationMain rather than in +load so
     * classes supplied by the main executable have already been registered.
     */
    Class bannerClass = objc_getClass("GADBannerView");
    if(!bannerClass) return;

    Method loadRequest = class_getInstanceMethod(
        bannerClass, sel_registerName("loadRequest:"));
    if(!loadRequest) return;

    method_setImplementation(
        loadRequest, (IMP)LC32NoopLegacyGADBannerLoadRequest);
    printf("LC32: disabled obsolete GADBannerView networking\n");
}

int UIApplicationMain(int argc, char * argv[], NSString *
principalClassName, NSString *delegateClassName) {
    pthread_once(&LC32LegacyAdMobOnce, LC32DisableLegacyAdMobNetworking);
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_UIKit_UIApplicationMain", YES);
    return LC32InvokeHostCRet32(hostPtr, argc, argv, principalClassName.host_self, delegateClassName.host_self);
}

static pthread_once_t LC32UIImageCGImageOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32UIImageCGImageSelector;
static pthread_once_t LC32UIKitGeometryOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32UIKitNSStringFromCGSize;
static uint64_t LC32UIKitCGSizeFromString;
static uint64_t LC32UIKitBeginImageContext;
static uint64_t LC32UIKitEndImageContext;
static uint64_t LC32UIKitGetCurrentContext;
static uint64_t LC32UIKitGetImageFromCurrentImageContext;

static void LC32UIImageResolveCGImageSelector(void) {
    LC32UIImageCGImageSelector = LC32GetHostSelector(@selector(CGImage));
}

static void LC32UIKitResolveGeometryFunctions(void) {
    LC32UIKitNSStringFromCGSize =
        LC32Dlsym("LC32_UIKit_NSStringFromCGSize", YES);
    LC32UIKitCGSizeFromString =
        LC32Dlsym("LC32_UIKit_CGSizeFromString", YES);
    LC32UIKitBeginImageContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsBeginImageContext", YES);
    LC32UIKitEndImageContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsEndImageContext", YES);
    LC32UIKitGetCurrentContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsGetCurrentContext", YES);
    LC32UIKitGetImageFromCurrentImageContext = LC32Dlsym(
        "LC32_UIKit_UIGraphicsGetImageFromCurrentImageContext", YES);
}

static uint32_t LC32UIKitFloatBits(CGFloat value) {
    union {
        float value;
        uint32_t bits;
    } converted = { .value = (float)value };
    return converted.bits;
}

NSString *NSStringFromCGSize(CGSize size) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitNSStringFromCGSize) return nil;
    const uint32_t guestString = LC32InvokeHostCRet32(
        LC32UIKitNSStringFromCGSize,
        LC32UIKitFloatBits(size.width),
        LC32UIKitFloatBits(size.height));
    return (__bridge NSString *)(void *)(uintptr_t)guestString;
}

CGSize CGSizeFromString(NSString *string) {
    CGSize result = CGSizeZero;
    if(!string) return result;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitCGSizeFromString) return result;
    const uint32_t guestResult = (uint32_t)(uintptr_t)&result;
    if(!LC32InvokeHostCRet32(LC32UIKitCGSizeFromString,
            string.host_self, (uint64_t)guestResult)) {
        return CGSizeZero;
    }
    return result;
}

void UIGraphicsBeginImageContext(CGSize size) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitBeginImageContext) return;
    LC32InvokeHostCRet32(LC32UIKitBeginImageContext,
        LC32UIKitFloatBits(size.width),
        LC32UIKitFloatBits(size.height));
}

void UIGraphicsEndImageContext(void) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(LC32UIKitEndImageContext)
        LC32InvokeHostCRet32(LC32UIKitEndImageContext);
}

CGContextRef UIGraphicsGetCurrentContext(void) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    return LC32UIKitGetCurrentContext
        ? (CGContextRef)LC32InvokeHostCRet32(LC32UIKitGetCurrentContext)
        : NULL;
}

UIImage *UIGraphicsGetImageFromCurrentImageContext(void) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitGetImageFromCurrentImageContext) return nil;
    const uint32_t guestImage = LC32InvokeHostCRet32(
        LC32UIKitGetImageFromCurrentImageContext);
    return (__bridge UIImage *)(void *)(uintptr_t)guestImage;
}

@implementation UIImage (LC32CoreGraphics)

+ (UIImage *)imageNamed:(NSString *)name {
    /*
     * UIKit's native +imageNamed: searches LiveContainer's bundle.  Route
     * the convenience API through its bundle-aware form so resources are
     * loaded from the selected guest application instead.
     */
    return [self imageNamed:name
                   inBundle:NSBundle.mainBundle
compatibleWithTraitCollection:nil];
}

+ (UIImage *)imageWithCGImage:(CGImageRef)image {
    if(!image) return nil;

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostImage = [(__bridge id)image host_self];
    const uint64_t hostResult = LC32InvokeHostSelector(
        self.host_self, selector, hostImage, (uint64_t)0);
    return LC32HostToGuestObject(hostResult);
}

+ (UIImage *)imageWithCGImage:(CGImageRef)image
                        scale:(CGFloat)scale
                  orientation:(UIImageOrientation)orientation {
    if(!image) return nil;

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostImage = [(__bridge id)image host_self];
    /*
     * CGFloat is float in this ARM32 framework and double in the ARM64 host
     * UIKit.  Variadic promotion stores this value as an IEEE-754 double;
     * LC32InvokeHostSelector uses the host method encoding to place it in d0.
     */
    const double hostScale = (double)scale;
    const uint64_t hostOrientation = (uint64_t)(int64_t)orientation;
    const uint64_t hostResult = LC32InvokeHostSelector(
        self.host_self, selector, hostImage, hostScale, hostOrientation,
        (uint64_t)0);
    return LC32HostToGuestObject(hostResult);
}

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
