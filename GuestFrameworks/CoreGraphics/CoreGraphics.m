@import Darwin;
#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>
#import "CoreGraphics+LC32.h"
#import "LC32CoreGraphicsBridge.h"

#include <pthread.h>
#include <float.h>
#include <string.h>

static pthread_once_t LC32CoreGraphicsDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32CoreGraphicsDispatcherAddress;

static void LC32CoreGraphicsResolveDispatcher(void) {
    LC32CoreGraphicsDispatcherAddress =
        LC32Dlsym("LC32_CoreGraphics_Dispatch", YES);
}

static uint32_t LC32CoreGraphicsDispatch(LC32CoreGraphicsOpcode opcode,
                                         const uint64_t *slots,
                                         uint32_t slotCount) {
    if(slotCount > LC32CoreGraphicsMaxSlots) return 0;
    pthread_once(&LC32CoreGraphicsDispatcherOnce,
        LC32CoreGraphicsResolveDispatcher);
    if(!LC32CoreGraphicsDispatcherAddress) return 0;

    LC32CoreGraphicsCall call = {
        .version = LC32CoreGraphicsABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32CoreGraphicsDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}

static uint64_t LC32CoreGraphicsFloat(CGFloat value) {
    union {
        float value;
        uint32_t bits;
    } converted = {.value = (float)value};
    return converted.bits;
}

static uint64_t LC32CoreGraphicsHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

#define LC32_CG_CALL0(opcode) \
    LC32CoreGraphicsDispatch((opcode), NULL, 0)
#define LC32_CG_CALL(opcode, ...) \
    LC32CoreGraphicsDispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t)))
#define LC32_CG_U32(value) ((uint64_t)(uint32_t)(value))
#define LC32_CG_F32(value) LC32CoreGraphicsFloat((CGFloat)(value))
#define LC32_CG_HOST(value) LC32CoreGraphicsHostObject((const void *)(value))

#pragma mark CGColor TODO

CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *components) {
    return nil; // TODO
}
void CGColorRelease(CGColorRef color) {
    
}

CGColorSpaceRef CGColorGetColorSpace(CGColorRef color) {
    return color ? (CGColorSpaceRef)LC32_CG_CALL(
        LC32CoreGraphicsOpColorGetColorSpace,
        LC32_CG_HOST(color)) : NULL;
}

size_t CGColorGetNumberOfComponents(CGColorRef color) {
    return color ? (size_t)LC32_CG_CALL(
        LC32CoreGraphicsOpColorGetNumberOfComponents,
        LC32_CG_HOST(color)) : 0;
}

const CGFloat *CGColorGetComponents(CGColorRef color) {
    if(!color) return NULL;
    const size_t count = CGColorGetNumberOfComponents(color);
    if(!count || count > UINT32_MAX / sizeof(CGFloat)) return NULL;

    CGFloat *components = LC32GetAssociatedGuestBuffer(
        (id)color, (uint32_t)(count * sizeof(CGFloat)));
    if(!components) return NULL;
    return LC32_CG_CALL(LC32CoreGraphicsOpColorCopyComponents,
        LC32_CG_HOST(color), LC32_CG_U32((uintptr_t)components),
        LC32_CG_U32(count)) ? components : NULL;
}
CGColorSpaceRef CGColorSpaceCreateDeviceRGB() {
    return (CGColorSpaceRef)LC32_CG_CALL0(
        LC32CoreGraphicsOpColorSpaceCreateDeviceRGB);
}

CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef space) {
    return space ? (CGColorSpaceModel)(int32_t)LC32_CG_CALL(
        LC32CoreGraphicsOpColorSpaceGetModel,
        LC32_CG_HOST(space)) : kCGColorSpaceModelUnknown;
}
void CGColorSpaceRelease(CGColorSpaceRef color) {
    if(!color) return;
    CFRelease(color);
}
CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url) {
    return nil;
}
void CGDataProviderRelease(CGDataProviderRef provider) {
    
}
CGImageRef CGImageCreateWithJPEGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate, CGColorRenderingIntent intent) {
    return nil;
}
void CGImageRelease(CGImageRef image) {
    if(!image) return;
    CFRelease(image);
}

#pragma mark CGBitmapContext and CGImage

