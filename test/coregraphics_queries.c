#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdio.h>

static int failures;
static void check(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static int near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.001; }
static void release(CFTypeRef object) { if(object) CFRelease(object); }

int main(void) {
    unsigned char pixels[16 * 16 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(pixels, 16, 16, 8, 64, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if(!space || !c) return 1;
    check("bitmap-format-queries", CGBitmapContextGetBitsPerComponent(c) == 8 &&
        CGBitmapContextGetBitsPerPixel(c) == 32 &&
        CGBitmapContextGetAlphaInfo(c) == kCGImageAlphaPremultipliedLast &&
        CGBitmapContextGetBitmapInfo(c) ==
            (kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
    check("bitmap-colorspace-borrowed", CGBitmapContextGetColorSpace(c) == space);
    check("context-retain", CGContextRetain(c) == c);
    CGContextRelease(c);
    check("colorspace-retain", CGColorSpaceRetain(space) == space);
    CGColorSpaceRelease(space);
    check("context-colorspace-typeids", CFGetTypeID(c) == CGContextGetTypeID() &&
        CFGetTypeID(space) == CGColorSpaceGetTypeID());
    CFStringRef name = CGColorSpaceCopyName(space);
    check("colorspace-copy-name", name && CFEqual(name, kCGColorSpaceSRGB));
    release(name);
    CFDataRef profile = CGColorSpaceCopyICCProfile(space);
    CFDataRef data = CGColorSpaceCopyICCData(space);
    CGColorSpaceRef copiedSpace = profile ? CGColorSpaceCreateWithICCProfile(profile) : NULL;
    check("colorspace-icc-roundtrip", data && profile && CFEqual(data, profile) &&
        copiedSpace && CGColorSpaceGetNumberOfComponents(copiedSpace) == 3);
    release(data); release(profile); release(copiedSpace);
    CGColorSpaceRef cmyk = CGColorSpaceCreateDeviceCMYK();
    CGColorSpaceRef pattern = CGColorSpaceCreatePattern(space);
    CGColorSpaceRef coloredPattern = CGColorSpaceCreatePattern(NULL);
    check("colorspace-cmyk-pattern", cmyk && pattern && coloredPattern &&
        CGColorSpaceGetModel(cmyk) == kCGColorSpaceModelCMYK &&
        CGColorSpaceGetBaseColorSpace(pattern) == space &&
        CGColorSpaceGetBaseColorSpace(coloredPattern) == NULL);
    check("colorspace-properties", CGColorSpaceSupportsOutput(space) &&
        !CGColorSpaceIsWideGamutRGB(space) && CGColorSpaceGetColorTableCount(space) == 0);
    release(cmyk); release(pattern); release(coloredPattern);

    CGFloat components[] = {1, 0, 0, 1};
    CGColorRef red = CGColorCreate(space, components);
    CGColorRef faded = CGColorCreateCopyWithAlpha(red, 0.25);
    check("color-alpha-copy", faded && near(CGColorGetAlpha(faded), 0.25) &&
        near(CGColorGetAlpha(red), 1) && CFGetTypeID(red) == CGColorGetTypeID());
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space,
        (CGFloat[]){1, 0, 0, 1, 0, 0, 1, 1}, NULL, 2);
    check("gradient-type-retain", gradient && CFGetTypeID(gradient) == CGGradientGetTypeID() &&
        CGGradientRetain(gradient) == gradient);
    CGGradientRelease(gradient); CGGradientRelease(gradient);

    CGContextTranslateCTM(c, 2, 3);
    CGContextScaleCTM(c, 2, 3);
    CGAffineTransform transform = CGContextGetCTM(c);
    check("context-ctm-float-layout", near(transform.a, 2) && near(transform.d, 3) &&
        near(transform.tx, 2) && near(transform.ty, 3));
    CGAffineTransform deviceTransform = CGContextGetUserSpaceToDeviceSpaceTransform(c);
    CGPoint expectedPoint = CGPointApplyAffineTransform(CGPointMake(2, 3), deviceTransform);
    CGPoint p = CGContextConvertPointToDeviceSpace(c, CGPointMake(2, 3));
    CGPoint q = CGContextConvertPointToUserSpace(c, p);
    CGSize s = CGContextConvertSizeToDeviceSpace(c, CGSizeMake(2, 3));
    CGSize t = CGContextConvertSizeToUserSpace(c, s);
    CGRect r = CGRectMake(1, 2, 3, 4);
    CGRect converted = CGContextConvertRectToDeviceSpace(c, r);
    check("context-device-transform", near(p.x, expectedPoint.x) && near(p.y, expectedPoint.y));
    check("context-convert-point-size-rect", near(q.x, 2) && near(q.y, 3) &&
        near(t.width, 2) && near(t.height, 3) &&
        CGRectEqualToRect(CGContextConvertRectToUserSpace(c, converted), r));
    CGAffineTransform text = CGAffineTransformMake(1.5, 0.25, 0.5, 2, 4, 5);
    CGContextSetTextMatrix(c, text);
    check("context-text-matrix", CGAffineTransformEqualToTransform(CGContextGetTextMatrix(c), text));
    CGContextConcatCTM(c, CGAffineTransformInvert(transform));
    check("context-clip-bounds", CGRectEqualToRect(CGContextGetClipBoundingBox(c), CGRectMake(0, 0, 16, 16)));
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    check("context-interpolation", CGContextGetInterpolationQuality(c) == kCGInterpolationHigh);

    CGMutablePathRef path = CGPathCreateMutable();
    check("path-empty", CGPathIsEmpty(path) && CGContextIsPathEmpty(c));
    CGPathAddRect(path, NULL, CGRectMake(2, 2, 8, 8));
    CGMutablePathRef pathCopy = CGPathCreateMutableCopy(path);
    check("path-copy-equality", pathCopy && CGPathEqualToPath(path, pathCopy) &&
        !CGPathIsEmpty(pathCopy) && CFGetTypeID(pathCopy) == CGPathGetTypeID());
    check("path-geometry", CGRectEqualToRect(CGPathGetPathBoundingBox(path), CGRectMake(2, 2, 8, 8)) &&
        CGPointEqualToPoint(CGPathGetCurrentPoint(path), CGPointMake(2, 2)));
    CGContextAddPath(c, path);
    CGPathRef current = CGContextCopyPath(c);
    check("context-path-copy-geometry", current && CGPathEqualToPath(current, path) &&
        !CGContextIsPathEmpty(c) &&
        CGRectEqualToRect(CGContextGetPathBoundingBox(c), CGPathGetPathBoundingBox(path)) &&
        CGPointEqualToPoint(CGContextGetPathCurrentPoint(c), CGPathGetCurrentPoint(path)));
    release(current);
    CGContextSetFlatness(c, 0.5);
    CGContextSetMiterLimit(c, 5);
    CGContextSetRenderingIntent(c, kCGRenderingIntentRelativeColorimetric);
    CGContextSetFillColorSpace(c, space);
    CGContextSetFillColorWithColor(c, red);
    CGContextSetShouldAntialias(c, false);
    CGContextAddRect(c, CGRectMake(4, 4, 4, 4));
    CGContextEOFillPath(c);
    int filled = 0;
    for(int i = 0; i < 256; ++i) filled += pixels[i * 4 + 3] == 255;
    check("even-odd-fill-pixel-sync", filled == 48);
    CGContextClearRect(c, CGRectMake(0, 0, 16, 16));
    CGContextSaveGState(c);
    CGContextAddRect(c, CGRectMake(0, 0, 8, 8));
    CGContextAddRect(c, CGRectMake(2, 2, 4, 4));
    CGContextEOClip(c);
    CGContextSetCMYKFillColor(c, 0, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 16, 16));
    CGContextRestoreGState(c);
    filled = 0;
    for(int i = 0; i < 256; ++i) filled += pixels[i * 4 + 3] == 255;
    check("even-odd-clip", filled == 48);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 1, 1);
    CGContextAddQuadCurveToPoint(c, 8, 12, 14, 1);
    check("context-quadratic-current-point", CGPointEqualToPoint(CGContextGetPathCurrentPoint(c), CGPointMake(14, 1)));
    CGContextSetLineWidth(c, 2);
    CGContextReplacePathWithStrokedPath(c);
    check("context-stroked-outline", !CGContextIsPathEmpty(c) && CGContextGetPathBoundingBox(c).size.height > 1);
    CGContextSetCMYKStrokeColor(c, 0, 1, 1, 0, 1);
    CGContextStrokePath(c);
    CGContextSynchronize(c);

    CGImageRef image = CGBitmapContextCreateImage(c);
    CGImageRef imageCopy = CGImageCreateCopyWithColorSpace(image, space);
    check("image-query-copy", imageCopy && !CGImageIsMask(image) &&
        CGImageGetShouldInterpolate(image) == CGImageGetShouldInterpolate(imageCopy) &&
        CGImageGetRenderingIntent(image) == CGImageGetRenderingIntent(imageCopy) &&
        CFGetTypeID(image) == CGImageGetTypeID() && CGImageGetWidth(imageCopy) == 16);
    CGDataProviderRef provider = CGImageGetDataProvider(image);
    check("provider-typeid", provider && CFGetTypeID(provider) == CGDataProviderGetTypeID());
    CGLayerRef layer = CGLayerCreateWithContext(c, CGSizeMake(4, 6), NULL);
    check("layer-size-typeid", layer && CFGetTypeID(layer) == CGLayerGetTypeID() &&
        CGSizeEqualToSize(CGLayerGetSize(layer), CGSizeMake(4, 6)));

    CGFontRef font = CGFontCreateWithFontName(CFSTR("Helvetica"));
    CFStringRef fullName = font ? CGFontCopyFullName(font) : NULL;
    CFStringRef postscript = font ? CGFontCopyPostScriptName(font) : NULL;
    CFArrayRef tables = font ? CGFontCopyTableTags(font) : NULL;
    check("font-copy-metadata", font && fullName && postscript && tables &&
        CFStringGetLength(fullName) && CFStringGetLength(postscript) &&
        CFArrayGetCount(tables) && CFGetTypeID(font) == CGFontGetTypeID());
    CGGlyph glyph = CGFontGetGlyphWithGlyphName(font, CFSTR("A"));
    CFStringRef glyphName = CGFontCopyGlyphNameForGlyph(font, glyph);
    check("font-glyph-name-bounds", glyph && glyphName && CFEqual(glyphName, CFSTR("A")) &&
        CGFontGetFontBBox(font).size.height > 0);
    CFArrayRef axes = CGFontCopyVariationAxes(font);
    CFDictionaryRef variations = CGFontCopyVariations(font);
    CGFontRef fontCopy = CGFontCreateCopyWithVariations(font, variations);
    check("font-variation-copy", fontCopy && CGFontGetNumberOfGlyphs(fontCopy) == CGFontGetNumberOfGlyphs(font) &&
        (!axes || CFGetTypeID(axes) == CFArrayGetTypeID()) &&
        (!variations || CFGetTypeID(variations) == CFDictionaryGetTypeID()));
    release(fontCopy); release(axes); release(variations); release(glyphName);
    release(fullName); release(postscript); release(tables); release(font);
    release(layer); release(imageCopy); release(image); release(pathCopy); release(path);
    release(faded); release(red); CGContextRelease(c); CGColorSpaceRelease(space);
    return failures;
}
