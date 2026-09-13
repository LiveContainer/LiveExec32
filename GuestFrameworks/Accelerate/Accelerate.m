#import <Accelerate/Accelerate.h>
#import <LC32/LC32.h>
#include "LC32AccelerateBridge.h"
#include <pthread.h>

static pthread_once_t dispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t dispatcher;

static void ResolveDispatcher(void) {
    dispatcher = LC32Dlsym("LC32_Accelerate_Dispatch", YES);
}

static void Dispatch(LC32AccelerateOpcode operation,
        const float *a, vDSP_Stride strideA,
        const float *b, vDSP_Stride strideB,
        float *output, vDSP_Stride strideOutput,
        const float *scalar, vDSP_Length count) {
    pthread_once(&dispatcherOnce, ResolveDispatcher);
    const LC32AccelerateCall call = {
        .version = LC32AccelerateABIVersion,
        .a = (uint32_t)(uintptr_t)a,
        .b = (uint32_t)(uintptr_t)b,
        .output = (uint32_t)(uintptr_t)output,
        .scalar = (uint32_t)(uintptr_t)scalar,
        .strideA = strideA, .strideB = strideB,
        .strideOutput = strideOutput, .count = count,
    };
    if(!dispatcher || !LC32InvokeHostCRet32(dispatcher,
            (uint32_t)operation, (uint32_t)(uintptr_t)&call)) {
        CRSetCrashLogMessage("Accelerate vDSP bridge: invalid request or inaccessible guest vector");
    }
}

// Keep the public positional order: vsub and vdiv take B before A.
#define VECTOR_PAIR(name, operation) \
    void name(const float *a, vDSP_Stride strideA, \
              const float *b, vDSP_Stride strideB, \
              float *output, vDSP_Stride strideOutput, vDSP_Length count) { \
        Dispatch(operation, a, strideA, b, strideB, output, strideOutput, NULL, count); \
    }
VECTOR_PAIR(vDSP_vmul, LC32AccelerateVMul)
VECTOR_PAIR(vDSP_vadd, LC32AccelerateVAdd)
VECTOR_PAIR(vDSP_vsub, LC32AccelerateVSub)
VECTOR_PAIR(vDSP_vdiv, LC32AccelerateVDiv)
VECTOR_PAIR(vDSP_vdist, LC32AccelerateVDist)

#define VECTOR_SCALAR(name, operation) \
    void name(const float *a, vDSP_Stride strideA, const float *scalar, \
              float *output, vDSP_Stride strideOutput, vDSP_Length count) { \
        Dispatch(operation, a, strideA, NULL, 0, output, strideOutput, scalar, count); \
    }
VECTOR_SCALAR(vDSP_vsmul, LC32AccelerateVSMul)
VECTOR_SCALAR(vDSP_vsdiv, LC32AccelerateVSDiv)

void vDSP_vintb(const float *a, vDSP_Stride strideA,
        const float *b, vDSP_Stride strideB, const float *scalar,
        float *output, vDSP_Stride strideOutput, vDSP_Length count) {
    Dispatch(LC32AccelerateVIntB, a, strideA, b, strideB,
        output, strideOutput, scalar, count);
}

void vDSP_dotpr(const float *a, vDSP_Stride strideA,
        const float *b, vDSP_Stride strideB, float *output, vDSP_Length count) {
    Dispatch(LC32AccelerateDotPr, a, strideA, b, strideB, output, 0, NULL, count);
}

void vDSP_svesq(const float *a, vDSP_Stride strideA, float *output, vDSP_Length count) {
    Dispatch(LC32AccelerateSVESq, a, strideA, NULL, 0, output, 0, NULL, count);
}
