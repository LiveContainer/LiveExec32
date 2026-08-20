@import Darwin;
#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>
#import "CoreGraphics+LC32.h"
#import "LC32CoreGraphicsBridge.h"

#include <pthread.h>
#include <float.h>
#include <math.h>
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

#pragma mark CGColor

CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *components) {
    if(!space || !components) return NULL;
    return (CGColorRef)LC32_CG_CALL(LC32CoreGraphicsOpColorCreate,
        LC32_CG_HOST(space), LC32_CG_U32((uintptr_t)components));
}
void CGColorRelease(CGColorRef color) {
    if(color) CFRelease(color);
}

CGFloat CGColorGetAlpha(CGColorRef color) {
    if(!color) return 0;
    const uint32_t bits = LC32_CG_CALL(
        LC32CoreGraphicsOpColorGetAlpha, LC32_CG_HOST(color));
    float alpha;
    memcpy(&alpha, &bits, sizeof(alpha));
    return alpha;
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

CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) {
    return (CGColorSpaceRef)LC32_CG_CALL0(
        LC32CoreGraphicsOpColorSpaceCreateDeviceGray);
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

#pragma mark CGGradient

CGGradientRef CGGradientCreateWithColorComponents(
        CGColorSpaceRef space, const CGFloat *components,
        const CGFloat *locations, size_t count) {
    if(!components || !count || count > UINT32_MAX) return NULL;
    return (CGGradientRef)LC32_CG_CALL(
        LC32CoreGraphicsOpGradientCreateWithColorComponents,
        LC32_CG_HOST(space), LC32_CG_U32((uintptr_t)components),
        LC32_CG_U32((uintptr_t)locations), LC32_CG_U32(count));
}

CGGradientRef CGGradientCreateWithColors(
        CGColorSpaceRef space, CFArrayRef colors,
        const CGFloat *locations) {
    if(!colors) return NULL;
    return (CGGradientRef)LC32_CG_CALL(
        LC32CoreGraphicsOpGradientCreateWithColors,
        LC32_CG_HOST(space), LC32_CG_HOST(colors),
        LC32_CG_U32((uintptr_t)locations));
}

void CGGradientRelease(CGGradientRef gradient) {
    if(gradient) CFRelease(gradient);
}

CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url) {
    return nil;
}

CGDataProviderRef CGDataProviderCreateWithFilename(const char *filename) {
    if(!filename) return NULL;
    const size_t length = strnlen(
        filename, LC32CoreGraphicsMaximumFilenameBytes + 1);
    if(length > LC32CoreGraphicsMaximumFilenameBytes) return NULL;

    /* The dispatcher copies these guest bytes before calling CoreGraphics;
     * an ARM32 pointer must never escape into the native provider. */
    return (CGDataProviderRef)LC32_CG_CALL(
        LC32CoreGraphicsOpDataProviderCreateWithFilename,
        LC32_CG_U32((uintptr_t)filename), LC32_CG_U32(length));
}

void CGDataProviderRelease(CGDataProviderRef provider) {
    if(!provider) return;
    CFRelease(provider);
}

CGImageRef CGImageCreateWithJPEGDataProvider(
        CGDataProviderRef source, const CGFloat *decode,
        bool shouldInterpolate, CGColorRenderingIntent intent) {
    /* CoreGraphics does not expose the decode-array length.  Until it can be
     * derived reliably, reject rather than let a native decoder dereference
     * an ARM32 address. */
    if(!source || decode) return NULL;
    return (CGImageRef)LC32_CG_CALL(
        LC32CoreGraphicsOpImageCreateWithJPEGDataProvider,
        LC32_CG_HOST(source), LC32_CG_U32((uintptr_t)decode),
        LC32_CG_U32(shouldInterpolate), LC32_CG_U32(intent));
}

