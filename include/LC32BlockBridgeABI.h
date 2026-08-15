#pragma once

#include <stddef.h>
#include <stdint.h>

#define LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS 5

typedef enum LC32GuestBlockCallbackKind {
    LC32GuestBlockCallbackKindInvoke = 1,
    LC32GuestBlockCallbackKindRelease = 2,
    /*
     * Invoke an ordinary guest C function rather than a block invoke
     * function.  arguments contains the complete argument list; guestBlock
     * is unused.  This is currently restricted to void callbacks so native
     * framework callbacks can be serialized onto a registered guest pthread
     * without borrowing a JIT from their host thread.
     */
    LC32GuestBlockCallbackKindFunction = 3,
} LC32GuestBlockCallbackKind;

typedef enum LC32GuestBlockCallbackWaitResult {
    LC32GuestBlockCallbackWaitResultStop = 0,
    LC32GuestBlockCallbackWaitResultJob = 1,
    LC32GuestBlockCallbackWaitResultRetry = 2,
} LC32GuestBlockCallbackWaitResult;

/*
 * The native and ARM32 block ABIs agree on neither pointer width nor the
 * layout of aggregate arguments.  Keep callback values self-describing while
 * they cross the serialized native-thread executor.  value2 is used only by
 * the two-word NSRange representation; pointer arguments carry their pointee
 * byte rather than exposing an ARM64 address to the guest.
 */
typedef enum LC32GuestBlockValueKind {
    LC32GuestBlockValueVoid = 0,
    LC32GuestBlockValueObject = 1,
    LC32GuestBlockValueSignedChar = 2,
    LC32GuestBlockValueSigned32 = 3,
    LC32GuestBlockValueUnsigned32 = 4,
    LC32GuestBlockValueSigned64 = 5,
    LC32GuestBlockValueUnsigned64 = 6,
    LC32GuestBlockValueRange = 7,
    LC32GuestBlockValueCharPointer = 8,
} LC32GuestBlockValueKind;

typedef struct LC32GuestBlockCallbackArgument {
    uint32_t kind;
    uint32_t reserved;
    uint64_t value;
    uint64_t value2;
} LC32GuestBlockCallbackArgument;

/*
 * Host object pointers deliberately remain 64-bit here. The host keeps only
 * arguments tagged Object retained until the guest acknowledges this
 * descriptor. Scalar values are copied verbatim, ranges use value/value2,
 * and CharPointer is copied into guest-local storage for the invocation.
 *
 * completionToken is opaque to the guest. A typed callback sends this
 * descriptor to LC32CompleteTypedGuestBlock before acknowledging the normal
 * callback job, which lets a blocked native caller receive the result and
 * pointer copyback without changing the scheduler's completion SVC.
 */
typedef struct LC32GuestBlockCallbackDescriptor {
    uint32_t identifier;
    uint32_t kind;
    uint32_t guestBlock;
    uint32_t guestInvoke;
    uint32_t argumentCount;
    uint32_t resultKind;
    uint64_t completionToken;
    uint64_t result;
    LC32GuestBlockCallbackArgument
        arguments[LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS];
} LC32GuestBlockCallbackDescriptor;

#if defined(__cplusplus)
static_assert(sizeof(LC32GuestBlockCallbackArgument) == 24,
              "callback argument ABI changed");
static_assert(offsetof(LC32GuestBlockCallbackDescriptor, arguments) == 40,
              "callback descriptor ABI changed");
static_assert(sizeof(LC32GuestBlockCallbackDescriptor) == 160,
              "callback descriptor ABI changed");
#else
_Static_assert(sizeof(LC32GuestBlockCallbackArgument) == 24,
               "callback argument ABI changed");
_Static_assert(offsetof(LC32GuestBlockCallbackDescriptor, arguments) == 40,
               "callback descriptor ABI changed");
_Static_assert(sizeof(LC32GuestBlockCallbackDescriptor) == 160,
               "callback descriptor ABI changed");
#endif
