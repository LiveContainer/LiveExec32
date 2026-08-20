@import Darwin;
@import UIKit;
#import <objc/runtime.h>
#include "bridge.h"

#include <dispatch/dispatch.h>

/*
symbol = r0 + r1 << 32
r0 = r2
r1 = r3
r2 = sp
r3 = sp+4
...
*/

namespace {

bool LC32GuestIsIPadOnly(void) {
    const char *guestExecutable = getenv("LC32_GUEST_EXECUTABLE");
    /* UIKit can create internal windows while the shim dylib is loading.
     * Do not consume the cache until main.cpp has published the guest. */
    if(!guestExecutable || !guestExecutable[0]) return false;

    static bool result = false;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSString stringWithUTF8String:
            getenv("LC32_GUEST_EXECUTABLE")];
        NSBundle *bundle = [NSBundle bundleWithPath:
            path.stringByDeletingLastPathComponent];
        NSArray *families = [bundle objectForInfoDictionaryKey:
            @"UIDeviceFamily"];
        bool supportsPhone = false;
        bool supportsPad = false;
        if([families isKindOfClass:NSArray.class]) {
            for(id family in families) {
                if(![family respondsToSelector:@selector(integerValue)]) {
                    continue;
                }
                const NSInteger value = [family integerValue];
                supportsPhone |= value == 1;
                supportsPad |= value == 2;
            }
        }
        result = supportsPad && !supportsPhone;
    });
    return result;
}

const void *LC32LegacyIPadWindowBoundsKey =
    &LC32LegacyIPadWindowBoundsKey;
const void *LC32LegacyIPadWindowBaseTransformKey =
    &LC32LegacyIPadWindowBaseTransformKey;
const void *LC32LegacyIPadWindowAppliedTransformKey =
    &LC32LegacyIPadWindowAppliedTransformKey;

CGAffineTransform LC32WindowOrientationTransform(
        CGAffineTransform transform) {
    /* A later UIKit orientation update can be composed with the fit scale
     * that this shim installed previously. Reduce each linear basis vector
     * back to unit length before treating it as the new orientation, or a
     * subsequent pass would fit an already-scaled window a second time. */
    const CGFloat xLength = hypot(transform.a, transform.b);
    const CGFloat yLength = hypot(transform.c, transform.d);
    if(xLength > 0) {
        transform.a /= xLength;
        transform.b /= xLength;
    }
    if(yLength > 0) {
        transform.c /= yLength;
        transform.d /= yLength;
    }
    transform.tx = 0;
    transform.ty = 0;
    return transform;
}