CGImageRef CGImageCreateWithPNGDataProvider(
        CGDataProviderRef source, const CGFloat *decode,
        bool shouldInterpolate, CGColorRenderingIntent intent) {
    if(!source || decode) return NULL;
    return (CGImageRef)LC32_CG_CALL(
        LC32CoreGraphicsOpImageCreateWithPNGDataProvider,
        LC32_CG_HOST(source), LC32_CG_U32((uintptr_t)decode),
        LC32_CG_U32(shouldInterpolate), LC32_CG_U32(intent));
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

CGImageRef CGBitmapContextCreateImage(CGContextRef context) {
    return context ? (CGImageRef)LC32_CG_CALL(
        LC32CoreGraphicsOpBitmapContextCreateImage,
        LC32_CG_HOST(context)) : NULL;
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

void CGContextDrawLinearGradient(CGContextRef context,
                                 CGGradientRef gradient,
                                 CGPoint startPoint, CGPoint endPoint,
                                 CGGradientDrawingOptions options) {
    if(!context || !gradient) return;
    LC32_CG_CALL(LC32CoreGraphicsOpContextDrawLinearGradient,
        LC32_CG_HOST(context), LC32_CG_HOST(gradient),
        LC32_CG_F32(startPoint.x), LC32_CG_F32(startPoint.y),
        LC32_CG_F32(endPoint.x), LC32_CG_F32(endPoint.y),
        LC32_CG_U32(options));
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

void CGContextSaveGState(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSaveGState,
        LC32_CG_HOST(context));
}

void CGContextRestoreGState(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextRestoreGState,
        LC32_CG_HOST(context));
}

void CGContextBeginPath(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextBeginPath,
        LC32_CG_HOST(context));
}

void CGContextClosePath(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextClosePath,
        LC32_CG_HOST(context));
}

void CGContextMoveToPoint(CGContextRef context, CGFloat x, CGFloat y) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextMoveToPoint,
        LC32_CG_HOST(context), LC32_CG_F32(x), LC32_CG_F32(y));
}

void CGContextAddLineToPoint(CGContextRef context, CGFloat x, CGFloat y) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextAddLineToPoint,
        LC32_CG_HOST(context), LC32_CG_F32(x), LC32_CG_F32(y));
}

void CGContextAddArc(CGContextRef context, CGFloat x, CGFloat y,
                     CGFloat radius, CGFloat startAngle, CGFloat endAngle,
                     int clockwise) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextAddArc,
        LC32_CG_HOST(context), LC32_CG_F32(x), LC32_CG_F32(y),
        LC32_CG_F32(radius), LC32_CG_F32(startAngle),
        LC32_CG_F32(endAngle), LC32_CG_U32(clockwise));
}

void CGContextAddArcToPoint(CGContextRef context, CGFloat x1, CGFloat y1,
                            CGFloat x2, CGFloat y2, CGFloat radius) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextAddArcToPoint,
        LC32_CG_HOST(context), LC32_CG_F32(x1), LC32_CG_F32(y1),
        LC32_CG_F32(x2), LC32_CG_F32(y2), LC32_CG_F32(radius));
}

void CGContextAddRect(CGContextRef context, CGRect rect) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextAddRect,
        LC32_CG_HOST(context), LC32_CG_F32(rect.origin.x),
        LC32_CG_F32(rect.origin.y), LC32_CG_F32(rect.size.width),
        LC32_CG_F32(rect.size.height));
}

void CGContextAddPath(CGContextRef context, CGPathRef path) {
    if(context && path) LC32_CG_CALL(LC32CoreGraphicsOpContextAddPath,
        LC32_CG_HOST(context), LC32_CG_HOST(path));
}

void CGContextClip(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextClip,
        LC32_CG_HOST(context));
}

void CGContextClipToMask(CGContextRef context, CGRect rect,
                         CGImageRef mask) {
    if(context && mask) LC32_CG_CALL(
        LC32CoreGraphicsOpContextClipToMask, LC32_CG_HOST(context),
        LC32_CG_F32(rect.origin.x), LC32_CG_F32(rect.origin.y),
        LC32_CG_F32(rect.size.width), LC32_CG_F32(rect.size.height),
        LC32_CG_HOST(mask));
}

