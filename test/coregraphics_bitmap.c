#include <CoreGraphics/CoreGraphics.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int report(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}

static int buffer_has_nonzero_byte(const uint8_t *bytes, size_t count) {
    for(size_t index = 0; index < count; ++index) {
        if(bytes[index] != 0) return 1;
    }
    return 0;
}

static int test_antialiasing(CGColorSpaceRef rgb) {
    uint8_t pixels[4 * 4 * 4] = {};
    CGContextRef context = CGBitmapContextCreate(pixels, 4, 4, 8, 16, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if(!context) return report("antialias-context", 0);
    int failures = 0;
    for(unsigned variant = 0; variant < 3; ++variant) {
        CGContextClearRect(context, CGRectMake(0, 0, 4, 4));
        CGContextSetAllowsAntialiasing(context, variant != 0);
        CGContextSetShouldAntialias(context, variant != 2);
        CGContextSetAllowsFontSubpixelPositioning(context, variant != 0);
        CGContextSetShouldSubpixelQuantizeFonts(context, variant != 2);
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0.25f, 0.25f, 2.5f, 2.5f));
        int fractional = 0;
        for(unsigned i = 3; i < sizeof(pixels); i += 4)
            fractional |= pixels[i] != 0 && pixels[i] != 255;
        static const char *names[] = {"antialias-disallowed", "antialias-enabled",
            "antialias-should-disabled"};
        failures += report(names[variant],
            buffer_has_nonzero_byte(pixels, sizeof(pixels)) && fractional == (variant == 1));
    }
    CGContextSetAllowsAntialiasing(NULL, false);
    CGContextSetAllowsFontSubpixelPositioning(NULL, false);
    CGContextSetShouldSubpixelQuantizeFonts(NULL, false);
    CGContextRelease(context);
    return failures;
}

