#import <QuartzCore/QuartzCore.h>

const CATransform3D CATransform3DIdentity = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
};

bool CATransform3DIsIdentity(CATransform3D t) {
    return !memcmp(&t, &CATransform3DIdentity, sizeof(t));
}
bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b) {
    return !memcmp(&a, &b, sizeof(a));
}

CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz) {
    CATransform3D result = CATransform3DIdentity;
    result.m41 = tx;
    result.m42 = ty;
    result.m43 = tz;
    return result;
}

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz) {
    CATransform3D result = CATransform3DIdentity;
    result.m11 = sx;
    result.m22 = sy;
    result.m33 = sz;
    return result;
}

CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform transform) {
    CATransform3D result = CATransform3DIdentity;
    result.m11 = transform.a;
    result.m12 = transform.b;
    result.m21 = transform.c;
    result.m22 = transform.d;
    result.m41 = transform.tx;
    result.m42 = transform.ty;
    return result;
}

CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    // If the vector has length zero, this function returns the identity transform
    if (x == 0.0 && y == 0.0 && z == 0.0) {
        return CATransform3DIdentity;
    }

    CGFloat s = sin(angle);
    CGFloat c = cos(angle);
    CGFloat length = sqrt(x*x + y*y + z*z);
    x /= length; y /= length; z /= length;
    CATransform3D result = {
        x*x*(1-c)+  c, y*x*(1-c)-z*s, z*x*(1-c)+y*s, 0,
        x*y*(1-c)+z*c, y*y*(1-c)+  c, z*y*(1-c)-x*s, 0,
        x*z*(1-c)-y*s, y*z*(1-c)+x*s, z*z*(1-c)+  c, 0,
        0, 0, 0, 1
    };
    return result;
}

CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz) {
    return CATransform3DConcat (CATransform3DMakeTranslation(tx, ty, tz), t);
}

CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz) {
    return CATransform3DConcat (CATransform3DMakeScale(sx, sy, sz), t);
}

CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    return CATransform3DConcat (CATransform3DMakeRotation(angle, x, y, z), t);
}

// https://github.com/microsoft/WinObjC/blob/develop/Frameworks/QuartzCore/CATransform3D.mm#L148-L158
typedef struct _CATransform3D {
    CGFloat m[4][4];
} _CATransform3D;
CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b) {
    CATransform3D ret;
    _CATransform3D *mat0 = (_CATransform3D*)&ret;
    _CATransform3D *mat1 = (_CATransform3D*)&a;
    _CATransform3D *mat2 = (_CATransform3D*)&b;
    int i, j, k;

    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            for (k = 0, mat0->m[i][j] = 0; k < 4; k++)
                mat0->m[i][j] += mat1->m[i][k] * mat2->m[k][j];

    return ret;
}

// gnustep's QuartzCore has a handy implementation of this, but it's LGPL licensed smh
// so this is using Mesa's impl which is MIT licensed

// https://github.com/chaotic-cx/mesa-mirror/blob/main/src/util/u_math.c#L127-L311
/**
 * Compute inverse of 4x4 matrix.
 *
 * \return false if the source matrix is singular.
 *
 * \author
 * Code contributed by Jacques Leroy jle@star.be
 *
 * Calculates the inverse matrix by performing the gaussian matrix reduction
 * with partial pivoting followed by back/substitution with the loops manually
 * unrolled.
 */
