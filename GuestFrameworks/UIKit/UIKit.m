#import <LC32/LC32.h>
#import <CoreGraphics/CoreGraphics+LC32.h>
#import <UIKit/UIKit+LC32.h>
#import <objc/runtime.h>

#include <pthread.h>
#include <stdio.h>

const NSString *UIApplicationStatusBarHeightChangedNotification = @"UIApplicationStatusBarHeightChangedNotification";
UIAccessibilityTraits UIAccessibilityTraitNone = 0;
UIAccessibilityTraits UIAccessibilityTraitButton = UINT64_C(1);
UIAccessibilityTraits UIAccessibilityTraitSelected = UINT64_C(8);
UIAccessibilityTraits UIAccessibilityTraitStaticText = UINT64_C(64);
UIAccessibilityNotifications UIAccessibilityLayoutChangedNotification = 1001;

NSNotificationName const UIApplicationDidBecomeActiveNotification =
    @"UIApplicationDidBecomeActiveNotification";
NSNotificationName const UIApplicationDidChangeStatusBarOrientationNotification =
    @"UIApplicationDidChangeStatusBarOrientationNotification";
NSNotificationName const UIApplicationDidChangeStatusBarFrameNotification =
    @"UIApplicationDidChangeStatusBarFrameNotification";
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
NSNotificationName const UIApplicationProtectedDataDidBecomeAvailable =
    @"UIApplicationProtectedDataDidBecomeAvailable";
NSNotificationName const UIApplicationProtectedDataWillBecomeUnavailable =
    @"UIApplicationProtectedDataWillBecomeUnavailable";
UIApplicationLaunchOptionsKey const UIApplicationLaunchOptionsLocalNotificationKey =
    @"UIApplicationLaunchOptionsLocalNotificationKey";
UIApplicationLaunchOptionsKey const UIApplicationLaunchOptionsRemoteNotificationKey =
    @"UIApplicationLaunchOptionsRemoteNotificationKey";
NSString *const UIApplicationStatusBarOrientationUserInfoKey =
    @"UIApplicationStatusBarOrientationUserInfoKey";
NSNotificationName const UIApplicationWillChangeStatusBarOrientationNotification =
    @"UIApplicationWillChangeStatusBarOrientationNotification";
NSNotificationName const UIDeviceOrientationDidChangeNotification =
    @"UIDeviceOrientationDidChangeNotification";
NSNotificationName const UIDeviceBatteryLevelDidChangeNotification =
    @"UIDeviceBatteryLevelDidChangeNotification";
NSNotificationName const UIDeviceBatteryStateDidChangeNotification =
    @"UIDeviceBatteryStateDidChangeNotification";

const UIBackgroundTaskIdentifier UIBackgroundTaskInvalid = 0;

NSString *const UIImagePickerControllerEditedImage =
    @"UIImagePickerControllerEditedImage";
NSString *const UIImagePickerControllerOriginalImage =
    @"UIImagePickerControllerOriginalImage";
NSString *const UIImagePickerControllerMediaType =
    @"UIImagePickerControllerMediaType";
NSString *const UIImagePickerControllerMediaURL =
    @"UIImagePickerControllerMediaURL";

NSString *const UILocalNotificationDefaultSoundName =
    @"UILocalNotificationDefaultSoundName";
NSNotificationName const UIMenuControllerDidHideMenuNotification =
    @"UIMenuControllerDidHideMenuNotification";

NSString *const UIKeyboardAnimationCurveUserInfoKey =
    @"UIKeyboardAnimationCurveUserInfoKey";
NSString *const UIKeyboardAnimationDurationUserInfoKey =
    @"UIKeyboardAnimationDurationUserInfoKey";
NSString *const UIKeyboardBoundsUserInfoKey =
    @"UIKeyboardBoundsUserInfoKey";
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
NSNotificationName const UIWindowDidBecomeKeyNotification =
    @"UIWindowDidBecomeKeyNotification";

