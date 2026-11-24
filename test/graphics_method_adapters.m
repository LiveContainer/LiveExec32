#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static unsigned failures;
static void check(BOOL passed, const char *name) {
    printf("graphics-method-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        const CGRect first = CGRectMake(1, 2, 3, 4);
        CGMutablePathRef source = CGPathCreateMutable();
        CGPathAddRect(source, NULL, first);
        UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:source];
        CGPathRelease(source);
        check(path && CGRectEqualToRect(path.bounds, first), "path-factory-native-copy");
        check(path.CGPath && CGRectEqualToRect(CGPathGetBoundingBox(path.CGPath), first),
            "path-getter");
        source = CGPathCreateMutable();
        const CGRect second = CGRectMake(-4, 5, 6, 7);
        CGPathAddRect(source, NULL, second);
        path.CGPath = source;
        CGPathRelease(source);
        check(CGRectEqualToRect(path.bounds, second), "path-setter-native-copy");
        [path removeAllPoints];
        check(CGPathIsEmpty(path.CGPath), "path-getter-after-native-mutation");

        uint8_t sourcePixels[16] = {0}, pixels[64] = {0};
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        const CGBitmapInfo format = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
        CGContextRef sourceContext = CGBitmapContextCreate(sourcePixels, 2, 2, 8, 8, rgb, format);
        CGContextRef target = CGBitmapContextCreate(pixels, 4, 4, 8, 16, rgb, format);
        CGContextSetRGBFillColor(sourceContext, 0, 1, 0, 1);
        CGContextFillRect(sourceContext, CGRectMake(0, 0, 2, 2));
        CGImageRef image = CGBitmapContextCreateImage(sourceContext);
        CALayer *layer = [CALayer layer];
        layer.bounds = CGRectMake(0, 0, 4, 4);
        layer.contents = (id)image;
        [layer renderInContext:target];
        // Do not call GetData/Flush here: renderInContext: must synchronize
        // the caller-owned buffer before returning.
        check(target && pixels[1] > 240 && pixels[3] > 240 && pixels[0] < 15,
            "layer-render-guest-bitmap-sync");
        memset(pixels, 0, sizeof(pixels));
        [layer renderInContext:target];
        check(pixels[1] > 240 && pixels[3] > 240, "layer-render-repeat");
        layer.contents = nil;
        CGImageRelease(image);
        CGContextRelease(sourceContext);
        CGContextRelease(target);
        CGColorSpaceRelease(rgb);
    }
    return failures != 0;
}
