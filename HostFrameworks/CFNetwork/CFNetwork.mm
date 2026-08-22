@import CFNetwork;
@import Foundation;

#include "bridge.h"
#include "../../GuestFrameworks/CFNetwork/LC32CFNetworkBridge.h"

#include <climits>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <strings.h>
#include <vector>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace {

constexpr uint32_t kMaximumHTTPChunkBytes = 64u * 1024u * 1024u;

bool ReadCFNetworkCall(u32 guestAddress, LC32CFNetworkCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32CFNetworkABIVersion ||
       header.slotCount > LC32CFNetworkMaxSlots) {
        return false;
    }

    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t slotsAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32CFNetworkCall, slots);
    if(slotsAddress > UINT32_MAX ||
       slotsAddress + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1) {
        return false;
    }
    return !byteCount || Dynarmic_mem_1read(
        static_cast<u32>(slotsAddress), byteCount,
        reinterpret_cast<char *>(call.slots)) == 0;
}

bool RequireSlots(const LC32CFNetworkCall &call, uint32_t count) {
    return call.slotCount == count;
}

u32 SlotU32(const LC32CFNetworkCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

template<typename T>
T SlotHostObject(const LC32CFNetworkCall &call, size_t index) {
    return reinterpret_cast<T>(
        static_cast<uintptr_t>(call.slots[index]));
}

u32 GuestForCreatedObject(CFTypeRef object) {
    return LC32GuestObjectForOwnedHostObject(object);
}

} // namespace

__BEGIN_DECLS

void LC32ConfigureLegacyAppTransportSecurity(
        uint32_t guestSDKVersion) {
    @autoreleasepool {
        /*
         * ATS was introduced for applications linked against the iOS 9 SDK.
         * LiveContainer replaces the process's NSBundle/CFBundle main bundle
         * with the selected guest bundle, while its SDK compatibility hook may
         * report a newer SDK to modern UIKit. Consequently host CFNetwork sees
         * a legacy guest's plist (with no ATS declaration) under modern linked
         * semantics and rejects the cleartext traffic that app historically
         * used.
         *
         * Restore only the pre-ATS default, in memory, and never override an
         * app that supplied an explicit NSAppTransportSecurity policy. The
         * environment override is useful for malformed/newer legacy binaries;
         * setting it to 0 disables even the automatic pre-iOS-9 behavior.
         */
        const char *overrideValue = getenv("LC32_LEGACY_ATS");
        const bool overridePresent =
            overrideValue != nullptr && overrideValue[0] != '\0';
        const bool overrideEnabled = overridePresent &&
            strcmp(overrideValue, "0") != 0 &&
            strcasecmp(overrideValue, "false") != 0 &&
            strcasecmp(overrideValue, "no") != 0;
        if((overridePresent && !overrideEnabled) ||
           (!overrideEnabled &&
            (guestSDKVersion == 0 || guestSDKVersion >= 0x00090000))) {
            return;
        }

        CFBundleRef bundle = CFBundleGetMainBundle();
        CFDictionaryRef immutableInfo = bundle
            ? CFBundleGetInfoDictionary(bundle) : nullptr;
        NSMutableDictionary *info =
            (__bridge NSMutableDictionary *)immutableInfo;
        if(![info isKindOfClass:NSMutableDictionary.class] ||
           info[@"NSAppTransportSecurity"] != nil) {
            return;
        }

        info[@"NSAppTransportSecurity"] = @{
            @"NSAllowsArbitraryLoads": @YES
        };
        fprintf(stderr,
            "LC32: enabled legacy ATS compatibility for guest SDK %u.%u.%u\n",
            guestSDKVersion >> 16,
            (guestSDKVersion >> 8) & 0xff,
            guestSDKVersion & 0xff);
    }
}

