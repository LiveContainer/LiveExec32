#import <GLKit/GLKit.h>
#include <float.h>
#include <math.h>

/* OpenGL ES 2 headers omit the ES 3 scalar encodings used by Model I/O. */
#ifndef GL_HALF_FLOAT
#define GL_HALF_FLOAT 0x140B
#endif
#ifndef GL_UNSIGNED_INT_2_10_10_10_REV
#define GL_UNSIGNED_INT_2_10_10_10_REV 0x8368
#endif
#ifndef GL_INT_2_10_10_10_REV
#define GL_INT_2_10_10_10_REV 0x8D9F
#endif

const GLKMatrix3 GLKMatrix3Identity = {.m = {
    1.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 1.0f,
}};

const GLKMatrix4 GLKMatrix4Identity = {.m = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f,
}};

const GLKQuaternion GLKQuaternionIdentity = {
    .q = {0.0f, 0.0f, 0.0f, 1.0f},
};

GLKMatrix3 GLKMatrix3Invert(GLKMatrix3 matrix, bool *isInvertible) {
    GLKMatrix3 inverse;
    inverse.m[0] = matrix.m[4] * matrix.m[8] - matrix.m[5] * matrix.m[7];
    inverse.m[1] = matrix.m[2] * matrix.m[7] - matrix.m[1] * matrix.m[8];
    inverse.m[2] = matrix.m[1] * matrix.m[5] - matrix.m[2] * matrix.m[4];
    inverse.m[3] = matrix.m[5] * matrix.m[6] - matrix.m[3] * matrix.m[8];
    inverse.m[4] = matrix.m[0] * matrix.m[8] - matrix.m[2] * matrix.m[6];
    inverse.m[5] = matrix.m[2] * matrix.m[3] - matrix.m[0] * matrix.m[5];
    inverse.m[6] = matrix.m[3] * matrix.m[7] - matrix.m[4] * matrix.m[6];
    inverse.m[7] = matrix.m[1] * matrix.m[6] - matrix.m[0] * matrix.m[7];
    inverse.m[8] = matrix.m[0] * matrix.m[4] - matrix.m[1] * matrix.m[3];

    const float determinant = matrix.m[0] * inverse.m[0] +
        matrix.m[1] * inverse.m[3] + matrix.m[2] * inverse.m[6];
    const bool invertible = determinant != 0.0f && isfinite(determinant);
    if(isInvertible) *isInvertible = invertible;
    if(!invertible) return GLKMatrix3Identity;
    const float scale = 1.0f / determinant;
    for(int index = 0; index < 9; index++) inverse.m[index] *= scale;
    return inverse;
}

GLKMatrix3 GLKMatrix3InvertAndTranspose(
        GLKMatrix3 matrix, bool *isInvertible) {
    return GLKMatrix3Transpose(GLKMatrix3Invert(matrix, isInvertible));
}

GLKMatrix4 GLKMatrix4Invert(GLKMatrix4 matrix, bool *isInvertible) {
    const float *m = matrix.m;
    GLKMatrix4 inverse;
    float *v = inverse.m;
    v[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] -
        m[9] * m[6] * m[15] + m[9] * m[7] * m[14] +
        m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    v[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] +
        m[8] * m[6] * m[15] - m[8] * m[7] * m[14] -
        m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    v[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] -
        m[8] * m[5] * m[15] + m[8] * m[7] * m[13] +
        m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    v[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] +
        m[8] * m[5] * m[14] - m[8] * m[6] * m[13] -
        m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    v[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] +
        m[9] * m[2] * m[15] - m[9] * m[3] * m[14] -
        m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    v[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] -
        m[8] * m[2] * m[15] + m[8] * m[3] * m[14] +
        m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    v[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] +
        m[8] * m[1] * m[15] - m[8] * m[3] * m[13] -
        m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    v[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] -
        m[8] * m[1] * m[14] + m[8] * m[2] * m[13] +
        m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    v[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] -
        m[5] * m[2] * m[15] + m[5] * m[3] * m[14] +
        m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    v[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] +
        m[4] * m[2] * m[15] - m[4] * m[3] * m[14] -
        m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    v[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] -
        m[4] * m[1] * m[15] + m[4] * m[3] * m[13] +
        m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    v[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] +
        m[4] * m[1] * m[14] - m[4] * m[2] * m[13] -
        m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    v[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] +
        m[5] * m[2] * m[11] - m[5] * m[3] * m[10] -
        m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    v[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] -
        m[4] * m[2] * m[11] + m[4] * m[3] * m[10] +
        m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    v[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] +
        m[4] * m[1] * m[11] - m[4] * m[3] * m[9] -
        m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    v[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] -
        m[4] * m[1] * m[10] + m[4] * m[2] * m[9] +
        m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

    const float determinant = m[0] * v[0] + m[1] * v[4] +
        m[2] * v[8] + m[3] * v[12];
    const bool invertible = determinant != 0.0f && isfinite(determinant);
    if(isInvertible) *isInvertible = invertible;
    if(!invertible) return GLKMatrix4Identity;
    const float scale = 1.0f / determinant;
    for(int index = 0; index < 16; index++) v[index] *= scale;
    return inverse;
}

