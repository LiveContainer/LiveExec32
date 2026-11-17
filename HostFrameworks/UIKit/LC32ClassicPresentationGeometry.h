#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <cmath>
#include <algorithm>

struct LC32ClassicWindowGeometry {
    CGRect bounds;
    CGPoint center;
    CGAffineTransform transform;
    CGRect parentBounds;
    CGFloat presentationScale;
};

inline bool LC32ClassicValidRect(CGRect rect) {
    return std::isfinite(rect.origin.x) && std::isfinite(rect.origin.y) &&
        std::isfinite(rect.size.width) && std::isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0;
}

// The host rectangle is in fixed display coordinates, not the window's
// possibly landscape/legacy-portrait backing coordinates.
inline bool LC32ClassicPresentationScale(CGRect screen, CGRect presentation,
        CGFloat *scale) {
    if(!LC32ClassicValidRect(screen) || !LC32ClassicValidRect(presentation)) return false;
    const CGFloat x = presentation.size.width / screen.size.width;
    const CGFloat y = presentation.size.height / screen.size.height;
    if(std::abs(x - y) > 0.001 * std::max(x, y)) return false;
    if(CGRectEqualToRect(screen, presentation)) return false;
    *scale = x;
    return true;
}

inline bool LC32ClassicWindowPlacement(const LC32ClassicWindowGeometry &saved,
        CGRect parent, CGPoint *center, CGAffineTransform *transform) {
    if(!LC32ClassicValidRect(saved.bounds) || !LC32ClassicValidRect(saved.parentBounds) ||
            !LC32ClassicValidRect(parent) || !std::isfinite(saved.presentationScale) ||
            saved.presentationScale <= 0) return false;
    // Preserve the measured Classic zoom; only shrink if the available
    // viewport is smaller. Do not infer a device model or a game aspect ratio.
    const CGFloat scale = std::min(saved.presentationScale, std::min(
        parent.size.width / saved.parentBounds.size.width,
        parent.size.height / saved.parentBounds.size.height));
    *center = CGPointMake(CGRectGetMidX(parent) + scale *
        (saved.center.x - CGRectGetMidX(saved.parentBounds)),
        CGRectGetMidY(parent) + scale *
        (saved.center.y - CGRectGetMidY(saved.parentBounds)));
    *transform = CGAffineTransformConcat(saved.transform,
        CGAffineTransformMakeScale(scale, scale));
    return std::isfinite(center->x) && std::isfinite(center->y) &&
        std::isfinite(transform->a) && std::isfinite(transform->b) &&
        std::isfinite(transform->c) && std::isfinite(transform->d) &&
        std::isfinite(transform->tx) && std::isfinite(transform->ty);
}