void CGContextFillPath(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextFillPath,
        LC32_CG_HOST(context));
}

void CGContextFillRect(CGContextRef context, CGRect rect) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextFillRect,
        LC32_CG_HOST(context), LC32_CG_F32(rect.origin.x),
        LC32_CG_F32(rect.origin.y), LC32_CG_F32(rect.size.width),
        LC32_CG_F32(rect.size.height));
}

void CGContextStrokePath(CGContextRef context) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextStrokePath,
        LC32_CG_HOST(context));
}

void CGContextStrokeRect(CGContextRef context, CGRect rect) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextStrokeRect,
        LC32_CG_HOST(context), LC32_CG_F32(rect.origin.x),
        LC32_CG_F32(rect.origin.y), LC32_CG_F32(rect.size.width),
        LC32_CG_F32(rect.size.height));
}

void CGContextScaleCTM(CGContextRef context, CGFloat sx, CGFloat sy) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextScaleCTM,
        LC32_CG_HOST(context), LC32_CG_F32(sx), LC32_CG_F32(sy));
}

void CGContextConcatCTM(CGContextRef context, CGAffineTransform transform) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextConcatCTM,
        LC32_CG_HOST(context), LC32_CG_F32(transform.a),
        LC32_CG_F32(transform.b), LC32_CG_F32(transform.c),
        LC32_CG_F32(transform.d), LC32_CG_F32(transform.tx),
        LC32_CG_F32(transform.ty));
}

void CGContextSetFillColorWithColor(CGContextRef context, CGColorRef color) {
    if(context && color) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetFillColorWithColor,
        LC32_CG_HOST(context), LC32_CG_HOST(color));
}

void CGContextSetFillColor(CGContextRef context,
                           const CGFloat *components) {
    if(context && components) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetFillColor,
        LC32_CG_HOST(context),
        LC32_CG_U32((uintptr_t)components));
}

void CGContextSetStrokeColorWithColor(CGContextRef context,
                                      CGColorRef color) {
    if(context && color) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetStrokeColorWithColor,
        LC32_CG_HOST(context), LC32_CG_HOST(color));
}

void CGContextSetStrokeColorSpace(CGContextRef context,
                                  CGColorSpaceRef space) {
    if(context && space) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetStrokeColorSpace,
        LC32_CG_HOST(context), LC32_CG_HOST(space));
}

void CGContextSetStrokeColor(CGContextRef context,
                             const CGFloat *components) {
    if(context && components) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetStrokeColor,
        LC32_CG_HOST(context),
        LC32_CG_U32((uintptr_t)components));
}

void CGContextStrokeLineSegments(CGContextRef context,
                                 const CGPoint *points,
                                 size_t count) {
    if(context && points && count && count <= UINT32_MAX) LC32_CG_CALL(
        LC32CoreGraphicsOpContextStrokeLineSegments,
        LC32_CG_HOST(context), LC32_CG_U32((uintptr_t)points),
        LC32_CG_U32(count));
}

void CGContextSetGrayFillColor(CGContextRef context, CGFloat gray,
                               CGFloat alpha) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSetGrayFillColor,
        LC32_CG_HOST(context), LC32_CG_F32(gray), LC32_CG_F32(alpha));
}

void CGContextSetBlendMode(CGContextRef context, CGBlendMode mode) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSetBlendMode,
        LC32_CG_HOST(context), LC32_CG_U32(mode));
}

void CGContextSetInterpolationQuality(CGContextRef context,
                                      CGInterpolationQuality quality) {
    if(context) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetInterpolationQuality,
        LC32_CG_HOST(context), LC32_CG_U32(quality));
}