GLKMatrix4 GLKMatrix4InvertAndTranspose(
        GLKMatrix4 matrix, bool *isInvertible) {
    return GLKMatrix4Transpose(GLKMatrix4Invert(matrix, isInvertible));
}

GLKVector3 GLKMathProject(GLKVector3 object, GLKMatrix4 model,
        GLKMatrix4 projection, int *viewport) {
    GLKVector4 projected = GLKMatrix4MultiplyVector4(
        GLKMatrix4Multiply(projection, model),
        GLKVector4Make(object.x, object.y, object.z, 1.0f));
    if(projected.w != 0.0f) {
        projected = GLKVector4DivideScalar(projected, projected.w);
    }
    return GLKVector3Make(
        viewport[0] + (projected.x + 1.0f) * viewport[2] * 0.5f,
        viewport[1] + (projected.y + 1.0f) * viewport[3] * 0.5f,
        (projected.z + 1.0f) * 0.5f);
}

GLKVector3 GLKMathUnproject(GLKVector3 window, GLKMatrix4 model,
        GLKMatrix4 projection, int *viewport, bool *success) {
    bool invertible = false;
    GLKMatrix4 inverse = GLKMatrix4Invert(
        GLKMatrix4Multiply(projection, model), &invertible);
    if(!invertible || viewport[2] == 0 || viewport[3] == 0) {
        if(success) *success = false;
        return GLKVector3Make(0.0f, 0.0f, 0.0f);
    }
    GLKVector4 value = GLKVector4Make(
        (window.x - viewport[0]) * 2.0f / viewport[2] - 1.0f,
        (window.y - viewport[1]) * 2.0f / viewport[3] - 1.0f,
        window.z * 2.0f - 1.0f, 1.0f);
    value = GLKMatrix4MultiplyVector4(inverse, value);
    if(value.w == 0.0f) {
        if(success) *success = false;
        return GLKVector3Make(0.0f, 0.0f, 0.0f);
    }
    if(success) *success = true;
    return GLKVector3Make(value.x / value.w, value.y / value.w,
        value.z / value.w);
}