void LC32ScaleLegacyIPadWindow(UIWindow *window) {
    /* UIKit owns additional keyboard, alert, and text-effects windows in the
     * same process. Only scale a UIWindow that is actually paired with a
     * guest object. */
    if(!window || !window.guest_selfOrNull || !LC32GuestIsIPadOnly()) return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    /* A classic/compatibility scene can be landscape while UIScreen still
     * reports the device's physical portrait bounds. UIWindow geometry is
     * expressed in the scene coordinate space, so fit and center there. */
    id<UICoordinateSpace> sceneSpace = window.windowScene.coordinateSpace;
    const CGRect hostBounds = sceneSpace ? sceneSpace.bounds : screen.bounds;
    const CGFloat hostShortEdge = MIN(hostBounds.size.width,
                                      hostBounds.size.height);
    if(hostShortEdge <= 0 || hostShortEdge >= 600) return;

    NSValue *savedValue = objc_getAssociatedObject(
        window, LC32LegacyIPadWindowBoundsKey);
    CGRect virtualBounds = savedValue
        ? savedValue.CGRectValue : window.bounds;
    if(virtualBounds.size.width < 700 ||
            virtualBounds.size.height < 900) {
        virtualBounds = CGRectMake(0, 0, 768, 1024);
    }
    if(!savedValue) {
        objc_setAssociatedObject(window, LC32LegacyIPadWindowBoundsKey,
            [NSValue valueWithCGRect:virtualBounds],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    const CGAffineTransform currentTransform = window.transform;
    NSValue *baseTransformValue = objc_getAssociatedObject(
        window, LC32LegacyIPadWindowBaseTransformKey);
    NSValue *appliedTransformValue = objc_getAssociatedObject(
        window, LC32LegacyIPadWindowAppliedTransformKey);
    const CGAffineTransform lastApplied = appliedTransformValue
        ? appliedTransformValue.CGAffineTransformValue
        : CGAffineTransformIdentity;
    const CGAffineTransform baseTransform =
        baseTransformValue && appliedTransformValue &&
            CGAffineTransformEqualToTransform(
                currentTransform, lastApplied)
        ? baseTransformValue.CGAffineTransformValue
        : LC32WindowOrientationTransform(currentTransform);

    /* Keep the raw portrait bounds used by the guest view and EAGL layer.
     * UIKit's quarter-turn transforms this 768x1024 extent into landscape
     * 1024x768 for composition. Swapping the bounds here rotates twice and
     * desynchronizes the EAGL viewport from its drawable storage. */
    const CGRect transformedVirtualBounds = CGRectApplyAffineTransform(
        CGRectMake(0, 0, virtualBounds.size.width,
                   virtualBounds.size.height), baseTransform);
    const CGFloat transformedWidth =
        fabs(transformedVirtualBounds.size.width);
    const CGFloat transformedHeight =
        fabs(transformedVirtualBounds.size.height);
    if(!(transformedWidth > 0) || !(transformedHeight > 0)) return;

    const CGFloat scale = MIN(
        hostBounds.size.width / transformedWidth,
        hostBounds.size.height / transformedHeight);
    if(!(scale > 0)) return;

    /* Keep one coherent virtual coordinate system. Core Animation scales the
     * entire window into the host scene, and UIKit's normal coordinate
     * conversion applies the inverse transform to touches before guest
     * callbacks are bridged. */
    window.transform = CGAffineTransformIdentity;
    window.bounds = virtualBounds;
    window.center = CGPointMake(CGRectGetMidX(hostBounds),
                                CGRectGetMidY(hostBounds));
    CGAffineTransform appliedTransform = baseTransform;
    appliedTransform.a *= scale;
    appliedTransform.b *= scale;
    appliedTransform.c *= scale;
    appliedTransform.d *= scale;
    /* bounds + center now own the placement. UIKit's old orientation
     * translation was calculated for the pre-virtualized window and would
     * otherwise shift the scaled canvas away from the host center. */
    appliedTransform.tx = 0;
    appliedTransform.ty = 0;
    window.transform = appliedTransform;
    window.clipsToBounds = YES;
    objc_setAssociatedObject(window, LC32LegacyIPadWindowBaseTransformKey,
        [NSValue valueWithCGAffineTransform:baseTransform],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window,
        LC32LegacyIPadWindowAppliedTransformKey,
        [NSValue valueWithCGAffineTransform:appliedTransform],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

}

UIViewController *LC32OwningViewController(UIView *view) {
    for(UIResponder *responder = view; responder;
            responder = responder.nextResponder) {
        if([responder isKindOfClass:UIViewController.class]) {
            return (UIViewController *)responder;
        }
        if([responder isKindOfClass:UIWindow.class]) break;
    }
    for(UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIViewController *controller = LC32OwningViewController(subview);
        if(controller) return controller;
    }
    return nil;
}

id LC32ObjectProperty(id object, const char *name) {
    SEL selector = sel_registerName(name);
    if(!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch(NSException *) {
        return nil;
    }
}

void LC32AdoptLegacyRootViewController(UIWindow *window) {
    if(!window) return;
    if(window.rootViewController) return;

    UIViewController *controller = nil;
    for(UIView *subview in [window.subviews reverseObjectEnumerator]) {
        controller = LC32OwningViewController(subview);
        if(controller) break;
    }

    id delegate = UIApplication.sharedApplication.delegate;
    UIWindow *delegateWindow = LC32ObjectProperty(delegate, "window");
    if(!controller && (!delegateWindow || delegateWindow == window)) {
        static const char *const candidateProperties[] = {
            "rootViewController", "viewController", "mainViewController",
            "navigationController",
        };
        for(const char *property : candidateProperties) {
            id candidate = LC32ObjectProperty(delegate, property);
            if([candidate isKindOfClass:UIViewController.class]) {
                controller = candidate;
                break;
            }
        }
    }

    if(controller) {
        window.rootViewController = controller;
        fprintf(stderr, "LC32: adopted legacy root view controller %s\n",
                object_getClassName(controller));
    }
}

void LC32AdoptLegacyRootViewControllers(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *delegateWindow = LC32ObjectProperty(application.delegate,
                                                   "window");
    if(delegateWindow) {
        LC32AdoptLegacyRootViewController(delegateWindow);
        LC32ScaleLegacyIPadWindow(delegateWindow);
        return;
    }
    for(UIScene *scene in application.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            LC32AdoptLegacyRootViewController(window);
            LC32ScaleLegacyIPadWindow(window);
        }
    }
}

} // namespace

@interface UIWindow (LC32LegacyRootViewController)
- (void)lc32_makeKeyAndVisible;
@end

@implementation UIWindow (LC32LegacyRootViewController)

+ (void)load {
    Method original = class_getInstanceMethod(self,
                                               @selector(makeKeyAndVisible));
    Method compatibility = class_getInstanceMethod(
        self, @selector(lc32_makeKeyAndVisible));
    if(original && compatibility) {
        method_exchangeImplementations(original, compatibility);
    }
}

- (void)lc32_makeKeyAndVisible {
    LC32AdoptLegacyRootViewController(self);
    [self lc32_makeKeyAndVisible];
    /* Let UIKit attach the scene and install its unscaled orientation
     * transform first. Scaling before the native call makes UIKit compose
     * the quarter-turn with our fit transform, and a second pass then fits
     * that already-scaled result again. */
    LC32ScaleLegacyIPadWindow(self);
}

@end

/*
 * Sentinel returned to the guest UIApplicationMain shim when the host run
 * loop was interrupted by a guest-debugger all-stop. The guest shim loops
 * back and re-enters this function, which then drives the run loop directly
 * (the app object and delegate already exist). Keep the value in sync with
 * GuestFrameworks/UIKit/UIKit.m.
 */
static const int LC32UIKITRunLoopDebuggerStop = 0x1C32DEAD;

/*
 * The guest debugger can request an all-stop (worker crash, ^C, breakpoint)
 * while the guest main thread is parked inside the host UIApplicationMain run
 * loop. That blocking mach_msg lives in CoreFoundation and is not tracked by
 * the coordinator's debuggerMachCalls, so it cannot be aborted like a guest
 * SVC wait. GSEventRunModal(0) also loops forever, so CFRunLoopStop alone
 * cannot make UIApplicationMain return. Instead the notifier below wakes the
 * main run loop and its armed block unwinds the run loop via a caught
 * Objective-C exception, returning control to the guest JIT so the stop
 * reply is delivered. Once the debugger resumes, the guest shim re-enters
 * this function and LC32RunDebuggerAwareMainRunLoop drives the run loop
 * directly with a poll, avoiding any further unwinding.
 */
@interface LC32DebuggerStopException : NSException
@end
@implementation LC32DebuggerStopException
@end

/* Non-zero only while UIApplicationMain's own run loop is executing, so the
 * notifier block only unwinds (throws) inside the @try below. */
static bool LC32RunLoopExceptionArmed = false;

static void LC32DebuggerStopRunLoopBlock(void) {
    if(LC32DebuggerAllStopRequested() && LC32RunLoopExceptionArmed) {
        @throw [LC32DebuggerStopException
            exceptionWithName:@"LC32DebuggerStopException"
                       reason:@"Guest debugger requested an all-stop"
                     userInfo:nil];
    }
}

static void LC32DebuggerStopRunLoopNotify(void) {
    CFRunLoopRef runLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
        LC32DebuggerStopRunLoopBlock();
    });
    CFRunLoopWakeUp(runLoop);
}

