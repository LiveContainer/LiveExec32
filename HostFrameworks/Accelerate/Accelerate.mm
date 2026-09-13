@import Accelerate;

#include "dynarmic_internal.h"
#include "../../GuestFrameworks/Accelerate/LC32AccelerateBridge.h"

#include <algorithm>
#include <stdint.h>
#include <sys/mman.h>

namespace {

constexpr uint32_t ChunkFloats = 256;
constexpr uint32_t FloatBytes = sizeof(float);
static_assert(FloatBytes == 4, "Accelerate bridge requires binary32 floats");

bool Range(uint32_t address, uint32_t size) {
    return address && uint64_t(address) + size <= uint64_t(UINT32_MAX) + 1;
}

bool VectorRange(uint32_t address, int32_t stride, uint32_t count) {
    if(!count) return true;
    if(!Range(address, FloatBytes)) return false;
    /* int32 * (uint32 - 1) fits int64, but multiplying that product by four
     * need not. Check the displacement in floats before converting to bytes.
     * For a linear stride, valid endpoints also bound every intermediate one. */
    const int64_t displacement = int64_t(stride) * int64_t(count - 1);
    return displacement >= -int64_t((address - 1) / FloatBytes) &&
        displacement <= int64_t((UINT32_MAX - (FloatBytes - 1) - address) / FloatBytes);
}

uint32_t ElementAddress(uint32_t address, int32_t stride, uint32_t index) {
    // Only called after VectorRange has bounded this entire vector.
    return uint32_t(int64_t(address) + int64_t(stride) * index * FloatBytes);
}

bool ReadFloat(uint32_t address, float &value) {
    return Range(address, FloatBytes) &&
        read_guest_memory_with_permissions(address, &value, FloatBytes, PROT_READ);
}

bool WriteFloat(uint32_t address, float &value) {
    return Range(address, FloatBytes) &&
        write_guest_memory_with_permissions(address, &value, FloatBytes, PROT_WRITE);
}

bool Gather(uint32_t address, int32_t stride, uint32_t index,
            uint32_t count, float repeated, float *values) {
    if(stride == 0) {
        std::fill_n(values, count, repeated);
        return true;
    }
    if(stride == 1) {
        return read_guest_memory_with_permissions(ElementAddress(address, stride, index),
            values, count * FloatBytes, PROT_READ);
    }
    for(uint32_t i = 0; i < count; ++i) {
        if(!ReadFloat(ElementAddress(address, stride, index + i), values[i])) return false;
    }
    return true;
}

bool Scatter(uint32_t address, int32_t stride, uint32_t index,
             uint32_t count, float *values) {
    if(stride == 0) return WriteFloat(address, values[count - 1]);
    if(stride == 1) {
        return write_guest_memory_with_permissions(ElementAddress(address, stride, index),
            values, count * FloatBytes, PROT_WRITE);
    }
    for(uint32_t i = 0; i < count; ++i) {
        if(!WriteFloat(ElementAddress(address, stride, index + i), values[i])) return false;
    }
    return true;
}

} // namespace

/* Gather both inputs before scattering each bounded chunk, preserving exact
 * same-pointer/same-stride in-place operation without exposing host addresses.
 * Broadcast inputs and scalar pointers are sampled once before any writes.
 * General partial overlap between differently based/strided vectors has no
 * additional guarantee. An inaccessible later chunk may leave earlier output
 * chunks written; reductions publish output only after all input reads succeed.
 * Native vDSP computes each chunk; reduction grouping/rounding may differ from
 * a single native call, as permitted by vDSP's floating-point contract. */
extern "C" uint32_t LC32_Accelerate_Dispatch(uint32_t operation, uint32_t guestCall) {
    LC32AccelerateCall call;
    if(!Range(guestCall, sizeof(call)) ||
            !read_guest_memory_with_permissions(guestCall, &call, sizeof(call), PROT_READ) ||
            call.version != LC32AccelerateABIVersion) return 0;

    bool binary = false, scalarOperation = false, reduction = false;
    switch(operation) {
        case LC32AccelerateVMul:
        case LC32AccelerateVAdd:
        case LC32AccelerateVSub:
        case LC32AccelerateVDiv:
        case LC32AccelerateVDist:
            binary = true;
            break;
        case LC32AccelerateVSMul:
        case LC32AccelerateVSDiv:
            scalarOperation = true;
            break;
        case LC32AccelerateVIntB:
            binary = scalarOperation = true;
            break;
        case LC32AccelerateDotPr:
            binary = reduction = true;
            break;
        case LC32AccelerateSVESq:
            reduction = true;
            break;
        default:
            return 0;
    }

    float total = 0;
    if(!call.count) return !reduction || WriteFloat(call.output, total);
    if(!VectorRange(call.a, call.strideA, call.count) ||
            (binary && !VectorRange(call.b, call.strideB, call.count)) ||
            !(reduction ? Range(call.output, FloatBytes) :
                VectorRange(call.output, call.strideOutput, call.count))) return 0;

    float scalar = 0, repeatedA = 0, repeatedB = 0;
    if((scalarOperation && !ReadFloat(call.scalar, scalar)) ||
            (!call.strideA && !ReadFloat(call.a, repeatedA)) ||
            (binary && !call.strideB && !ReadFloat(call.b, repeatedB))) return 0;

    alignas(16) float a[ChunkFloats], b[ChunkFloats], output[ChunkFloats];
    for(uint32_t index = 0; index < call.count;) {
        const uint32_t count = std::min(ChunkFloats, call.count - index);
        if(!Gather(call.a, call.strideA, index, count, repeatedA, a) ||
                (binary && !Gather(call.b, call.strideB, index, count, repeatedB, b))) return 0;
        float partial = 0;
        switch(operation) {
            case LC32AccelerateVMul: vDSP_vmul(a, 1, b, 1, output, 1, count); break;
            case LC32AccelerateVAdd: vDSP_vadd(a, 1, b, 1, output, 1, count); break;
            // Public vsub/vdiv order is (B, IB, A, IA, ...), not (A, IA, B, IB).
            case LC32AccelerateVSub: vDSP_vsub(a, 1, b, 1, output, 1, count); break;
            case LC32AccelerateVDiv: vDSP_vdiv(a, 1, b, 1, output, 1, count); break;
            case LC32AccelerateVDist: vDSP_vdist(a, 1, b, 1, output, 1, count); break;
            case LC32AccelerateVSMul: vDSP_vsmul(a, 1, &scalar, output, 1, count); break;
            case LC32AccelerateVSDiv: vDSP_vsdiv(a, 1, &scalar, output, 1, count); break;
            case LC32AccelerateVIntB: vDSP_vintb(a, 1, b, 1, &scalar, output, 1, count); break;
            case LC32AccelerateDotPr: vDSP_dotpr(a, 1, b, 1, &partial, count); break;
            case LC32AccelerateSVESq: vDSP_svesq(a, 1, &partial, count); break;
            default: return 0;
        }
        if(reduction) total += partial;
        else if(!Scatter(call.output, call.strideOutput, index, count, output)) return 0;
        index += count;
    }
    return !reduction || WriteFloat(call.output, total);
}
