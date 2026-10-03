#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <initializer_list>
#include <mach-o/loader.h>
#include <ptrauth.h>
#include <stdint.h>
#include <string.h>

@interface UIViewController (LC32LegacyPresentation)
- (void)presentViewController:(UIViewController *)presented
              withTransition:(int)transition completion:(void (^)(void))completion;
- (void)_windowControllerBasedPresentViewController:(UIViewController *)presented
                                    withTransition:(int)transition completion:(void (^)(void))completion;
- (void)_didFinishDismissTransition:(UIViewController *)dismissed;
@end

struct LC32AlertBuildVersion { uint32_t platform, version; };
extern "C" bool dyld_program_sdk_at_least(LC32AlertBuildVersion version);

namespace {
struct NativeMethod {
    Class owner;
    SEL selector;
    Method method;
    IMP original;
};

NativeMethod alertPolicy, publicPresent, modernPresent, viewInit, viewHosting;
NativeMethod windowPolicy, publicDismiss, privateDismiss, finishDismiss, finishDismissWithController;
NativeMethod alertAnimator, builtinDelegate, builtinDuration, builtinAnimator;

void *CodeAddress(void *address) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(address, ptrauth_key_function_pointer);
#else
    return address;
#endif
}

bool Prepare(NativeMethod &entry, Class owner, const char *name,
             const char *result, std::initializer_list<const char *> arguments,
             void *nativeImage) {
    if(!owner) return false;
    entry.owner = owner;
    entry.selector = sel_registerName(name);
    entry.method = class_getInstanceMethod(owner, entry.selector);
    if(!entry.method || method_getNumberOfArguments(entry.method) != arguments.size() + 2)
        return false;
    char type[128];
    method_getReturnType(entry.method, type, sizeof(type));
    if(strcmp(type, result)) return false;
    unsigned index = 2;
    for(const char *argument : arguments) {
        method_getArgumentType(entry.method, index++, type, sizeof(type));
        if(strcmp(type, argument)) return false;
    }
    entry.original = method_getImplementation(entry.method);
    void *address = CodeAddress((void *)entry.original);
    Dl_info info = {};
    // Require native method boundaries, not a previously installed trampoline.
    // Return-address classification below must never broaden to arbitrary code.
    return dladdr(address, &info) && info.dli_fbase == nativeImage && info.dli_saddr == address;
}

void Replace(const NativeMethod &entry, IMP replacement) {
    class_replaceMethod(entry.owner, entry.selector, replacement,
        method_getTypeEncoding(entry.method));
}

// UIKit's policy helper tail-calls this UIWindow class method. Select a modern
// branch only in the exact original native method currently handling an alert.
// Other policy reads, including window rotation/layout, retain the real SDK.
thread_local void *policyCaller;
struct PolicyScope {
    void *previous = policyCaller;
    PolicyScope(BOOL alert, const NativeMethod &method) {
        policyCaller = alert ? CodeAddress((void *)method.original) : nullptr;
    }
    ~PolicyScope() { policyCaller = previous; }
    PolicyScope(const PolicyScope &) = delete;
    PolicyScope &operator=(const PolicyScope &) = delete;
};

__attribute__((noinline)) BOOL TransformPolicy(id self, SEL selector) {
    if(policyCaller) {
        void *returnPC = CodeAddress(__builtin_extract_return_addr(__builtin_return_address(0)));
        Dl_info info = {};
        // Look inside the calling instruction, not the next function boundary.
        if(dladdr((void *)((uintptr_t)returnPC - 1), &info) && info.dli_saddr == policyCaller)
            return YES;
    }
    return ((BOOL (*)(id, SEL))windowPolicy.original)(self, selector);
}

BOOL IsAlert(id object) { return [object isKindOfClass:UIAlertController.class]; }

BOOL DismissesAlert(UIViewController *controller) {
    // An ordinary child presented by an alert is not an alert dismissal.
    UIViewController *child = controller.presentedViewController;
    return IsAlert(child ?: controller);
}

BOOL BuiltinAnimatesAlert(id animator) {
    id delegate = ((id (*)(id, SEL))objc_msgSend)(animator, builtinDelegate.selector);
    return [delegate isKindOfClass:UIPresentationController.class] &&
        IsAlert([(UIPresentationController *)delegate presentedViewController]);
}

BOOL UseAlertPresentationController(id, SEL) { return YES; }

void ResumeLegacyPresentation(UIViewController *self, SEL, UIViewController *presented,
                              int transition, void (^completion)(void)) {
    [self presentViewController:presented withTransition:transition completion:completion];
}

