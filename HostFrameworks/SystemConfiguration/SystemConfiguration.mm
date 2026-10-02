#import <SystemConfiguration/SystemConfiguration.h>
#include "bridge.h"
#include "../../GuestFrameworks/SystemConfiguration/LC32SystemConfigurationBridge.h"
#include <cstddef>

// Some historical getters remain exported on iOS despite being marked
// unavailable in modern headers. Resolve them optionally; preserve native
// entitlement/privacy failures rather than fabricating network/device data.
static void *NativeSymbol(const char *name) {
    static void *library = dlopen(
        "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",
        RTLD_LAZY | RTLD_LOCAL);
    return library ? dlsym(library, name) : nullptr;
}

extern "C" u32 LC32_SystemConfiguration_Copy(u32 opcode, u32 address) {
    static_assert(sizeof(LC32SCCopyCall) == 24, "shared ARM32/ARM64 copy ABI");
    LC32SCCopyCall call = {};
    if(!address || uint64_t(address) + sizeof(call) > (uint64_t(1) << 32) ||
       Dynarmic_mem_1read(address, sizeof(call), (char *)&call) || call.version != 1)
        return 0;
    CFTypeRef result = nullptr;
    bool available = false;
    auto object = reinterpret_cast<CFTypeRef>(uintptr_t(call.object));
    using CopyGetter = CFTypeRef (*)(CFTypeRef);
    using ErrorGetter = int (*)(void);
    switch(opcode) {
        case LC32SCOpCopyComputerName: {
            using Getter = CFStringRef (*)(CFTypeRef, CFStringEncoding *);
            static auto getter = (Getter)NativeSymbol("SCDynamicStoreCopyComputerName");
            available = getter != nullptr;
            if(getter) result = getter(object, &call.encoding);
            break;
        }
        case LC32SCOpCopyLocalHostName:
        case LC32SCOpCopyLocation:
        case LC32SCOpCopyProxies:
        case LC32SCOpCopyCurrentNetworkInfo: {
            static const CopyGetter getters[] = {
                (CopyGetter)NativeSymbol("SCDynamicStoreCopyLocalHostName"),
                (CopyGetter)NativeSymbol("SCDynamicStoreCopyLocation"),
                (CopyGetter)NativeSymbol("SCDynamicStoreCopyProxies"),
                (CopyGetter)NativeSymbol("CNCopyCurrentNetworkInfo"),
            };
            unsigned index = opcode == LC32SCOpCopyCurrentNetworkInfo ? 3 :
                opcode - LC32SCOpCopyLocalHostName;
            available = getters[index] != nullptr;
            if(available) result = getters[index](object);
            break;
        }
        case LC32SCOpCopySupportedInterfaces: {
            using Getter = CFArrayRef (*)(void);
            static auto getter = (Getter)NativeSymbol("CNCopySupportedInterfaces");
            available = getter != nullptr;
            if(getter) result = getter();
            break;
        }
        default: break;
    }
    static auto error = (ErrorGetter)NativeSymbol("SCError");
    call.status = result ? kSCStatusOK :
        (available && error ? error() : kSCStatusFailed);
    if(Dynarmic_mem_1write(address, sizeof(call), (char *)&call)) {
        if(result) CFRelease(result);
        return 0;
    }
    return LC32GuestObjectForOwnedHostObject(result);
}