static int LC32RunDebuggerAwareMainRunLoop(void) {
    /* Re-entry after a debugger stop: the app object and delegate already
     * exist, so drive the run loop directly. The short timeout bounds stop
     * latency even if the wake-up is missed. */
    for(;;) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        if(LC32DebuggerAllStopRequested()) {
            return LC32UIKITRunLoopDebuggerStop;
        }
    }
}

__BEGIN_DECLS

int LC32_UIKit_UIApplicationMain(u32 r2, u32 r3, u32 sp) {
    int argc = r2;
    u32 guest_argv = r3;
    NSString *principalClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    NSString *delegateClassName = (id)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);

    NSLog(@"UIApplicationMain(%d, 0x%x, %@, %@)\n", argc, guest_argv, principalClassName, delegateClassName);
    static id launchObserver;
    launchObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:nil
                usingBlock:^(__unused NSNotification *notification) {
        LC32AdoptLegacyRootViewControllers();
    }];
    (void)launchObserver;
    char executableName[] = "exec";
    char *host_argv[] = {executableName, nullptr};

    static bool firstEntry = true;
    if(!firstEntry) {
        return LC32RunDebuggerAwareMainRunLoop();
    }
    firstEntry = false;
    if(!LC32DebuggerActive()) {
        return UIApplicationMain(
            argc, host_argv, principalClassName, delegateClassName);
    }

    LC32SetDebuggerStopRunLoopNotifier(
        LC32DebuggerStopRunLoopNotify);
    LC32RunLoopExceptionArmed = true;
    int result;
    @try {
        result = UIApplicationMain(
            argc, host_argv, principalClassName, delegateClassName);
    } @catch(LC32DebuggerStopException *exception) {
        LC32RunLoopExceptionArmed = false;
        fprintf(stderr,
            "LC32: host run loop interrupted by guest debugger stop\n");
        fflush(stderr);
        return LC32UIKITRunLoopDebuggerStop;
    }
    LC32RunLoopExceptionArmed = false;
    fprintf(stderr,
        "LC32: host UIApplicationMain returned %d\n", result);
    fflush(stderr);
    return result;
}