void CGContextSetLineCap(CGContextRef context, CGLineCap cap) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSetLineCap,
        LC32_CG_HOST(context), LC32_CG_U32(cap));
}

void CGContextSetLineWidth(CGContextRef context, CGFloat width) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSetLineWidth,
        LC32_CG_HOST(context), LC32_CG_F32(width));
}

void CGContextSetShouldAntialias(CGContextRef context, bool shouldAntialias) {
    if(context) LC32_CG_CALL(
        LC32CoreGraphicsOpContextSetShouldAntialias,
        LC32_CG_HOST(context), LC32_CG_U32(shouldAntialias));
}

void CGContextSetTextPosition(CGContextRef context, CGFloat x, CGFloat y) {
    if(context) LC32_CG_CALL(LC32CoreGraphicsOpContextSetTextPosition,
        LC32_CG_HOST(context), LC32_CG_F32(x), LC32_CG_F32(y));
}

size_t CGImageGetHeight(CGImageRef image) {
    return image ? LC32_CG_CALL(LC32CoreGraphicsOpImageGetHeight,
        LC32_CG_HOST(image)) : 0;
}

size_t CGImageGetWidth(CGImageRef image) {
    return image ? LC32_CG_CALL(LC32CoreGraphicsOpImageGetWidth,
        LC32_CG_HOST(image)) : 0;
}

CGImageRef CGImageCreateWithImageInRect(CGImageRef image, CGRect rect) {
    if(!image) return NULL;
    return (CGImageRef)LC32_CG_CALL(
        LC32CoreGraphicsOpImageCreateWithImageInRect,
        LC32_CG_HOST(image), LC32_CG_F32(rect.origin.x),
        LC32_CG_F32(rect.origin.y), LC32_CG_F32(rect.size.width),
        LC32_CG_F32(rect.size.height));
}

CGImageRef CGImageCreateWithMask(CGImageRef image, CGImageRef mask) {
    if(!image || !mask) return NULL;
    return (CGImageRef)LC32_CG_CALL(
        LC32CoreGraphicsOpImageCreateWithMask,
        LC32_CG_HOST(image), LC32_CG_HOST(mask));
}

CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image) {
    return image ? (CGImageAlphaInfo)LC32_CG_CALL(
        LC32CoreGraphicsOpImageGetAlphaInfo, LC32_CG_HOST(image))
        : kCGImageAlphaNone;
}

CGBitmapInfo CGImageGetBitmapInfo(CGImageRef image) {
    return image ? (CGBitmapInfo)LC32_CG_CALL(
        LC32CoreGraphicsOpImageGetBitmapInfo, LC32_CG_HOST(image)) : 0;
}

size_t CGImageGetBitsPerComponent(CGImageRef image) {
    return image ? (size_t)LC32_CG_CALL(
        LC32CoreGraphicsOpImageGetBitsPerComponent,
        LC32_CG_HOST(image)) : 0;
}

size_t CGImageGetBitsPerPixel(CGImageRef image) {
    return image ? (size_t)LC32_CG_CALL(
        LC32CoreGraphicsOpImageGetBitsPerPixel,
        LC32_CG_HOST(image)) : 0;
}

CGColorSpaceRef CGImageGetColorSpace(CGImageRef image) {
    return image ? (CGColorSpaceRef)LC32_CG_CALL(
        LC32CoreGraphicsOpImageGetColorSpace, LC32_CG_HOST(image)) : NULL;
}

#pragma mark CGPath

CGMutablePathRef CGPathCreateMutable() {
    return (CGMutablePathRef)LC32_CG_CALL0(
        LC32CoreGraphicsOpPathCreateMutable);
}

void CGPathAddLineToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathAddLineToPoint,
        LC32_CG_HOST(path), LC32_CG_U32(m != NULL),
        m ? LC32_CG_F32(m->a) : 0, m ? LC32_CG_F32(m->b) : 0,
        m ? LC32_CG_F32(m->c) : 0, m ? LC32_CG_F32(m->d) : 0,
        m ? LC32_CG_F32(m->tx) : 0, m ? LC32_CG_F32(m->ty) : 0,
        LC32_CG_F32(x), LC32_CG_F32(y));
}

