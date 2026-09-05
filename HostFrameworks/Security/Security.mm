@import Foundation;
@import Security;

#include "bridge.h"
#include "../../GuestFrameworks/Security/LC32SecurityBridge.h"

#include <cstddef>
#include <cstdint>

extern "C" CFDictionaryRef SecTrustCopyInfo(SecTrustRef trust)
    __attribute__((weak_import));

namespace {

static_assert(sizeof(LC32SecurityCall) == 32,
              "Security bridge ABI must remain ARM32-compatible");
static_assert(offsetof(LC32SecurityCall, slots) == 16,
              "Security bridge slot offset changed");

bool ReadSecurityCall(u32 guestAddress, LC32SecurityCall &call) {
    if(!guestAddress ||
       static_cast<uint64_t>(guestAddress) + sizeof(call) >
           static_cast<uint64_t>(UINT32_MAX) + 1 ||
       Dynarmic_mem_1read(guestAddress, sizeof(call),
           reinterpret_cast<char *>(&call)) != 0) {
        return false;
    }
    return call.version == LC32SecurityABIVersion &&
        call.slotCount <= LC32SecurityMaxSlots && call.reserved == 0;
}

bool WriteSecurityStatus(u32 guestAddress, OSStatus status) {
    const uint64_t statusAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32SecurityCall, status);
    if(statusAddress + sizeof(int32_t) >
       static_cast<uint64_t>(UINT32_MAX) + 1) {
        return false;
    }
    int32_t value = status;
    return Dynarmic_mem_1write(static_cast<u32>(statusAddress),
        sizeof(value), reinterpret_cast<char *>(&value)) == 0;
}

bool RequireSlots(const LC32SecurityCall &call, uint32_t count) {
    return call.slotCount == count;
}

template<typename T>
T SlotHostObject(const LC32SecurityCall &call, size_t index) {
    return reinterpret_cast<T>(
        static_cast<uintptr_t>(call.slots[index]));
}

class SecurityHostCallQuiescence {
public:
    SecurityHostCallQuiescence()
        : active(Dynarmic_guest_host_call_quiescence_begin()) {}

    ~SecurityHostCallQuiescence() {
        if(active) Dynarmic_guest_host_call_quiescence_end();
    }

    SecurityHostCallQuiescence(const SecurityHostCallQuiescence &) = delete;
    SecurityHostCallQuiescence &operator=(
        const SecurityHostCallQuiescence &) = delete;

private:
    bool active;
};

OSStatus CallItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    SecurityHostCallQuiescence quiescence;
    return SecItemAdd(attributes, result);
}

OSStatus CallItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    SecurityHostCallQuiescence quiescence;
    return SecItemCopyMatching(query, result);
}

OSStatus CallItemDelete(CFDictionaryRef query) {
    SecurityHostCallQuiescence quiescence;
    return SecItemDelete(query);
}

OSStatus CallItemUpdate(CFDictionaryRef query,
                        CFDictionaryRef attributes) {
    SecurityHostCallQuiescence quiescence;
    return SecItemUpdate(query, attributes);
}

CFDictionaryRef CallTrustCopyInfo(SecTrustRef trust) {
    SecurityHostCallQuiescence quiescence;
    return SecTrustCopyInfo(trust);
}

u32 FinishOwnedResult(OSStatus &status, CFTypeRef nativeResult) {
    if(status != errSecSuccess) {
        if(nativeResult) CFRelease(nativeResult);
        return 0;
    }
    if(!nativeResult) return 0;

    const u32 guestResult =
        LC32GuestObjectForOwnedHostObject(nativeResult);
    if(!guestResult) status = errSecAllocate;
    return guestResult;
}

} // namespace

__BEGIN_DECLS

u32 LC32_Security_Dispatch(u32 opcodeValue, u32 guestCall, u32) {
    LC32SecurityCall call = {};
    if(!ReadSecurityCall(guestCall, call)) return 0;

    OSStatus status = errSecParam;
    u32 guestResult = 0;
    @autoreleasepool {
        switch(static_cast<LC32SecurityOpcode>(opcodeValue)) {
            case LC32SecurityOpItemAdd: {
                if(!RequireSlots(call, 2)) break;
                CFTypeRef nativeResult = nullptr;
                status = CallItemAdd(
                    SlotHostObject<CFDictionaryRef>(call, 0),
                    call.slots[1] ? &nativeResult : nullptr);
                guestResult = FinishOwnedResult(status, nativeResult);
                break;
            }
            case LC32SecurityOpItemCopyMatching: {
                if(!RequireSlots(call, 2)) break;
                CFTypeRef nativeResult = nullptr;
                status = CallItemCopyMatching(
                    SlotHostObject<CFDictionaryRef>(call, 0),
                    call.slots[1] ? &nativeResult : nullptr);
                guestResult = FinishOwnedResult(status, nativeResult);
                break;
            }
            case LC32SecurityOpItemDelete:
                if(RequireSlots(call, 1)) {
                    status = CallItemDelete(
                        SlotHostObject<CFDictionaryRef>(call, 0));
                }
                break;
            case LC32SecurityOpItemUpdate:
                if(RequireSlots(call, 2)) {
                    status = CallItemUpdate(
                        SlotHostObject<CFDictionaryRef>(call, 0),
                        SlotHostObject<CFDictionaryRef>(call, 1));
                }
                break;
            case LC32SecurityOpTrustCopyInfo: {
                if(!RequireSlots(call, 1)) break;
                if(!SecTrustCopyInfo) {
                    status = errSecUnimplemented;
                    break;
                }
                status = errSecSuccess;
                CFDictionaryRef nativeResult = CallTrustCopyInfo(
                    SlotHostObject<SecTrustRef>(call, 0));
                guestResult = FinishOwnedResult(status, nativeResult);
                break;
            }
        }
    }

    /*
     * If this write unexpectedly fails, the guest-side call retains its
     * initialized errSecUnimplemented status and releases guestResult before
     * returning.  That keeps the native Create/Copy ownership balanced.
     */
    (void)WriteSecurityStatus(guestCall, status);
    return guestResult;
}

__END_DECLS
