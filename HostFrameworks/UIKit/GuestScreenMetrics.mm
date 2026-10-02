#import <UIKit/UIKit.h>
#import "../LC32/host_selector_hooks.h"
#import "LC32LegacyRotation.h"
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
@end

@implementation UIScreenMode (LC32GuestScreenMetrics)
- (CGSize)lc32_guestScreenModeSize {
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
    using ScaleGetter = CGFloat (*)(id, SEL);
    const SEL scaleSelector = @selector(scale);
    const CGFloat scale = ((ScaleGetter)LC32NativeHostMethod(self, scaleSelector))(
        self, scaleSelector);
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
@end

@interface LC32GuestScreenMetricsHooks : NSObject
@end
@implementation LC32GuestScreenMetricsHooks
+ (void)load {
    if(!LC32NativeLegacyRotationEnabled()) return;
    // Runtime lookups avoid initializing UIScreen during the runtime's dlopen.
    Class mode = objc_getClass("UIScreenMode");
    if(!class_getInstanceMethod(mode, @selector(_sizeWithLevel:))) return;
    LC32RegisterHostSelectorHook(mode, @selector(size),
        {@selector(lc32_guestScreenModeSize), nullptr});
    LC32RegisterHostSelectorHook(objc_getClass("UIScreen"), @selector(scale),
        {@selector(lc32_guestScreenScale), nullptr});
}
@end
#endif
