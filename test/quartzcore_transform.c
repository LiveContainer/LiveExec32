#include <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdio.h>

static int near(CGFloat first, CGFloat second) {
    return fabsf((float)(first - second)) < 0.0001f;
}

static int rotationIsOrthonormal(CATransform3D t) {
    const CGFloat rows[3][3] = {
        {t.m11, t.m12, t.m13}, {t.m21, t.m22, t.m23},
        {t.m31, t.m32, t.m33}
    };
    for(int i = 0; i < 3; ++i)
        for(int j = 0; j < 3; ++j) {
            CGFloat dot = 0;
            for(int k = 0; k < 3; ++k) dot += rows[i][k] * rows[j][k];
            if(!near(dot, i == j ? 1 : 0)) return 0;
        }
    const CGFloat determinant =
        t.m11 * (t.m22 * t.m33 - t.m23 * t.m32) -
        t.m12 * (t.m21 * t.m33 - t.m23 * t.m31) +
        t.m13 * (t.m21 * t.m32 - t.m22 * t.m31);
    return near(determinant, 1);
}

static int checkRotations(void) {
    const CGFloat angles[] = {0, 0.37, -0.37, M_PI_4, M_PI_2, -M_PI_2, M_PI};
    const CGFloat axes[][3] = {{1,0,0}, {0,1,0}, {0,0,1}, {2,-3,4}};
    for(unsigned i = 0; i < sizeof(angles) / sizeof(angles[0]); ++i) {
        const CGFloat angle = angles[i], c = cos(angle), s = sin(angle);
        const CATransform3D x = CATransform3DMakeRotation(angle, 1, 0, 0);
        const CATransform3D y = CATransform3DMakeRotation(angle, 0, 1, 0);
        const CATransform3D z = CATransform3DMakeRotation(angle, 0, 0, 1);
        const CGAffineTransform affine = CGAffineTransformMakeRotation(angle);
        if(!near(x.m22,c) || !near(x.m23,s) || !near(x.m32,-s) || !near(x.m33,c) ||
           !near(y.m11,c) || !near(y.m13,-s) || !near(y.m31,s) || !near(y.m33,c) ||
           !near(z.m11,affine.a) || !near(z.m12,affine.b) ||
           !near(z.m21,affine.c) || !near(z.m22,affine.d)) return 0;
        for(unsigned j = 0; j < sizeof(axes) / sizeof(axes[0]); ++j) {
            CATransform3D rotation = CATransform3DMakeRotation(
                angle, axes[j][0], axes[j][1], axes[j][2]);
            if(!rotationIsOrthonormal(rotation)) return 0;
        }
    }
    return CATransform3DIsIdentity(CATransform3DMakeRotation(1,0,0,0));
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
    const int rotationsPassed = checkRotations();
    printf("quartzcore-axis-angle-rotation: %s\n", rotationsPassed ? "PASS" : "FAIL");
    return passed && rotationsPassed ? 0 : 1;
}
