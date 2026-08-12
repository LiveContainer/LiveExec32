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
constexpr uint32_t kMaximumDataBytes = 256u * 1024u * 1024u;
constexpr uint32_t kMaximumStringBytes = 64u * 1024u * 1024u;
constexpr uint32_t kMaximumUserInfoEntries = 1024u * 1024u;
constexpr uint32_t kMaximumSetEntries = 1024u * 1024u;

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

int32_t SlotS32(const LC32CoreFoundationCall &call, size_t index) {
    return static_cast<int32_t>(SlotU32(call, index));
}

double SlotDouble(const LC32CoreFoundationCall &call, size_t index) {
    double value;
    const uint64_t bits = call.slots[index];
    memcpy(&value, &bits, sizeof(value));
    return value;
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
        case LC32CoreFoundationCallbacksCopyString:
            break;
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
        case LC32CoreFoundationCallbacksCopyString:
            return &kCFCopyStringDictionaryKeyCallBacks;
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
        case LC32CoreFoundationCallbacksCopyString:
            break;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFDictionaryValueCallBacks *>(UINTPTR_MAX);
}

u32 GuestForCreatedObject(CFTypeRef object) {
    return LC32GuestObjectForOwnedHostObject(object);
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

bool GuestRangeIsValid(u32 address, u32 length) {
    return !length || (address &&
        static_cast<uint64_t>(address) + length <=
            static_cast<uint64_t>(UINT32_MAX) + 1);
}

template<typename T>
bool WriteGuestValue(u32 address, T value) {
    return GuestRangeIsValid(address, sizeof(value)) &&
        Dynarmic_mem_1write(address, sizeof(value),
            reinterpret_cast<char *>(&value)) == 0;
}

bool WriteGuestCreatedObject(u32 guestAddress, CFTypeRef object) {
    if(!guestAddress) {
        if(object) CFRelease(object);
        return true;
    }
    const u32 guestObject = GuestForCreatedObject(object);
    if(object && !guestObject) return false;
    return WriteGuestValue(guestAddress, guestObject);
}

bool ReadGuestHostObjects(u32 address, u32 count,
                          std::vector<const void *> &objects) {
    if(count > kMaximumUserInfoEntries) return false;
    const uint64_t byteCount = static_cast<uint64_t>(count) * sizeof(uint64_t);
    if(byteCount > UINT32_MAX ||
       !GuestRangeIsValid(address, static_cast<u32>(byteCount))) {
        return false;
    }

    std::vector<uint64_t> rawObjects(count);
    if(byteCount && Dynarmic_mem_1read(address, byteCount,
            reinterpret_cast<char *>(rawObjects.data())) != 0) {
        return false;
    }
    objects.resize(count);
    for(size_t index = 0; index < count; ++index) {
        objects[index] = reinterpret_cast<const void *>(
            static_cast<uintptr_t>(rawObjects[index]));
        if(!objects[index]) return false;
    }
    return true;
}

bool ReadGuestBytes(u32 address, u32 length, std::vector<UInt8> &bytes) {
    if(length > kMaximumDataBytes || !GuestRangeIsValid(address, length))
        return false;
    bytes.resize(length);
    return !length || Dynarmic_mem_1read(address, length,
        reinterpret_cast<char *>(bytes.data())) == 0;
}

bool ReadGuestStringBytes(u32 address, u32 length,
                          std::vector<UInt8> &bytes) {
    if(length > kMaximumStringBytes ||
       !GuestRangeIsValid(address, length)) return false;
    bytes.resize(length);
    return !length || Dynarmic_mem_1read(address, length,
        reinterpret_cast<char *>(bytes.data())) == 0;
}

bool ReadGuestCharacters(u32 address, u32 count,
                         std::vector<UniChar> &characters) {
    const uint64_t byteCount =
        static_cast<uint64_t>(count) * sizeof(UniChar);
    if(byteCount > kMaximumStringBytes ||
       !GuestRangeIsValid(address, static_cast<u32>(byteCount))) {
        return false;
    }
    characters.resize(count);
    return !byteCount || Dynarmic_mem_1read(address, byteCount,
        reinterpret_cast<char *>(characters.data())) == 0;
}

bool StringRangeIsValid(CFStringRef string, u32 location, u32 length) {
    if(!string || location > INT32_MAX || length > INT32_MAX) return false;
    const CFIndex stringLength = CFStringGetLength(string);
    return static_cast<CFIndex>(location) <= stringLength &&
        static_cast<CFIndex>(length) <=
            stringLength - static_cast<CFIndex>(location);
}

struct LC32GuestCFRange {
    int32_t location;
    int32_t length;
};

bool WriteGuestStringRange(u32 guestAddress, CFRange range) {
    if(!guestAddress) return true;
    const bool notFound = range.location == kCFNotFound;
    if((!notFound && (range.location < 0 || range.location > INT32_MAX)) ||
       range.length < 0 || range.length > INT32_MAX ||
       !GuestRangeIsValid(guestAddress, sizeof(LC32GuestCFRange))) {
        return false;
    }
    LC32GuestCFRange guestRange = {
        notFound ? INT32_MAX : static_cast<int32_t>(range.location),
        static_cast<int32_t>(range.length),
    };
    return Dynarmic_mem_1write(guestAddress, sizeof(guestRange),
        reinterpret_cast<char *>(&guestRange)) == 0;
}

bool WriteGuestCFIndex(u32 guestAddress, CFIndex value) {
    if(!guestAddress) return true;
    if(value < INT32_MIN || value > INT32_MAX ||
       !GuestRangeIsValid(guestAddress, sizeof(int32_t))) return false;
    int32_t guestValue = static_cast<int32_t>(value);
    return Dynarmic_mem_1write(guestAddress, sizeof(guestValue),
        reinterpret_cast<char *>(&guestValue)) == 0;
}

template<typename T>
u32 CreateNumberValue(CFNumberType hostType, u32 guestValue) {
    if(!GuestRangeIsValid(guestValue, sizeof(T))) return 0;
    T value = {};
    if(Dynarmic_mem_1read(guestValue, sizeof(value),
            reinterpret_cast<char *>(&value)) != 0) {
        return 0;
    }
    return GuestForCreatedObject(CFNumberCreate(
        kCFAllocatorDefault, hostType, &value));
}

u32 DispatchNumberCreate(const LC32CoreFoundationCall &call) {
    if(!RequireSlots(call, 2)) return 0;
    const auto type = static_cast<CFNumberType>(SlotU32(call, 0));
    const u32 value = SlotU32(call, 1);

    switch(type) {
        case kCFNumberSInt8Type:
        case kCFNumberCharType:
            return CreateNumberValue<int8_t>(kCFNumberSInt8Type, value);
        case kCFNumberSInt16Type:
        case kCFNumberShortType:
            return CreateNumberValue<int16_t>(kCFNumberSInt16Type, value);
        case kCFNumberSInt32Type:
        case kCFNumberIntType:
        case kCFNumberLongType:
        case kCFNumberCFIndexType:
        case kCFNumberNSIntegerType:
            return CreateNumberValue<int32_t>(kCFNumberSInt32Type, value);
        case kCFNumberSInt64Type:
        case kCFNumberLongLongType:
            return CreateNumberValue<int64_t>(kCFNumberSInt64Type, value);
        case kCFNumberFloat32Type:
        case kCFNumberFloatType:
        case kCFNumberCGFloatType:
            return CreateNumberValue<float>(kCFNumberFloat32Type, value);
        case kCFNumberFloat64Type:
        case kCFNumberDoubleType:
            return CreateNumberValue<double>(kCFNumberFloat64Type, value);
        default:
            return 0;
    }
}

CFTypeID KnownTypeID(uint32_t typeValue) {
    switch(static_cast<LC32CoreFoundationKnownType>(typeValue)) {
        case LC32CoreFoundationTypeArray:
            return CFArrayGetTypeID();
        case LC32CoreFoundationTypeBoolean:
            return CFBooleanGetTypeID();
        case LC32CoreFoundationTypeData:
            return CFDataGetTypeID();
        case LC32CoreFoundationTypeDate:
            return CFDateGetTypeID();
        case LC32CoreFoundationTypeDictionary:
            return CFDictionaryGetTypeID();
        case LC32CoreFoundationTypeNull:
            return CFNullGetTypeID();
        case LC32CoreFoundationTypeNumber:
            return CFNumberGetTypeID();
        case LC32CoreFoundationTypeSet:
            return CFSetGetTypeID();
        case LC32CoreFoundationTypeString:
            return CFStringGetTypeID();
    }
    return 0;
}

/*
 * CFBundle's native implementation returns a native function pointer, which
 * an ARM32 caller cannot execute. Load the corresponding guest image and ask
 * the guest dyld for its ARM32 symbol instead.
 */
u32 GuestBundleFunctionPointer(NSBundle *bundle, NSString *functionName) {
    if(!bundle || !functionName.length || !threadHandle.jit ||
       !sharedHandle.fs || !sharedHandle.guest_dlsym) {
        return 0;
    }

    const char *hostExecutable = bundle.executablePath.fileSystemRepresentation;
    if(!hostExecutable || !hostExecutable[0]) return 0;

    char guestExecutable[PATH_MAX] = {};
    if(!sharedHandle.fs->pathHostToGuest(
            hostExecutable, guestExecutable) || !guestExecutable[0]) {
        return 0;
    }

    const u32 guestDlopen = guest_dlsym("dlopen");
    if(!guestDlopen) return 0;

    DynarmicGuestStackString guestPath(guestExecutable);
    u32 dlopenArgs[] = {
        guestPath.guestPtr,
        static_cast<u32>(RTLD_LAZY | RTLD_LOCAL),
    };
    const u32 handle = static_cast<u32>(LC32InvokeGuestC(
        guestDlopen, false,
        sizeof(dlopenArgs) / sizeof(dlopenArgs[0]), dlopenArgs));
    if(!handle) return 0;

    const char *name = functionName.UTF8String;
    if(!name || !name[0]) return 0;
    DynarmicGuestStackString guestName(name);
    u32 dlsymArgs[] = { handle, guestName.guestPtr };
    return static_cast<u32>(LC32InvokeGuestC(
        sharedHandle.guest_dlsym, false,
        sizeof(dlsymArgs) / sizeof(dlsymArgs[0]), dlsymArgs));
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
        case LC32CoreFoundationOpStringCreateWithBytes: {
            if(!RequireSlots(call, 4) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            std::vector<UInt8> bytes;
            if(!ReadGuestStringBytes(SlotU32(call, 0), SlotU32(call, 1),
                                     bytes)) return 0;
            return GuestForCreatedObject(CFStringCreateWithBytes(
                kCFAllocatorDefault,
                bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                static_cast<CFStringEncoding>(SlotU32(call, 2)),
                SlotU32(call, 3) != 0));
        }
        case LC32CoreFoundationOpStringCreateWithCharacters: {
            if(!RequireSlots(call, 2) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            std::vector<UniChar> characters;
            if(!ReadGuestCharacters(SlotU32(call, 0), SlotU32(call, 1),
                                    characters)) return 0;
            return GuestForCreatedObject(CFStringCreateWithCharacters(
                kCFAllocatorDefault,
                characters.empty() ? nullptr : characters.data(),
                characters.size()));
        }
        case LC32CoreFoundationOpStringAppendCString: {
            if(!RequireSlots(call, 3) || !SlotU32(call, 1)) return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            if(!string) return 0;
            DynarmicHostString cString(SlotU32(call, 1));
            CFStringAppendCString(string, cString.hostPtr,
                static_cast<CFStringEncoding>(SlotU32(call, 2)));
            return 1;
        }
        case LC32CoreFoundationOpStringAppendCharacters: {
            if(!RequireSlots(call, 3) || SlotU32(call, 2) > INT32_MAX)
                return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            std::vector<UniChar> characters;
            if(!string || !ReadGuestCharacters(SlotU32(call, 1),
                    SlotU32(call, 2), characters)) return 0;
            if(!characters.empty()) CFStringAppendCharacters(
                string, characters.data(), characters.size());
            return 1;
        }
        case LC32CoreFoundationOpStringCompareWithOptions: {
            if(!RequireSlots(call, 5)) return 0;
            CFStringRef string1 = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef string2 = SlotHostObject<CFStringRef>(call, 1);
            const u32 location = SlotU32(call, 2);
            const u32 length = SlotU32(call, 3);
            if(!string2 || !StringRangeIsValid(string1, location, length))
                return 0;
            return static_cast<u32>(static_cast<int32_t>(
                CFStringCompareWithOptions(string1, string2,
                    CFRangeMake(location, length),
                    static_cast<CFStringCompareFlags>(SlotU32(call, 4)))));
        }
        case LC32CoreFoundationOpStringCreateExternalRepresentation: {
            if(!RequireSlots(call, 3)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? GuestForCreatedObject(
                CFStringCreateExternalRepresentation(kCFAllocatorDefault,
                    string,
                    static_cast<CFStringEncoding>(SlotU32(call, 1)),
                    static_cast<UInt8>(SlotU32(call, 2)))) : 0;
        }
        case LC32CoreFoundationOpStringCreateFromExternalRepresentation: {
            if(!RequireSlots(call, 2)) return 0;
            CFDataRef data = SlotHostObject<CFDataRef>(call, 0);
            return data ? GuestForCreatedObject(
                CFStringCreateFromExternalRepresentation(
                    kCFAllocatorDefault, data,
                    static_cast<CFStringEncoding>(SlotU32(call, 1)))) : 0;
        }
        case LC32CoreFoundationOpStringFindWithOptions: {
            if(!RequireSlots(call, 6)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef stringToFind =
                SlotHostObject<CFStringRef>(call, 1);
            const u32 location = SlotU32(call, 2);
            const u32 length = SlotU32(call, 3);
            if(!stringToFind || !StringRangeIsValid(string, location, length))
                return 0;
            CFRange result = CFRangeMake(kCFNotFound, 0);
            const Boolean found = CFStringFindWithOptions(
                string, stringToFind, CFRangeMake(location, length),
                static_cast<CFStringCompareFlags>(SlotU32(call, 4)),
                &result);
            if(found && !WriteGuestStringRange(SlotU32(call, 5), result))
                return 0;
            return found != false;
        }
        case LC32CoreFoundationOpStringFindCharacterFromSet: {
            if(!RequireSlots(call, 6)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            CFCharacterSetRef characterSet =
                SlotHostObject<CFCharacterSetRef>(call, 1);
            const u32 location = SlotU32(call, 2);
            const u32 length = SlotU32(call, 3);
            if(!characterSet || !StringRangeIsValid(string, location, length))
                return 0;
            CFRange result = CFRangeMake(kCFNotFound, 0);
            const Boolean found = CFStringFindCharacterFromSet(
                string, characterSet, CFRangeMake(location, length),
                static_cast<CFStringCompareFlags>(SlotU32(call, 4)),
                &result);
            if(found && !WriteGuestStringRange(SlotU32(call, 5), result))
                return 0;
            return found != false;
        }
        case LC32CoreFoundationOpStringFindAndReplace: {
            if(!RequireSlots(call, 6)) return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            CFStringRef stringToFind =
                SlotHostObject<CFStringRef>(call, 1);
            CFStringRef replacement =
                SlotHostObject<CFStringRef>(call, 2);
            const u32 location = SlotU32(call, 3);
            const u32 length = SlotU32(call, 4);
            if(!stringToFind || !replacement ||
               !StringRangeIsValid(string, location, length)) return 0;
            const CFIndex count = CFStringFindAndReplace(
                string, stringToFind, replacement,
                CFRangeMake(location, length),
                static_cast<CFStringCompareFlags>(SlotU32(call, 5)));
            return count > INT32_MAX ? INT32_MAX : static_cast<u32>(count);
        }
        case LC32CoreFoundationOpStringGetBytes: {
            if(!RequireSlots(call, 8)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            const u32 location = SlotU32(call, 1);
            const u32 length = SlotU32(call, 2);
            const u32 guestBuffer = SlotU32(call, 5);
            const u32 maximumLength = SlotU32(call, 6);
            const u32 guestUsedLength = SlotU32(call, 7);
            if(!StringRangeIsValid(string, location, length) ||
               maximumLength > kMaximumStringBytes ||
               (guestBuffer &&
                !GuestRangeIsValid(guestBuffer, maximumLength)) ||
               (guestUsedLength && !GuestRangeIsValid(
                    guestUsedLength, sizeof(int32_t)))) return 0;

            std::vector<UInt8> buffer(guestBuffer ? maximumLength : 0);
            CFIndex usedLength = 0;
            const u32 options = SlotU32(call, 4);
            const CFIndex converted = CFStringGetBytes(
                string, CFRangeMake(location, length),
                static_cast<CFStringEncoding>(SlotU32(call, 3)),
                static_cast<UInt8>(options & 0xff),
                (options & 0x100) != 0,
                buffer.empty() ? nullptr : buffer.data(),
                guestBuffer ? maximumLength : 0, &usedLength);
            if(converted < 0 || converted > INT32_MAX || usedLength < 0 ||
               (guestBuffer &&
                static_cast<uint64_t>(usedLength) > buffer.size()) ||
               !WriteGuestCFIndex(guestUsedLength, usedLength)) return 0;
            if(guestBuffer && usedLength && Dynarmic_mem_1write(
                    guestBuffer, usedLength,
                    reinterpret_cast<char *>(buffer.data())) != 0) {
                return 0;
            }
            return static_cast<u32>(converted);
        }
        case LC32CoreFoundationOpStringGetCharacterAtIndex: {
            if(!RequireSlots(call, 2)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            const u32 index = SlotU32(call, 1);
            if(!string || index > INT32_MAX ||
               static_cast<CFIndex>(index) >= CFStringGetLength(string))
                return 0;
            return CFStringGetCharacterAtIndex(string, index);
        }
        case LC32CoreFoundationOpStringGetCharacters: {
            if(!RequireSlots(call, 4)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            const u32 location = SlotU32(call, 1);
            const u32 length = SlotU32(call, 2);
            const u32 guestBuffer = SlotU32(call, 3);
            const uint64_t byteCount =
                static_cast<uint64_t>(length) * sizeof(UniChar);
            if(!StringRangeIsValid(string, location, length) ||
               byteCount > kMaximumStringBytes ||
               (byteCount && (!guestBuffer || !GuestRangeIsValid(
                    guestBuffer, static_cast<u32>(byteCount))))) return 0;
            if(!length) return 1;
            std::vector<UniChar> characters(length);
            CFStringGetCharacters(string, CFRangeMake(location, length),
                                  characters.data());
            return Dynarmic_mem_1write(guestBuffer, byteCount,
                reinterpret_cast<char *>(characters.data())) == 0;
        }
        case LC32CoreFoundationOpStringGetIntValue: {
            if(!RequireSlots(call, 1)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? static_cast<u32>(CFStringGetIntValue(string)) : 0;
        }
        case LC32CoreFoundationOpStringUppercase: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            if(!string) return 0;
            CFStringUppercase(string, SlotHostObject<CFLocaleRef>(call, 1));
            return 1;
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
        case LC32CoreFoundationOpBundleGetIdentifier: {
            if(!RequireSlots(call, 1)) return 0;
            NSBundle *bundle = SlotHostObject<NSBundle *>(call, 0);
            NSString *identifier = bundle.bundleIdentifier;
            return identifier ? identifier.guest_self : 0;
        }
        case LC32CoreFoundationOpBundleCopyLocalizedString: {
            if(!RequireSlots(call, 4)) return 0;
            NSBundle *bundle = SlotHostObject<NSBundle *>(call, 0);
            NSString *key = SlotHostObject<NSString *>(call, 1);
            if(!bundle || !key) return 0;
            NSString *localized = [bundle localizedStringForKey:key
                value:SlotHostObject<NSString *>(call, 2)
                table:SlotHostObject<NSString *>(call, 3)];
            return localized ? GuestForCreatedObject(
                reinterpret_cast<CFTypeRef>([localized copy])) : 0;
        }
        case LC32CoreFoundationOpBundleCopyResourceURL: {
            if(!RequireSlots(call, 4)) return 0;
            NSBundle *bundle = SlotHostObject<NSBundle *>(call, 0);
            NSString *resourceName =
                SlotHostObject<NSString *>(call, 1);
            if(!bundle || !resourceName) return 0;
            NSURL *url = [bundle URLForResource:resourceName
                withExtension:SlotHostObject<NSString *>(call, 2)
                subdirectory:SlotHostObject<NSString *>(call, 3)];
            return url ? GuestForCreatedObject(
                reinterpret_cast<CFTypeRef>([url copy])) : 0;
        }
        case LC32CoreFoundationOpBundleCreate: {
            if(!RequireSlots(call, 1)) return 0;
            NSURL *bundleURL = SlotHostObject<NSURL *>(call, 0);
            return bundleURL ? GuestForCreatedObject(
                reinterpret_cast<CFTypeRef>(
                    [[NSBundle alloc] initWithURL:bundleURL])) : 0;
        }
        case LC32CoreFoundationOpBundleGetBundleWithIdentifier: {
            if(!RequireSlots(call, 1)) return 0;
            NSString *identifier = SlotHostObject<NSString *>(call, 0);
            NSBundle *bundle = identifier
                ? [NSBundle bundleWithIdentifier:identifier] : nil;
            return bundle ? bundle.guest_self : 0;
        }
        case LC32CoreFoundationOpBundleGetFunctionPointerForName: {
            if(!RequireSlots(call, 2)) return 0;
            return GuestBundleFunctionPointer(
                SlotHostObject<NSBundle *>(call, 0),
                SlotHostObject<NSString *>(call, 1));
        }
        case LC32CoreFoundationOpRunLoopGetMain: {
            if(!RequireSlots(call, 0)) return 0;
            CFRunLoopRef runLoop = CFRunLoopGetMain();
            return runLoop ? [(id)runLoop guest_self] : 0;
        }
        case LC32CoreFoundationOpRunLoopGetCurrent: {
            if(!RequireSlots(call, 0)) return 0;
            CFRunLoopRef runLoop = CFRunLoopGetCurrent();
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
        case LC32CoreFoundationOpDictionaryContainsKey: {
            if(!RequireSlots(call, 2)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const void *key = SlotHostObject<const void *>(call, 1);
            return dictionary && key &&
                CFDictionaryContainsKey(dictionary, key);
        }
        case LC32CoreFoundationOpDictionaryGetCount: {
            if(!RequireSlots(call, 1)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            if(!dictionary) return 0;
            const CFIndex count = CFDictionaryGetCount(dictionary);
            return count > UINT32_MAX ? UINT32_MAX : static_cast<u32>(count);
        }
        case LC32CoreFoundationOpDictionaryGetKeysAndValues: {
            if(!RequireSlots(call, 3)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const u32 guestKeys = SlotU32(call, 1);
            const u32 guestValues = SlotU32(call, 2);
            if(!dictionary || (!guestKeys && !guestValues)) return 0;

            const CFIndex count = CFDictionaryGetCount(dictionary);
            if(count < 0 || static_cast<uint64_t>(count) >
                    UINT32_MAX / sizeof(u32)) {
                return 0;
            }
            const u32 byteCount = static_cast<u32>(count) * sizeof(u32);
            if((guestKeys && !GuestRangeIsValid(guestKeys, byteCount)) ||
               (guestValues && !GuestRangeIsValid(guestValues, byteCount))) {
                return 0;
            }

            std::vector<const void *> keys(guestKeys ? count : 0);
            std::vector<const void *> values(guestValues ? count : 0);
            CFDictionaryGetKeysAndValues(dictionary,
                guestKeys ? keys.data() : nullptr,
                guestValues ? values.data() : nullptr);

            std::vector<u32> guestObjects(count);
            if(guestKeys) {
                for(CFIndex index = 0; index < count; ++index) {
                    guestObjects[index] = keys[index]
                        ? [(id)keys[index] guest_self] : 0;
                    if(keys[index] && !guestObjects[index]) return 0;
                }
                if(byteCount && Dynarmic_mem_1write(guestKeys, byteCount,
                        reinterpret_cast<char *>(guestObjects.data())) != 0) {
                    return 0;
                }
            }
            if(guestValues) {
                for(CFIndex index = 0; index < count; ++index) {
                    guestObjects[index] = values[index]
                        ? [(id)values[index] guest_self] : 0;
                    if(values[index] && !guestObjects[index]) return 0;
                }
                if(byteCount && Dynarmic_mem_1write(guestValues, byteCount,
                        reinterpret_cast<char *>(guestObjects.data())) != 0) {
                    return 0;
                }
            }
            return 1;
        }
        case LC32CoreFoundationOpDataCreate: {
            if(!RequireSlots(call, 2)) return 0;
            std::vector<UInt8> bytes;
            if(!ReadGuestBytes(SlotU32(call, 0), SlotU32(call, 1), bytes))
                return 0;
            return GuestForCreatedObject(CFDataCreate(kCFAllocatorDefault,
                bytes.empty() ? nullptr : bytes.data(), bytes.size()));
        }
        case LC32CoreFoundationOpDataCreateCopy: {
            if(!RequireSlots(call, 1)) return 0;
            CFDataRef data = SlotHostObject<CFDataRef>(call, 0);
            return data ? GuestForCreatedObject(CFDataCreateCopy(
                kCFAllocatorDefault, data)) : 0;
        }
        case LC32CoreFoundationOpDataCreateMutable: {
            if(!RequireSlots(call, 1) ||
               SlotU32(call, 0) > kMaximumDataBytes) return 0;
            return GuestForCreatedObject(CFDataCreateMutable(
                kCFAllocatorDefault, SlotU32(call, 0)));
        }
        case LC32CoreFoundationOpDataCreateMutableCopy: {
            if(!RequireSlots(call, 2) ||
               SlotU32(call, 0) > kMaximumDataBytes) return 0;
            CFDataRef data = SlotHostObject<CFDataRef>(call, 1);
            return data ? GuestForCreatedObject(CFDataCreateMutableCopy(
                kCFAllocatorDefault, SlotU32(call, 0), data)) : 0;
        }
        case LC32CoreFoundationOpDataAppendBytes: {
            if(!RequireSlots(call, 3)) return 0;
            CFMutableDataRef data =
                SlotHostObject<CFMutableDataRef>(call, 0);
            std::vector<UInt8> bytes;
            if(!data || !ReadGuestBytes(SlotU32(call, 1),
                    SlotU32(call, 2), bytes)) return 0;
            const CFIndex oldLength = CFDataGetLength(data);
            if(oldLength < 0 || static_cast<uint64_t>(oldLength) +
                    bytes.size() > kMaximumDataBytes) return 0;
            CFDataAppendBytes(data,
                bytes.empty() ? nullptr : bytes.data(), bytes.size());
            return 1;
        }
        case LC32CoreFoundationOpDataDeleteBytes: {
            if(!RequireSlots(call, 3)) return 0;
            CFMutableDataRef data =
                SlotHostObject<CFMutableDataRef>(call, 0);
            const CFRange range = CFRangeMake(
                SlotU32(call, 1), SlotU32(call, 2));
            const CFIndex length = data ? CFDataGetLength(data) : 0;
            if(!data || range.location > length ||
               range.length > length - range.location) return 0;
            CFDataDeleteBytes(data, range);
            return 1;
        }
        case LC32CoreFoundationOpDataIncreaseLength: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableDataRef data =
                SlotHostObject<CFMutableDataRef>(call, 0);
            const CFIndex length = data ? CFDataGetLength(data) : 0;
            if(!data || length < 0 || static_cast<uint64_t>(length) +
                    SlotU32(call, 1) > kMaximumDataBytes) return 0;
            CFDataIncreaseLength(data, SlotU32(call, 1));
            return 1;
        }
        case LC32CoreFoundationOpDataReplaceBytes: {
            if(!RequireSlots(call, 5)) return 0;
            CFMutableDataRef data =
                SlotHostObject<CFMutableDataRef>(call, 0);
            const CFRange range = CFRangeMake(
                SlotU32(call, 1), SlotU32(call, 2));
            const CFIndex length = data ? CFDataGetLength(data) : 0;
            std::vector<UInt8> bytes;
            if(!data || range.location > length ||
               range.length > length - range.location ||
               !ReadGuestBytes(SlotU32(call, 3), SlotU32(call, 4), bytes) ||
               static_cast<uint64_t>(length - range.length) + bytes.size() >
                    kMaximumDataBytes) return 0;
            CFDataReplaceBytes(data, range,
                bytes.empty() ? nullptr : bytes.data(), bytes.size());
            return 1;
        }
        case LC32CoreFoundationOpDataSetLength: {
            if(!RequireSlots(call, 2) ||
               SlotU32(call, 1) > kMaximumDataBytes) return 0;
            CFMutableDataRef data =
                SlotHostObject<CFMutableDataRef>(call, 0);
            if(!data) return 0;
            CFDataSetLength(data, SlotU32(call, 1));
            return 1;
        }
        case LC32CoreFoundationOpSetCreate: {
            if(!RequireSlots(call, 2) ||
               SlotU32(call, 1) > kMaximumSetEntries) return 0;
            std::vector<const void *> values;
            if(!ReadGuestHostObjects(SlotU32(call, 0),
                                     SlotU32(call, 1), values)) return 0;
            return GuestForCreatedObject(CFSetCreate(
                kCFAllocatorDefault,
                values.empty() ? nullptr : values.data(), values.size(),
                &kCFTypeSetCallBacks));
        }
        case LC32CoreFoundationOpSetCreateCopy: {
            if(!RequireSlots(call, 1)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            return set ? GuestForCreatedObject(CFSetCreateCopy(
                kCFAllocatorDefault, set)) : 0;
        }
        case LC32CoreFoundationOpSetCreateMutable: {
            if(!RequireSlots(call, 1) ||
               SlotU32(call, 0) > kMaximumSetEntries) return 0;
            return GuestForCreatedObject(CFSetCreateMutable(
                kCFAllocatorDefault, SlotU32(call, 0),
                &kCFTypeSetCallBacks));
        }
        case LC32CoreFoundationOpSetCreateMutableCopy: {
            if(!RequireSlots(call, 2) ||
               SlotU32(call, 0) > kMaximumSetEntries) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 1);
            return set ? GuestForCreatedObject(CFSetCreateMutableCopy(
                kCFAllocatorDefault, SlotU32(call, 0), set)) : 0;
        }
        case LC32CoreFoundationOpSetGetCount: {
            if(!RequireSlots(call, 1)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            if(!set) return 0;
            const CFIndex count = CFSetGetCount(set);
            if(count < 0) return 0;
            return count > INT32_MAX
                ? INT32_MAX : static_cast<u32>(count);
        }
        case LC32CoreFoundationOpSetGetValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            const void *candidate =
                SlotHostObject<const void *>(call, 1);
            if(!set || !candidate) return 0;
            const void *value = CFSetGetValue(set, candidate);
            return value ? [(id)value guest_self] : 0;
        }
        case LC32CoreFoundationOpSetGetValues: {
            if(!RequireSlots(call, 2)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            const u32 guestValues = SlotU32(call, 1);
            if(!set || !guestValues) return 0;

            const CFIndex count = CFSetGetCount(set);
            if(count < 0 ||
               static_cast<uint64_t>(count) > kMaximumSetEntries ||
               static_cast<uint64_t>(count) > UINT32_MAX / sizeof(u32)) {
                return 0;
            }
            const u32 byteCount = static_cast<u32>(count) * sizeof(u32);
            if(!GuestRangeIsValid(guestValues, byteCount)) return 0;

            std::vector<const void *> values(count);
            if(count) CFSetGetValues(set, values.data());
            std::vector<u32> guestObjects(count);
            for(CFIndex index = 0; index < count; ++index) {
                if(!values[index] ||
                   !(guestObjects[index] = [(id)values[index] guest_self])) {
                    return 0;
                }
            }
            return !byteCount || Dynarmic_mem_1write(
                guestValues, byteCount,
                reinterpret_cast<char *>(guestObjects.data())) == 0;
        }
        case LC32CoreFoundationOpSetContainsValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            const void *value = SlotHostObject<const void *>(call, 1);
            return set && value && CFSetContainsValue(set, value);
        }
        case LC32CoreFoundationOpSetAddValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableSetRef set =
                SlotHostObject<CFMutableSetRef>(call, 0);
            const void *value = SlotHostObject<const void *>(call, 1);
            if(set && value) CFSetAddValue(set, value);
            return 0;
        }
        case LC32CoreFoundationOpSetSetValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableSetRef set =
                SlotHostObject<CFMutableSetRef>(call, 0);
            const void *value = SlotHostObject<const void *>(call, 1);
            if(set && value) CFSetSetValue(set, value);
            return 0;
        }
        case LC32CoreFoundationOpSetRemoveValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableSetRef set =
                SlotHostObject<CFMutableSetRef>(call, 0);
            const void *value = SlotHostObject<const void *>(call, 1);
            if(set && value) CFSetRemoveValue(set, value);
            return 0;
        }
        case LC32CoreFoundationOpSetRemoveAllValues: {
            if(!RequireSlots(call, 1)) return 0;
            CFMutableSetRef set =
                SlotHostObject<CFMutableSetRef>(call, 0);
            if(set) CFSetRemoveAllValues(set);
            return 0;
        }
        case LC32CoreFoundationOpGetTypeID: {
            if(!RequireSlots(call, 1)) return 0;
            CFTypeRef object = SlotHostObject<CFTypeRef>(call, 0);
            return object ? static_cast<u32>(CFGetTypeID(object)) : 0;
        }
        case LC32CoreFoundationOpGetKnownTypeID:
            return RequireSlots(call, 1)
                ? static_cast<u32>(KnownTypeID(SlotU32(call, 0))) : 0;
        case LC32CoreFoundationOpNumberCreate:
            return DispatchNumberCreate(call);
        case LC32CoreFoundationOpDateCreate: {
            if(!RequireSlots(call, 1)) return 0;
            return GuestForCreatedObject(CFDateCreate(
                kCFAllocatorDefault, SlotDouble(call, 0)));
        }
        case LC32CoreFoundationOpDateGetAbsoluteTime: {
            if(!RequireSlots(call, 2)) return 0;
            CFDateRef date = SlotHostObject<CFDateRef>(call, 0);
            if(!date) return 0;
            const CFAbsoluteTime result = CFDateGetAbsoluteTime(date);
            return WriteGuestValue(SlotU32(call, 1), result);
        }
        case LC32CoreFoundationOpDateGetTimeIntervalSinceDate: {
            if(!RequireSlots(call, 3)) return 0;
            CFDateRef date = SlotHostObject<CFDateRef>(call, 0);
            CFDateRef otherDate = SlotHostObject<CFDateRef>(call, 1);
            if(!date || !otherDate) return 0;
            const CFTimeInterval result =
                CFDateGetTimeIntervalSinceDate(date, otherDate);
            return WriteGuestValue(SlotU32(call, 2), result);
        }
        case LC32CoreFoundationOpDateCompare: {
            if(!RequireSlots(call, 2)) return 0;
            CFDateRef date = SlotHostObject<CFDateRef>(call, 0);
            CFDateRef otherDate = SlotHostObject<CFDateRef>(call, 1);
            return date && otherDate ? static_cast<u32>(
                static_cast<int32_t>(CFDateCompare(
                    date, otherDate, nullptr))) : 0;
        }
        case LC32CoreFoundationOpDateFormatterCreate: {
            if(!RequireSlots(call, 3)) return 0;
            return GuestForCreatedObject(CFDateFormatterCreate(
                kCFAllocatorDefault,
                SlotHostObject<CFLocaleRef>(call, 0),
                static_cast<CFDateFormatterStyle>(SlotU32(call, 1)),
                static_cast<CFDateFormatterStyle>(SlotU32(call, 2))));
        }
        case LC32CoreFoundationOpDateFormatterSetFormat: {
            if(!RequireSlots(call, 2)) return 0;
            CFDateFormatterRef formatter =
                SlotHostObject<CFDateFormatterRef>(call, 0);
            CFStringRef format = SlotHostObject<CFStringRef>(call, 1);
            if(!formatter || !format) return 0;
            CFDateFormatterSetFormat(formatter, format);
            return 1;
        }
        case LC32CoreFoundationOpDateFormatterCreateStringWithAbsoluteTime: {
            if(!RequireSlots(call, 2)) return 0;
            CFDateFormatterRef formatter =
                SlotHostObject<CFDateFormatterRef>(call, 0);
            return formatter ? GuestForCreatedObject(
                CFDateFormatterCreateStringWithAbsoluteTime(
                    kCFAllocatorDefault, formatter,
                    SlotDouble(call, 1))) : 0;
        }
        case LC32CoreFoundationOpErrorCreate: {
            if(!RequireSlots(call, 3)) return 0;
            CFErrorDomain domain =
                SlotHostObject<CFErrorDomain>(call, 0);
            if(!domain) return 0;
            return GuestForCreatedObject(CFErrorCreate(
                kCFAllocatorDefault, domain, SlotS32(call, 1),
                SlotHostObject<CFDictionaryRef>(call, 2)));
        }
        case LC32CoreFoundationOpErrorCreateWithUserInfoKeysAndValues: {
            if(!RequireSlots(call, 5)) return 0;
            CFErrorDomain domain =
                SlotHostObject<CFErrorDomain>(call, 0);
            const u32 count = SlotU32(call, 4);
            std::vector<const void *> keys;
            std::vector<const void *> values;
            if(!domain ||
               !ReadGuestHostObjects(SlotU32(call, 2), count, keys) ||
               !ReadGuestHostObjects(SlotU32(call, 3), count, values)) {
                return 0;
            }
            return GuestForCreatedObject(
                CFErrorCreateWithUserInfoKeysAndValues(
                    kCFAllocatorDefault, domain, SlotS32(call, 1),
                    keys.empty() ? nullptr : keys.data(),
                    values.empty() ? nullptr : values.data(), count));
        }
        case LC32CoreFoundationOpErrorGetDomain: {
            if(!RequireSlots(call, 1)) return 0;
            CFErrorRef error = SlotHostObject<CFErrorRef>(call, 0);
            CFErrorDomain domain = error ? CFErrorGetDomain(error) : nullptr;
            return domain ? [(id)domain guest_self] : 0;
        }
        case LC32CoreFoundationOpErrorGetCode: {
            if(!RequireSlots(call, 1)) return 0;
            CFErrorRef error = SlotHostObject<CFErrorRef>(call, 0);
            return error ? static_cast<u32>(static_cast<int32_t>(
                CFErrorGetCode(error))) : 0;
        }
        case LC32CoreFoundationOpErrorCopyUserInfo: {
            if(!RequireSlots(call, 1)) return 0;
            CFErrorRef error = SlotHostObject<CFErrorRef>(call, 0);
            return error ? GuestForCreatedObject(
                CFErrorCopyUserInfo(error)) : 0;
        }
        case LC32CoreFoundationOpErrorCopyDescription: {
            if(!RequireSlots(call, 1)) return 0;
            CFErrorRef error = SlotHostObject<CFErrorRef>(call, 0);
            return error ? GuestForCreatedObject(
                CFErrorCopyDescription(error)) : 0;
        }
        case LC32CoreFoundationOpLocaleCopyCurrent: {
            if(!RequireSlots(call, 0)) return 0;
            return GuestForCreatedObject(CFLocaleCopyCurrent());
        }
        case LC32CoreFoundationOpPreferencesCopyAppValue: {
            if(!RequireSlots(call, 2)) return 0;
            CFStringRef key = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef applicationID =
                SlotHostObject<CFStringRef>(call, 1);
            return key && applicationID ? GuestForCreatedObject(
                CFPreferencesCopyAppValue(key, applicationID)) : 0;
        }
        case LC32CoreFoundationOpPreferencesGetAppBooleanValue: {
            if(!RequireSlots(call, 3)) return 0;
            CFStringRef key = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef applicationID =
                SlotHostObject<CFStringRef>(call, 1);
            if(!key || !applicationID) return 0;
            Boolean exists = false;
            const Boolean result = CFPreferencesGetAppBooleanValue(
                key, applicationID, &exists);
            const u32 guestExists = SlotU32(call, 2);
            if(guestExists && !WriteGuestValue(guestExists, exists)) return 0;
            return result != false;
        }
        case LC32CoreFoundationOpPreferencesGetAppIntegerValue: {
            if(!RequireSlots(call, 3)) return 0;
            CFStringRef key = SlotHostObject<CFStringRef>(call, 0);
            CFStringRef applicationID =
                SlotHostObject<CFStringRef>(call, 1);
            if(!key || !applicationID) return 0;
            Boolean exists = false;
            const CFIndex result = CFPreferencesGetAppIntegerValue(
                key, applicationID, &exists);
            const u32 guestExists = SlotU32(call, 2);
            if(guestExists && !WriteGuestValue(guestExists, exists)) return 0;
            return static_cast<u32>(static_cast<int32_t>(result));
        }
        case LC32CoreFoundationOpPropertyListCreateWithData: {
            if(!RequireSlots(call, 5)) return 0;
            std::vector<UInt8> bytes;
            if(!ReadGuestBytes(SlotU32(call, 0), SlotU32(call, 1),
                               bytes)) {
                return 0;
            }
            const u32 guestFormat = SlotU32(call, 3);
            const u32 guestError = SlotU32(call, 4);
            if((guestFormat && !GuestRangeIsValid(
                    guestFormat, sizeof(int32_t))) ||
               (guestError && !GuestRangeIsValid(
                    guestError, sizeof(u32)))) {
                return 0;
            }

            CFDataRef data = CFDataCreate(
                kCFAllocatorDefault,
                bytes.empty() ? nullptr : bytes.data(), bytes.size());
            if(!data) return 0;
            CFPropertyListFormat format =
                static_cast<CFPropertyListFormat>(0);
            CFErrorRef error = nullptr;
            CFPropertyListRef propertyList = CFPropertyListCreateWithData(
                kCFAllocatorDefault, data,
                static_cast<CFOptionFlags>(SlotU32(call, 2)),
                guestFormat ? &format : nullptr,
                guestError ? &error : nullptr);
            CFRelease(data);

            if(guestFormat) {
                if(format < INT32_MIN || format > INT32_MAX ||
                   !WriteGuestValue(guestFormat,
                       static_cast<int32_t>(format))) {
                    if(propertyList) CFRelease(propertyList);
                    if(error) CFRelease(error);
                    return 0;
                }
            }
            if(guestError &&
               !WriteGuestCreatedObject(guestError, error)) {
                if(propertyList) CFRelease(propertyList);
                return 0;
            }
            return GuestForCreatedObject(propertyList);
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