static bool
util_invert_mat4x4(float *out, const float *m)
{
   float wtmp[4][8];
   float m0, m1, m2, m3, s;
   float *r0, *r1, *r2, *r3;

#define MAT(m, r, c) (m)[(c)*4 + (r)]
#define SWAP_ROWS(a, b)                                                                            \
   {                                                                                               \
      float *_tmp = a;                                                                             \
      (a) = (b);                                                                                   \
      (b) = _tmp;                                                                                  \
   }

   r0 = wtmp[0], r1 = wtmp[1], r2 = wtmp[2], r3 = wtmp[3];

   r0[0] = MAT(m, 0, 0), r0[1] = MAT(m, 0, 1), r0[2] = MAT(m, 0, 2), r0[3] = MAT(m, 0, 3),
   r0[4] = 1.0, r0[5] = r0[6] = r0[7] = 0.0,

   r1[0] = MAT(m, 1, 0), r1[1] = MAT(m, 1, 1), r1[2] = MAT(m, 1, 2), r1[3] = MAT(m, 1, 3),
   r1[5] = 1.0, r1[4] = r1[6] = r1[7] = 0.0,

   r2[0] = MAT(m, 2, 0), r2[1] = MAT(m, 2, 1), r2[2] = MAT(m, 2, 2), r2[3] = MAT(m, 2, 3),
   r2[6] = 1.0, r2[4] = r2[5] = r2[7] = 0.0,

   r3[0] = MAT(m, 3, 0), r3[1] = MAT(m, 3, 1), r3[2] = MAT(m, 3, 2), r3[3] = MAT(m, 3, 3),
   r3[7] = 1.0, r3[4] = r3[5] = r3[6] = 0.0;

   /* choose pivot - or die */
   if (fabsf(r3[0]) > fabsf(r2[0]))
      SWAP_ROWS(r3, r2);
   if (fabsf(r2[0]) > fabsf(r1[0]))
      SWAP_ROWS(r2, r1);
   if (fabsf(r1[0]) > fabsf(r0[0]))
      SWAP_ROWS(r1, r0);
   if (0.0F == r0[0])
      return false;

   /* eliminate first variable     */
   m1 = r1[0] / r0[0];
   m2 = r2[0] / r0[0];
   m3 = r3[0] / r0[0];
   s = r0[1];
   r1[1] -= m1 * s;
   r2[1] -= m2 * s;
   r3[1] -= m3 * s;
   s = r0[2];
   r1[2] -= m1 * s;
   r2[2] -= m2 * s;
   r3[2] -= m3 * s;
   s = r0[3];
   r1[3] -= m1 * s;
   r2[3] -= m2 * s;
   r3[3] -= m3 * s;
   s = r0[4];
   if (s != 0.0F) {
      r1[4] -= m1 * s;
      r2[4] -= m2 * s;
      r3[4] -= m3 * s;
   }
   s = r0[5];
   if (s != 0.0F) {
      r1[5] -= m1 * s;
      r2[5] -= m2 * s;
      r3[5] -= m3 * s;
   }
   s = r0[6];
   if (s != 0.0F) {
      r1[6] -= m1 * s;
      r2[6] -= m2 * s;
      r3[6] -= m3 * s;
   }
   s = r0[7];
   if (s != 0.0F) {
      r1[7] -= m1 * s;
      r2[7] -= m2 * s;
      r3[7] -= m3 * s;
   }

   /* choose pivot - or die */
   if (fabsf(r3[1]) > fabsf(r2[1]))
      SWAP_ROWS(r3, r2);
   if (fabsf(r2[1]) > fabsf(r1[1]))
      SWAP_ROWS(r2, r1);
   if (0.0F == r1[1])
      return false;

   /* eliminate second variable */
   m2 = r2[1] / r1[1];
   m3 = r3[1] / r1[1];
   r2[2] -= m2 * r1[2];
   r3[2] -= m3 * r1[2];
   r2[3] -= m2 * r1[3];
   r3[3] -= m3 * r1[3];
   s = r1[4];
   if (0.0F != s) {
      r2[4] -= m2 * s;
      r3[4] -= m3 * s;
   }
   s = r1[5];
   if (0.0F != s) {
      r2[5] -= m2 * s;
      r3[5] -= m3 * s;
   }
   s = r1[6];
   if (0.0F != s) {
      r2[6] -= m2 * s;
      r3[6] -= m3 * s;
   }
   s = r1[7];
   if (0.0F != s) {
      r2[7] -= m2 * s;
      r3[7] -= m3 * s;
   }

   /* choose pivot - or die */
   if (fabsf(r3[2]) > fabsf(r2[2]))
      SWAP_ROWS(r3, r2);
   if (0.0F == r2[2])
      return false;

   /* eliminate third variable */
   m3 = r3[2] / r2[2];
   r3[3] -= m3 * r2[3], r3[4] -= m3 * r2[4], r3[5] -= m3 * r2[5], r3[6] -= m3 * r2[6],
      r3[7] -= m3 * r2[7];

   /* last check */
   if (0.0F == r3[3])
      return false;

   s = 1.0F / r3[3]; /* now back substitute row 3 */
   r3[4] *= s;
   r3[5] *= s;
   r3[6] *= s;
   r3[7] *= s;

   m2 = r2[3]; /* now back substitute row 2 */
   s = 1.0F / r2[2];
   r2[4] = s * (r2[4] - r3[4] * m2), r2[5] = s * (r2[5] - r3[5] * m2),
   r2[6] = s * (r2[6] - r3[6] * m2), r2[7] = s * (r2[7] - r3[7] * m2);
   m1 = r1[3];
   r1[4] -= r3[4] * m1, r1[5] -= r3[5] * m1, r1[6] -= r3[6] * m1, r1[7] -= r3[7] * m1;
   m0 = r0[3];
   r0[4] -= r3[4] * m0, r0[5] -= r3[5] * m0, r0[6] -= r3[6] * m0, r0[7] -= r3[7] * m0;

   m1 = r1[2]; /* now back substitute row 1 */
   s = 1.0F / r1[1];
   r1[4] = s * (r1[4] - r2[4] * m1), r1[5] = s * (r1[5] - r2[5] * m1),
   r1[6] = s * (r1[6] - r2[6] * m1), r1[7] = s * (r1[7] - r2[7] * m1);
   m0 = r0[2];
   r0[4] -= r2[4] * m0, r0[5] -= r2[5] * m0, r0[6] -= r2[6] * m0, r0[7] -= r2[7] * m0;

   m0 = r0[1]; /* now back substitute row 0 */
   s = 1.0F / r0[0];
   r0[4] = s * (r0[4] - r1[4] * m0), r0[5] = s * (r0[5] - r1[5] * m0),
   r0[6] = s * (r0[6] - r1[6] * m0), r0[7] = s * (r0[7] - r1[7] * m0);

   MAT(out, 0, 0) = r0[4];
   MAT(out, 0, 1) = r0[5], MAT(out, 0, 2) = r0[6];
   MAT(out, 0, 3) = r0[7], MAT(out, 1, 0) = r1[4];
   MAT(out, 1, 1) = r1[5], MAT(out, 1, 2) = r1[6];
   MAT(out, 1, 3) = r1[7], MAT(out, 2, 0) = r2[4];
   MAT(out, 2, 1) = r2[5], MAT(out, 2, 2) = r2[6];
   MAT(out, 2, 3) = r2[7], MAT(out, 3, 0) = r3[4];
   MAT(out, 3, 1) = r3[5], MAT(out, 3, 2) = r3[6];
   MAT(out, 3, 3) = r3[7];

#undef MAT
#undef SWAP_ROWS

   return true;
}

CATransform3D CATransform3DInvert(CATransform3D t) {
    CATransform3D result;
    util_invert_mat4x4((float *)&result, (float *)&t);
    return result;
}

@implementation NSValue (CATransform3D)
+ (NSValue *)valueWithCATransform3D:(CATransform3D)transform {
    return [NSValue valueWithBytes:&transform objCType:@encode(CATransform3D)];
}

- (CATransform3D)CATransform3DValue {
    CATransform3D result;
    [self getValue:&result];
    return result;
}
@end