bool CGPathContainsPoint(CGPathRef path, const CGAffineTransform *m, CGPoint point, bool eoFill) {
    if(!path) return false;
    return LC32_CG_CALL(LC32CoreGraphicsOpPathContainsPoint,
        LC32_CG_HOST(path), LC32_CG_U32(m != NULL),
        m ? LC32_CG_F32(m->a) : 0, m ? LC32_CG_F32(m->b) : 0,
        m ? LC32_CG_F32(m->c) : 0, m ? LC32_CG_F32(m->d) : 0,
        m ? LC32_CG_F32(m->tx) : 0, m ? LC32_CG_F32(m->ty) : 0,
        LC32_CG_F32(point.x), LC32_CG_F32(point.y),
        LC32_CG_U32(eoFill)) != 0;
}

void CGPathMoveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathMoveToPoint,
        LC32_CG_HOST(path), LC32_CG_U32(m != NULL),
        m ? LC32_CG_F32(m->a) : 0, m ? LC32_CG_F32(m->b) : 0,
        m ? LC32_CG_F32(m->c) : 0, m ? LC32_CG_F32(m->d) : 0,
        m ? LC32_CG_F32(m->tx) : 0, m ? LC32_CG_F32(m->ty) : 0,
        LC32_CG_F32(x), LC32_CG_F32(y));
}

void CGPathCloseSubpath(CGMutablePathRef path) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathCloseSubpath,
        LC32_CG_HOST(path));
}

void CGPathAddArcToPoint(CGMutablePathRef path,
                         const CGAffineTransform *transform,
                         CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2,
                         CGFloat radius) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathAddArcToPoint,
        LC32_CG_HOST(path), LC32_CG_U32(transform != NULL),
        transform ? LC32_CG_F32(transform->a) : 0,
        transform ? LC32_CG_F32(transform->b) : 0,
        transform ? LC32_CG_F32(transform->c) : 0,
        transform ? LC32_CG_F32(transform->d) : 0,
        transform ? LC32_CG_F32(transform->tx) : 0,
        transform ? LC32_CG_F32(transform->ty) : 0,
        LC32_CG_F32(x1), LC32_CG_F32(y1), LC32_CG_F32(x2),
        LC32_CG_F32(y2), LC32_CG_F32(radius));
}

void CGPathAddCurveToPoint(CGMutablePathRef path,
                           const CGAffineTransform *transform,
                           CGFloat cp1x, CGFloat cp1y, CGFloat cp2x,
                           CGFloat cp2y, CGFloat x, CGFloat y) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathAddCurveToPoint,
        LC32_CG_HOST(path), LC32_CG_U32(transform != NULL),
        transform ? LC32_CG_F32(transform->a) : 0,
        transform ? LC32_CG_F32(transform->b) : 0,
        transform ? LC32_CG_F32(transform->c) : 0,
        transform ? LC32_CG_F32(transform->d) : 0,
        transform ? LC32_CG_F32(transform->tx) : 0,
        transform ? LC32_CG_F32(transform->ty) : 0,
        LC32_CG_F32(cp1x), LC32_CG_F32(cp1y), LC32_CG_F32(cp2x),
        LC32_CG_F32(cp2y), LC32_CG_F32(x), LC32_CG_F32(y));
}

void CGPathAddRect(CGMutablePathRef path,
                   const CGAffineTransform *transform, CGRect rect) {
    if(!path) return;
    LC32_CG_CALL(LC32CoreGraphicsOpPathAddRect,
        LC32_CG_HOST(path), LC32_CG_U32(transform != NULL),
        transform ? LC32_CG_F32(transform->a) : 0,
        transform ? LC32_CG_F32(transform->b) : 0,
        transform ? LC32_CG_F32(transform->c) : 0,
        transform ? LC32_CG_F32(transform->d) : 0,
        transform ? LC32_CG_F32(transform->tx) : 0,
        transform ? LC32_CG_F32(transform->ty) : 0,
        LC32_CG_F32(rect.origin.x), LC32_CG_F32(rect.origin.y),
        LC32_CG_F32(rect.size.width), LC32_CG_F32(rect.size.height));
}

