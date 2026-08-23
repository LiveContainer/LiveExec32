#ifndef LC32_SECURITY_BRIDGE_H
#define LC32_SECURITY_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

enum {
    LC32SecurityABIVersion = 1,
    LC32SecurityMaxSlots = 2,
};

/*
 * The dispatcher returns an owned guest object address in r0 and writes the
 * OSStatus here.  Keeping the two values separate preserves the full signed
 * status range without exposing a native pointer to ARM32 code.
 */
typedef struct {
    uint32_t version;
    uint32_t slotCount;
    int32_t status;
    uint32_t reserved;
    uint64_t slots[LC32SecurityMaxSlots];
} LC32SecurityCall;

#if defined(__cplusplus)
static_assert(sizeof(LC32SecurityCall) == 32,
              "Security bridge ABI size changed");
static_assert(offsetof(LC32SecurityCall, slots) == 16,
              "Security bridge ABI slot offset changed");
#else
_Static_assert(sizeof(LC32SecurityCall) == 32,
               "Security bridge ABI size changed");
_Static_assert(offsetof(LC32SecurityCall, slots) == 16,
               "Security bridge ABI slot offset changed");
#endif

typedef enum : uint32_t {
    LC32SecurityOpItemAdd = 1,
    LC32SecurityOpItemCopyMatching = 2,
    LC32SecurityOpItemDelete = 3,
    LC32SecurityOpItemUpdate = 4,
} LC32SecurityOpcode;

#endif