void RestoreDelayedPresentation(void) {
    Class controller = UIViewController.class;
    SEL resume = @selector(_windowControllerBasedPresentViewController:withTransition:completion:);
    if([controller instancesRespondToSelector:resume]) return;
    Method present = class_getInstanceMethod(controller,
        @selector(presentViewController:withTransition:completion:));
    if(!present) return;
    // iOS 15 inlined the old method into presentViewController:withTransition:
    // completion:, but its delayed-presentation branch still builds an
    // NSInvocation for the removed selector (e.g. Game Center authentication).
    // Restore only that entry point, including its native argument encoding.
    class_addMethod(controller, resume, (IMP)ResumeLegacyPresentation,
        method_getTypeEncoding(present));
}

void Present(id self, SEL selector, UIViewController *presented, BOOL animated,
             void (^completion)(void)) {
    // Suppress an enclosing alert scope if user completion code starts a new
    // presentation synchronously. This method needs no policy override itself.
    PolicyScope scope(NO, publicPresent);
    if(!IsAlert(presented)) {
        ((void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))publicPresent.original)(
            self, selector, presented, animated, completion);
        return;
    }
    void (^modernCompletion)(BOOL) = nil;
    if(completion) modernCompletion = ^(BOOL) { completion(); };
    ((void (*)(id, SEL, UIViewController *, BOOL, void (^)(BOOL)))objc_msgSend)(
        self, modernPresent.selector, presented, animated, modernCompletion);
}

typedef id (*ViewInitializer)(id __attribute__((ns_consumed)), SEL, CGRect)
    __attribute__((ns_returns_retained));
id InitializeAlertView(id self __attribute__((ns_consumed)), SEL selector,
                       CGRect frame) __attribute__((ns_returns_retained));
id InitializeAlertView(id self __attribute__((ns_consumed)), SEL selector, CGRect frame) {
    self = ((ViewInitializer)viewInit.original)(self, selector, frame);
    if(self) {
        // Match this native alert root's modern initialization. Its pre-iOS-8
        // host/autoresizing setup otherwise stretches an empty action-sheet
        // header across the window. Stop hosting before setting TAMIC to NO.
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, viewHosting.selector, NO);
        [(UIView *)self setTranslatesAutoresizingMaskIntoConstraints:NO];
        [(UIView *)self setAutoresizingMask:UIViewAutoresizingNone];
    }
    return self;
}

void Dismiss(UIViewController *self, SEL selector, int transition, void (^completion)(void)) {
    PolicyScope scope(DismissesAlert(self), publicDismiss);
    ((void (*)(id, SEL, int, void (^)(void)))publicDismiss.original)(
        self, selector, transition, completion);
}

void DismissFrom(UIViewController *self, SEL selector, int transition,
                 UIViewController *from, void (^completion)(void)) {
    PolicyScope scope(from ? IsAlert(from) : DismissesAlert(self), privateDismiss);
    ((void (*)(id, SEL, int, UIViewController *, void (^)(void)))privateDismiss.original)(
        self, selector, transition, from, completion);
}

void FinishDismiss(UIViewController *self, SEL selector) {
    PolicyScope scope(DismissesAlert(self), finishDismiss);
    ((void (*)(id, SEL))finishDismiss.original)(self, selector);
}

void FinishDismissWithController(UIViewController *self, SEL selector, UIViewController *dismissed) {
    // Newer UIKit passes the dismissed child explicitly; the old no-argument
    // selector is only a notification there. Older releases use the latter.
    PolicyScope scope(IsAlert(dismissed), finishDismissWithController);
    ((void (*)(id, SEL, UIViewController *))finishDismissWithController.original)(self, selector, dismissed);
}

void AnimateAlert(id self, SEL selector, id<UIViewControllerContextTransitioning> context,
                   void (^completion)(BOOL)) {
    BOOL alert = IsAlert([context viewControllerForKey:UITransitionContextFromViewControllerKey]) ||
        IsAlert([context viewControllerForKey:UITransitionContextToViewControllerKey]);
    PolicyScope scope(alert, alertAnimator);
    // The modern context deliberately returns no underlying presenter view.
    // The legacy animator instead grabs toViewController.view during dismissal,
    // reparents it into its temporary container and leaves the app invisible.
    ((void (*)(id, SEL, id, void (^)(BOOL)))alertAnimator.original)(self, selector, context, completion);
}

