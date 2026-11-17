#import "screen-metrics-stubs/UIKit/UIKit.h"
#import "../HostFrameworks/LC32/host_selector_hooks.h"
#import "../HostFrameworks/UIKit/LC32ClassicPresentation.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool restoredClassic;
static LC32ClassicScreenGeometry classicGeometry;
bool LC32GetClassicScreenGeometry(UIScreen *screen, LC32ClassicScreenGeometry *geometry) {
    if(!restoredClassic || screen != UIScreen.mainScreen) return false;
    *geometry=classicGeometry;
    return true;
}

extern "C" bool LC32NativeLegacyRotationEnabled(void) {
    const char *value = getenv("LC32_TEST_LEGACY");
    return value && !strcmp(value, "1");
}
@interface NSObject (LC32ScreenMetricsTest)
- (BOOL)isGuestClass;
@end
@implementation NSObject (LC32ScreenMetricsTest)
- (BOOL)isGuestClass { return NO; }
@end
@implementation UIScreenMode
- (CGSize)size { return self.pixels; }
#if LC32_TEST_MODE_SPI
- (CGSize)_sizeWithLevel:(NSInteger)level {
    self.lastLevel = level;
    return self.applicationPixels;
}
#endif
@end
@implementation UIScreen
+ (instancetype)mainScreen {
    static UIScreen *screen = [UIScreen new];
    return screen;
}
- (CGFloat)scale { return self.testScale; }
@end
@interface ExternalTestScreen : UIScreen
@end
@implementation ExternalTestScreen
@end

