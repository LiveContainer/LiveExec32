#ifndef LC32_ACCELERATE_BRIDGE_H
#define LC32_ACCELERATE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

enum { LC32AccelerateABIVersion = 1 };

/* All pointers name guest float storage; strides count floats, not bytes.
 * a/b follow public argument order, including vsub/vdiv's reversed B,A order.
 * Scalar operations use scalar; reductions write one float to output and
 * ignore strideOutput. Fields unused by an operation are ignored. */
typedef struct {
    uint32_t version;
    uint32_t a, b, output, scalar;
    int32_t strideA, strideB, strideOutput;
    uint32_t count;
} LC32AccelerateCall;

typedef enum {
    LC32AccelerateVMul = 1,
    LC32AccelerateVAdd,
    LC32AccelerateVSub,
    LC32AccelerateVDiv,
    LC32AccelerateVDist,
    LC32AccelerateVSMul,
    LC32AccelerateVSDiv,
    LC32AccelerateVIntB,
    LC32AccelerateDotPr,
    LC32AccelerateSVESq,
} LC32AccelerateOpcode;

#ifdef __cplusplus
static_assert(sizeof(LC32AccelerateCall) == 36 &&
    offsetof(LC32AccelerateCall, strideA) == 20 &&
    offsetof(LC32AccelerateCall, count) == 32,
    "Accelerate request layout must match ARM32");
#else
_Static_assert(sizeof(LC32AccelerateCall) == 36 &&
    offsetof(LC32AccelerateCall, strideA) == 20 &&
    offsetof(LC32AccelerateCall, count) == 32,
    "Accelerate request layout must match ARM64");
#endif

#endif