static GLKQuaternion LC32QuaternionFromMatrix3(GLKMatrix3 matrix) {
#define LC32_M(row, column) matrix.m[(column) * 3 + (row)]
    GLKQuaternion result;
    const float trace = LC32_M(0, 0) + LC32_M(1, 1) + LC32_M(2, 2);
    if(trace > 0.0f) {
        const float scale = sqrtf(trace + 1.0f) * 2.0f;
        result.w = 0.25f * scale;
        result.x = (LC32_M(2, 1) - LC32_M(1, 2)) / scale;
        result.y = (LC32_M(0, 2) - LC32_M(2, 0)) / scale;
        result.z = (LC32_M(1, 0) - LC32_M(0, 1)) / scale;
    } else if(LC32_M(0, 0) > LC32_M(1, 1) &&
              LC32_M(0, 0) > LC32_M(2, 2)) {
        const float scale = sqrtf(1.0f + LC32_M(0, 0) -
            LC32_M(1, 1) - LC32_M(2, 2)) * 2.0f;
        result.w = (LC32_M(2, 1) - LC32_M(1, 2)) / scale;
        result.x = 0.25f * scale;
        result.y = (LC32_M(0, 1) + LC32_M(1, 0)) / scale;
        result.z = (LC32_M(0, 2) + LC32_M(2, 0)) / scale;
    } else if(LC32_M(1, 1) > LC32_M(2, 2)) {
        const float scale = sqrtf(1.0f + LC32_M(1, 1) -
            LC32_M(0, 0) - LC32_M(2, 2)) * 2.0f;
        result.w = (LC32_M(0, 2) - LC32_M(2, 0)) / scale;
        result.x = (LC32_M(0, 1) + LC32_M(1, 0)) / scale;
        result.y = 0.25f * scale;
        result.z = (LC32_M(1, 2) + LC32_M(2, 1)) / scale;
    } else {
        const float scale = sqrtf(1.0f + LC32_M(2, 2) -
            LC32_M(0, 0) - LC32_M(1, 1)) * 2.0f;
        result.w = (LC32_M(1, 0) - LC32_M(0, 1)) / scale;
        result.x = (LC32_M(0, 2) + LC32_M(2, 0)) / scale;
        result.y = (LC32_M(1, 2) + LC32_M(2, 1)) / scale;
        result.z = 0.25f * scale;
    }
#undef LC32_M
    return GLKQuaternionNormalize(result);
}

GLKQuaternion GLKQuaternionMakeWithMatrix3(GLKMatrix3 matrix) {
    return LC32QuaternionFromMatrix3(matrix);
}

GLKQuaternion GLKQuaternionMakeWithMatrix4(GLKMatrix4 matrix) {
    return LC32QuaternionFromMatrix3(GLKMatrix4GetMatrix3(matrix));
}

float GLKQuaternionAngle(GLKQuaternion quaternion) {
    quaternion = GLKQuaternionNormalize(quaternion);
    return 2.0f * acosf(fmaxf(-1.0f, fminf(1.0f, quaternion.w)));
}

GLKVector3 GLKQuaternionAxis(GLKQuaternion quaternion) {
    quaternion = GLKQuaternionNormalize(quaternion);
    const float length = sqrtf(quaternion.x * quaternion.x +
        quaternion.y * quaternion.y + quaternion.z * quaternion.z);
    if(length == 0.0f) return GLKVector3Make(0.0f, 0.0f, 0.0f);
    return GLKVector3Make(quaternion.x / length, quaternion.y / length,
        quaternion.z / length);
}

GLKQuaternion GLKQuaternionSlerp(
        GLKQuaternion start, GLKQuaternion end, float t) {
    start = GLKQuaternionNormalize(start);
    end = GLKQuaternionNormalize(end);
    float dot = start.x * end.x + start.y * end.y +
        start.z * end.z + start.w * end.w;
    if(dot < 0.0f) {
        end = GLKQuaternionMake(-end.x, -end.y, -end.z, -end.w);
        dot = -dot;
    }
    dot = fmaxf(-1.0f, fminf(1.0f, dot));
    if(dot > 0.9995f) {
        return GLKQuaternionNormalize(GLKQuaternionMake(
            start.x + t * (end.x - start.x),
            start.y + t * (end.y - start.y),
            start.z + t * (end.z - start.z),
            start.w + t * (end.w - start.w)));
    }
    const float theta = acosf(dot);
    const float denominator = sinf(theta);
    const float startScale = sinf((1.0f - t) * theta) / denominator;
    const float endScale = sinf(t * theta) / denominator;
    return GLKQuaternionMake(
        start.x * startScale + end.x * endScale,
        start.y * startScale + end.y * endScale,
        start.z * startScale + end.z * endScale,
        start.w * startScale + end.w * endScale);
}

void GLKQuaternionRotateVector3Array(
        GLKQuaternion quaternion, GLKVector3 *vectors, size_t count) {
    for(size_t index = 0; index < count; index++) {
        vectors[index] = GLKQuaternionRotateVector3(quaternion, vectors[index]);
    }
}

