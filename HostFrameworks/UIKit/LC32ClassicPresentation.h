#pragma once
#import <UIKit/UIKit.h>
@class UIWindow;

struct LC32ClassicScreenGeometry {
    CGRect bounds;
    CGRect applicationFrame;
    CGSize modeSize;
    CGFloat scale;
};

// Read the effective guest metrics before the fallback changes host scenes.
LC32ClassicScreenGeometry LC32CaptureGuestScreenGeometry(UIScreen *screen);

// Only available after the fallback has taken ownership of the saved canvas.
bool LC32GetClassicScreenGeometry(UIScreen *screen, LC32ClassicScreenGeometry *geometry);
bool LC32GetClassicWindowGeometry(UIWindow *window, CGRect *bounds, CGRect *sceneBounds);