CGContextRef CGBitmapContextCreate(void *data, size_t width, size_t height,
                                   size_t bitsPerComponent,
                                   size_t bytesPerRow,
                                   CGColorSpaceRef space,
                                   CGBitmapInfo bitmapInfo) {
    return (CGContextRef)LC32_CG_CALL(
        LC32CoreGraphicsOpBitmapContextCreate,
        LC32_CG_U32((uintptr_t)data), LC32_CG_U32(width),
        LC32_CG_U32(height), LC32_CG_U32(bitsPerComponent),
        LC32_CG_U32(bytesPerRow), LC32_CG_HOST(space),
        LC32_CG_U32(bitmapInfo));
}

void CGContextClearRect(CGContextRef context, CGRect rect) {
    if(!context) return;
    LC32_CG_CALL(LC32CoreGraphicsOpContextClearRect,
        LC32_CG_HOST(context),
        LC32_CG_F32(rect.origin.x), LC32_CG_F32(rect.origin.y),
        LC32_CG_F32(rect.size.width), LC32_CG_F32(rect.size.height));
}

void CGContextDrawImage(CGContextRef context, CGRect rect,
                        CGImageRef image) {
    if(!context || !image) return;
    LC32_CG_CALL(LC32CoreGraphicsOpContextDrawImage,
        LC32_CG_HOST(context),
        LC32_CG_F32(rect.origin.x), LC32_CG_F32(rect.origin.y),
        LC32_CG_F32(rect.size.width), LC32_CG_F32(rect.size.height),
        LC32_CG_HOST(image));
}

void CGContextRelease(CGContextRef context) {
    if(!context) return;
    // Copy host bitmap bytes back before the final host retain can disappear.
    LC32_CG_CALL(LC32CoreGraphicsOpContextRelease,
        LC32_CG_HOST(context));
    CFRelease(context);
}

void CGContextTranslateCTM(CGContextRef context, CGFloat tx, CGFloat ty) {
    if(!context) return;
    LC32_CG_CALL(LC32CoreGraphicsOpContextTranslateCTM,
        LC32_CG_HOST(context), LC32_CG_F32(tx), LC32_CG_F32(ty));
}

size_t CGImageGetHeight(CGImageRef image) {
    return image ? LC32_CG_CALL(LC32CoreGraphicsOpImageGetHeight,
        LC32_CG_HOST(image)) : 0;
}

size_t CGImageGetWidth(CGImageRef image) {
    return image ? LC32_CG_CALL(LC32CoreGraphicsOpImageGetWidth,
        LC32_CG_HOST(image)) : 0;
}

#pragma mark CGPath

CGMutablePathRef CGPathCreateMutable() {
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_CoreGraphics_CGPathCreateMutable", YES);
    return (CGMutablePathRef)LC32InvokeHostCRet32(hostPtr);
}

void CGPathAddLineToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y) {
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_CoreGraphics_CGPathAddLineToPoint", YES);
    CGAffineTransform_64 host_m = LC32HostCGAffineTransform(*m);
    LC32InvokeHostCRet32(hostPtr, [(id)path host_self], (uint64_t)&host_m, (double)x, (double)y);
}

bool CGPathContainsPoint(CGPathRef path, const CGAffineTransform *m, CGPoint point, bool eoFill) {
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_CoreGraphics_CGPathContainsPoint", YES);
    CGAffineTransform_64 host_m = LC32HostCGAffineTransform(*m);
    CGPoint_64 host_point = {point.x, point.y};
    return (bool)LC32InvokeHostCRet32(hostPtr, [(id)path host_self], (uint64_t)&host_m, host_point, (uint64_t)eoFill);
}

void CGPathMoveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y) {
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("LC32_CoreGraphics_CGPathMoveToPoint", YES);
    CGAffineTransform_64 host_m = LC32HostCGAffineTransform(*m);
    LC32InvokeHostCRet32(hostPtr, [(id)path host_self], (uint64_t)&host_m, (double)x, (double)y);
}

void CGPathCloseSubpath(CGMutablePathRef path) {
    if(!path) return;
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("CGPathCloseSubpath", YES);
    LC32InvokeHostCRet32(hostPtr, [(id)path host_self]);
}