const UIEdgeInsets UIEdgeInsetsZero = {0,0,0,0};
const UIOffset UIOffsetZero = {0,0};
const UIWindowLevel UIWindowLevelAlert = 2000.0f;
const UIWindowLevel UIWindowLevelNormal = 0.0f;
const UIWindowLevel UIWindowLevelStatusBar = 1000.0f;
const CGFloat UIScrollViewDecelerationRateNormal = 0.998f;
const CGFloat UIScrollViewDecelerationRateFast = 0.99f;
NSRunLoopMode const UITrackingRunLoopMode = @"UITrackingRunLoopMode";

static pthread_once_t LC32LegacyAdMobOnce = PTHREAD_ONCE_INIT;
static pthread_once_t LC32VoiceOverOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32HostUIAccessibilityIsVoiceOverRunning;
static pthread_once_t LC32GuidedAccessOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32HostUIAccessibilityIsGuidedAccessEnabled;
static pthread_once_t LC32LegacyIPadCanvasOnce = PTHREAD_ONCE_INIT;
static BOOL LC32LegacyIPadCanvasRequired;
static BOOL LC32LegacyIPadStatusBarHidden;

static void LC32ResolveLegacyIPadCanvas(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSArray *families = [info objectForKey:@"UIDeviceFamily"];
    BOOL supportsPhone = NO;
    BOOL supportsPad = NO;
    if([families isKindOfClass:NSArray.class]) {
        for(id family in families) {
            if(![family respondsToSelector:@selector(integerValue)]) continue;
            const NSInteger value = [family integerValue];
            supportsPhone |= value == 1;
            supportsPad |= value == 2;
        }
    }
    LC32LegacyIPadCanvasRequired = supportsPad && !supportsPhone;
    LC32LegacyIPadStatusBarHidden = [[info objectForKey:
        @"UIStatusBarHidden"] boolValue];
}

static BOOL LC32RequiresLegacyIPadCanvas(void) {
    pthread_once(&LC32LegacyIPadCanvasOnce, LC32ResolveLegacyIPadCanvas);
    return LC32LegacyIPadCanvasRequired;
}

static BOOL LC32ScreenNeedsLegacyIPadCanvas(CGRect hostBounds) {
    if(!LC32RequiresLegacyIPadCanvas()) return NO;
    const CGFloat shortEdge = MIN(hostBounds.size.width,
                                  hostBounds.size.height);
    /* A full-size iPad canvas has never had a short edge below 600 points.
     * A smaller value means that an iPad-only guest is running inside a
     * phone/classic host scene and needs a coherent virtual canvas. */
    return shortEdge > 0 && shortEdge < 600;
}

static CGRect LC32HostScreenRect(UIScreen *screen, SEL selector) {
    static uint64_t boundsSelector __attribute__((aligned(8)));
    static uint64_t applicationFrameSelector __attribute__((aligned(8)));
    uint64_t *storage = selector == @selector(bounds)
        ? &boundsSelector : &applicationFrameSelector;
    const uint64_t hostSelector = LC32CachedHostSelector(
        storage, selector, YES);
    CGRect_64 hostResult;
    LC32InvokeHostSelector(screen.host_self, hostSelector,
                           &hostResult, sizeof(hostResult), (uint64_t)0);
    return LC32GuestCGRect(hostResult);
}

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

static void LC32ResolveGuidedAccessFunction(void) {
    LC32HostUIAccessibilityIsGuidedAccessEnabled =
        LC32Dlsym("UIAccessibilityIsGuidedAccessEnabled", YES);
}

