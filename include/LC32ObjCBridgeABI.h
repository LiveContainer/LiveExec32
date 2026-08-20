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
    UINT64_C(0x4c43320000000000)
#define LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG \
    UINT64_C(0x4c43320100000000)
#define LC32_GUEST_AGGREGATE_ARGUMENT_TAG \
    UINT64_C(0x4c43320200000000)
#define LC32_GUEST_INVOCATION_ARGUMENT_TAG \
    UINT64_C(0x4c43320300000000)
#define LC32_GUEST_FLOATING_INDIRECT_ARGUMENT_TAG \
    UINT64_C(0x4c43320400000000)
#define LC32_GUEST_SIZED_INDIRECT_ARGUMENT_TAG \
    UINT64_C(0x4c43320500000000)

/*
 * Selector flag consumed by LC32InvokeHostSelector.  An Objective-C object
 * result is converted to its guest proxy before the SVC returns, while the
 * autoreleased native result is still valid in the original call frame.
 */
#define LC32_HOST_SELECTOR_RETURN_GUEST_OBJECT \
    UINT64_C(0x4000000000000000)
#define LC32_HOST_SELECTOR_RETURN_STRUCT \
    UINT64_C(0x8000000000000000)
#define LC32_HOST_SELECTOR_FLAG_MASK \
    UINT64_C(0xc000000000000000)

#define LC32_HOST_OBJECT_ARRAY_MAGIC UINT32_C(0x4f413332) /* "OA32" */
#define LC32_HOST_OBJECT_ARRAY_MAX_COUNT UINT32_C(1048576)
#define LC32_HOST_SIZED_INDIRECT_MAGIC UINT32_C(0x53493332) /* "SI32" */
#define LC32_HOST_SIZED_INDIRECT_MAX_SIZE UINT32_C(64)

/*
 * Result of SVC 1019.  A mapped success transfers one native +1 to the
 * guest's matching weak retain.  NoMapping means the object is guest-only;
 * MappedDead means it had a native peer which can no longer be retained.
 */
typedef uint32_t LC32HostWeakRetainStatus;
enum {
    LC32HostWeakRetainNoMapping = 0,
    LC32HostWeakRetainRetained = 1,
    LC32HostWeakRetainMappedDead = 2,
};

typedef struct LC32HostObjectArrayDescriptor {
    uint32_t count;
    uint32_t countArgumentIndex;
    uint32_t magic;
    uint32_t reserved;
    uint64_t objects[];
} LC32HostObjectArrayDescriptor;

/*
 * Describes guest storage whose native pointee is larger or smaller than the
 * bridge's ordinary eight-byte indirect cell.  The bridge copies exactly
 * `size` bytes in both directions around the synchronous host invocation.
 */
typedef struct LC32HostSizedIndirectDescriptor {
    uint32_t storage;
    uint32_t size;
    uint32_t magic;
    uint32_t reserved;
} LC32HostSizedIndirectDescriptor;

#endif