u32 LC32_UIKit_NSStringFromCGSize(u32 widthBits, u32 heightBits, u32) {
    float width;
    float height;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    return NSStringFromCGSize(CGSizeMake(width, height)).guest_self;
}

u32 LC32_UIKit_CGSizeFromString(u32 stringLow, u32 stringHigh, u32 sp) {
    NSString *string = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(stringLow |
            (static_cast<u64>(stringHigh) << 32)));
    const u32 guestResult =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    if(!string || !guestResult || guestResult > UINT32_MAX - 7)
        return 0;

    const CGSize size = CGSizeFromString(string);
    const struct {
        float width;
        float height;
    } guestSize = {
        static_cast<float>(size.width),
        static_cast<float>(size.height),
    };
    return Dynarmic_mem_1write(guestResult, sizeof(guestSize),
        const_cast<char *>(reinterpret_cast<const char *>(&guestSize))) == 0;
}

u32 LC32_UIKit_CGRectFromString(u32 stringLow, u32 stringHigh, u32 sp) {
    NSString *string = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(stringLow |
            (static_cast<u64>(stringHigh) << 32)));
    const u32 guestResult =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    if(!string || !guestResult || guestResult > UINT32_MAX - 15)
        return 0;

    const CGRect rect = CGRectFromString(string);
    const struct {
        float x;
        float y;
        float width;
        float height;
    } guestRect = {
        static_cast<float>(rect.origin.x),
        static_cast<float>(rect.origin.y),
        static_cast<float>(rect.size.width),
        static_cast<float>(rect.size.height),
    };
    return Dynarmic_mem_1write(guestResult, sizeof(guestRect),
        const_cast<char *>(reinterpret_cast<const char *>(&guestRect))) == 0;
}

void LC32_UIKit_UIGraphicsBeginImageContext(
        u32 widthBits, u32 heightBits, u32) {
    float width;
    float height;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
}