void GLKQuaternionRotateVector4Array(
        GLKQuaternion quaternion, GLKVector4 *vectors, size_t count) {
    for(size_t index = 0; index < count; index++) {
        vectors[index] = GLKQuaternionRotateVector4(quaternion, vectors[index]);
    }
}

GLKVertexAttributeParameters GLKVertexAttributeParametersFromModelIO(
        MDLVertexFormat format) {
    GLKVertexAttributeParameters result = {};
    const NSUInteger category = format & 0xf0000;
    result.size = format & 0xf;
    switch(category) {
        case MDLVertexFormatUCharBits: result.type = GL_UNSIGNED_BYTE; break;
        case MDLVertexFormatCharBits: result.type = GL_BYTE; break;
        case MDLVertexFormatUCharNormalizedBits:
            result.type = GL_UNSIGNED_BYTE; result.normalized = GL_TRUE; break;
        case MDLVertexFormatCharNormalizedBits:
            result.type = GL_BYTE; result.normalized = GL_TRUE; break;
        case MDLVertexFormatUShortBits: result.type = GL_UNSIGNED_SHORT; break;
        case MDLVertexFormatShortBits: result.type = GL_SHORT; break;
        case MDLVertexFormatUShortNormalizedBits:
            result.type = GL_UNSIGNED_SHORT; result.normalized = GL_TRUE; break;
        case MDLVertexFormatShortNormalizedBits:
            result.type = GL_SHORT; result.normalized = GL_TRUE; break;
        case MDLVertexFormatUIntBits: result.type = GL_UNSIGNED_INT; break;
        case MDLVertexFormatIntBits: result.type = GL_INT; break;
        case MDLVertexFormatHalfBits: result.type = GL_HALF_FLOAT; break;
        case MDLVertexFormatFloatBits: result.type = GL_FLOAT; break;
        default: result.size = 0; return result;
    }
    if(format & MDLVertexFormatPackedBit) {
        result.size = 4;
        result.normalized = GL_TRUE;
        result.type = category == MDLVertexFormatIntBits
            ? GL_INT_2_10_10_10_REV : GL_UNSIGNED_INT_2_10_10_10_REV;
    }
    return result;
}

NSString *NSStringFromGLKVector2(GLKVector2 value) {
    return [NSString stringWithFormat:@"{%g, %g}", value.x, value.y];
}

NSString *NSStringFromGLKVector3(GLKVector3 value) {
    return [NSString stringWithFormat:@"{%g, %g, %g}",
        value.x, value.y, value.z];
}

NSString *NSStringFromGLKVector4(GLKVector4 value) {
    return [NSString stringWithFormat:@"{%g, %g, %g, %g}",
        value.x, value.y, value.z, value.w];
}

NSString *NSStringFromGLKQuaternion(GLKQuaternion value) {
    return [NSString stringWithFormat:@"{{%g, %g, %g}, %g}",
        value.x, value.y, value.z, value.w];
}

NSString *NSStringFromGLKMatrix2(GLKMatrix2 value) {
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}",
        value.m[0], value.m[1], value.m[2], value.m[3]];
}

NSString *NSStringFromGLKMatrix3(GLKMatrix3 value) {
    return [NSString stringWithFormat:
        @"{{%g, %g, %g}, {%g, %g, %g}, {%g, %g, %g}}",
        value.m[0], value.m[1], value.m[2],
        value.m[3], value.m[4], value.m[5],
        value.m[6], value.m[7], value.m[8]];
}

NSString *NSStringFromGLKMatrix4(GLKMatrix4 value) {
    return [NSString stringWithFormat:
        @"{{%g, %g, %g, %g}, {%g, %g, %g, %g}, "
         "{%g, %g, %g, %g}, {%g, %g, %g, %g}}",
        value.m[0], value.m[1], value.m[2], value.m[3],
        value.m[4], value.m[5], value.m[6], value.m[7],
        value.m[8], value.m[9], value.m[10], value.m[11],
        value.m[12], value.m[13], value.m[14], value.m[15]];
}
