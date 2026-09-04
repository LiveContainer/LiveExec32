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

u32 GuestForBorrowedObject(CFTypeRef object) {
    return object ? [(__bridge id)object guest_self] : 0;
}

bool GuestRangeIsValid(u32 address, size_t length) {
    return !length || (address &&
        static_cast<uint64_t>(address) + length <=
            static_cast<uint64_t>(UINT32_MAX) + 1);
}

struct LC32GuestCFStreamError {
    int32_t domain;
    int32_t error;
};

bool ReadGuestCFStreamError(u32 guestAddress, CFStreamError &error) {
    if(!guestAddress) return true;
    if(!GuestRangeIsValid(guestAddress, sizeof(LC32GuestCFStreamError)))
        return false;
    LC32GuestCFStreamError guestError = {};
    if(Dynarmic_mem_1read(guestAddress, sizeof(guestError),
            reinterpret_cast<char *>(&guestError)) != 0) {
        return false;
    }
    error.domain = guestError.domain;
    error.error = guestError.error;
    return true;
}

bool WriteGuestCFStreamError(u32 guestAddress,
                             const CFStreamError &error) {
    if(!guestAddress) return true;
    if(error.domain < INT32_MIN || error.domain > INT32_MAX ||
       !GuestRangeIsValid(guestAddress, sizeof(LC32GuestCFStreamError))) {
        return false;
    }
    LC32GuestCFStreamError guestError = {
        static_cast<int32_t>(error.domain), error.error,
    };
    return Dynarmic_mem_1write(guestAddress, sizeof(guestError),
        reinterpret_cast<char *>(&guestError)) == 0;
}

bool ReadGuestBoolean(u32 guestAddress, Boolean &value) {
    return !guestAddress || (GuestRangeIsValid(guestAddress, sizeof(value)) &&
        Dynarmic_mem_1read(guestAddress, sizeof(value),
            reinterpret_cast<char *>(&value)) == 0);
}

bool WriteGuestBoolean(u32 guestAddress, Boolean value) {
    return !guestAddress || (GuestRangeIsValid(guestAddress, sizeof(value)) &&
        Dynarmic_mem_1write(guestAddress, sizeof(value),
            reinterpret_cast<char *>(&value)) == 0);
}