void LC32_UIKit_UIGraphicsBeginImageContextWithOptions(
        u32 widthBits, u32 heightBits, u32 sp) {
    float width;
    float height;
    float scale;
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    const BOOL opaque = Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 scaleBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + sizeof(u32));
    memcpy(&scale, &scaleBits, sizeof(scale));
    UIGraphicsBeginImageContextWithOptions(
        CGSizeMake(width, height), opaque, scale);
}

void LC32_UIKit_UIGraphicsEndImageContext(u32, u32, u32) {
    UIGraphicsEndImageContext();
}

u32 LC32_UIKit_UIGraphicsGetCurrentContext(u32, u32, u32) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    return context ? [(id)context guest_self] : 0;
}

u32 LC32_UIKit_UIGraphicsGetImageFromCurrentImageContext(u32, u32, u32) {
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    return image ? image.guest_self : 0;
}

u32 LC32_UIKit_UIImageJPEGRepresentation(
        u32 imageLow, u32 imageHigh, u32 sp) {
    UIImage *image = reinterpret_cast<UIImage *>(static_cast<uintptr_t>(
        imageLow | (static_cast<u64>(imageHigh) << 32)));
    const u32 qualityBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    float quality;
    memcpy(&quality, &qualityBits, sizeof(quality));
    NSData *data = image
        ? UIImageJPEGRepresentation(image, static_cast<CGFloat>(quality))
        : nil;
    return data ? data.guest_self : 0;
}

u32 LC32_UIKit_UIImagePNGRepresentation(u32 imageLow, u32 imageHigh, u32) {
    UIImage *image = reinterpret_cast<UIImage *>(static_cast<uintptr_t>(
        imageLow | (static_cast<u64>(imageHigh) << 32)));
    NSData *data = image ? UIImagePNGRepresentation(image) : nil;
    return data ? data.guest_self : 0;
}

u32 LC32_UIKit_NSStringFromCGRect(
        u32 xBits, u32 yBits, u32 sp) {
    float x;
    float y;
    float width;
    float height;
    memcpy(&x, &xBits, sizeof(x));
    memcpy(&y, &yBits, sizeof(y));
    const u32 widthBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp);
    const u32 heightBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(sp + sizeof(u32));
    memcpy(&width, &widthBits, sizeof(width));
    memcpy(&height, &heightBits, sizeof(height));
    return NSStringFromCGRect(CGRectMake(x, y, width, height)).guest_self;
}

void LC32_UIKit_SetWindowRootViewController(
        u32 windowLow, u32 windowHigh, u32 sp) {
    UIWindow *window = reinterpret_cast<UIWindow *>(static_cast<uintptr_t>(
        windowLow | (static_cast<u64>(windowHigh) << 32)));
    const u64 controllerAddress =
        Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    UIViewController *controller = reinterpret_cast<UIViewController *>(
        static_cast<uintptr_t>(controllerAddress));
    if(!window) return;

    dispatch_block_t setRoot = ^{
        /* The host mirror may itself be a guest-defined UIWindow subclass.
         * An ordinary objc_msgSend would re-enter that class's guest
         * trampoline and eventually arrive back at this helper.  Start the
         * lookup at the first native superclass, just as the generic selector
         * bridge does for guest-super calls. */
        Class dispatchClass = object_getClass(window);
        while(dispatchClass && [(id)dispatchClass isGuestClass]) {
            dispatchClass = class_getSuperclass(dispatchClass);
        }
        if(!dispatchClass) return;

        struct objc_super superInfo = {window, dispatchClass};
        using SetRootViewController =
            void (*)(struct objc_super *, SEL, UIViewController *);
        reinterpret_cast<SetRootViewController>(objc_msgSendSuper)(
            &superInfo, @selector(setRootViewController:), controller);
    };
    if(pthread_main_np()) {
        setRoot();
    } else {
        /* Guest network/operation callbacks execute on LC32's registered
         * callback pthread. UIKit still requires window hierarchy mutations
         * on the native main queue; dispatch_sync also preserves the legacy
         * method's synchronous completion contract. Block captures retain
         * both objects until the main-thread assignment has finished. */
        dispatch_sync(dispatch_get_main_queue(), setRoot);
    }
}

__END_DECLS
