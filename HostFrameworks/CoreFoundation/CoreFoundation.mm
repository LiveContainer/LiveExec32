@import CoreFoundation;
@import Foundation;

#include "bridge.h"
#include "../../GuestFrameworks/CoreFoundation/LC32CoreFoundationBridge.h"

#include <climits>
#include <cstdint>
#include <cstring>
#include <vector>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace {

constexpr uint32_t kMaximumCStringBytes = 64u * 1024u * 1024u;

bool ReadCoreFoundationCall(u32 guestAddress,
                            LC32CoreFoundationCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32CoreFoundationABIVersion ||
       header.slotCount > LC32CoreFoundationMaxSlots) {
        return false;
    }

    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t slotsAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32CoreFoundationCall, slots);
    if(slotsAddress > UINT32_MAX ||
       slotsAddress + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1) {
        return false;
    }
    return !byteCount || Dynarmic_mem_1read(
        static_cast<u32>(slotsAddress), byteCount,
        reinterpret_cast<char *>(call.slots)) == 0;
}

bool RequireSlots(const LC32CoreFoundationCall &call, uint32_t count) {
    return call.slotCount == count;
}

u32 SlotU32(const LC32CoreFoundationCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

template<typename T>
T SlotHostObject(const LC32CoreFoundationCall &call, size_t index) {
    return reinterpret_cast<T>(
        static_cast<uintptr_t>(call.slots[index]));
}

const CFArrayCallBacks *ArrayCallbacks(uint32_t mode) {
    static const CFArrayCallBacks weakCFTypeCallbacks = {
        0, nullptr, nullptr, CFCopyDescription, CFEqual,
    };
    static const CFArrayCallBacks weakCFTypeNoDescriptionCallbacks = {
        0, nullptr, nullptr, nullptr, CFEqual,
    };
    switch(static_cast<LC32CoreFoundationCallbacksMode>(mode)) {
        case LC32CoreFoundationCallbacksCFType:
            return &kCFTypeArrayCallBacks;
        case LC32CoreFoundationCallbacksNull:
            return nullptr;
        case LC32CoreFoundationCallbacksWeakCFType:
            return &weakCFTypeCallbacks;
        case LC32CoreFoundationCallbacksWeakCFTypeNoDescription:
            return &weakCFTypeNoDescriptionCallbacks;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFArrayCallBacks *>(UINTPTR_MAX);
}

CFHashCode WeakCFTypeHash(const void *value) {
    return value ? CFHash(static_cast<CFTypeRef>(value)) : 0;
}

const CFDictionaryKeyCallBacks *DictionaryKeyCallbacks(uint32_t mode) {
    static const CFDictionaryKeyCallBacks weakCFTypeCallbacks = {
        0, nullptr, nullptr, CFCopyDescription, CFEqual, WeakCFTypeHash,
    };
    static const CFDictionaryKeyCallBacks
        weakCFTypeNoDescriptionCallbacks = {
            0, nullptr, nullptr, nullptr, CFEqual, WeakCFTypeHash,
        };
    switch(static_cast<LC32CoreFoundationCallbacksMode>(mode)) {
        case LC32CoreFoundationCallbacksCFType:
            return &kCFTypeDictionaryKeyCallBacks;
        case LC32CoreFoundationCallbacksNull:
            return nullptr;
        case LC32CoreFoundationCallbacksWeakCFType:
            return &weakCFTypeCallbacks;
        case LC32CoreFoundationCallbacksWeakCFTypeNoDescription:
            return &weakCFTypeNoDescriptionCallbacks;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFDictionaryKeyCallBacks *>(UINTPTR_MAX);
}

const CFDictionaryValueCallBacks *DictionaryValueCallbacks(uint32_t mode) {
    static const CFDictionaryValueCallBacks weakCFTypeCallbacks = {
        0, nullptr, nullptr, CFCopyDescription, CFEqual,
    };
    static const CFDictionaryValueCallBacks
        weakCFTypeNoDescriptionCallbacks = {
            0, nullptr, nullptr, nullptr, CFEqual,
        };
    switch(static_cast<LC32CoreFoundationCallbacksMode>(mode)) {
        case LC32CoreFoundationCallbacksCFType:
            return &kCFTypeDictionaryValueCallBacks;
        case LC32CoreFoundationCallbacksNull:
            return nullptr;
        case LC32CoreFoundationCallbacksWeakCFType:
            return &weakCFTypeCallbacks;
        case LC32CoreFoundationCallbacksWeakCFTypeNoDescription:
            return &weakCFTypeNoDescriptionCallbacks;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFDictionaryValueCallBacks *>(UINTPTR_MAX);
}

u32 GuestForCreatedObject(CFTypeRef object) {
    if(!object) return 0;
    const u32 guestObject = [(id)object guest_self];
    if(!guestObject) CFRelease(object);
    return guestObject;
}

template<typename T>
u32 GetNumberValue(CFNumberRef number, CFNumberType type,
                   u32 guestOutput) {
    if(!guestOutput || guestOutput > UINT32_MAX - sizeof(T) + 1)
        return 0;
    T value = {};
    const Boolean exact = CFNumberGetValue(number, type, &value);
    if(Dynarmic_mem_1write(guestOutput, sizeof(value),
            reinterpret_cast<char *>(&value)) != 0) {
        return 0;
    }
    return exact != false;
}

u32 DispatchNumberGetValue(const LC32CoreFoundationCall &call) {
    if(!RequireSlots(call, 3)) return 0;
    const CFNumberRef number = SlotHostObject<CFNumberRef>(call, 0);
    const auto type = static_cast<CFNumberType>(SlotU32(call, 1));
    const u32 output = SlotU32(call, 2);
    if(!number) return 0;

    switch(type) {
        case kCFNumberSInt8Type:
        case kCFNumberCharType:
            return GetNumberValue<int8_t>(
                number, kCFNumberSInt8Type, output);
        case kCFNumberSInt16Type:
        case kCFNumberShortType:
            return GetNumberValue<int16_t>(
                number, kCFNumberSInt16Type, output);
        case kCFNumberSInt32Type:
        case kCFNumberIntType:
        case kCFNumberLongType:
        case kCFNumberCFIndexType:
        case kCFNumberNSIntegerType:
            return GetNumberValue<int32_t>(
                number, kCFNumberSInt32Type, output);
        case kCFNumberSInt64Type:
        case kCFNumberLongLongType:
            return GetNumberValue<int64_t>(
                number, kCFNumberSInt64Type, output);
        case kCFNumberFloat32Type:
        case kCFNumberFloatType:
        case kCFNumberCGFloatType:
            return GetNumberValue<float>(
                number, kCFNumberFloat32Type, output);
        case kCFNumberFloat64Type:
        case kCFNumberDoubleType:
            return GetNumberValue<double>(
                number, kCFNumberFloat64Type, output);
        default:
            return 0;
    }
}

} // namespace

__BEGIN_DECLS

u32 LC32_CoreFoundation_Dispatch(u32 opcodeValue, u32 guestCall, u32) {
    LC32CoreFoundationCall call;
    if(!ReadCoreFoundationCall(guestCall, call)) return 0;

    switch(static_cast<LC32CoreFoundationOpcode>(opcodeValue)) {
        case LC32CoreFoundationOpArrayCreateMutable: {
            if(!RequireSlots(call, 2) || SlotU32(call, 0) > INT32_MAX)
                return 0;
            const CFArrayCallBacks *callbacks =
                ArrayCallbacks(SlotU32(call, 1));
            if(callbacks == reinterpret_cast<const CFArrayCallBacks *>(
                    UINTPTR_MAX)) {
                return 0;
            }
            return GuestForCreatedObject(CFArrayCreateMutable(
                kCFAllocatorDefault, static_cast<CFIndex>(SlotU32(call, 0)),
                callbacks));
        }
        case LC32CoreFoundationOpDictionaryCreateMutable: {
            if(!RequireSlots(call, 3) || SlotU32(call, 0) > INT32_MAX)
                return 0;
            const CFDictionaryKeyCallBacks *keyCallbacks =
                DictionaryKeyCallbacks(SlotU32(call, 1));
            const CFDictionaryValueCallBacks *valueCallbacks =
                DictionaryValueCallbacks(SlotU32(call, 2));
            if(keyCallbacks == reinterpret_cast<
                    const CFDictionaryKeyCallBacks *>(UINTPTR_MAX) ||
               valueCallbacks == reinterpret_cast<
                    const CFDictionaryValueCallBacks *>(UINTPTR_MAX)) {
                return 0;
            }
            return GuestForCreatedObject(CFDictionaryCreateMutable(
                kCFAllocatorDefault, static_cast<CFIndex>(SlotU32(call, 0)),
                keyCallbacks, valueCallbacks));
        }
        case LC32CoreFoundationOpStringCreateCopy: {
            if(!RequireSlots(call, 1)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? GuestForCreatedObject(CFStringCreateCopy(
                kCFAllocatorDefault, string)) : 0;
        }
        case LC32CoreFoundationOpStringCreateMutable: {
            if(!RequireSlots(call, 1) || SlotU32(call, 0) > INT32_MAX)
                return 0;
            return GuestForCreatedObject(CFStringCreateMutable(
                kCFAllocatorDefault, static_cast<CFIndex>(SlotU32(call, 0))));
        }
        case LC32CoreFoundationOpStringCreateMutableCopy: {
            if(!RequireSlots(call, 2) || SlotU32(call, 0) > INT32_MAX)
                return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 1);
            return string ? GuestForCreatedObject(CFStringCreateMutableCopy(
                kCFAllocatorDefault, static_cast<CFIndex>(SlotU32(call, 0)),
                string)) : 0;
        }
        case LC32CoreFoundationOpStringCreateWithCString: {
            if(!RequireSlots(call, 2) || !SlotU32(call, 0)) return 0;
            DynarmicHostString string(SlotU32(call, 0));
            return GuestForCreatedObject(CFStringCreateWithCString(
                kCFAllocatorDefault, string.hostPtr,
                static_cast<CFStringEncoding>(SlotU32(call, 1))));
        }
        case LC32CoreFoundationOpStringCreateWithSubstring: {
            if(!RequireSlots(call, 3) ||
               SlotU32(call, 1) > INT32_MAX ||
               SlotU32(call, 2) > INT32_MAX) {
                return 0;
            }
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? GuestForCreatedObject(CFStringCreateWithSubstring(
                kCFAllocatorDefault, string,
                CFRangeMake(static_cast<CFIndex>(SlotU32(call, 1)),
                            static_cast<CFIndex>(SlotU32(call, 2))))) : 0;
        }
        case LC32CoreFoundationOpStringCreateArrayBySeparatingStrings: {
            if(!RequireSlots(call, 2)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef separator = SlotHostObject<CFStringRef>(call, 1);
            return string && separator ? GuestForCreatedObject(
                CFStringCreateArrayBySeparatingStrings(
                    kCFAllocatorDefault, string, separator)) : 0;
        }
        case LC32CoreFoundationOpStringGetCString: {
            if(!RequireSlots(call, 4)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            const u32 guestBuffer = SlotU32(call, 1);
            const u32 capacity = SlotU32(call, 2);
            if(!string || !guestBuffer || !capacity ||
               capacity > kMaximumCStringBytes ||
               guestBuffer > UINT32_MAX - capacity + 1) {
                return 0;
            }
            std::vector<char> buffer(capacity, 0);
            if(!CFStringGetCString(string, buffer.data(), capacity,
                    static_cast<CFStringEncoding>(SlotU32(call, 3)))) {
                return 0;
            }
            return Dynarmic_mem_1write(guestBuffer, capacity,
                buffer.data()) == 0;
        }
        case LC32CoreFoundationOpStringGetMaximumSizeForEncoding: {
            if(!RequireSlots(call, 2) || SlotU32(call, 0) > INT32_MAX)
                return UINT32_MAX;
            const CFIndex result = CFStringGetMaximumSizeForEncoding(
                static_cast<CFIndex>(SlotU32(call, 0)),
                static_cast<CFStringEncoding>(SlotU32(call, 1)));
            if(result < 0) return UINT32_MAX;
            return result > INT32_MAX ? INT32_MAX : static_cast<u32>(result);
        }
        case LC32CoreFoundationOpURLCreateStringByAddingPercentEscapes: {
            if(!RequireSlots(call, 4)) return 0;
            CFStringRef original = SlotHostObject<CFStringRef>(call, 0);
            if(!original) return 0;
            return GuestForCreatedObject(
                CFURLCreateStringByAddingPercentEscapes(
                    kCFAllocatorDefault, original,
                    SlotHostObject<CFStringRef>(call, 1),
                    SlotHostObject<CFStringRef>(call, 2),
                    static_cast<CFStringEncoding>(SlotU32(call, 3))));
        }
        case LC32CoreFoundationOpNumberGetValue:
            return DispatchNumberGetValue(call);
        case LC32CoreFoundationOpBundleGetMainBundle: {
            if(!RequireSlots(call, 0)) return 0;
            const char *guestExecutable = getenv("LC32_GUEST_EXECUTABLE");
            if(!guestExecutable || !guestExecutable[0]) return 0;
            NSString *executablePath = [NSString
                stringWithUTF8String:guestExecutable];
            NSBundle *bundle = [NSBundle bundleWithPath:
                executablePath.stringByDeletingLastPathComponent];
            return bundle ? bundle.guest_self : 0;
        }
        case LC32CoreFoundationOpRunLoopGetMain: {
            if(!RequireSlots(call, 0)) return 0;
            CFRunLoopRef runLoop = CFRunLoopGetMain();
            return runLoop ? [(id)runLoop guest_self] : 0;
        }
        case LC32CoreFoundationOpDictionaryGetValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const void *key = SlotHostObject<const void *>(call, 1);
            if(!dictionary || !key) return 0;
            const void *value = CFDictionaryGetValue(dictionary, key);
            return value ? [(id)value guest_self] : 0;
        }
        case LC32CoreFoundationOpDictionarySetValue: {
            if(!RequireSlots(call, 3)) return 0;
            CFMutableDictionaryRef dictionary =
                SlotHostObject<CFMutableDictionaryRef>(call, 0);
            const void *key = SlotHostObject<const void *>(call, 1);
            const void *value = SlotHostObject<const void *>(call, 2);
            if(dictionary && key && value)
                CFDictionarySetValue(dictionary, key, value);
            return 0;
        }
        case LC32CoreFoundationOpDictionaryRemoveValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableDictionaryRef dictionary =
                SlotHostObject<CFMutableDictionaryRef>(call, 0);
            const void *key = SlotHostObject<const void *>(call, 1);
            if(dictionary && key) CFDictionaryRemoveValue(dictionary, key);
            return 0;
        }
        case LC32CoreFoundationOpURLCreateFromFileSystemRepresentation: {
            if(!RequireSlots(call, 3)) return 0;
            const u32 guestBuffer = SlotU32(call, 0);
            const u32 length = SlotU32(call, 1);
            if(length >= PATH_MAX || (length && !guestBuffer) ||
               (length && static_cast<uint64_t>(guestBuffer) + length >
                    static_cast<uint64_t>(UINT32_MAX) + 1)) {
                return 0;
            }

            std::vector<char> guestPath(static_cast<size_t>(length) + 1, 0);
            if(length && Dynarmic_mem_1read(guestBuffer, length,
                    guestPath.data()) != 0) {
                return 0;
            }
            // File-system paths cannot contain an embedded NUL. Reject one
            // instead of silently translating a different prefix.
            if(memchr(guestPath.data(), '\0', length)) return 0;

            char hostPath[PATH_MAX] = {};
            if(!sharedHandle.fs ||
               !sharedHandle.fs->pathGuestToHost(
                    guestPath.data(), hostPath)) {
                return 0;
            }
            const size_t hostLength = strlen(hostPath);
            return GuestForCreatedObject(
                CFURLCreateFromFileSystemRepresentation(
                    kCFAllocatorDefault,
                    reinterpret_cast<const UInt8 *>(hostPath),
                    static_cast<CFIndex>(hostLength),
                    SlotU32(call, 2) != 0));
        }
    }
    return 0;
}

__END_DECLS

#pragma clang diagnostic pop
