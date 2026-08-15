#include <CoreGraphics/CoreGraphics.h>

#include <stdint.h>
#include <stdio.h>

static int report(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}

static int byte_is_near(uint8_t value, uint8_t expected) {
    const int difference = (int)value - (int)expected;
    return difference >= -2 && difference <= 2;
}

int main(void) {
    int failures = 0;

    uint8_t rgbaPixel[4] = {};
    CGColorSpaceRef rgbSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef rgbContext = rgbSpace ? CGBitmapContextCreate(
        rgbaPixel, 1, 1, 8, sizeof(rgbaPixel), rgbSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    const CGFloat initialRGB[] = {0, 0, 0, 1};
    CGColorRef initialRGBColor = rgbSpace
        ? CGColorCreate(rgbSpace, initialRGB) : NULL;
    if(rgbContext && initialRGBColor)
        CGContextSetFillColorWithColor(rgbContext, initialRGBColor);
    const CGFloat rgba[] = {0.25f, 0.5f, 0.75f, 1.0f};
    if(rgbContext) {
        CGContextSetFillColor(rgbContext, rgba);
        CGContextFillRect(rgbContext, CGRectMake(0, 0, 1, 1));
    }
    failures += report("fill-color-rgba", rgbContext &&
        byte_is_near(rgbaPixel[0], 64) &&
        byte_is_near(rgbaPixel[1], 128) &&
        byte_is_near(rgbaPixel[2], 191) &&
        byte_is_near(rgbaPixel[3], 255));

    uint8_t grayAlphaPixel[2] = {};
    CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
    CGContextRef grayContext = graySpace ? CGBitmapContextCreate(
        grayAlphaPixel, 1, 1, 8, sizeof(grayAlphaPixel), graySpace,
        kCGImageAlphaPremultipliedLast) : NULL;
    const CGFloat initialGray[] = {0, 1};
    CGColorRef initialGrayColor = graySpace
        ? CGColorCreate(graySpace, initialGray) : NULL;
    if(grayContext && initialGrayColor)
        CGContextSetFillColorWithColor(grayContext, initialGrayColor);
    const CGFloat grayAlpha[] = {0.75f, 0.5f};
    if(grayContext) {
        CGContextSetFillColor(grayContext, grayAlpha);
        CGContextFillRect(grayContext, CGRectMake(0, 0, 1, 1));
    }
    failures += report("fill-color-gray-alpha", grayContext &&
        byte_is_near(grayAlphaPixel[0], 96) &&
        byte_is_near(grayAlphaPixel[1], 128));

    if(initialGrayColor) CGColorRelease(initialGrayColor);
    if(grayContext) CGContextRelease(grayContext);
    if(graySpace) CGColorSpaceRelease(graySpace);
    if(initialRGBColor) CGColorRelease(initialRGBColor);
    if(rgbContext) CGContextRelease(rgbContext);
    if(rgbSpace) CGColorSpaceRelease(rgbSpace);

    return failures == 0 ? 0 : 1;
}
