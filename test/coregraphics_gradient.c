#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int report(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}

static int buffer_has_nonzero_byte(const uint8_t *bytes, size_t count) {
    for(size_t index = 0; index < count; ++index) {
        if(bytes[index]) return 1;
    }
    return 0;
}

int main(void) {
    int failures = 0;
    uint8_t pixels[8 * 2 * 4] = {};
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = rgb ? CGBitmapContextCreate(
        pixels, 8, 2, 8, 8 * 4, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;

    const CGFloat components[] = {
        1, 0, 0, 1,
        0, 0, 1, 1,
    };
    CGGradientRef componentGradient =
        CGGradientCreateWithColorComponents(rgb, components, NULL, 2);
    failures += report("gradient-components-null-locations-owned",
        componentGradient != NULL);
    if(context && componentGradient) {
        CGContextDrawLinearGradient(context, componentGradient,
            CGPointMake(0, 0), CGPointMake(8, 0), 0);
    }
    failures += report("gradient-linear-draw-sync",
        context && buffer_has_nonzero_byte(pixels, sizeof(pixels)) &&
        memcmp(pixels, pixels + 7 * 4, 4) != 0);

    const CGFloat greenComponents[] = {0, 1, 0, 1};
    CGColorRef red = rgb ? CGColorCreate(rgb, components) : NULL;
    CGColorRef green = rgb ? CGColorCreate(rgb, greenComponents) : NULL;
    const void *colorValues[] = {red, green};
    CFArrayRef colors = red && green ? CFArrayCreate(
        kCFAllocatorDefault, colorValues, 2, &kCFTypeArrayCallBacks) : NULL;
    const CGFloat locations[] = {0.25f, 0.75f};
    CGGradientRef colorGradient = colors
        ? CGGradientCreateWithColors(NULL, colors, locations) : NULL;
    failures += report("gradient-colors-null-space-explicit-locations-owned",
        colorGradient != NULL);

    const CGFloat oneComponent[] = {0, 0, 0, 1};
    failures += report("gradient-stop-cap-rejected",
        !CGGradientCreateWithColorComponents(
            rgb, oneComponent, NULL, 4097));

    if(colorGradient) CGGradientRelease(colorGradient);
    if(colors) CFRelease(colors);
    if(green) CGColorRelease(green);
    if(red) CGColorRelease(red);
    if(componentGradient) CGGradientRelease(componentGradient);
    if(context) CGContextRelease(context);
    if(rgb) CGColorSpaceRelease(rgb);
    return failures == 0 ? 0 : 1;
}