BOOL UIAccessibilityIsGuidedAccessEnabled(void) {
    pthread_once(&LC32GuidedAccessOnce, LC32ResolveGuidedAccessFunction);
    if(!LC32HostUIAccessibilityIsGuidedAccessEnabled) return NO;
    return (BOOL)LC32InvokeHostCRet32(
        LC32HostUIAccessibilityIsGuidedAccessEnabled);
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

/*
 * Sentinel returned by the host UIApplicationMain shim when the host run
 * loop was interrupted by a guest-debugger all-stop. Keep in sync with
 * HostFrameworks/UIKit/UIKit.mm.
 */
#define LC32_UIKIT_RUNLOOP_DEBUGGER_STOP 0x1C32DEAD

int UIApplicationMain(int argc, char * argv[], NSString *
principalClassName, NSString *delegateClassName) {
    pthread_once(&LC32LegacyAdMobOnce, LC32DisableLegacyAdMobNetworking);
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_UIKit_UIApplicationMain", YES);
    for(;;) {
        const int result = LC32InvokeHostCRet32(
            hostPtr, argc, argv,
            principalClassName.host_self, delegateClassName.host_self);
        if(result != LC32_UIKIT_RUNLOOP_DEBUGGER_STOP) {
            return result;
        }
        /* The host run loop returned because the guest debugger stopped the
         * process. The guest JIT halts at this host call; when the debugger
         * resumes, re-enter the host run loop so the app keeps running. */
    }
}

static pthread_once_t LC32UIImageCGImageOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32UIImageCGImageSelector;
static pthread_once_t LC32UIKitGeometryOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32UIKitNSStringFromCGSize;
static uint64_t LC32UIKitNSStringFromCGPoint;
static uint64_t LC32UIKitCGSizeFromString;
static uint64_t LC32UIKitCGRectFromString;
static uint64_t LC32UIKitBeginImageContext;
static uint64_t LC32UIKitBeginImageContextWithOptions;
static uint64_t LC32UIKitEndImageContext;
static uint64_t LC32UIKitPushContext;
static uint64_t LC32UIKitPopContext;
static uint64_t LC32UIKitGetCurrentContext;
static uint64_t LC32UIKitGetImageFromCurrentImageContext;
static uint64_t LC32UIKitJPEGRepresentation;
static uint64_t LC32UIKitPNGRepresentation;
static uint64_t LC32UIKitWriteImageToSavedPhotosAlbum;
static uint64_t LC32UIKitNSStringFromCGRect;
static uint64_t LC32UIKitGetWindowRootViewController;
static uint64_t LC32UIKitSetWindowRootViewController;
static void LC32UIImageResolveCGImageSelector(void) {
    LC32UIImageCGImageSelector = LC32GetHostSelector(@selector(CGImage));
}

static void LC32UIKitResolveGeometryFunctions(void) {
    LC32UIKitNSStringFromCGSize =
        LC32Dlsym("LC32_UIKit_NSStringFromCGSize", YES);
    LC32UIKitNSStringFromCGPoint =
        LC32Dlsym("LC32_UIKit_NSStringFromCGPoint", YES);
    LC32UIKitCGSizeFromString =
        LC32Dlsym("LC32_UIKit_CGSizeFromString", YES);
    LC32UIKitCGRectFromString =
        LC32Dlsym("LC32_UIKit_CGRectFromString", YES);
    LC32UIKitBeginImageContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsBeginImageContext", YES);
    LC32UIKitBeginImageContextWithOptions = LC32Dlsym(
        "LC32_UIKit_UIGraphicsBeginImageContextWithOptions", YES);
    LC32UIKitEndImageContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsEndImageContext", YES);
    LC32UIKitPushContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsPushContext", YES);
    LC32UIKitPopContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsPopContext", YES);
    LC32UIKitGetCurrentContext =
        LC32Dlsym("LC32_UIKit_UIGraphicsGetCurrentContext", YES);
    LC32UIKitGetImageFromCurrentImageContext = LC32Dlsym(
        "LC32_UIKit_UIGraphicsGetImageFromCurrentImageContext", YES);
    LC32UIKitJPEGRepresentation =
        LC32Dlsym("LC32_UIKit_UIImageJPEGRepresentation", YES);
    LC32UIKitPNGRepresentation =
        LC32Dlsym("LC32_UIKit_UIImagePNGRepresentation", YES);
    LC32UIKitWriteImageToSavedPhotosAlbum = LC32Dlsym(
        "LC32_UIKit_UIImageWriteToSavedPhotosAlbum", YES);
    LC32UIKitNSStringFromCGRect =
        LC32Dlsym("LC32_UIKit_NSStringFromCGRect", YES);
    LC32UIKitGetWindowRootViewController = LC32Dlsym(
        "LC32_UIKit_GetWindowRootViewController", YES);
    LC32UIKitSetWindowRootViewController = LC32Dlsym(
        "LC32_UIKit_SetWindowRootViewController", YES);
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

NSString *NSStringFromCGPoint(CGPoint point) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitNSStringFromCGPoint) return nil;
    const uint32_t guestString = LC32InvokeHostCRet32(
        LC32UIKitNSStringFromCGPoint,
        LC32UIKitFloatBits(point.x),
        LC32UIKitFloatBits(point.y));
    return (__bridge NSString *)(void *)(uintptr_t)guestString;
}