void CGPathRelease(CGPathRef cg_nullable path) {
    if(!path) return;
    static uint64_t hostPtr = 0;
    if(!hostPtr) hostPtr = LC32Dlsym("CGPathRelease", YES);
    LC32InvokeHostCRet32(hostPtr, [(id)path host_self]);
    // FIXME: does this cause double-free in host?
    CFRelease(path);
}

const CGPoint CGPointZero = {0,0};
const CGRect CGRectInfinite = {
    {-FLT_MAX / 2.0f, -FLT_MAX / 2.0f},
    {FLT_MAX, FLT_MAX},
};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGRect CGRectZero = {{0,0},{0,0}};
const CGSize CGSizeZero = {0,0};

// We don't call host functions if possible to avoid performance cost.
// CGRect* from darling-cocotron
CGFloat CGRectGetMinX(CGRect rect) {
    return rect.origin.x;
}

CGFloat CGRectGetMaxX(CGRect rect) {
    return rect.origin.x + rect.size.width;
}

CGFloat CGRectGetMidX(CGRect rect) {
    return CGRectGetMinX(rect) +
           ((CGRectGetMaxX(rect) - CGRectGetMinX(rect)) / 2.f);
}

CGFloat CGRectGetMinY(CGRect rect) {
    return rect.origin.y;
}

CGFloat CGRectGetMaxY(CGRect rect) {
    return rect.origin.y + rect.size.height;
}

CGFloat CGRectGetMidY(CGRect rect) {
    return CGRectGetMinY(rect) +
           ((CGRectGetMaxY(rect) - CGRectGetMinY(rect)) / 2.f);
}

CGFloat CGRectGetWidth(CGRect rect) {
    return rect.size.width;
}

CGFloat CGRectGetHeight(CGRect rect) {
    return rect.size.height;
}

bool CGRectContainsPoint(CGRect rect, CGPoint point) {
    return (point.x >= CGRectGetMinX(rect) && point.x <= CGRectGetMaxX(rect)) &&
           (point.y >= CGRectGetMinY(rect) && point.y <= CGRectGetMaxY(rect));
}

CGRect CGRectInset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect.origin.x += dx;
    rect.origin.y += dy;
    rect.size.width -= dx * 2;
    rect.size.height -= dy * 2;
    return rect;
}

CGRect CGRectOffset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect.origin.x += dx;
    rect.origin.y += dy;
    return rect;
}

bool CGRectIsEmpty(CGRect rect) {
    return CGRectIsNull(rect) || rect.size.width <= 0 ||
        rect.size.height <= 0;
}

bool CGRectIntersectsRect(CGRect a, CGRect b) {
    return !CGRectIsNull(CGRectIntersection(a, b));
}

CGRect CGRectIntersection(CGRect a, CGRect b) {
    if(CGRectIsEmpty(a) || CGRectIsEmpty(b)) return CGRectNull;

    const CGFloat minX = MAX(CGRectGetMinX(a), CGRectGetMinX(b));
    const CGFloat minY = MAX(CGRectGetMinY(a), CGRectGetMinY(b));
    const CGFloat maxX = MIN(CGRectGetMaxX(a), CGRectGetMaxX(b));
    const CGFloat maxY = MIN(CGRectGetMaxY(a), CGRectGetMaxY(b));
    if(!(minX < maxX && minY < maxY)) return CGRectNull;
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

bool CGRectEqualToRect(CGRect a, CGRect b) {
    return CGPointEqualToPoint(a.origin, b.origin) &&
           CGSizeEqualToSize(a.size, b.size);
}

bool CGRectIsInfinite(CGRect rect) {
    return CGRectEqualToRect(rect, CGRectInfinite);
}

bool CGRectIsNull(CGRect rect) {
    return rect.origin.x == INFINITY || rect.origin.y == INFINITY;
}

bool CGRectContainsRect(CGRect a, CGRect b) {
    return (CGRectGetMinX(b) >= CGRectGetMinX(a) &&
            CGRectGetMaxX(b) <= CGRectGetMaxX(a) &&
            CGRectGetMinY(b) >= CGRectGetMinY(a) &&
            CGRectGetMaxY(b) <= CGRectGetMaxY(a));
}
