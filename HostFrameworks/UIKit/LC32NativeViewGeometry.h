#pragma once
#import <UIKit/UIKit.h>

// Native base implementations, bypassing synthesized ARM32 overrides during
// UIKit's host-side scene callbacks. Implemented in UIKit.mm.
CGRect LC32NativeViewBounds(UIView *view);
CGPoint LC32NativeViewCenter(UIView *view);
CGAffineTransform LC32NativeViewTransform(UIView *view);
CALayer *LC32NativeViewLayer(UIView *view);
void LC32NativeSetViewBounds(UIView *view, CGRect bounds);
void LC32NativeSetViewCenter(UIView *view, CGPoint center);
void LC32NativeSetViewTransform(UIView *view, CGAffineTransform transform);
