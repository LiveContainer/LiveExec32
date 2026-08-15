#pragma once

@import CoreGraphics;

__BEGIN_DECLS

// Copies a guest-backed bitmap context's host shadow pixels back into guest
// memory. This is shared by drawing bridges outside CoreGraphics itself.
void LC32CoreGraphicsSyncBitmapBacking(CGContextRef context);

__END_DECLS