CGPathRef CGPathCreateCopy(CGPathRef path) {
    return path ? (CGPathRef)LC32_CG_CALL(
        LC32CoreGraphicsOpPathCreateCopy, LC32_CG_HOST(path)) : NULL;
}

void CGPathRelease(CGPathRef cg_nullable path) {
    if(!path) return;
    /* Validate the native peer through the typed bridge, but let CFRelease
     * perform the one paired guest/native ownership decrement. Calling the
     * native CGPathRelease here as well would release the peer twice. */
    LC32_CG_CALL(LC32CoreGraphicsOpPathRelease, LC32_CG_HOST(path));
    CFRelease(path);
}

const CGPoint CGPointZero = {0,0};
const CGAffineTransform CGAffineTransformIdentity = {1,0,0,1,0,0};
const CGRect CGRectInfinite = {
    {-FLT_MAX / 2.0f, -FLT_MAX / 2.0f},
    {FLT_MAX, FLT_MAX},
};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGRect CGRectZero = {{0,0},{0,0}};
const CGSize CGSizeZero = {0,0};

#pragma mark CGAffineTransform

/*
 * These are value-only operations.  Computing them in ARM32 keeps CGFloat as
 * float and avoids both a host transition and the incompatible ARM64 struct
 * return ABI.
 */
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) {
    return (CGAffineTransform){1, 0, 0, 1, tx, ty};
}

CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy) {
    return (CGAffineTransform){sx, 0, 0, sy, 0, 0};
}

CGAffineTransform CGAffineTransformMakeRotation(CGFloat angle) {
    CGFloat sine = (CGFloat)sin((double)angle);
    CGFloat cosine = (CGFloat)cos((double)angle);
    const CGFloat epsilon = 0x1p-22f;
    if(fabsf(sine) < epsilon) sine = 0;
    else if(fabsf(sine - 1) < epsilon) sine = 1;
    if(fabsf(cosine) < epsilon) cosine = 0;
    else if(fabsf(cosine - 1) < epsilon) cosine = 1;
    return (CGAffineTransform){cosine, sine, -sine, cosine, 0, 0};
}

bool CGAffineTransformIsIdentity(CGAffineTransform transform) {
    return transform.a == 1 && transform.b == 0 &&
        transform.c == 0 && transform.d == 1 &&
        transform.tx == 0 && transform.ty == 0;
}

CGAffineTransform CGAffineTransformConcat(CGAffineTransform first,
                                          CGAffineTransform second) {
    return (CGAffineTransform){
        (CGFloat)((double)first.a * second.a +
                  (double)first.b * second.c),
        (CGFloat)((double)first.a * second.b +
                  (double)first.b * second.d),
        (CGFloat)((double)first.c * second.a +
                  (double)first.d * second.c),
        (CGFloat)((double)first.c * second.b +
                  (double)first.d * second.d),
        (CGFloat)((double)first.tx * second.a +
                  (double)first.ty * second.c + second.tx),
        (CGFloat)((double)first.tx * second.b +
                  (double)first.ty * second.d + second.ty),
    };
}

static CGAffineTransform LC32CGAffineTransformConcat(
        CGAffineTransform first, CGAffineTransform second) {
    return (CGAffineTransform){
        (CGFloat)((double)first.a * second.a +
                  (double)first.b * second.c),
        (CGFloat)((double)first.a * second.b +
                  (double)first.b * second.d),
        (CGFloat)((double)first.c * second.a +
                  (double)first.d * second.c),
        (CGFloat)((double)first.c * second.b +
                  (double)first.d * second.d),
        (CGFloat)((double)first.tx * second.a +
                  (double)first.ty * second.c + second.tx),
        (CGFloat)((double)first.tx * second.b +
                  (double)first.ty * second.d + second.ty),
    };
}

