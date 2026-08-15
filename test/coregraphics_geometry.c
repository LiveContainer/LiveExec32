#include <CoreGraphics/CoreGraphics.h>

#include <math.h>
#include <stdbool.h>
#include <stdio.h>

static bool near(CGFloat a, CGFloat b) {
    return fabsf(a - b) < 0.0001f;
}

static bool transform_near(CGAffineTransform value,
                           CGAffineTransform expected) {
    return near(value.a, expected.a) && near(value.b, expected.b) &&
        near(value.c, expected.c) && near(value.d, expected.d) &&
        near(value.tx, expected.tx) && near(value.ty, expected.ty);
}

static bool rect_near(CGRect value, CGRect expected) {
    return near(value.origin.x, expected.origin.x) &&
        near(value.origin.y, expected.origin.y) &&
        near(value.size.width, expected.size.width) &&
        near(value.size.height, expected.size.height);
}

int main(void) {
    const CGAffineTransform transform =
        CGAffineTransformMake(2, 3, 5, 7, 11, 13);
    bool transformsPassed =
        CGAffineTransformIsIdentity(CGAffineTransformIdentity) &&
        !CGAffineTransformIsIdentity(transform) &&
        transform_near(CGAffineTransformMakeTranslation(17, 19),
            CGAffineTransformMake(1, 0, 0, 1, 17, 19)) &&
        transform_near(CGAffineTransformMakeScale(17, 19),
            CGAffineTransformMake(17, 0, 0, 19, 0, 0)) &&
        transform_near(CGAffineTransformTranslate(transform, 17, 19),
            CGAffineTransformMake(2, 3, 5, 7, 140, 197)) &&
        transform_near(CGAffineTransformScale(transform, 17, 19),
            CGAffineTransformMake(34, 51, 95, 133, 11, 13));
    const CGAffineTransform quarterTurn =
        CGAffineTransformMakeRotation((CGFloat)M_PI_2);
    transformsPassed = transformsPassed &&
        near(quarterTurn.a, 0) && near(quarterTurn.b, 1) &&
        near(quarterTurn.c, -1) && near(quarterTurn.d, 0);
    printf("coregraphics-transforms: %s\n",
           transformsPassed ? "PASS" : "FAIL");

    bool geometryPassed =
        rect_near(CGRectIntegral(CGRectMake(1.2f, 2.8f, 3.1f, 4.1f)),
                  CGRectMake(1, 2, 4, 5)) &&
        rect_near(CGRectUnion(CGRectMake(5, 6, -3, -4),
                              CGRectMake(10, 11, 2, 3)),
                  CGRectMake(2, 2, 10, 12)) &&
        rect_near(CGRectApplyAffineTransform(
                      CGRectMake(1, 2, 3, 4), quarterTurn),
                  CGRectMake(-6, 1, 4, 3));
    CGRect slice = CGRectZero;
    CGRect remainder = CGRectZero;
    CGRectDivide(CGRectMake(10, 20, 100, 200), &slice, &remainder,
                 30, CGRectMaxXEdge);
    geometryPassed = geometryPassed &&
        rect_near(slice, CGRectMake(80, 20, 30, 200)) &&
        rect_near(remainder, CGRectMake(10, 20, 70, 200));
    printf("coregraphics-geometry: %s\n",
           geometryPassed ? "PASS" : "FAIL");
    return !(transformsPassed && geometryPassed);
}
