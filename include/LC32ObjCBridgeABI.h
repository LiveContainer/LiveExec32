#ifndef LC32_OBJC_BRIDGE_ABI_H
#define LC32_OBJC_BRIDGE_ABI_H

#include <stdint.h>

/*
 * Pointer arguments passed by an ARM32 shim occupy the low 32 bits of their
 * 64-bit bridge slot.  The high word identifies storage which must be
 * translated before it can be passed to an ARM64 Objective-C implementation.
 */
#define LC32_GUEST_ARGUMENT_TAG_MASK \
    UINT64_C(0xffffffff00000000)
#define LC32_GUEST_INDIRECT_ARGUMENT_TAG \
    UINT64_C(0x8000000000000000)
#define LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG \
    UINT64_C(0x8000000100000000)

#define LC32_HOST_OBJECT_ARRAY_MAGIC UINT32_C(0x4f413332) /* "OA32" */
#define LC32_HOST_OBJECT_ARRAY_MAX_COUNT UINT32_C(1048576)

typedef struct LC32HostObjectArrayDescriptor {
    uint32_t count;
    uint32_t countArgumentIndex;
    uint32_t magic;
    uint32_t reserved;
    uint64_t objects[];
} LC32HostObjectArrayDescriptor;

#endif