CGAffineTransform CGAffineTransformTranslate(
        CGAffineTransform transform, CGFloat tx, CGFloat ty) {
    return LC32CGAffineTransformConcat(
        CGAffineTransformMakeTranslation(tx, ty), transform);
}

CGAffineTransform CGAffineTransformScale(
        CGAffineTransform transform, CGFloat sx, CGFloat sy) {
    return LC32CGAffineTransformConcat(
        CGAffineTransformMakeScale(sx, sy), transform);
}

CGAffineTransform CGAffineTransformRotate(
        CGAffineTransform transform, CGFloat angle) {
    return LC32CGAffineTransformConcat(
        CGAffineTransformMakeRotation(angle), transform);
}

// We don't call host functions if possible to avoid performance cost.
static CGRect LC32CGRectStandardized(CGRect rect) {
    if(rect.size.width < 0) {
        rect.origin.x += rect.size.width;
        rect.size.width = -rect.size.width;
    }
    if(rect.size.height < 0) {
        rect.origin.y += rect.size.height;
        rect.size.height = -rect.size.height;
    }
    return rect;
}

CGFloat CGRectGetMinX(CGRect rect) {
    return rect.size.width < 0
        ? rect.origin.x + rect.size.width : rect.origin.x;
}

CGFloat CGRectGetMaxX(CGRect rect) {
    return rect.size.width < 0
        ? rect.origin.x : rect.origin.x + rect.size.width;
}

CGFloat CGRectGetMidX(CGRect rect) {
    return CGRectGetMinX(rect) +
           ((CGRectGetMaxX(rect) - CGRectGetMinX(rect)) / 2.f);
}

CGFloat CGRectGetMinY(CGRect rect) {
    return rect.size.height < 0
        ? rect.origin.y + rect.size.height : rect.origin.y;
}

CGFloat CGRectGetMaxY(CGRect rect) {
    return rect.size.height < 0
        ? rect.origin.y : rect.origin.y + rect.size.height;
}

CGFloat CGRectGetMidY(CGRect rect) {
    return CGRectGetMinY(rect) +
           ((CGRectGetMaxY(rect) - CGRectGetMinY(rect)) / 2.f);
}

CGFloat CGRectGetWidth(CGRect rect) {
    return fabsf(rect.size.width);
}

CGFloat CGRectGetHeight(CGRect rect) {
    return fabsf(rect.size.height);
}

bool CGRectContainsPoint(CGRect rect, CGPoint point) {
    if(CGRectIsEmpty(rect)) return false;
    return point.x >= CGRectGetMinX(rect) &&
        point.x < CGRectGetMaxX(rect) &&
        point.y >= CGRectGetMinY(rect) &&
        point.y < CGRectGetMaxY(rect);
}

CGRect CGRectInset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect = LC32CGRectStandardized(rect);
    if(CGRectIsNull(rect)) return rect;
    rect.origin.x += dx;
    rect.origin.y += dy;
    rect.size.width -= dx * 2;
    rect.size.height -= dy * 2;
    if(rect.size.width < 0 || rect.size.height < 0) return CGRectNull;
    return rect;
}

CGRect CGRectOffset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect = LC32CGRectStandardized(rect);
    if(CGRectIsNull(rect)) return rect;
    rect.origin.x += dx;
    rect.origin.y += dy;
    return rect;
}

