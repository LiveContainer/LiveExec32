#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct SDKBuildVersion { uint32_t platform, version; };
extern uint32_t dyld_get_program_sdk_version(void);
extern bool dyld_program_sdk_at_least(struct SDKBuildVersion version);
/* The deliberately unpatched baseline does not link the production policy. */
#if LC32_TEST_LINKED_COMPATIBILITY_POLICY
extern uint32_t LC32UIKitLegacyCompatibilityEnabled(void);
#endif

#if LC32_TEST_EFFECTIVE_SDK_PROVIDER
/* The policy-only binary substitutes these two query names at compile time
 * in this file and LegacyAutoLayout.mm. Its real Mach-O remains SDK11. The
 * provider is ready before +load, like LiveContainer's pre-dlopen SDK hook,
 * but it deliberately does not interpose or alter UIKit's own dyld calls. */
static bool policyTestEnteredMain;
static unsigned policyQueriesBeforeMain;

uint32_t dyld_get_program_sdk_version(void) {
    if(!policyTestEnteredMain) ++policyQueriesBeforeMain;
    const char *value = getenv("LC32_TEST_EFFECTIVE_SDK");
    if(!value || !*value) abort();
    char *end = NULL;
    unsigned long sdk = strtoul(value, &end, 0);
    if(!end || *end || sdk > UINT32_MAX) abort();
    return (uint32_t)sdk;
}

bool dyld_program_sdk_at_least(struct SDKBuildVersion version) {
    return version.platform == PLATFORM_IOS &&
        version.version <= dyld_get_program_sdk_version();
}
#endif

static int failures;
static uint32_t expectedSDK, effectiveSDK;