static unsigned checks, failures;
static void check(const char *name, bool pass) {
    printf("screen-metrics-host-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static CGFloat guestScale(UIScreen *screen) {
    SEL selector = LC32FindHostSelectorHook(object_getClass(screen), @selector(scale)).replacement;
    selector = selector ?: @selector(scale);
    return ((CGFloat (*)(id, SEL))LC32NativeHostMethod(screen, selector))(screen, selector);
}
static CGSize guestSize(UIScreenMode *mode) {
    SEL selector = LC32FindHostSelectorHook(object_getClass(mode), @selector(size)).replacement;
    selector = selector ?: @selector(size);
    return ((CGSize (*)(id, SEL))LC32NativeHostMethod(mode, selector))(mode, selector);
}
static CGRect guestRect(UIScreen *screen, SEL native) {
    SEL selector = LC32FindHostSelectorHook(object_getClass(screen), native).replacement ?: native;
    return ((CGRect (*)(id, SEL))LC32NativeHostMethod(screen, selector))(screen, selector);
}
int main() {
    @autoreleasepool {
        const bool enabled = LC32_UIKIT_COMPATIBILITY && LC32NativeLegacyRotationEnabled();
        UIScreenMode *mode = [UIScreenMode new];
        mode.pixels = CGSizeMake(960,1704);
        mode.applicationPixels = CGSizeMake(640,1136);
        mode.lastLevel = -1;
        UIScreen *screen = UIScreen.mainScreen;
        screen.testScale = 3;
        screen.currentMode = mode;
        screen.availableModes = @[mode];
        check("scale-registration", !!LC32FindHostSelectorHook(UIScreen.class, @selector(scale)).replacement == !!LC32_UIKIT_COMPATIBILITY);
        check("mode-registration", !!LC32FindHostSelectorHook(UIScreenMode.class, @selector(size)).replacement == !!LC32_UIKIT_COMPATIBILITY);
        check("classic-scale", guestScale(screen) == (enabled ? 2 : 3));
        check("classic-mode", CGSizeEqualToSize(guestSize(mode), enabled ? mode.applicationPixels : mode.pixels));
        check("level-zero", mode.lastLevel == (enabled && LC32_TEST_MODE_SPI ? 0 : -1));
        check("native-unchanged", screen.scale == 3 && CGSizeEqualToSize(mode.size, mode.pixels));
        check("other-selector", !LC32FindHostSelectorHook(UIScreen.class, @selector(currentMode)).replacement);
        check("other-class", !LC32FindHostSelectorHook(NSString.class, @selector(size)).replacement);
        screen.bounds=CGRectMake(0,0,440,956);
        screen.applicationFrame=screen.bounds;
        classicGeometry={CGRectMake(0,0,320,568),CGRectMake(0,20,320,548),
            enabled ? CGSizeMake(640,1136) : mode.pixels, enabled ? 2.0 : 3.0};
        restoredClassic=true;
        mode.pixels=CGSizeMake(1320,2868);
        check("restored-bounds", CGRectEqualToRect(guestRect(screen,@selector(bounds)),
            LC32_UIKIT_COMPATIBILITY ? classicGeometry.bounds : screen.bounds));
        check("restored-application-frame", CGRectEqualToRect(guestRect(screen,@selector(applicationFrame)),
            LC32_UIKIT_COMPATIBILITY ? classicGeometry.applicationFrame : screen.applicationFrame));
        check("restored-mode", CGSizeEqualToSize(guestSize(mode), LC32_UIKIT_COMPATIBILITY
            ? classicGeometry.modeSize : mode.pixels));
        classicGeometry.scale=1;
        classicGeometry.modeSize=CGSizeMake(320,568);
        check("restored-original-application-scale", guestScale(screen)==(LC32_UIKIT_COMPATIBILITY ? 1 : 3));
        check("restored-original-application-pixels", CGSizeEqualToSize(guestSize(mode),
            LC32_UIKIT_COMPATIBILITY ? classicGeometry.modeSize : mode.pixels));
        check("restored-native-unaffected", screen.bounds.size.width==440 && mode.size.width==1320);
        restoredClassic=false;
        mode.pixels = CGSizeMake(1536,2048);
        mode.applicationPixels = mode.pixels;
        screen.testScale = 2;
        check("native-ipad", guestScale(screen) == 2 && CGSizeEqualToSize(guestSize(mode), mode.pixels));
        ExternalTestScreen *external = [ExternalTestScreen new];
        external.testScale = 1.5;
        external.currentMode = mode;
        check("external-display-subclass", guestScale(external) == 1.5);
        external.testScale = 3;
        check("external-high-density-unchanged", guestScale(external) == 3);
        UIScreenMode *externalMode = [UIScreenMode new];
        externalMode.pixels = externalMode.applicationPixels = CGSizeMake(3840,2160);
        external.currentMode = externalMode;
        check("external-mode-unchanged", CGSizeEqualToSize(guestSize(externalMode), externalMode.pixels));
        screen.testScale = 1;
        check("non-retina-preserved", guestScale(screen) == 1);
        screen.testScale = 2;
        screen.currentMode = nil;
        check("no-mode", guestScale(screen) == 2);
        screen.currentMode = mode;
        mode.pixels = CGSizeZero;
        check("zero-native-width", guestScale(screen) == 2);
        mode.pixels = CGSizeMake(NAN,2048);
        check("nan-native-width", guestScale(screen) == 2);
        mode.pixels = CGSizeMake(1536,2048);
        mode.applicationPixels = CGSizeZero;
        check("zero-application-width", guestScale(screen) == 2);
        mode.applicationPixels = CGSizeMake(NAN,2048);
        check("nan-application-width", guestScale(screen) == 2);
        screen.testScale = INFINITY;
        check("invalid-scale-preserved", std::isinf(guestScale(screen)));
        if(enabled && !LC32_TEST_MODE_SPI) {
            check("invalid-scale-mode-preserved", CGSizeEqualToSize(guestSize(mode), mode.pixels));
            screen.testScale = 4;
            mode.pixels = CGSizeMake(1280,2272);
            check("fallback-ratio-not-resolution", guestScale(screen) == 2 &&
                CGSizeEqualToSize(guestSize(mode), CGSizeMake(640,1136)));
            UIScreenMode *alternate = [UIScreenMode new];
            alternate.pixels = CGSizeMake(1920,1080);
            screen.availableModes = @[mode, alternate];
            check("alternate-main-mode", CGSizeEqualToSize(guestSize(alternate), CGSizeMake(960,540)));
        }
    }
    printf("screen-metrics-host: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
