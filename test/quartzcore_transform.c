#include <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdio.h>

static int near(CGFloat first, CGFloat second) {
    return fabsf((float)(first - second)) < 0.0001f;
}

int main(void) {
    const CGAffineTransform affine =
        CGAffineTransformMake(2, 3, 5, 7, 11, 13);
    const CATransform3D transform =
        CATransform3DMakeAffineTransform(affine);
    const int passed =
        near(transform.m11, 2) && near(transform.m12, 3) &&
        near(transform.m13, 0) && near(transform.m14, 0) &&
        near(transform.m21, 5) && near(transform.m22, 7) &&
        near(transform.m23, 0) && near(transform.m24, 0) &&
        near(transform.m31, 0) && near(transform.m32, 0) &&
        near(transform.m33, 1) && near(transform.m34, 0) &&
        near(transform.m41, 11) && near(transform.m42, 13) &&
        near(transform.m43, 0) && near(transform.m44, 1);
    printf("quartzcore-affine-transform: %s\n",
        passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}
