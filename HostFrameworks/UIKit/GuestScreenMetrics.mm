#import <UIKit/UIKit.h>
#import "../LC32/host_selector_hooks.h"
#import "LC32LegacyRotation.h"
#import "LC32ClassicPresentation.h"
#include "../../include/LC32UIKitCompatibilityConfig.h"
#if LC32_UIKIT_COMPATIBILITY
#include <cmath>

@interface UIScreenMode (LC32ScreenMetricsPrivate)
- (CGSize)_sizeWithLevel:(NSInteger)level;
@end

@interface UIScreenMode (LC32GuestScreenMetrics)
- (CGSize)lc32_guestScreenModeSize;
@end

@interface UIScreen (LC32GuestScreenMetrics)
- (CGFloat)lc32_guestScreenScale;
- (CGRect)lc32_classicScreenBounds;
- (CGRect)lc32_classicApplicationFrame;
@end

namespace {
bool hasApplicationModeSize;
bool usesLegacyMetrics;

CGFloat NativeScale(UIScreen *screen) {
    const SEL selector = @selector(scale);
    return ((CGFloat (*)(id, SEL))LC32NativeHostMethod(screen, selector))(screen, selector);
}

CGFloat LegacyScale(UIScreen *screen, CGFloat nativeScale) {
    // New UIKit has removed the caller-sensitive application-scale API.
    // Preserve the pre-iOS-8 main-display contract (before 3x displays), not
    // a game-specific scale or resolution. External screens remain native.
    constexpr CGFloat legacyMaximumScale = 2;
    return usesLegacyMetrics && std::isfinite(nativeScale) && nativeScale > legacyMaximumScale &&
        screen == UIScreen.mainScreen ? legacyMaximumScale : nativeScale;
}
}

@implementation UIScreenMode (LC32GuestScreenMetrics)
- (CGSize)lc32_guestScreenModeSize {
    UIScreen *main = UIScreen.mainScreen;
    LC32ClassicScreenGeometry saved;
    if(self == main.currentMode && LC32GetClassicScreenGeometry(main, &saved)) return saved.modeSize;
    if(!usesLegacyMetrics) {
        const SEL selector = @selector(size);
        return ((CGSize (*)(id, SEL))LC32NativeHostMethod(self, selector))(self, selector);
    }
    if(!hasApplicationModeSize) {
        const SEL selector = @selector(size);
        CGSize size = ((CGSize (*)(id, SEL))LC32NativeHostMethod(self, selector))(self, selector);
        UIScreen *screen = UIScreen.mainScreen;
        if(self != screen.currentMode && ![screen.availableModes containsObject:self]) return size;
        const CGFloat nativeScale = NativeScale(screen);
        const CGFloat scale = LegacyScale(screen, nativeScale);
        if(nativeScale > 0 && std::isfinite(nativeScale)) {
            const CGFloat ratio = scale / nativeScale;
            size.width *= ratio;
            size.height *= ratio;
        }
        return size;
    }
    // Level zero asks for the application's legacy scale without inspecting
    // the native caller's image. The external emulator is not the executable
    // (or a framework inside its bundle), so -size can otherwise expose 3x
    // pixels to a guest whose Classic Mode canvas is defined at 2x.
    const SEL selector = @selector(_sizeWithLevel:);
    using Getter = CGSize (*)(id, SEL, NSInteger);
    return ((Getter)LC32NativeHostMethod(self, selector))(self, selector, 0);
}
@end

@implementation UIScreen (LC32GuestScreenMetrics)
- (CGFloat)lc32_guestScreenScale {
    LC32ClassicScreenGeometry saved;
    if(LC32GetClassicScreenGeometry(self, &saved)) return saved.scale;
    const CGFloat scale = NativeScale(self);
    if(!usesLegacyMetrics) return scale;
    if(!hasApplicationModeSize) return LegacyScale(self, scale);
    const SEL modeSelector = @selector(currentMode);
    using ModeGetter = UIScreenMode *(*)(id, SEL);
    UIScreenMode *mode = ((ModeGetter)LC32NativeHostMethod(self, modeSelector))(
        self, modeSelector);
    if(!mode) return scale;

    // Read both unadapted getters from this same native image, so their
    // caller-dependent scale cancels. Do not derive pixels from window bounds
    // or hard-code an iPhone resolution/scale: UIKit owns the main/external
    // display and iPad policy, and a mode need not match a window's extent.
    using SizeGetter = CGSize (*)(id, SEL);
    const SEL sizeSelector = @selector(size);
    const CGSize nativeSize = ((SizeGetter)LC32NativeHostMethod(mode, sizeSelector))(
        mode, sizeSelector);
    const CGSize appSize = [mode lc32_guestScreenModeSize];
    if(nativeSize.width <= 0 || appSize.width <= 0 ||
            !std::isfinite(nativeSize.width) || !std::isfinite(appSize.width))
        return scale;
    return scale * (appSize.width / nativeSize.width);
}
- (CGRect)lc32_classicScreenBounds {
    LC32ClassicScreenGeometry saved;
    if(LC32GetClassicScreenGeometry(self, &saved)) return saved.bounds;
    const SEL selector = @selector(bounds);
    return ((CGRect (*)(id, SEL))LC32NativeHostMethod(self, selector))(self, selector);
}
- (CGRect)lc32_classicApplicationFrame {
    LC32ClassicScreenGeometry saved;
    if(LC32GetClassicScreenGeometry(self, &saved)) return saved.applicationFrame;
    const SEL selector = @selector(applicationFrame);
    return ((CGRect (*)(id, SEL))LC32NativeHostMethod(self, selector))(self, selector);
}
@end

LC32ClassicScreenGeometry LC32CaptureGuestScreenGeometry(UIScreen *screen) {
    // Preserve the effective application scale, including older UIKit's
    // caller-sensitive mode API; do not reconstruct it from the native scale
    // after the host has changed presentation.
    return {screen.bounds, screen.applicationFrame,
        [screen.currentMode lc32_guestScreenModeSize], [screen lc32_guestScreenScale]};
}

@interface LC32GuestScreenMetricsHooks : NSObject
@end
@implementation LC32GuestScreenMetricsHooks
+ (void)load {
    LC32RegisterHostSelectorHook(objc_getClass("UIScreen"), @selector(bounds),
        {@selector(lc32_classicScreenBounds), nullptr});
    LC32RegisterHostSelectorHook(objc_getClass("UIScreen"), @selector(applicationFrame),
        {@selector(lc32_classicApplicationFrame), nullptr});
    usesLegacyMetrics = LC32NativeLegacyRotationEnabled();
    // Runtime lookups avoid initializing UIScreen during the runtime's dlopen.
    Class mode = objc_getClass("UIScreenMode");
    hasApplicationModeSize = class_getInstanceMethod(mode, @selector(_sizeWithLevel:)) != nullptr;
    LC32RegisterHostSelectorHook(mode, @selector(size),
        {@selector(lc32_guestScreenModeSize), nullptr});
    LC32RegisterHostSelectorHook(objc_getClass("UIScreen"), @selector(scale),
        {@selector(lc32_guestScreenScale), nullptr});
}
@end
#endif