bool WriteGuestCreatedObject(u32 guestAddress, CFTypeRef object) {
    if(!guestAddress) {
        if(object) CFRelease(object);
        return true;
    }
    if(!GuestRangeIsValid(guestAddress, sizeof(u32))) {
        if(object) CFRelease(object);
        return false;
    }
    u32 guestObject = GuestForCreatedObject(object);
    if(object && !guestObject) return false;
    return Dynarmic_mem_1write(guestAddress, sizeof(guestObject),
        reinterpret_cast<char *>(&guestObject)) == 0;
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
        case LC32CFNetworkOpHTTPMessageCopyResponseStatusLine:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCopyResponseStatusLine(
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
        case LC32CFNetworkOpHTTPMessageCreateCopy:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPMessageCreateCopy(kCFAllocatorDefault,
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
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
        case LC32CFNetworkOpHTTPMessageGetTypeID:
            return RequireSlots(call, 0)
                ? static_cast<u32>(CFHTTPMessageGetTypeID()) : 0;
        case LC32CFNetworkOpHTTPMessageIsHeaderComplete:
            return RequireSlots(call, 1) && CFHTTPMessageIsHeaderComplete(
                SlotHostObject<CFHTTPMessageRef>(call, 0));
        case LC32CFNetworkOpHTTPMessageIsRequest:
            return RequireSlots(call, 1) && CFHTTPMessageIsRequest(
                SlotHostObject<CFHTTPMessageRef>(call, 0));
        case LC32CFNetworkOpHTTPAuthenticationGetTypeID:
            return RequireSlots(call, 0)
                ? static_cast<u32>(CFHTTPAuthenticationGetTypeID()) : 0;
        case LC32CFNetworkOpHTTPAuthenticationCreateFromResponse:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault,
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPAuthenticationAppliesToRequest:
            return RequireSlots(call, 2) &&
                CFHTTPAuthenticationAppliesToRequest(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0),
                    SlotHostObject<CFHTTPMessageRef>(call, 1));
        case LC32CFNetworkOpHTTPAuthenticationRequiresOrderedRequests:
            return RequireSlots(call, 1) &&
                CFHTTPAuthenticationRequiresOrderedRequests(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0));
        case LC32CFNetworkOpHTTPAuthenticationCopyRealm:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPAuthenticationCopyRealm(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPAuthenticationCopyDomains:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPAuthenticationCopyDomains(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPAuthenticationCopyMethod:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHTTPAuthenticationCopyMethod(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0))) : 0;
        case LC32CFNetworkOpHTTPAuthenticationRequiresUserNameAndPassword:
            return RequireSlots(call, 1) &&
                CFHTTPAuthenticationRequiresUserNameAndPassword(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0));
        case LC32CFNetworkOpHTTPAuthenticationRequiresAccountDomain:
            return RequireSlots(call, 1) &&
                CFHTTPAuthenticationRequiresAccountDomain(
                    SlotHostObject<CFHTTPAuthenticationRef>(call, 0));
        case LC32CFNetworkOpHTTPAuthenticationIsValid: {
            if(!RequireSlots(call, 2)) return 0;
            CFHTTPAuthenticationRef authentication =
                SlotHostObject<CFHTTPAuthenticationRef>(call, 0);
            const u32 guestError = SlotU32(call, 1);
            CFStreamError error = {};
            if(!authentication ||
               !ReadGuestCFStreamError(guestError, error)) {
                return 0;
            }
            const Boolean result = CFHTTPAuthenticationIsValid(
                authentication, guestError ? &error : nullptr);
            return WriteGuestCFStreamError(guestError, error) && result;
        }
        case LC32CFNetworkOpHTTPMessageAddAuthentication:
            return RequireSlots(call, 6) &&
                CFHTTPMessageAddAuthentication(
                    SlotHostObject<CFHTTPMessageRef>(call, 0),
                    SlotHostObject<CFHTTPMessageRef>(call, 1),
                    SlotHostObject<CFStringRef>(call, 2),
                    SlotHostObject<CFStringRef>(call, 3),
                    SlotHostObject<CFStringRef>(call, 4),
                    SlotU32(call, 5) != 0);
        case LC32CFNetworkOpHTTPMessageApplyCredentials: {
            if(!RequireSlots(call, 5)) return 0;
            CFHTTPMessageRef request =
                SlotHostObject<CFHTTPMessageRef>(call, 0);
            CFHTTPAuthenticationRef authentication =
                SlotHostObject<CFHTTPAuthenticationRef>(call, 1);
            const u32 guestError = SlotU32(call, 4);
            CFStreamError error = {};
            if(!request || !authentication ||
               !ReadGuestCFStreamError(guestError, error)) {
                return 0;
            }
            const Boolean result = CFHTTPMessageApplyCredentials(
                request, authentication,
                SlotHostObject<CFStringRef>(call, 2),
                SlotHostObject<CFStringRef>(call, 3),
                guestError ? &error : nullptr);
            return WriteGuestCFStreamError(guestError, error) && result;
        }
        case LC32CFNetworkOpHTTPMessageApplyCredentialDictionary: {
            if(!RequireSlots(call, 4)) return 0;
            CFHTTPMessageRef request =
                SlotHostObject<CFHTTPMessageRef>(call, 0);
            CFHTTPAuthenticationRef authentication =
                SlotHostObject<CFHTTPAuthenticationRef>(call, 1);
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 2);
            const u32 guestError = SlotU32(call, 3);
            CFStreamError error = {};
            if(!request || !authentication || !dictionary ||
               !ReadGuestCFStreamError(guestError, error)) {
                return 0;
            }
            const Boolean result = CFHTTPMessageApplyCredentialDictionary(
                request, authentication, dictionary,
                guestError ? &error : nullptr);
            return WriteGuestCFStreamError(guestError, error) && result;
        }
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
        case LC32CFNetworkOpCopyProxiesForAutoConfigurationScript: {
            if(!RequireSlots(call, 3)) return 0;
            CFStringRef script = SlotHostObject<CFStringRef>(call, 0);
            CFURLRef targetURL = SlotHostObject<CFURLRef>(call, 1);
            const u32 guestError = SlotU32(call, 2);
            if(!script || !targetURL || (guestError &&
               !GuestRangeIsValid(guestError, sizeof(u32)))) {
                return 0;
            }
            if(guestError &&
               !WriteGuestCreatedObject(guestError, nullptr)) {
                return 0;
            }
            CFErrorRef error = nullptr;
            CFArrayRef proxies =
                CFNetworkCopyProxiesForAutoConfigurationScript(
                    script, targetURL, guestError ? &error : nullptr);
            if(guestError && !WriteGuestCreatedObject(guestError, error)) {
                if(proxies) CFRelease(proxies);
                return 0;
            }
            return GuestForCreatedObject(proxies);
        }
        case LC32CFNetworkOpReadStreamCreateForHTTPRequest:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault,
                    SlotHostObject<CFHTTPMessageRef>(call, 0))) : 0;
        case LC32CFNetworkOpReadStreamCreateForStreamedHTTPRequest:
            return RequireSlots(call, 2) ? GuestForCreatedObject(
                CFReadStreamCreateForStreamedHTTPRequest(
                    kCFAllocatorDefault,
                    SlotHostObject<CFHTTPMessageRef>(call, 0),
                    SlotHostObject<CFReadStreamRef>(call, 1))) : 0;
        case LC32CFNetworkOpHostGetTypeID:
            return RequireSlots(call, 0)
                ? static_cast<u32>(CFHostGetTypeID()) : 0;
        case LC32CFNetworkOpHostCreateWithName:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHostCreateWithName(kCFAllocatorDefault,
                    SlotHostObject<CFStringRef>(call, 0))) : 0;
        case LC32CFNetworkOpHostCreateWithAddress:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHostCreateWithAddress(kCFAllocatorDefault,
                    SlotHostObject<CFDataRef>(call, 0))) : 0;
        case LC32CFNetworkOpHostCreateCopy:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFHostCreateCopy(kCFAllocatorDefault,
                    SlotHostObject<CFHostRef>(call, 0))) : 0;
        case LC32CFNetworkOpHostGetAddressing:
        case LC32CFNetworkOpHostGetNames:
        case LC32CFNetworkOpHostGetReachability: {
            if(!RequireSlots(call, 2)) return 0;
            CFHostRef host = SlotHostObject<CFHostRef>(call, 0);
            const u32 guestResolved = SlotU32(call, 1);
            Boolean resolved = false;
            if(!host || !ReadGuestBoolean(guestResolved, resolved)) return 0;
            CFTypeRef result = nullptr;
            switch(static_cast<LC32CFNetworkOpcode>(opcodeValue)) {
                case LC32CFNetworkOpHostGetAddressing:
                    result = CFHostGetAddressing(host,
                        guestResolved ? &resolved : nullptr);
                    break;
                case LC32CFNetworkOpHostGetNames:
                    result = CFHostGetNames(host,
                        guestResolved ? &resolved : nullptr);
                    break;
                case LC32CFNetworkOpHostGetReachability:
                    result = CFHostGetReachability(host,
                        guestResolved ? &resolved : nullptr);
                    break;
                default:
                    break;
            }
            if(!WriteGuestBoolean(guestResolved, resolved)) return 0;
            return GuestForBorrowedObject(result);
        }
        case LC32CFNetworkOpNetServiceGetTypeID:
            return RequireSlots(call, 0)
                ? static_cast<u32>(CFNetServiceGetTypeID()) : 0;
        case LC32CFNetworkOpNetServiceCreate:
            return RequireSlots(call, 4) ? GuestForCreatedObject(
                CFNetServiceCreate(kCFAllocatorDefault,
                    SlotHostObject<CFStringRef>(call, 0),
                    SlotHostObject<CFStringRef>(call, 1),
                    SlotHostObject<CFStringRef>(call, 2),
                    static_cast<SInt32>(SlotU32(call, 3)))) : 0;
        case LC32CFNetworkOpNetServiceCreateCopy:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFNetServiceCreateCopy(kCFAllocatorDefault,
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetDomain:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetDomain(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetType:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetType(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetName:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetName(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetTargetHost:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetTargetHost(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetPortNumber:
            return RequireSlots(call, 1) ? static_cast<u32>(
                CFNetServiceGetPortNumber(
                    SlotHostObject<CFNetServiceRef>(call, 0))) :
                static_cast<u32>(-1);
        case LC32CFNetworkOpNetServiceGetAddressing:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetAddressing(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceGetTXTData:
            return RequireSlots(call, 1) ? GuestForBorrowedObject(
                CFNetServiceGetTXTData(
                    SlotHostObject<CFNetServiceRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceSetTXTData:
            return RequireSlots(call, 2) && CFNetServiceSetTXTData(
                SlotHostObject<CFNetServiceRef>(call, 0),
                SlotHostObject<CFDataRef>(call, 1));
        case LC32CFNetworkOpNetServiceCreateDictionaryWithTXTData:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFNetServiceCreateDictionaryWithTXTData(kCFAllocatorDefault,
                    SlotHostObject<CFDataRef>(call, 0))) : 0;
        case LC32CFNetworkOpNetServiceCreateTXTDataWithDictionary:
            return RequireSlots(call, 1) ? GuestForCreatedObject(
                CFNetServiceCreateTXTDataWithDictionary(kCFAllocatorDefault,
                    SlotHostObject<CFDictionaryRef>(call, 0))) : 0;
    }
    return 0;
}

__END_DECLS

#pragma clang diagnostic pop