int main(void) {
    int failures = 0;
    uint8_t pixels[4 * 4 * 4] = {};
    uint8_t maskPixels[4 * 4] = {};

    const UInt8 providerBytes[] = {0x10, 0x20, 0x30, 0x40};
    CFDataRef providerData = CFDataCreate(
        kCFAllocatorDefault, providerBytes, sizeof(providerBytes));
    CGDataProviderRef provider = providerData
        ? CGDataProviderCreateWithCFData(providerData) : NULL;
    failures += report("data-provider-cfdata-owned", provider != NULL);

    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    failures += report("color-space-component-counts", rgb && gray &&
        CGColorSpaceGetNumberOfComponents(rgb) == 3 &&
        CGColorSpaceGetNumberOfComponents(gray) == 1 &&
        CGColorSpaceGetNumberOfComponents(NULL) == 0);
    const CGFloat grayComponents[] = {0.5f, 0.25f};
    CGColorRef retainedColor = CGColorCreate(gray, grayComponents);
    failures += report("color-retain-identity", retainedColor &&
        CGColorRetain(retainedColor) == retainedColor && CGColorRetain(NULL) == NULL);
    CGColorRelease(retainedColor);
    CGColorSpaceRelease(gray);
    failures += report("color-retain-lifetime", retainedColor &&
        CGColorGetNumberOfComponents(retainedColor) == 2 &&
        fabsf(CGColorGetAlpha(retainedColor) - 0.25f) < 0.001f);
    CGColorRef copiedColor = CGColorCreateCopy(retainedColor);
    CGColorRelease(retainedColor);
    failures += report("color-copy-lifetime", copiedColor &&
        fabsf(CGColorGetAlpha(copiedColor) - 0.25f) < 0.001f &&
        CGColorCreateCopy(NULL) == NULL);
    CGColorRelease(copiedColor);
    failures += test_antialiasing(rgb);
    const CGFloat imageDecode[] = {0, 1, 0, 1, 0, 1};
    CGImageRef providerImage = rgb && provider ? CGImageCreate(
        1, 1, 8, 32, 4, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
        provider, imageDecode, false, kCGRenderingIntentDefault) : NULL;
    failures += report("image-create-provider-decode", providerImage &&
        CGImageGetWidth(providerImage) == 1 &&
        CGImageGetHeight(providerImage) == 1 &&
        CGImageGetDataProvider(providerImage) != NULL);
    CFDataRef copiedProviderData = providerImage ? CGDataProviderCopyData(
        CGImageGetDataProvider(providerImage)) : NULL;
    failures += report("data-provider-copy-image-bytes", copiedProviderData &&
        CFDataGetLength(copiedProviderData) == sizeof(providerBytes) &&
        memcmp(CFDataGetBytePtr(copiedProviderData), providerBytes,
            sizeof(providerBytes)) == 0);
    failures += report("data-provider-copy-null",
        CGDataProviderCopyData(NULL) == NULL);
    const CGFloat redComponents[] = {1.0f, 0.0f, 0.0f, 0.75f};
    CGColorRef red = rgb ? CGColorCreate(rgb, redComponents) : NULL;
    const CGFloat *roundTrip = red ? CGColorGetComponents(red) : NULL;
    failures += report("color-create-components", red && roundTrip &&
        fabsf((float)(roundTrip[0] - 1.0f)) < 0.001f &&
        fabsf((float)(roundTrip[1] - 0.0f)) < 0.001f &&
        fabsf((float)(roundTrip[2] - 0.0f)) < 0.001f &&
        fabsf((float)(roundTrip[3] - 0.75f)) < 0.001f &&
        fabsf((float)(CGColorGetAlpha(red) - 0.75f)) < 0.001f &&
        CGColorSpaceGetModel(CGColorGetColorSpace(red)) ==
            kCGColorSpaceModelRGB);

    CGContextRef context = rgb ? CGBitmapContextCreate(
        pixels, 4, 4, 8, 16, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    failures += report("bitmap-context-create", context != NULL);
    if(context) {
        CGContextSaveGState(context);
        CGContextSetFillColorWithColor(context, red);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextSetInterpolationQuality(context, kCGInterpolationLow);
        CGContextSetShouldAntialias(context, false);
        CGContextFillRect(context, CGRectMake(0, 0, 4, 4));
        failures += report("bitmap-fill-sync",
            buffer_has_nonzero_byte(pixels, sizeof(pixels)));

        CGContextRestoreGState(context);
        CGContextClearRect(context, CGRectMake(0, 0, 4, 4));
        failures += report("bitmap-clear-sync",
            !buffer_has_nonzero_byte(pixels, sizeof(pixels)));

        CGContextSetAlpha(context, 0.5f);
        CGContextSetGrayFillColor(context, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 4, 4));
        failures += report("bitmap-global-alpha", pixels[3] >= 127 && pixels[3] <= 128);
        CGContextSetAlpha(context, 1);
        CGContextClearRect(context, CGRectMake(0, 0, 4, 4));

        const CGPoint linePoints[] = {
            CGPointMake(0, 0), CGPointMake(3, 0), CGPointMake(3, 3),
        };
        CGContextBeginPath(context);
        CGContextAddLines(context, linePoints,
            sizeof(linePoints) / sizeof(linePoints[0]));
        CGContextSetGrayStrokeColor(context, 1.0f, 1.0f);
        CGContextSetLineJoin(context, kCGLineJoinBevel);
        CGContextSetLineWidth(context, 1.0f);
        CGContextSetShadow(context, CGSizeMake(0, 0), 0);
        CGContextStrokePath(context);
        failures += report("context-lines-stroke-sync",
            buffer_has_nonzero_byte(pixels, sizeof(pixels)));
        CGContextClearRect(context, CGRectMake(0, 0, 4, 4));

        CGMutablePathRef path = CGPathCreateMutable();
        CGAffineTransform translation =
            CGAffineTransformMakeTranslation(1.0f, 1.0f);
        if(path) {
            CGPathAddRect(path, &translation, CGRectMake(0, 0, 2, 2));
            CGPathMoveToPoint(path, NULL, 0, 0);
            CGPathAddArcToPoint(path, NULL, 1, 0, 1, 1, 0.25f);
            CGPathAddCurveToPoint(path, NULL, 1, 2, 2, 2, 3, 3);
            CGPathCloseSubpath(path);
        }
        CGPathRef copiedPath = path ? CGPathCreateCopy(path) : NULL;
        failures += report("path-copy-transform-contains",
            copiedPath && CGPathContainsPoint(copiedPath, NULL,
                CGPointMake(1.5f, 1.5f), false));

        CGMutablePathRef boundingPath = CGPathCreateMutable();
        CGMutablePathRef ellipse = CGPathCreateMutable();
        CGPathAddEllipseInRect(ellipse, &translation, CGRectMake(0, 0, 4, 2));
        failures += report("path-ellipse-transformed-shape",
            CGPathContainsPoint(ellipse, NULL, CGPointMake(3, 2), false) &&
            !CGPathContainsPoint(ellipse, NULL, CGPointMake(1.1f, 1.1f), false));
        CGPathRelease(ellipse);
        CGMutablePathRef curve = CGPathCreateMutable();
        CGPathMoveToPoint(curve, NULL, 0, 0);
        CGPathAddQuadCurveToPoint(curve, &translation, 1, 3, 3, 0);
        CGRect curveBounds = CGPathGetBoundingBox(curve);
        failures += report("path-quad-transformed-control", curveBounds.size.width == 4 &&
            curveBounds.size.height == 4);
        CGPathRelease(curve);
        if(boundingPath) CGPathAddRect(
            boundingPath, NULL, CGRectMake(2, 3, 4, 5));
        const CGRect boundingBox = boundingPath
            ? CGPathGetBoundingBox(boundingPath) : CGRectNull;
        failures += report("path-bounding-box",
            boundingPath && fabsf((float)(boundingBox.origin.x - 2)) < 0.001f &&
            fabsf((float)(boundingBox.origin.y - 3)) < 0.001f &&
            fabsf((float)(boundingBox.size.width - 4)) < 0.001f &&
            fabsf((float)(boundingBox.size.height - 5)) < 0.001f);

        CGContextBeginPath(context);
        CGContextAddPath(context, copiedPath);
        CGContextSetGrayFillColor(context, 0.5f, 1.0f);
        CGContextFillPath(context);
        failures += report("context-path-fill-sync",
            buffer_has_nonzero_byte(pixels, sizeof(pixels)));

        CGContextBeginPath(context);
        CGContextMoveToPoint(context, 0, 0);
        CGContextAddLineToPoint(context, 3, 0);
        CGContextAddArcToPoint(context, 4, 0, 4, 1, 0.5f);
        CGContextAddArc(context, 2, 2, 1, 0, 3.1415927f, false);
        CGContextClosePath(context);
        CGContextSetStrokeColorWithColor(context, red);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineWidth(context, 1.0f);
        CGContextStrokePath(context);
        CGContextStrokeRect(context, CGRectMake(0, 0, 3, 3));
        CGContextSetTextPosition(context, 1.25f, -2.5f);
        const CGPoint textPosition = CGContextGetTextPosition(context);
        failures += report("context-text-position-float-abi",
            fabsf(textPosition.x - 1.25f) < 0.001f &&
            fabsf(textPosition.y + 2.5f) < 0.001f);
        CGContextSetTextMatrix(context,
            CGAffineTransformMake(1, 0, 0, 1, 2, 3));
        const CGPoint matrixPosition = CGContextGetTextPosition(context);
        failures += report("context-text-position-from-matrix",
            fabsf(matrixPosition.x - 2.0f) < 0.001f &&
            fabsf(matrixPosition.y - 3.0f) < 0.001f);
        CGContextScaleCTM(context, 1, 1);
        CGContextTranslateCTM(context, 0, 0);
        CGContextConcatCTM(context, CGAffineTransformIdentity);

        CGImageRef image = CGBitmapContextCreateImage(context);
        failures += report("bitmap-create-image-properties", image &&
            CGImageGetWidth(image) == 4 && CGImageGetHeight(image) == 4 &&
            CGImageGetBitsPerComponent(image) == 8 &&
            CGImageGetAlphaInfo(image) == kCGImageAlphaPremultipliedLast &&
            CGImageGetColorSpace(image) != NULL &&
            CGColorSpaceGetModel(CGImageGetColorSpace(image)) ==
                kCGColorSpaceModelRGB);

        CGImageRef copiedImage = image ? CGImageCreateCopy(image) : NULL;
        CGImageRef retainedImage = CGImageRetain(image);
        failures += report("image-retain-identity-null",
            retainedImage && retainedImage == image && CGImageRetain(NULL) == NULL);
        failures += report("image-copy-provider", copiedImage &&
            CGImageGetWidth(copiedImage) == 4 &&
            CGImageGetHeight(copiedImage) == 4 &&
            CGImageGetDataProvider(copiedImage) != NULL);

        CGImageRef cropped = image ? CGImageCreateWithImageInRect(
            image, CGRectMake(1, 1, 2, 2)) : NULL;
        failures += report("image-crop-owned", cropped &&
            CGImageGetWidth(cropped) == 2 && CGImageGetHeight(cropped) == 2);

        CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
        CGContextRef maskContext = gray ? CGBitmapContextCreate(
            maskPixels, 4, 4, 8, 4, gray, kCGImageAlphaNone) : NULL;
        if(maskContext) {
            CGContextSetGrayFillColor(maskContext, 1, 1);
            CGContextFillRect(maskContext, CGRectMake(0, 0, 4, 4));
        }
        CGImageRef mask = maskContext
            ? CGBitmapContextCreateImage(maskContext) : NULL;
        CGImageRef masked = image && mask
            ? CGImageCreateWithMask(image, mask) : NULL;
        failures += report("image-mask-owned", masked != NULL);

        if(masked) CGImageRelease(masked);
        if(mask) CGImageRelease(mask);
        if(maskContext) CGContextRelease(maskContext);
        if(gray) CGColorSpaceRelease(gray);
        if(cropped) CGImageRelease(cropped);
        if(copiedImage) CGImageRelease(copiedImage);
        if(image) CGImageRelease(image);
        if(boundingPath) CGPathRelease(boundingPath);
        if(copiedPath) CGPathRelease(copiedPath);
        if(path) CGPathRelease(path);
        CGContextRelease(context);
        failures += report("image-retain-outlives-owner-and-context", retainedImage &&
            CGImageGetWidth(retainedImage) == 4 && CGImageGetHeight(retainedImage) == 4 &&
            CGImageGetDataProvider(retainedImage) != NULL);
        if(retainedImage) CGImageRelease(retainedImage);
    }

    if(red) CGColorRelease(red);
    if(providerImage) CGImageRelease(providerImage);
    if(rgb) CGColorSpaceRelease(rgb);
    if(provider) CGDataProviderRelease(provider);
    if(providerData) CFRelease(providerData);
    failures += report("data-provider-copy-outlives-image-provider",
        copiedProviderData &&
        CFDataGetLength(copiedProviderData) == sizeof(providerBytes) &&
        memcmp(CFDataGetBytePtr(copiedProviderData), providerBytes,
            sizeof(providerBytes)) == 0);
    if(copiedProviderData) CFRelease(copiedProviderData);
    return failures == 0 ? 0 : 1;
}
