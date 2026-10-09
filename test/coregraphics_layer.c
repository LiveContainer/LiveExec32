#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>

static int check(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return !passed;
}

int main(void) {
    uint8_t pixels[8 * 8 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels, 8, 8, 8, 32, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGLayerRef layer = CGLayerCreateWithContext(bitmap, CGSizeMake(4, 4), NULL);
    CGContextRef drawing = layer ? CGLayerGetContext(layer) : NULL;
    int failures = check("layer-create-and-borrowed-context", bitmap && layer &&
        drawing && drawing == CGLayerGetContext(layer));
    if(!drawing) return failures;
    CGLayerRef retained = CGLayerRetain(layer);
    CGLayerRelease(layer);
    failures += check("layer-retain-identity", retained == layer &&
        drawing == CGLayerGetContext(retained));
    CGContextSetRGBFillColor(drawing, 1, 0, 0, 1);
    CGContextFillRect(drawing, CGRectMake(0, 0, 4, 4));
    CGContextDrawLayerAtPoint(bitmap, CGPointMake(2, 2), retained);
    int red = 0, unexpected = 0;
    for(int y = 0; y < 8; ++y) for(int x = 0; x < 8; ++x) {
        uint8_t *p = pixels + (y * 8 + x) * 4;
        if(x >= 2 && x < 6 && y >= 2 && y < 6)
            red += p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255;
        else unexpected += p[3] != 0;
    }
    failures += check("layer-draw-at-point-syncs-bitmap", red == 16 && unexpected == 0);
    CGLayerRelease(retained);
    CGContextClearRect(bitmap, CGRectMake(0, 0, 8, 8));
    CGContextSetShouldAntialias(bitmap, false);
    CGContextSetRGBFillColor(bitmap, 0, 1, 0, 1);
    CGContextBeginPath(bitmap);
    CGContextMoveToPoint(bitmap, 2, 2);
    CGContextAddCurveToPoint(bitmap, 2, 6, 6, 6, 6, 2);
    CGContextClosePath(bitmap);
    CGContextFillPath(bitmap);
    int green = 0;
    for(int i = 0; i < 64; ++i) green += pixels[i * 4 + 1] != 0;
    failures += check("context-cubic-curve-fills-area", green > 0 && green < 16);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(space);
    return failures;
}