NSString *NSStringFromCGRect(CGRect rect) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitNSStringFromCGRect) return nil;
    const uint32_t guestString = LC32InvokeHostCRet32(
        LC32UIKitNSStringFromCGRect,
        LC32UIKitFloatBits(rect.origin.x),
        LC32UIKitFloatBits(rect.origin.y),
        LC32UIKitFloatBits(rect.size.width),
        LC32UIKitFloatBits(rect.size.height));
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

CGRect CGRectFromString(NSString *string) {
    CGRect result = CGRectZero;
    if(!string) return result;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitCGRectFromString) return result;
    const uint32_t guestResult = (uint32_t)(uintptr_t)&result;
    if(!LC32InvokeHostCRet32(LC32UIKitCGRectFromString,
            string.host_self, (uint64_t)guestResult)) {
        return CGRectZero;
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

void UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque,
                                             CGFloat scale) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitBeginImageContextWithOptions) return;
    LC32InvokeHostCRet32(LC32UIKitBeginImageContextWithOptions,
        LC32UIKitFloatBits(size.width),
        LC32UIKitFloatBits(size.height),
        (uint32_t)opaque, LC32UIKitFloatBits(scale));
}

void UIGraphicsEndImageContext(void) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(LC32UIKitEndImageContext)
        LC32InvokeHostCRet32(LC32UIKitEndImageContext);
}

void UIGraphicsPushContext(CGContextRef context) {
    if(!context) return;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(LC32UIKitPushContext) {
        LC32InvokeHostCRet32(LC32UIKitPushContext,
            [(__bridge id)context host_self]);
    }
}

void UIGraphicsPopContext(void) {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(LC32UIKitPopContext)
        LC32InvokeHostCRet32(LC32UIKitPopContext);
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

NSData *UIImageJPEGRepresentation(UIImage *image,
                                  CGFloat compressionQuality) {
    if(!image) return nil;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitJPEGRepresentation) return nil;
    const uint32_t guestData = LC32InvokeHostCRet32(
        LC32UIKitJPEGRepresentation, image.host_self,
        LC32UIKitFloatBits(compressionQuality));
    return (__bridge NSData *)(void *)(uintptr_t)guestData;
}

NSData *UIImagePNGRepresentation(UIImage *image) {
    if(!image) return nil;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitPNGRepresentation) return nil;
    const uint32_t guestData = LC32InvokeHostCRet32(
        LC32UIKitPNGRepresentation, image.host_self);
    return (__bridge NSData *)(void *)(uintptr_t)guestData;
}