CGRect CGRectIntegral(CGRect rect) {
    if(CGRectIsNull(rect) || CGRectIsInfinite(rect)) return rect;
    const CGFloat minX = floorf(CGRectGetMinX(rect));
    const CGFloat minY = floorf(CGRectGetMinY(rect));
    const CGFloat maxX = ceilf(CGRectGetMaxX(rect));
    const CGFloat maxY = ceilf(CGRectGetMaxY(rect));
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

bool CGRectIsEmpty(CGRect rect) {
    return CGRectIsNull(rect) || rect.size.width == 0 ||
        rect.size.height == 0;
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

CGRect CGRectUnion(CGRect a, CGRect b) {
    if(CGRectIsNull(a)) return b;
    if(CGRectIsNull(b)) return a;
    const CGFloat minX = MIN(CGRectGetMinX(a), CGRectGetMinX(b));
    const CGFloat minY = MIN(CGRectGetMinY(a), CGRectGetMinY(b));
    const CGFloat maxX = MAX(CGRectGetMaxX(a), CGRectGetMaxX(b));
    const CGFloat maxY = MAX(CGRectGetMaxY(a), CGRectGetMaxY(b));
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

CGRect CGRectApplyAffineTransform(CGRect rect, CGAffineTransform transform) {
    if(CGRectIsNull(rect) || CGRectIsInfinite(rect)) return rect;
    const CGPoint corners[] = {
        CGPointApplyAffineTransform(
            CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)),
            transform),
        CGPointApplyAffineTransform(
            CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)),
            transform),
        CGPointApplyAffineTransform(
            CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)),
            transform),
        CGPointApplyAffineTransform(
            CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)),
            transform),
    };
    CGFloat minX = corners[0].x;
    CGFloat minY = corners[0].y;
    CGFloat maxX = corners[0].x;
    CGFloat maxY = corners[0].y;
    for(unsigned int index = 1; index < 4; index++) {
        minX = MIN(minX, corners[index].x);
        minY = MIN(minY, corners[index].y);
        maxX = MAX(maxX, corners[index].x);
        maxY = MAX(maxY, corners[index].y);
    }
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

void CGRectDivide(CGRect rect, CGRect *slice, CGRect *remainder,
                  CGFloat amount, CGRectEdge edge) {
    CGRect normalized = rect;
    const CGFloat minX = MIN(CGRectGetMinX(rect), CGRectGetMaxX(rect));
    const CGFloat minY = MIN(CGRectGetMinY(rect), CGRectGetMaxY(rect));
    normalized.origin = CGPointMake(minX, minY);
    normalized.size = CGSizeMake(fabsf(rect.size.width),
                                 fabsf(rect.size.height));
    const BOOL vertical = edge == CGRectMinYEdge || edge == CGRectMaxYEdge;
    const CGFloat extent = vertical
        ? normalized.size.height : normalized.size.width;
    const CGFloat clampedAmount = MIN(MAX(amount, 0), extent);
    CGRect first = normalized;
    CGRect rest = normalized;
    if(vertical) {
        first.size.height = clampedAmount;
        rest.size.height = extent - clampedAmount;
        if(edge == CGRectMinYEdge) {
            rest.origin.y += clampedAmount;
        } else {
            first.origin.y += extent - clampedAmount;
        }
    } else {
        first.size.width = clampedAmount;
        rest.size.width = extent - clampedAmount;
        if(edge == CGRectMinXEdge) {
            rest.origin.x += clampedAmount;
        } else {
            first.origin.x += extent - clampedAmount;
        }
    }
    if(slice) *slice = first;
    if(remainder) *remainder = rest;
}

bool CGRectEqualToRect(CGRect a, CGRect b) {
    a = LC32CGRectStandardized(a);
    b = LC32CGRectStandardized(b);
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
    if(CGRectIsNull(a) || CGRectIsNull(b)) return false;
    return CGRectGetMinX(b) >= CGRectGetMinX(a) &&
        CGRectGetMaxX(b) <= CGRectGetMaxX(a) &&
        CGRectGetMinY(b) >= CGRectGetMinY(a) &&
        CGRectGetMaxY(b) <= CGRectGetMaxY(a);
}
