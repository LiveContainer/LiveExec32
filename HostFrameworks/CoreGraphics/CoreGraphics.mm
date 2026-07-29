@import Darwin;
@import CoreGraphics;
#include "bridge.h"

__BEGIN_DECLS

u32 LC32_CoreGraphics_CGPathCreateMutable() {
    return [(id)CGPathCreateMutable() guest_self];
}

void LC32_CoreGraphics_CGPathAddLineToPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGFloat x = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGFloat y = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGPathAddLineToPoint(path, (const CGAffineTransform *)&m, x, y);
}

bool LC32_CoreGraphics_CGPathContainsPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGPoint point;
    Dynarmic_mem_1read(sp += 8, sizeof(m), (char *)&m);

    bool eoFill = (bool)Dynarmic_current_user_callbacks()->MemoryRead64(sp += sizeof(point));
    return CGPathContainsPoint(path, (const CGAffineTransform *)&m, point, eoFill);
}

void LC32_CoreGraphics_CGPathMoveToPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGFloat x = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGFloat y = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGPathMoveToPoint(path, (const CGAffineTransform *)&m, x, y);
}

__END_DECLS