void UIImageWriteToSavedPhotosAlbum(UIImage *image,
                                    id completionTarget,
                                    SEL completionSelector,
                                    void *contextInfo) {
    if(!image) return;
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitWriteImageToSavedPhotosAlbum) return;
    const uint64_t hostSelector = completionSelector
        ? LC32GetHostSelector(completionSelector) : 0;
    LC32InvokeHostCRet32(LC32UIKitWriteImageToSavedPhotosAlbum,
        image.host_self,
        [completionTarget host_self],
        hostSelector,
        (uint32_t)(uintptr_t)contextInfo);
}

@implementation UIWindow (LC32MainThreadRootViewController)

- (UIViewController *)rootViewController {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitGetWindowRootViewController) return nil;
    const uint32_t guestController = LC32InvokeHostCRet32(
        LC32UIKitGetWindowRootViewController, self.host_self);
    return (__bridge UIViewController *)(void *)(uintptr_t)guestController;
}

- (void)setRootViewController:(UIViewController *)rootViewController {
    pthread_once(&LC32UIKitGeometryOnce,
        LC32UIKitResolveGeometryFunctions);
    if(!LC32UIKitSetWindowRootViewController) return;
    LC32InvokeHostCRet32(LC32UIKitSetWindowRootViewController,
        self.host_self, [rootViewController host_self]);
}

@end

@implementation UIColor (LC32CoreGraphics)

- (CGColorRef)CGColor {
    /*
     * CGColorRef is an Objective-C-compatible CF object, but the generator
     * sees its opaque C pointer spelling and omits this selector.  Convert
     * the native borrowed result to its guest proxy while it is still
     * protected by the host call's +0 return convention.
     */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return (__bridge CGColorRef)LC32InvokeHostObjectSelector(
        self.host_self, selector);
}

@end

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
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, hostImage, (uint64_t)0);
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
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, hostImage, hostScale, hostOrientation,
        (uint64_t)0);
}

- (CGImageRef)CGImage {
    pthread_once(&LC32UIImageCGImageOnce,
        LC32UIImageResolveCGImageSelector);
    return (__bridge CGImageRef)LC32InvokeHostObjectSelector(
        self.host_self, LC32UIImageCGImageSelector);
}

@end

@implementation UIDevice (LC32LegacyUniqueIdentifier)

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if(LC32RequiresLegacyIPadCanvas()) {
        return UIUserInterfaceIdiomPad;
    }

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return (UIUserInterfaceIdiom)LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0);
}

- (NSString *)uniqueIdentifier {
    /* uniqueIdentifier was removed from UIDevice in iOS 7. Legacy apps call
     * it to fingerprint the install; synthesize one from the modern
     * identifierForVendor (stable per vendor per device), which both
     * forwarding shims already provide for the guest. */
    return self.identifierForVendor.UUIDString;
}

@end

@implementation UIScreen (LC32LegacyIPadCanvas)

- (CGRect)bounds {
    CGRect bounds = LC32HostScreenRect(self, _cmd);
    if(LC32ScreenNeedsLegacyIPadCanvas(bounds)) {
        bounds = CGRectMake(0, 0, 768, 1024);
    }
    return bounds;
}

- (CGRect)applicationFrame {
    CGRect frame = LC32HostScreenRect(self, _cmd);
    if(LC32ScreenNeedsLegacyIPadCanvas(frame)) {
        /* iOS 3.x iPad applications laid out below a 20-point status bar.
         * Preserve it when visible; full-screen apps use -bounds instead. */
        frame = LC32LegacyIPadStatusBarHidden
            ? CGRectMake(0, 0, 768, 1024)
            : CGRectMake(0, 20, 768, 1004);
    }
    return frame;
}

- (CGFloat)scale {
    const CGRect bounds = LC32HostScreenRect(self, @selector(bounds));
    if(LC32ScreenNeedsLegacyIPadCanvas(bounds)) {
        return 1.0f;
    }

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return (CGFloat)LC32HostFloatingResult(LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0));
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