static void check(const char *name, BOOL passed) {
    printf("sdk-layout-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static void uncaught(NSException *exception) {
    fprintf(stderr, "sdk-layout-uncaught: %s: %s\n",
        exception.name.UTF8String, exception.reason.UTF8String);
}

/* Read the actual main executable, not the compilation SDK or Info.plist. */
static BOOL checkBuildVersion(void) {
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    if(header->magic != MH_MAGIC_64) return NO;
    const unsigned char *cursor = (const unsigned char *)(header + 1);
    const unsigned char *end = cursor + header->sizeofcmds;
    for(uint32_t index = 0; index < header->ncmds; ++index) {
        if((size_t)(end - cursor) < sizeof(struct load_command)) return NO;
        const struct load_command *command = (const void *)cursor;
        if(command->cmdsize < sizeof(*command) ||
                command->cmdsize > (size_t)(end - cursor)) return NO;
        if(command->cmd == LC_BUILD_VERSION &&
                command->cmdsize >= sizeof(struct build_version_command)) {
            const struct build_version_command *build = (const void *)command;
            printf("sdk-layout-build: platform=%u minos=0x%08x sdk=0x%08x\n",
                build->platform, build->minos, build->sdk);
            return build->platform == PLATFORM_IOSSIMULATOR &&
                build->minos == 0x000b0000 && build->sdk == expectedSDK;
        }
        cursor += command->cmdsize;
    }
    return NO;
}

@interface SDKLayoutOptOutView : UIView
@end
@implementation SDKLayoutOptOutView
- (BOOL)_forceLayoutEngineSolutionInRationalEdges { return NO; }
@end

static void checkCompatibilityPolicy(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    expectedSDK = [[bundle objectForInfoDictionaryKey:@"LC32ExpectedSDK"]
        unsignedIntValue];
    BOOL hasFix = [[bundle objectForInfoDictionaryKey:@"LC32HasFix"] boolValue];
    check("actual-mach-o-sdk", checkBuildVersion());
    effectiveSDK = dyld_get_program_sdk_version();
    BOOL atLeast8 = dyld_program_sdk_at_least(
        (struct SDKBuildVersion){PLATFORM_IOS, 0x00080000});
    printf("sdk-layout-dyld: sdk=0x%08x at-least-ios8=%d fix=%d\n",
        effectiveSDK, atLeast8, hasFix);
    /* A zero Mach-O SDK has a dyld-defined fallback; do not treat it as
     * necessarily pre-8. Both the predicate and effective SDK are observed. */
    NSNumber *expectedEffectiveSDK = [bundle objectForInfoDictionaryKey:
        @"LC32ExpectedEffectiveSDK"];
    check("dyld-sdk", expectedEffectiveSDK
        ? effectiveSDK == expectedEffectiveSDK.unsignedIntValue
        : expectedSDK == 0 || effectiveSDK == expectedSDK);
    check("dyld-sdk-predicate", atLeast8 == (effectiveSDK >= 0x00080000));
    if(hasFix) {
#if LC32_TEST_LINKED_COMPATIBILITY_POLICY
        BOOL expectedCompatibility = [[bundle objectForInfoDictionaryKey:
            @"LC32ExpectedCompatibility"] boolValue];
        BOOL forcedOff = [[bundle objectForInfoDictionaryKey:
            @"LC32ForcedCompatibilityOff"] boolValue];
        const char *disable = getenv("LC32_DISABLE_UIKIT_COMPATIBILITY");
        check("compatibility-launch-environment",
            (disable && !strcmp(disable, "1")) == forcedOff);
        BOOL enabled = LC32UIKitLegacyCompatibilityEnabled() != 0;
        printf("sdk-layout-compatibility: enabled=%d expected=%d forced-off=%d\n",
            enabled, expectedCompatibility, forcedOff);
        check("compatibility-sdk-default-or-override",
            enabled == expectedCompatibility);
        check("compatibility-policy-stable",
            (LC32UIKitLegacyCompatibilityEnabled() != 0) == enabled);
#else
        check("production-compatibility-policy-linked", NO);
#endif
    }
#if LC32_TEST_EFFECTIVE_SDK_PROVIDER
    check("policy-provider-keeps-sdk11-executable", expectedSDK == 0x000b0000);
    check("effective-sdk-provider-active-during-load", policyQueriesBeforeMain != 0);
    puts("sdk-layout-policy-only: no UIKit geometry or system-wide SDK spoof is exercised");
    return;
#endif
    SEL selector = sel_registerName("_forceLayoutEngineSolutionInRationalEdges");
    Method method = class_getInstanceMethod([UIView class], selector);
    check("native-policy-selector", method != NULL);
    if(method) {
        BOOL (*send)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        check("base-opt-in-only-pre8", send([[UIView alloc] init], selector) ==
            (hasFix && !atLeast8));
        check("subclass-opt-out-preserved",
            !send([[SDKLayoutOptOutView alloc] init], selector));
    }
    selector = sel_registerName("_hostsLayoutEngineAllowsTAMIC_NO");
    BOOL (*send)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    if(!atLeast8) {
        check("ordinary-view-host-policy-unchanged",
            !send([[UIView alloc] init], selector));
        if(hasFix) {
            // Both native roots must receive the scoped YES implementation;
            // checking IMPs avoids constructing private keyboard views before
            // UIApplication has initialized. The text-field alert regression
            // separately exercises an actual UIRemoteKeyboardWindow root.
            IMP yesPolicy = class_getMethodImplementation([UIView class],
                sel_registerName("_forceLayoutEngineSolutionInRationalEdges"));
            for(NSString *name in @[@"UITrackingWindowView", @"UIInputSetContainerView"]) {
                Class hostClass = NSClassFromString(name);
                Method policy = hostClass ? class_getInstanceMethod(hostClass, selector) : NULL;
                if(policy) {
                    NSString *testName = [name stringByAppendingString:@"-host-policy-opt-in"];
                    check(testName.UTF8String, method_getImplementation(policy) == yesPolicy);
                } else {
                    printf("sdk-layout-%s-host-policy: SKIP (optional class/selector absent)\n",
                        name.UTF8String);
                }
            }
        }
    }
}

static BOOL sameRect(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.01 &&
        fabs(a.origin.y - b.origin.y) < 0.01 &&
        fabs(a.size.width - b.size.width) < 0.01 &&
        fabs(a.size.height - b.size.height) < 0.01;
}

@interface SDKLayoutViewController : UIViewController
@property(nonatomic, strong) UIView *canvas;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UILayoutGuide *guide;
- (void)checkSize:(CGSize)size stage:(const char *)stage;
@end

@implementation SDKLayoutViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    [self.view addSubview:self.canvas];
    self.guide = [[UILayoutGuide alloc] init];
    [self.canvas addLayoutGuide:self.guide];
    self.panel = [[UIView alloc] initWithFrame:CGRectZero];
    self.panel.backgroundColor = [UIColor blueColor];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.canvas addSubview:self.panel];
    puts("sdk-layout-stage: activating layout-guide constraints");
    [NSLayoutConstraint activateConstraints:@[
        [self.guide.leadingAnchor constraintEqualToAnchor:
            self.canvas.leadingAnchor constant:12],
        [self.guide.trailingAnchor constraintEqualToAnchor:
            self.canvas.trailingAnchor constant:-12],
        [self.guide.topAnchor constraintEqualToAnchor:
            self.canvas.topAnchor constant:20],
        [self.guide.bottomAnchor constraintEqualToAnchor:
            self.canvas.bottomAnchor constant:-20],
        [self.panel.leadingAnchor constraintEqualToAnchor:self.guide.leadingAnchor],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.guide.trailingAnchor],
        [self.panel.topAnchor constraintEqualToAnchor:self.guide.topAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:self.guide.bottomAnchor]
    ]];
    puts("sdk-layout-stage: constraints activated");
}