CGFloat BuiltinDuration(id self, SEL selector, int transition) {
    PolicyScope scope(BuiltinAnimatesAlert(self), builtinDuration);
    return ((CGFloat (*)(id, SEL, int))builtinDuration.original)(self, selector, transition);
}

void AnimateBuiltin(id self, SEL selector, id context) {
    PolicyScope scope(BuiltinAnimatesAlert(self), builtinAnimator);
    // Native nonanimated alerts use this animator too. Both its duration and
    // animation phases must use the modern context, not legacy view/delegate
    // callbacks that a UIAlertController presentation controller cannot serve.
    ((void (*)(id, SEL, id))builtinAnimator.original)(self, selector, context);
}

bool PrepareHooks(void) {
    Dl_info image = {};
    if(!dladdr((__bridge const void *)UIViewController.class, &image)) return false;
    void *nativeImage = image.dli_fbase;
    Class controller = UIViewController.class;
    Class alertView = NSClassFromString(@"_UIAlertControllerPhoneTVMacView");
    Class animator = NSClassFromString(@"_UIAlertControllerAnimatedTransitioning");
    Class builtin = NSClassFromString(@"UIViewControllerBuiltinTransitionViewAnimator");
    if(!Prepare(alertPolicy, object_getClass(UIAlertController.class), "_shouldUsePresentationController", "B", {}, nativeImage) ||
       !Prepare(publicPresent, controller, "presentViewController:animated:completion:", "v", {"@", "B", "@?"}, nativeImage) ||
       !Prepare(modernPresent, controller, "_presentViewController:animated:completion:", "v", {"@", "B", "@?"}, nativeImage) ||
       !Prepare(viewInit, alertView, "initWithFrame:", "@", {@encode(CGRect)}, nativeImage) ||
       !Prepare(viewHosting, alertView, "_setHostsLayoutEngine:", "v", {"B"}, nativeImage) ||
       !Prepare(windowPolicy, object_getClass(UIWindow.class), "_transformLayerRotationsAreEnabled", "B", {}, nativeImage) ||
       !Prepare(publicDismiss, controller, "dismissViewControllerWithTransition:completion:", "v", {"i", "@?"}, nativeImage) ||
       !Prepare(privateDismiss, controller, "_dismissViewControllerWithTransition:from:completion:", "v", {"i", "@", "@?"}, nativeImage) ||
       !Prepare(finishDismiss, controller, "_didFinishDismissTransition", "v", {}, nativeImage) ||
       !Prepare(alertAnimator, animator, "_animateTransition:completionBlock:", "v", {"@", "@?"}, nativeImage) ||
       !Prepare(builtinDelegate, builtin, "delegate", "@", {}, nativeImage) ||
       !Prepare(builtinDuration, builtin, "durationForTransition:", @encode(CGFloat), {"i"}, nativeImage) ||
       !Prepare(builtinAnimator, builtin, "animateTransition:", "v", {"@"}, nativeImage)) return false;
    if([controller instancesRespondToSelector:@selector(_didFinishDismissTransition:)] &&
       !Prepare(finishDismissWithController, controller, "_didFinishDismissTransition:", "v", {"@"}, nativeImage))
        return false;
    return true;
}
} // namespace

@interface LC32LegacyAlerts : NSObject
@end
@implementation LC32LegacyAlerts
+ (void)load {
    if(dyld_program_sdk_at_least({PLATFORM_IOS, 0x00080000})) return;
    // This missing-selector repair does not depend on the alert-specific
    // presentation/layout hooks being available on this UIKit release.
    RestoreDelayedPresentation();
    // Presentation, layout and dismissal are a matched native flow. Install
    // nothing if this UIKit version (or an earlier hook) lacks a prerequisite.
    if(!PrepareHooks()) return;
    Replace(alertPolicy, (IMP)UseAlertPresentationController);
    Replace(publicPresent, (IMP)Present);
    Replace(viewInit, (IMP)InitializeAlertView);
    Replace(windowPolicy, (IMP)TransformPolicy);
    Replace(publicDismiss, (IMP)Dismiss);
    Replace(privateDismiss, (IMP)DismissFrom);
    Replace(finishDismiss, (IMP)FinishDismiss);
    if(finishDismissWithController.method)
        Replace(finishDismissWithController, (IMP)FinishDismissWithController);
    Replace(alertAnimator, (IMP)AnimateAlert);
    Replace(builtinDuration, (IMP)BuiltinDuration);
    Replace(builtinAnimator, (IMP)AnimateBuiltin);
}
@end
