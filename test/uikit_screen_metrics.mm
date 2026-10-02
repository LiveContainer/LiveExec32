// Build the probe as an external dylib: putting it inside the app would hide
// UIKit's caller-image distinction and miss the standalone runtime regression.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

struct Metrics { CGFloat scale; CGSize modeSize; bool scaleHook, modeHook; };

#ifdef LC32_SCREEN_METRICS_PROBE
#import "../HostFrameworks/LC32/host_selector_hooks.h"
@interface NSObject (LC32ScreenMetricsTest)
- (BOOL)isGuestClass;
@end
@implementation NSObject (LC32ScreenMetricsTest)
- (BOOL)isGuestClass { return NO; }
@end

extern "C" Metrics LC32ReadScreenMetrics(UIScreen *screen, bool guest) {
    const auto scaleHook = LC32FindHostSelectorHook(object_getClass(screen), @selector(scale));
    UIScreenMode *mode = screen.currentMode;
    const auto modeHook = LC32FindHostSelectorHook(object_getClass(mode), @selector(size));
    const SEL scale = guest && scaleHook.replacement ? scaleHook.replacement : @selector(scale);
    const SEL size = guest && modeHook.replacement ? modeHook.replacement : @selector(size);
    return {((CGFloat (*)(id, SEL))objc_msgSend)(screen, scale),
        ((CGSize (*)(id, SEL))objc_msgSend)(mode, size),
        !!scaleHook.replacement, !!modeHook.replacement};
}
#else
struct BuildVersion { uint32_t platform, version; };
extern "C" bool dyld_program_sdk_at_least(BuildVersion);
extern "C" uint32_t dyld_get_program_sdk_version(void);
extern "C" bool LC32NativeLegacyRotationEnabled(void) {
    const char *disabled = getenv("LC32_DISABLE_UIKIT_COMPATIBILITY");
    return !(disabled && !strcmp(disabled, "1")) &&
        !dyld_program_sdk_at_least({2, 0x80000});
}

static unsigned failures, checks;
static void check(const char *name, bool pass) {
    printf("screen-metrics-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static bool close(CGFloat a, CGFloat b) { return std::isfinite(a) && fabs(a-b) < .001; }
static bool close(CGSize a, CGSize b) { return close(a.width,b.width) && close(a.height,b.height); }

@interface ScreenMetricsDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ScreenMetricsDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        const uint32_t sdk = dyld_get_program_sdk_version();
        check("effective-sdk", sdk == [info[@"LC32ExpectedSDK"] unsignedIntValue]);
        printf("screen-metrics-sdk: 0x%x legacy=%d\n", sdk, LC32NativeLegacyRotationEnabled());
        void *library = dlopen([info[@"LC32Probe"] fileSystemRepresentation], RTLD_NOW);
        check("external-probe-loaded", library != nullptr);
        if(!library) { fprintf(stderr, "%s\n", dlerror()); exit(1); }
        auto read = (Metrics (*)(UIScreen *, bool))dlsym(library, "LC32ReadScreenMetrics");
        check("probe-export", read != nullptr);
        if(!read) exit(1);
        UIScreen *screen = UIScreen.mainScreen;
        CGFloat appScale = screen.scale;
        CGSize appMode = screen.currentMode.size;
        const Metrics native = read(screen, false), guest = read(screen, true);
        const bool hasSPI = class_getInstanceMethod(objc_getClass("UIScreenMode"),
            sel_registerName("_sizeWithLevel:")) != nullptr;
        const bool enabled = LC32NativeLegacyRotationEnabled() && [info[@"LC32Hooks"] boolValue] && hasSPI;
        printf("screen-metrics-private-api: %s\n", hasSPI ? "available" : "unavailable; native fallback");
        printf("screen-metrics: idiom=%ld enabled=%d app=%.3f/%.0fx%.0f external=%.3f/%.0fx%.0f guest=%.3f/%.0fx%.0f\n",
            (long)UIDevice.currentDevice.userInterfaceIdiom, enabled,
            (double)appScale, (double)appMode.width, (double)appMode.height,
            (double)native.scale, (double)native.modeSize.width, (double)native.modeSize.height,
            (double)guest.scale, (double)guest.modeSize.width, (double)guest.modeSize.height);
        check("registration-gate", guest.scaleHook == enabled && guest.modeHook == enabled);
        check("scale", close(guest.scale, enabled ? appScale : native.scale));
        check("mode", close(guest.modeSize, enabled ? appMode : native.modeSize));
        check("native-scale-unchanged", close(screen.scale, appScale));
        check("native-mode-unchanged", close(screen.currentMode.size, appMode));
        check("external-call-unchanged", close(read(screen, false).scale, native.scale));
        check("finite-positive", guest.scale > 0 && std::isfinite(guest.scale) &&
            guest.modeSize.width > 0 && guest.modeSize.height > 0);
        printf("screen-metrics-regression: %s (%u checks, %u failures)\n",
            failures ? "FAIL" : "PASS", checks, failures);
        fflush(stdout); exit(failures != 0);
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ScreenMetricsDelegate.class)); }
}
#endif