- (void)checkSize:(CGSize)size stage:(const char *)stage {
    self.canvas.frame = (CGRect){CGPointZero, size};
    [self.canvas setNeedsLayout];
    [self.canvas layoutIfNeeded];
    CGRect expected = CGRectMake(12, 20, size.width - 24, size.height - 40);
    printf("sdk-layout-geometry: %s guide=%s panel=%s\n", stage,
        NSStringFromCGRect(self.guide.layoutFrame).UTF8String,
        NSStringFromCGRect(self.panel.frame).UTF8String);
    check(stage, sameRect(self.guide.layoutFrame, expected) &&
        sameRect(self.panel.frame, expected) && !self.panel.hasAmbiguousLayout);
}
@end

@interface SDKLayoutAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation SDKLayoutAppDelegate
- (void)checkTextEffectsWindow {
    /* Opening native overlays (for example FLEX) can request the modern
     * text-effects window even though the executable advertises an old SDK.
     * Exercise that UIKit path directly, without a third-party dependency. */
    Class effectsClass = NSClassFromString(@"UITextEffectsWindow");
    SEL factory = sel_registerName(
        "sharedTextEffectsWindowForWindowScene:forViewService:");
    check("text-effects-factory", [effectsClass respondsToSelector:factory]);
    if(![effectsClass respondsToSelector:factory]) return;
    puts("sdk-layout-stage: creating text-effects window");
    UIWindow *(*create)(id, SEL, UIWindowScene *, BOOL) =
        (UIWindow *(*)(id, SEL, UIWindowScene *, BOOL))objc_msgSend;
    UIWindow *effects = create(effectsClass, factory, self.window.windowScene, NO);
    check("text-effects-window", effects != nil && effects.rootViewController != nil);
    BOOL atLeast8 = dyld_program_sdk_at_least(
        (struct SDKBuildVersion){PLATFORM_IOS, 0x00080000});
    check("text-effects-autoresizing-policy-preserved", atLeast8 ||
        !effects.rootViewController.view.translatesAutoresizingMaskIntoConstraints);
    [effects layoutIfNeeded];
    check("text-effects-root-finite",
        isfinite(effects.rootViewController.view.bounds.size.width) &&
        isfinite(effects.rootViewController.view.bounds.size.height));
    check("text-effects-reuse",
        create(effectsClass, factory, self.window.windowScene, NO) == effects);
}
- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    SDKLayoutViewController *controller = [[SDKLayoutViewController alloc] init];
    self.window.rootViewController = controller;
    puts("sdk-layout-stage: before makeKeyAndVisible");
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
            [controller checkSize:CGSizeMake(320, 480) stage:"initial-layout"];
            [controller checkSize:CGSizeMake(480, 320) stage:"landscape-resize"];
            [controller checkSize:CGSizeMake(360, 568) stage:"portrait-resize"];
            [controller checkSize:CGSizeMake(360, 568) stage:"repeat-layout"];
            [self checkTextEffectsWindow];
            printf("sdk-layout-regression: %s sdk=0x%08x effective=0x%08x\n",
                failures ? "FAIL" : "PASS", expectedSDK, effectiveSDK);
            exit(failures ? 1 : 0);
        });
    return YES;
}
@end

int main(int argc, char *argv[]) {
#if LC32_TEST_EFFECTIVE_SDK_PROVIDER
    policyTestEnteredMain = true;
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(uncaught);
        checkCompatibilityPolicy();
#if LC32_TEST_EFFECTIVE_SDK_PROVIDER
        printf("sdk-layout-regression: %s policy-only sdk=0x%08x effective=0x%08x\n",
            failures ? "FAIL" : "PASS", expectedSDK, effectiveSDK);
        return failures ? 1 : 0;
#endif
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass([SDKLayoutAppDelegate class]));
    }
}
