#import <SceneKit/SceneKit.h>

#include <math.h>

typedef union {
    SCNMatrix4 matrix;
    float values[16];
} LC32SCNMatrixStorage;

bool SCNVector3EqualToVector3(SCNVector3 left, SCNVector3 right) {
    return left.x == right.x && left.y == right.y && left.z == right.z;
}

bool SCNVector4EqualToVector4(SCNVector4 left, SCNVector4 right) {
    return left.x == right.x && left.y == right.y &&
        left.z == right.z && left.w == right.w;
}

bool SCNMatrix4EqualToMatrix4(SCNMatrix4 left, SCNMatrix4 right) {
    const LC32SCNMatrixStorage leftStorage = { .matrix = left };
    const LC32SCNMatrixStorage rightStorage = { .matrix = right };
    for(unsigned index = 0; index < 16; index++) {
        if(leftStorage.values[index] != rightStorage.values[index])
            return false;
    }
    return true;
}

bool SCNMatrix4IsIdentity(SCNMatrix4 matrix) {
    return SCNMatrix4EqualToMatrix4(matrix, SCNMatrix4Identity);
}

SCNMatrix4 SCNMatrix4Mult(SCNMatrix4 left, SCNMatrix4 right) {
    const LC32SCNMatrixStorage leftStorage = { .matrix = left };
    const LC32SCNMatrixStorage rightStorage = { .matrix = right };
    LC32SCNMatrixStorage result = { 0 };
    for(unsigned row = 0; row < 4; row++) {
        for(unsigned column = 0; column < 4; column++) {
            float value = 0.0f;
            for(unsigned index = 0; index < 4; index++) {
                value += leftStorage.values[row * 4 + index] *
                    rightStorage.values[index * 4 + column];
            }
            result.values[row * 4 + column] = value;
        }
    }
    return result.matrix;
}

SCNMatrix4 SCNMatrix4MakeRotation(float angle, float x, float y, float z) {
    const float magnitude = sqrtf(x * x + y * y + z * z);
    if(magnitude == 0.0f) return SCNMatrix4Identity;
    x /= magnitude;
    y /= magnitude;
    z /= magnitude;

    const float cosine = cosf(angle);
    const float sine = sinf(angle);
    const float oneMinusCosine = 1.0f - cosine;
    return (SCNMatrix4){
        x * x * oneMinusCosine + cosine,
        x * y * oneMinusCosine + z * sine,
        x * z * oneMinusCosine - y * sine,
        0.0f,
        y * x * oneMinusCosine - z * sine,
        y * y * oneMinusCosine + cosine,
        y * z * oneMinusCosine + x * sine,
        0.0f,
        z * x * oneMinusCosine + y * sine,
        z * y * oneMinusCosine - x * sine,
        z * z * oneMinusCosine + cosine,
        0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    };
}

SCNMatrix4 SCNMatrix4Scale(SCNMatrix4 matrix,
                           float x, float y, float z) {
    SCNMatrix4 scale = SCNMatrix4Identity;
    scale.m11 = x;
    scale.m22 = y;
    scale.m33 = z;
    return SCNMatrix4Mult(scale, matrix);
}

SCNMatrix4 SCNMatrix4Rotate(SCNMatrix4 matrix, float angle,
                            float x, float y, float z) {
    return SCNMatrix4Mult(
        SCNMatrix4MakeRotation(angle, x, y, z), matrix);
}

SCNMatrix4 SCNMatrix4Invert(SCNMatrix4 matrix) {
    const LC32SCNMatrixStorage input = { .matrix = matrix };
    double augmented[4][8] = { 0 };
    for(unsigned row = 0; row < 4; row++) {
        for(unsigned column = 0; column < 4; column++)
            augmented[row][column] = input.values[row * 4 + column];
        augmented[row][row + 4] = 1.0;
    }

    for(unsigned column = 0; column < 4; column++) {
        unsigned pivotRow = column;
        double pivotMagnitude = fabs(augmented[pivotRow][column]);
        for(unsigned row = column + 1; row < 4; row++) {
            const double magnitude = fabs(augmented[row][column]);
            if(magnitude > pivotMagnitude) {
                pivotMagnitude = magnitude;
                pivotRow = row;
            }
        }
        if(pivotMagnitude == 0.0) return matrix;

        if(pivotRow != column) {
            for(unsigned index = 0; index < 8; index++) {
                const double temporary = augmented[column][index];
                augmented[column][index] = augmented[pivotRow][index];
                augmented[pivotRow][index] = temporary;
            }
        }

        const double pivot = augmented[column][column];
        for(unsigned index = 0; index < 8; index++)
            augmented[column][index] /= pivot;
        for(unsigned row = 0; row < 4; row++) {
            if(row == column) continue;
            const double factor = augmented[row][column];
            for(unsigned index = 0; index < 8; index++)
                augmented[row][index] -= factor * augmented[column][index];
        }
    }

    LC32SCNMatrixStorage result;
    for(unsigned row = 0; row < 4; row++) {
        for(unsigned column = 0; column < 4; column++)
            result.values[row * 4 + column] =
                (float)augmented[row][column + 4];
    }
    return result.matrix;
}

GLKMatrix4 SCNMatrix4ToGLKMatrix4(SCNMatrix4 matrix) {
    return (GLKMatrix4){{
        matrix.m11, matrix.m12, matrix.m13, matrix.m14,
        matrix.m21, matrix.m22, matrix.m23, matrix.m24,
        matrix.m31, matrix.m32, matrix.m33, matrix.m34,
        matrix.m41, matrix.m42, matrix.m43, matrix.m44,
    }};
}

SCNMatrix4 SCNMatrix4FromGLKMatrix4(GLKMatrix4 matrix) {
    return (SCNMatrix4){
        matrix.m00, matrix.m01, matrix.m02, matrix.m03,
        matrix.m10, matrix.m11, matrix.m12, matrix.m13,
        matrix.m20, matrix.m21, matrix.m22, matrix.m23,
        matrix.m30, matrix.m31, matrix.m32, matrix.m33,
    };
}