u32 LC32_CFNetwork_Dispatch(u32 opcodeValue, u32 guestCall, u32) {
    LC32CFNetworkCall call;
    if(!ReadCFNetworkCall(guestCall, call)) return 0;

    switch(static_cast<LC32CFNetworkOpcode>(opcodeValue)) {
        case LC32CFNetworkOpHTTPMessageAppendBytes: {
            if(!RequireSlots(call, 3)) return 0;
            CFHTTPMessageRef message =
                SlotHostObject<CFHTTPMessageRef>(call, 0);
            const u32 guestBytes = SlotU32(call, 1);
            const u32 byteCount = SlotU32(call, 2);
            if(!message || byteCount > kMaximumHTTPChunkBytes ||
               (byteCount && !guestBytes) ||
               static_cast<uint64_t>(guestBytes) + byteCount >
                    static_cast<uint64_t>(UINT32_MAX) + 1) {
                return 0;
            }
            std::vector<UInt8> bytes(byteCount);
            if(byteCount && Dynarmic_mem_1read(guestBytes, byteCount,
                    reinterpret_cast<char *>(bytes.data())) != 0) {
                return 0;
            }
            return CFHTTPMessageAppendBytes(message,
                byteCount ? bytes.data() : nullptr, byteCount) != false;
        }
        case LC32CFNetworkOpHTTPMessageCopyAllHeaderFields:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyAllHeaderFields(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCopyBody:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyBody(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCopyHeaderFieldValue:
            return RequireSlots(call, 2) ? GuestForCreatedObject(
                CFHTTPMessageCopyHeaderFieldValue(
                    SlotHostObject<CFHTTPMessageRef>(call, 0),
                    SlotHostObject<CFStringRef>(call, 1))) : 0;
        case LC32CFNetworkOpHTTPMessageCopyRequestMethod:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyRequestMethod(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCopyRequestURL:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyRequestURL(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCopySerializedMessage:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopySerializedMessage(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCopyVersion:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyVersion(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageCreateEmpty:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCreateEmpty(kCFAllocatorDefault,
                    SlotU32(call, 0) != 0)) : 0;
        case LC32CFNetworkOpHTTPMessageCreateRequest:
            return RequireSlots(call, 3) ? GuestForCreatedObject(
                CFHTTPMessageCreateRequest(kCFAllocatorDefault,
                    SlotHostObject<CFStringRef>(call, 0),
                    SlotHostObject<CFURLRef>(call, 1),
                    SlotHostObject<CFStringRef>(call, 2))) : 0;
        case LC32CFNetworkOpHTTPMessageCreateResponse:
            return RequireSlots(call, 3) ? GuestForCreatedObject(
                CFHTTPMessageCreateResponse(kCFAllocatorDefault,
                    static_cast<CFIndex>(static_cast<int32_t>(
                        SlotU32(call, 0))),
                    SlotHostObject<CFStringRef>(call, 1),
                    SlotHostObject<CFStringRef>(call, 2))) : 0;
        case LC32CFNetworkOpHTTPMessageGetResponseStatusCode:
            return RequireSlots(call, 1) ? static_cast<u32>(
                CFHTTPMessageGetResponseStatusCode(
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPMessageIsHeaderComplete:
            return RequireSlots(call, 1) && CFHTTPMessageIsHeaderComplete(
                SlotHostObject<CFHTTPMessageRef>(call, 0));
        case LC32CFNetworkOpHTTPMessageSetBody:
            if(RequireSlots(call, 2)) CFHTTPMessageSetBody(
                SlotHostObject<CFHTTPMessageRef>(call, 0),
                SlotHostObject<CFDataRef>(call, 1));
            return 0;
        case LC32CFNetworkOpHTTPMessageSetHeaderFieldValue:
            if(RequireSlots(call, 3)) CFHTTPMessageSetHeaderFieldValue(
                SlotHostObject<CFHTTPMessageRef>(call, 0),
                SlotHostObject<CFStringRef>(call, 1),
                SlotHostObject<CFStringRef>(call, 2));
            return 0;
        case LC32CFNetworkOpCopySystemProxySettings:
            return RequireSlots(call, 0) ? GuestForCreatedObject(
                CFNetworkCopySystemProxySettings()) : 0;
        case LC32CFNetworkOpCopyProxiesForURL:
            return RequireSlots(call, 2) ? GuestForCreatedObject(
                CFNetworkCopyProxiesForURL(
                    SlotHostObject<CFURLRef>(call, 0),
                    SlotHostObject<CFDictionaryRef>(call, 1))) : 0;
        case LC32CFNetworkOpReadStreamCreateForHTTPRequest:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault,
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
    }
    return 0;
}

__END_DECLS

#pragma clang diagnostic pop
