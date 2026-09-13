/* Public-API regression for the ten vDSP imports used by WheresMyXYY.
 * Native oracle: xcrun clang -O2 -Wall -Wextra -Werror accelerate_vdsp.c
 *                 -framework Accelerate -o /private/tmp/lc32-vdsp-native
 */
#include <Accelerate/Accelerate.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__arm__) && !defined(__LP64__)
_Static_assert(sizeof(vDSP_Stride) == 4, "guest stride must be signed ARM32 long");
_Static_assert(sizeof(vDSP_Length) == 4, "guest count must be ARM32 unsigned long");
#endif

enum Operation { Dot, Squares, Add, Distance, Divide, Interpolate,
                 Multiply, ScalarDivide, ScalarMultiply, Subtract, OperationCount };
static const char *names[] = {"dotpr", "svesq", "vadd", "vdist", "vdiv",
                             "vintb", "vmul", "vsdiv", "vsmul", "vsub"};
static const float guard = -12345.0f;
static unsigned checks, failures;

typedef struct {
    float *storage;
    float *first;
    size_t size;
} Vector;

static void check(const char *name, int passed) {
    printf("vDSP-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static Vector vector(vDSP_Length count, vDSP_Stride stride, unsigned seed) {
    size_t span = count ? 1 + (count - 1) * (size_t)(stride < 0 ? -stride : stride) : 1;
    Vector result = {calloc(span + 2, sizeof(float)), NULL, span + 2};
    if(!result.storage) { perror("allocate vDSP fixture"); exit(2); }
    result.first = result.storage + 1 + (stride < 0 ? span - 1 : 0);
    for(size_t i = 0; i < result.size; ++i)
        result.storage[i] = !seed || i == 0 || i == result.size - 1 ? guard :
            (1.0f + (float)((i * seed) % 19) * 0.125f) * (i % 3 ? 1.0f : -1.0f);
    return result;
}

static float *copy(const Vector *source) {
    float *result = malloc(source->size * sizeof(float));
    if(!result) { perror("copy vDSP fixture"); exit(2); }
    memcpy(result, source->storage, source->size * sizeof(float));
    return result;
}

static int closeEnough(float actual, float expected) {
    /* The SDK explicitly permits reassociation and does not promise IEEE-754
     * behavior for NaNs/infinities. Do not require payloads or exact rounding. */
    if(!isfinite(expected)) return !isfinite(actual);
    if(expected == guard) return actual == guard; // Untouched gaps/canaries.
    return isfinite(actual) && fabsf(actual - expected) <=
        0.00003f * fmaxf(1.0f, fabsf(expected));
}

static void call(enum Operation operation, const float *a, vDSP_Stride ia,
                 const float *b, vDSP_Stride ib, const float *scalar,
                 float *output, vDSP_Stride io, vDSP_Length count) {
    switch(operation) {
        case Dot: vDSP_dotpr(a, ia, b, ib, output, count); break;
        case Squares: vDSP_svesq(a, ia, output, count); break;
        case Add: vDSP_vadd(a, ia, b, ib, output, io, count); break;
        case Distance: vDSP_vdist(a, ia, b, ib, output, io, count); break;
        case Divide: vDSP_vdiv(a, ia, b, ib, output, io, count); break;
        case Interpolate: vDSP_vintb(a, ia, b, ib, scalar, output, io, count); break;
        case Multiply: vDSP_vmul(a, ia, b, ib, output, io, count); break;
        case ScalarDivide: vDSP_vsdiv(a, ia, scalar, output, io, count); break;
        case ScalarMultiply: vDSP_vsmul(a, ia, scalar, output, io, count); break;
        case Subtract: vDSP_vsub(a, ia, b, ib, output, io, count); break;
        default: abort();
    }
}

static float reference(enum Operation operation, float a, float b, float scalar) {
    switch(operation) {
        case Add: return a + b;
        case Distance: return sqrtf(a * a + b * b);
        // Apple's real-vector subtraction/division take the denominator or
        // subtrahend FIRST, unlike their mathematical pseudocode argument names.
        case Divide: return b / a;
        case Interpolate: return a + scalar * (b - a);
        case Multiply: return a * b;
        case ScalarDivide: return a / scalar;
        case ScalarMultiply: return a * scalar;
        case Subtract: return b - a;
        default: abort();
    }
}

static void run(enum Operation operation, const char *label, vDSP_Length count,
                vDSP_Stride ia, vDSP_Stride ib, vDSP_Stride io, int alias,
                float scalar, int special) {
    Vector a = vector(count, ia, 3), b = vector(count, ib, 7), c = vector(count, io, 0);
    if(special) {
        const float values[] = {NAN, INFINITY, -INFINITY, 3.0f, -4.0f};
        for(vDSP_Length i = 0; i < count; ++i) {
            a.first[(vDSP_Stride)i * ia] = values[i % 5];
            b.first[(vDSP_Stride)i * ib] = 2.0f;
        }
    }
    Vector *output = alias == 1 ? &a : alias == 2 ? &b : &c;
    if(alias) io = alias == 1 ? ia : ib;
    float *aBefore = copy(&a), *bBefore = copy(&b), *expected = copy(output);
    float *expectedFirst = expected + (output->first - output->storage);
    if(operation == Dot || operation == Squares) {
        double sum = 0;
        for(vDSP_Length i = 0; i < count; ++i) {
            double av = a.first[(vDSP_Stride)i * ia];
            sum += av * (operation == Dot ? b.first[(vDSP_Stride)i * ib] : av);
        }
        expectedFirst[0] = (float)sum;
    } else {
        for(vDSP_Length i = 0; i < count; ++i)
            expectedFirst[(vDSP_Stride)i * io] = reference(operation,
                a.first[(vDSP_Stride)i * ia], b.first[(vDSP_Stride)i * ib], scalar);
    }
    float scalarBefore = scalar;
    call(operation, a.first, ia, b.first, ib, &scalar, output->first, io, count);
    int valid = scalar == scalarBefore &&
        (alias == 1 || !memcmp(a.storage, aBefore, a.size * sizeof(float))) &&
        (alias == 2 || !memcmp(b.storage, bBefore, b.size * sizeof(float)));
    for(size_t i = 0; i < output->size; ++i) {
        if(!closeEnough(output->storage[i], expected[i])) {
            fprintf(stderr, "%s/%s: slot %zu got %.9g, expected %.9g\n",
                    names[operation], label, i, output->storage[i], expected[i]);
            valid = 0;
            break;
        }
    }
    char name[128];
    snprintf(name, sizeof(name), "%s/%s", names[operation], label);
    check(name, valid);
    free(expected); free(aBefore); free(bBefore);
    free(a.storage); free(b.storage); free(c.storage);
}

int main(void) {
    const struct {
        const char *name;
        vDSP_Length count;
        vDSP_Stride a, b, output;
    } cases[] = {
        {"unit", 9, 1, 1, 1},
        {"nonunit", 9, 2, 3, 2},
        {"negative", 9, -2, -3, -2},
        {"mixed-sign", 9, -2, 3, -3},
        {"broadcast-first", 9, 0, 2, 1},
        {"broadcast-second", 9, 2, 0, 1},
        // Constant inputs make repeated writes independent of store order.
        {"zero-strides", 9, 0, 0, 0},
        {"zero-count", 0, -2, 3, -3},
        {"cross-page", 4099, 1, 1, 1},
        {"cross-page-strided", 4099, -2, 3, -2},
    };
    for(enum Operation operation = Dot; operation < OperationCount; ++operation) {
        for(size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i)
            run(operation, cases[i].name, cases[i].count, cases[i].a, cases[i].b,
                cases[i].output, 0, 0.25f, 0);
        if(operation != Dot && operation != Squares) {
            run(operation, "in-place-first", 9, 1, 1, 1, 1, 0.25f, 0);
            run(operation, "in-place-second", 9, 1, 1, 1, 2, 0.25f, 0);
            run(operation, "in-place-negative", 9, -2, 3, -2, 1, 0.25f, 0);
        }
        run(operation, "nonfinite", 5, 1, 1, 1, 0, 0.25f, 1);
    }
    run(Interpolate, "weight-zero", 9, 2, -2, 3, 0, 0.0f, 0);
    run(Interpolate, "weight-one", 9, 2, -2, 3, 0, 1.0f, 0);
    run(Interpolate, "extrapolation", 9, 2, -2, 3, 0, 1.5f, 0);
    run(ScalarDivide, "negative-scalar", 9, -2, 1, 3, 0, -2.0f, 0);
    run(ScalarMultiply, "zero-scalar", 9, -2, 1, 3, 0, 0.0f, 0);
    printf("vDSP summary: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
