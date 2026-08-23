@import CoreFoundation;
@import Foundation;

#include "bridge.h"
#include "../../GuestFrameworks/CoreFoundation/LC32CoreFoundationBridge.h"

#include <atomic>
#include <climits>
#include <cstdint>
#include <cstring>
#include <new>
#include <vector>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace {

constexpr uint32_t kMaximumCStringBytes = 64u * 1024u * 1024u;
constexpr uint32_t kMaximumDataBytes = 256u * 1024u * 1024u;
constexpr uint32_t kMaximumStringBytes = 64u * 1024u * 1024u;
constexpr uint32_t kMaximumUserInfoEntries = 1024u * 1024u;
constexpr uint32_t kMaximumSetEntries = 1024u * 1024u;
constexpr uint32_t kMaximumReadStreamBytes = 64u * 1024u * 1024u;
constexpr uint32_t kMaximumWriteStreamBytes = 64u * 1024u * 1024u;

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
        case LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual:
            break;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFArrayCallBacks *>(UINTPTR_MAX);
}

const CFSetCallBacks *SetCallbacks(uint32_t mode) {
    switch(static_cast<LC32CoreFoundationCallbacksMode>(mode)) {
        case LC32CoreFoundationCallbacksCFType:
            return &kCFTypeSetCallBacks;
        case LC32CoreFoundationCallbacksNull:
            return nullptr;
        case LC32CoreFoundationCallbacksWeakCFType:
        case LC32CoreFoundationCallbacksWeakCFTypeNoDescription:
        case LC32CoreFoundationCallbacksCopyString:
        case LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual:
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFSetCallBacks *>(UINTPTR_MAX);
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
        case LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual:
            break;
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
    static const CFDictionaryValueCallBacks retainedObjectCallbacks = {
        0,
        [](CFAllocatorRef, const void *value) -> const void * {
            return CFRetain(static_cast<CFTypeRef>(value));
        },
        [](CFAllocatorRef, const void *value) {
            CFRelease(static_cast<CFTypeRef>(value));
        },
        nullptr,
        nullptr,
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
        case LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual:
            return &retainedObjectCallbacks;
        case LC32CoreFoundationCallbacksInvalid:
            break;
    }
    return reinterpret_cast<const CFDictionaryValueCallBacks *>(UINTPTR_MAX);
}

bool DictionaryCallbacksModeIsValid(uint32_t mode) {
    switch(static_cast<LC32CoreFoundationCallbacksMode>(mode)) {
        case LC32CoreFoundationCallbacksCFType:
        case LC32CoreFoundationCallbacksNull:
        case LC32CoreFoundationCallbacksWeakCFType:
        case LC32CoreFoundationCallbacksWeakCFTypeNoDescription:
        case LC32CoreFoundationCallbacksCopyString:
        case LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual:
            return true;
        case LC32CoreFoundationCallbacksInvalid:
            return false;
    }
    return false;
}

const void *DictionaryOperand(
        const LC32CoreFoundationCall &call,
        size_t modeIndex, size_t valueIndex) {
    const uint32_t mode = SlotU32(call, modeIndex);
    if(!DictionaryCallbacksModeIsValid(mode)) return nullptr;
    if(mode == LC32CoreFoundationCallbacksNull) {
        return reinterpret_cast<const void *>(
            static_cast<uintptr_t>(SlotU32(call, valueIndex)));
    }
    return SlotHostObject<const void *>(call, valueIndex);
}

u32 GuestDictionaryOperand(
        const void *value, uint32_t mode) {
    if(!value || !DictionaryCallbacksModeIsValid(mode)) return 0;
    if(mode == LC32CoreFoundationCallbacksNull) {
        const uintptr_t raw = reinterpret_cast<uintptr_t>(value);
        return raw <= UINT32_MAX ? static_cast<u32>(raw) : 0;
    }
    return [(id)value guest_self];
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

bool AttributedStringRangeIsValid(CFAttributedStringRef string,
                                  int32_t location, int32_t length) {
    if(!string || location < 0 || length < 0) return false;
    const CFIndex stringLength = CFAttributedStringGetLength(string);
    return static_cast<CFIndex>(location) <= stringLength &&
        static_cast<CFIndex>(length) <=
            stringLength - static_cast<CFIndex>(location);
}

struct LC32GuestCFRange {
    int32_t location;
    int32_t length;
};

struct LC32GuestCFStreamError {
    int32_t domain;
    int32_t error;
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

bool InvokeGuestVoidFunction(u32 function, const u32 *arguments,
                             size_t argumentCount) {
    if(!function || argumentCount >
            LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS) {
        return false;
    }
    if(Dynarmic_guest_thread_is_registered()) {
        (void)LC32InvokeGuestC(function, false,
            static_cast<int>(argumentCount),
            const_cast<u32 *>(arguments));
        return true;
    }

    LC32GuestBlockCallbackDescriptor descriptor = {};
    descriptor.kind = LC32GuestBlockCallbackKindFunction;
    descriptor.guestInvoke = function;
    descriptor.argumentCount = static_cast<uint32_t>(argumentCount);
    descriptor.resultKind = LC32GuestBlockValueVoid;
    for(size_t index = 0; index < argumentCount; ++index) {
        descriptor.arguments[index].kind = LC32GuestBlockValueUnsigned32;
        descriptor.arguments[index].value = arguments[index];
    }
    return Dynarmic_submit_guest_function_callback(&descriptor);
}

struct ReadStreamClientContext {
    std::atomic<uint32_t> referenceCount{1};
    u32 guestStream = 0;
    u32 guestCallback = 0;
    u32 guestInfo = 0;
    u32 guestRelease = 0;
    u32 guestCopyDescription = 0;
};

void *RetainReadStreamClientContext(void *rawContext) {
    ReadStreamClientContext *context =
        static_cast<ReadStreamClientContext *>(rawContext);
    if(context) context->referenceCount.fetch_add(
        1, std::memory_order_relaxed);
    return context;
}

void ReleaseReadStreamClientContext(void *rawContext) {
    ReadStreamClientContext *context =
        static_cast<ReadStreamClientContext *>(rawContext);
    if(!context || context->referenceCount.fetch_sub(
            1, std::memory_order_acq_rel) != 1) {
        return;
    }

    if(context->guestRelease) {
        const u32 arguments[] = {context->guestInfo};
        if(!InvokeGuestVoidFunction(
                context->guestRelease, arguments, 1)) {
            /* Never borrow another native thread's JIT. During teardown the
             * serialized executor may already be gone, in which case the
             * retained guest context is intentionally leaked with the
             * exiting process instead of executing it unsafely. */
            fprintf(stderr,
                "LC32: could not dispatch CFReadStream context release "
                "0x%08x\n", context->guestRelease);
        }
    }
    delete context;
}

CFStringRef CopyReadStreamClientContextDescription(
        void *rawContext) {
    const ReadStreamClientContext *context =
        static_cast<const ReadStreamClientContext *>(rawContext);
    if(!context) return CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("LC32 CFReadStream client"));

    /* CF invokes this diagnostic hook from arbitrary threads and expects a
     * synchronous owned string. The guest callback executor currently only
     * transports void C callbacks, so return a useful native description
     * without ever invoking guest code on the calling thread. */
    return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
        CFSTR("LC32 CFReadStream client callback=0x%08x info=0x%08x "
              "description=0x%08x"),
        context->guestCallback, context->guestInfo,
        context->guestCopyDescription);
}

void ReadStreamClientCallback(CFReadStreamRef,
                              CFStreamEventType eventType,
                              void *rawContext) {
    ReadStreamClientContext *context =
        static_cast<ReadStreamClientContext *>(rawContext);
    if(!context || !context->guestCallback) return;
    const u32 arguments[] = {
        context->guestStream,
        static_cast<u32>(eventType),
        context->guestInfo,
    };
    if(!InvokeGuestVoidFunction(
            context->guestCallback, arguments, 3)) {
        fprintf(stderr,
            "LC32: could not dispatch CFReadStream client callback "
            "0x%08x\n", context->guestCallback);
    }
}

struct WriteStreamClientContext {
    std::atomic<uint32_t> referenceCount{1};
    u32 guestStream = 0;
    u32 guestCallback = 0;
    u32 guestInfo = 0;
    u32 guestRelease = 0;
    u32 guestCopyDescription = 0;
};

void *RetainWriteStreamClientContext(void *rawContext) {
    WriteStreamClientContext *context =
        static_cast<WriteStreamClientContext *>(rawContext);
    if(context) context->referenceCount.fetch_add(
        1, std::memory_order_relaxed);
    return context;
}

void ReleaseWriteStreamClientContext(void *rawContext) {
    WriteStreamClientContext *context =
        static_cast<WriteStreamClientContext *>(rawContext);
    if(!context || context->referenceCount.fetch_sub(
            1, std::memory_order_acq_rel) != 1) {
        return;
    }

    if(context->guestRelease) {
        const u32 arguments[] = {context->guestInfo};
        if(!InvokeGuestVoidFunction(
                context->guestRelease, arguments, 1)) {
            fprintf(stderr,
                "LC32: could not dispatch CFWriteStream context release "
                "0x%08x\n", context->guestRelease);
        }
    }
    delete context;
}

CFStringRef CopyWriteStreamClientContextDescription(
        void *rawContext) {
    const WriteStreamClientContext *context =
        static_cast<const WriteStreamClientContext *>(rawContext);
    if(!context) return CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("LC32 CFWriteStream client"));

    return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
        CFSTR("LC32 CFWriteStream client callback=0x%08x info=0x%08x "
              "description=0x%08x"),
        context->guestCallback, context->guestInfo,
        context->guestCopyDescription);
}

void WriteStreamClientCallback(CFWriteStreamRef,
                               CFStreamEventType eventType,
                               void *rawContext) {
    WriteStreamClientContext *context =
        static_cast<WriteStreamClientContext *>(rawContext);
    if(!context || !context->guestCallback) return;
    const u32 arguments[] = {
        context->guestStream,
        static_cast<u32>(eventType),
        context->guestInfo,
    };
    if(!InvokeGuestVoidFunction(
            context->guestCallback, arguments, 3)) {
        fprintf(stderr,
            "LC32: could not dispatch CFWriteStream client callback "
            "0x%08x\n", context->guestCallback);
    }
}

struct RunLoopTimerClientContext {
    std::atomic<uint32_t> referenceCount{1};
    std::atomic<u32> guestTimer{0};
    u32 guestCallback = 0;
    u32 guestInfo = 0;
    u32 guestRelease = 0;
    u32 guestCopyDescription = 0;
};

const void *RetainRunLoopTimerClientContext(const void *rawContext) {
    RunLoopTimerClientContext *context =
        const_cast<RunLoopTimerClientContext *>(
            static_cast<const RunLoopTimerClientContext *>(rawContext));
    if(context) context->referenceCount.fetch_add(
        1, std::memory_order_relaxed);
    return context;
}

void ReleaseRunLoopTimerClientContext(const void *rawContext) {
    RunLoopTimerClientContext *context =
        const_cast<RunLoopTimerClientContext *>(
            static_cast<const RunLoopTimerClientContext *>(rawContext));
    if(!context || context->referenceCount.fetch_sub(
            1, std::memory_order_acq_rel) != 1) {
        return;
    }

    if(context->guestRelease) {
        const u32 arguments[] = {context->guestInfo};
        if(!InvokeGuestVoidFunction(
                context->guestRelease, arguments, 1)) {
            fprintf(stderr,
                "LC32: could not dispatch CFRunLoopTimer context release "
                "0x%08x\n", context->guestRelease);
        }
    }
    delete context;
}

CFStringRef CopyRunLoopTimerClientContextDescription(
        const void *rawContext) {
    const RunLoopTimerClientContext *context =
        static_cast<const RunLoopTimerClientContext *>(rawContext);
    if(!context) return CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("LC32 CFRunLoopTimer client"));

    /* CoreFoundation may ask from an arbitrary native thread. The existing
     * serialized C callback executor intentionally transports void calls, so
     * provide a native owned diagnostic string without borrowing a guest JIT. */
    return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
        CFSTR("LC32 CFRunLoopTimer callback=0x%08x info=0x%08x "
              "description=0x%08x"),
        context->guestCallback, context->guestInfo,
        context->guestCopyDescription);
}

void RunLoopTimerClientCallback(CFRunLoopTimerRef,
                                void *rawContext) {
    RunLoopTimerClientContext *context =
        static_cast<RunLoopTimerClientContext *>(rawContext);
    if(!context || !context->guestCallback) return;
    const u32 guestTimer = context->guestTimer.load(
        std::memory_order_acquire);
    if(!guestTimer) return;
    const u32 arguments[] = {guestTimer, context->guestInfo};
    if(!InvokeGuestVoidFunction(
            context->guestCallback, arguments, 2)) {
        fprintf(stderr,
            "LC32: could not dispatch CFRunLoopTimer callback 0x%08x\n",
            context->guestCallback);
    }
}

struct RunLoopSourceClientContext {
    std::atomic<uint32_t> referenceCount{1};
    u32 guestPerform = 0;
    u32 guestInfo = 0;
    u32 guestRelease = 0;
    u32 guestCopyDescription = 0;
};

const void *RetainRunLoopSourceClientContext(const void *rawContext) {
    RunLoopSourceClientContext *context =
        const_cast<RunLoopSourceClientContext *>(
            static_cast<const RunLoopSourceClientContext *>(rawContext));
    if(context) context->referenceCount.fetch_add(
        1, std::memory_order_relaxed);
    return context;
}

void ReleaseRunLoopSourceClientContext(const void *rawContext) {
    RunLoopSourceClientContext *context =
        const_cast<RunLoopSourceClientContext *>(
            static_cast<const RunLoopSourceClientContext *>(rawContext));
    if(!context || context->referenceCount.fetch_sub(
            1, std::memory_order_acq_rel) != 1) {
        return;
    }

    if(context->guestRelease) {
        const u32 arguments[] = {context->guestInfo};
        if(!InvokeGuestVoidFunction(
                context->guestRelease, arguments, 1)) {
            fprintf(stderr,
                "LC32: could not dispatch CFRunLoopSource context release "
                "0x%08x\n", context->guestRelease);
        }
    }
    delete context;
}

CFStringRef CopyRunLoopSourceClientContextDescription(
        const void *rawContext) {
    const RunLoopSourceClientContext *context =
        static_cast<const RunLoopSourceClientContext *>(rawContext);
    if(!context) return CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("LC32 CFRunLoopSource client"));

    return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
        CFSTR("LC32 CFRunLoopSource perform=0x%08x info=0x%08x "
              "description=0x%08x"),
        context->guestPerform, context->guestInfo,
        context->guestCopyDescription);
}

void RunLoopSourceClientPerform(void *rawContext) {
    RunLoopSourceClientContext *context =
        static_cast<RunLoopSourceClientContext *>(rawContext);
    if(!context || !context->guestPerform) return;
    const u32 arguments[] = {context->guestInfo};
    if(!InvokeGuestVoidFunction(
            context->guestPerform, arguments, 1)) {
        fprintf(stderr,
            "LC32: could not dispatch CFRunLoopSource perform 0x%08x\n",
            context->guestPerform);
    }
}

struct SocketClientContext {
    std::atomic<uint32_t> referenceCount{1};
    std::atomic<u32> guestSocket{0};
    u32 guestCallback = 0;
    u32 guestInfo = 0;
    u32 guestRelease = 0;
    u32 guestCopyDescription = 0;
};

const void *RetainSocketClientContext(const void *rawContext) {
    SocketClientContext *context =
        const_cast<SocketClientContext *>(
            static_cast<const SocketClientContext *>(rawContext));
    if(context) context->referenceCount.fetch_add(
        1, std::memory_order_relaxed);
    return context;
}

void ReleaseSocketClientContext(const void *rawContext) {
    SocketClientContext *context =
        const_cast<SocketClientContext *>(
            static_cast<const SocketClientContext *>(rawContext));
    if(!context || context->referenceCount.fetch_sub(
            1, std::memory_order_acq_rel) != 1) {
        return;
    }

    if(context->guestRelease) {
        const u32 arguments[] = {context->guestInfo};
        if(!InvokeGuestVoidFunction(
                context->guestRelease, arguments, 1)) {
            fprintf(stderr,
                "LC32: could not dispatch CFSocket context release "
                "0x%08x\n", context->guestRelease);
        }
    }
    delete context;
}

CFStringRef CopySocketClientContextDescription(
        const void *rawContext) {
    const SocketClientContext *context =
        static_cast<const SocketClientContext *>(rawContext);
    if(!context) return CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("LC32 CFSocket client"));

    /* CFSocket may request descriptions on an arbitrary native thread.
     * Never borrow a JIT merely to run a diagnostic guest callback. */
    return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
        CFSTR("LC32 CFSocket callback=0x%08x info=0x%08x "
              "description=0x%08x"),
        context->guestCallback, context->guestInfo,
        context->guestCopyDescription);
}

class SocketClientContextLease {
public:
    explicit SocketClientContextLease(SocketClientContext *context)
        : context_(context) {
        RetainSocketClientContext(context_);
    }

    ~SocketClientContextLease() {
        ReleaseSocketClientContext(context_);
    }

private:
    SocketClientContext *context_;
};

class GuestStackSInt32 {
public:
    explicit GuestStackSInt32(int32_t value) {
        if(!threadHandle.jit) return;
        std::array<std::uint32_t, 16> &registers =
            threadHandle.jit->Regs();
        originalStackPointer_ = registers[Reg::SP];
        if(originalStackPointer_ < sizeof(uint64_t)) return;
        guestAddress_ =
            (originalStackPointer_ - sizeof(uint64_t)) & ~7u;
        if(!GuestRangeIsValid(guestAddress_, sizeof(value))) {
            guestAddress_ = 0;
            return;
        }
        registers[Reg::SP] = guestAddress_;
        if(Dynarmic_mem_1write(guestAddress_, sizeof(value),
                reinterpret_cast<char *>(&value)) != 0) {
            registers[Reg::SP] = originalStackPointer_;
            guestAddress_ = 0;
        }
    }

    ~GuestStackSInt32() {
        if(guestAddress_ && threadHandle.jit) {
            threadHandle.jit->Regs()[Reg::SP] = originalStackPointer_;
        }
    }

    u32 address() const { return guestAddress_; }

private:
    u32 originalStackPointer_ = 0;
    u32 guestAddress_ = 0;
};

void SocketClientCallback(CFSocketRef,
                          CFSocketCallBackType type,
                          CFDataRef address,
                          const void *data,
                          void *rawContext) {
    SocketClientContext *context =
        static_cast<SocketClientContext *>(rawContext);
    if(!context || !context->guestCallback) return;
    SocketClientContextLease contextLease(context);

    /* Borrowed CFData values can only be converted while this host thread
     * owns a registered guest JIT. In particular, do not route this callback
     * through the foreign-thread serialized executor: its raw CFData
     * arguments would no longer be valid by the time it ran. */
    if(!Dynarmic_guest_thread_is_registered()) {
        fprintf(stderr,
            "LC32: dropping CFSocket callback type %u on an "
            "unregistered host thread\n", static_cast<unsigned>(type));
        return;
    }

    const u32 guestSocket = context->guestSocket.load(
        std::memory_order_acquire);
    if(!guestSocket) {
        fprintf(stderr,
            "LC32: dropping CFSocket callback before guest socket "
            "identity was assigned\n");
        return;
    }

    const u32 guestAddress = address ? [(id)address guest_self] : 0;
    if(address && !guestAddress) {
        fprintf(stderr,
            "LC32: could not map borrowed CFSocket callback address\n");
        return;
    }

    if(type == kCFSocketDataCallBack) {
        CFDataRef callbackData = static_cast<CFDataRef>(data);
        const u32 guestData = callbackData
            ? [(id)callbackData guest_self] : 0;
        if(callbackData && !guestData) {
            fprintf(stderr,
                "LC32: could not map borrowed CFSocket callback data\n");
            return;
        }
        u32 arguments[] = {
            guestSocket,
            static_cast<u32>(type),
            guestAddress,
            guestData,
            context->guestInfo,
        };
        (void)LC32InvokeGuestC(context->guestCallback, false,
            sizeof(arguments) / sizeof(arguments[0]), arguments);
        return;
    }

    if(type == kCFSocketConnectCallBack) {
        GuestStackSInt32 guestError(
            data ? *static_cast<const SInt32 *>(data) : 0);
        if(data && !guestError.address()) {
            fprintf(stderr,
                "LC32: could not stage CFSocket connect error in guest "
                "memory\n");
            return;
        }
        u32 arguments[] = {
            guestSocket,
            static_cast<u32>(type),
            guestAddress,
            data ? guestError.address() : 0,
            context->guestInfo,
        };
        (void)LC32InvokeGuestC(context->guestCallback, false,
            sizeof(arguments) / sizeof(arguments[0]), arguments);
        return;
    }

    fprintf(stderr,
        "LC32: dropping unsupported CFSocket callback type %u\n",
        static_cast<unsigned>(type));
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
        case LC32CoreFoundationOpStringConvertEncodingToNSStringEncoding:
            if(!RequireSlots(call, 1)) return kCFStringEncodingInvalidId;
            return static_cast<u32>(
                CFStringConvertEncodingToNSStringEncoding(
                    static_cast<CFStringEncoding>(SlotU32(call, 0))));
        case LC32CoreFoundationOpStringConvertNSStringEncodingToEncoding:
            if(!RequireSlots(call, 1)) return kCFStringEncodingInvalidId;
            return CFStringConvertNSStringEncodingToEncoding(
                static_cast<unsigned long>(SlotU32(call, 0)));
        case LC32CoreFoundationOpStringConvertIANACharSetNameToEncoding: {
            if(!RequireSlots(call, 1)) return kCFStringEncodingInvalidId;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? CFStringConvertIANACharSetNameToEncoding(string)
                          : kCFStringEncodingInvalidId;
        }
        case LC32CoreFoundationOpStringConvertEncodingToIANACharSetName: {
            if(!RequireSlots(call, 1)) return 0;
            CFStringRef string = CFStringConvertEncodingToIANACharSetName(
                static_cast<CFStringEncoding>(SlotU32(call, 0)));
            return string ? [(id)string guest_self] : 0;
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
        case LC32CoreFoundationOpURLCreateWithString: {
            if(!RequireSlots(call, 2)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? GuestForCreatedObject(CFURLCreateWithString(
                kCFAllocatorDefault, string,
                SlotHostObject<CFURLRef>(call, 1))) : 0;
        }
        case LC32CoreFoundationOpURLCreateWithBytes: {
            if(!RequireSlots(call, 4) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            std::vector<UInt8> bytes;
            if(!ReadGuestStringBytes(SlotU32(call, 0), SlotU32(call, 1),
                                     bytes)) return 0;
            return GuestForCreatedObject(CFURLCreateWithBytes(
                kCFAllocatorDefault,
                bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                static_cast<CFStringEncoding>(SlotU32(call, 2)),
                SlotHostObject<CFURLRef>(call, 3)));
        }
        case LC32CoreFoundationOpURLCreateStringByReplacingPercentEscapes: {
            if(!RequireSlots(call, 3)) return 0;
            CFStringRef original = SlotHostObject<CFStringRef>(call, 0);
            return original ? GuestForCreatedObject(
                CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
                    kCFAllocatorDefault, original,
                    SlotHostObject<CFStringRef>(call, 1),
                    static_cast<CFStringEncoding>(SlotU32(call, 2)))) : 0;
        }
        case LC32CoreFoundationOpStringTrimWhitespace: {
            if(!RequireSlots(call, 1)) return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            if(!string) return 0;
            CFStringTrimWhitespace(string);
            return 1;
        }
        case LC32CoreFoundationOpNumberGetValue:
            return DispatchNumberGetValue(call);
        case LC32CoreFoundationOpNumberGetType: {
            if(!RequireSlots(call, 1)) return 0;
            CFNumberRef number = SlotHostObject<CFNumberRef>(call, 0);
            return number ? static_cast<u32>(CFNumberGetType(number)) : 0;
        }
        case LC32CoreFoundationOpBundleGetVersionNumber: {
            if(!RequireSlots(call, 1)) return 0;
            /* Guest CFBundleRefs are represented by NSBundle peers throughout
             * this bridge (see BundleGetMainBundle/Create below). Modern
             * CoreFoundation no longer accepts an NSBundle object directly
             * here, even though legacy clients treated the pair as bridged.
             * Reconstitute a real CFBundle for the duration of this scalar
             * query so the historical version-number parsing stays exact. */
            NSBundle *bundle = SlotHostObject<NSBundle *>(call, 0);
            NSURL *bundleURL = bundle.bundleURL;
            if(!bundleURL) return 0;
            CFBundleRef coreBundle = CFBundleCreate(
                kCFAllocatorDefault, (__bridge CFURLRef)bundleURL);
            if(!coreBundle) return 0;
            const UInt32 version = CFBundleGetVersionNumber(coreBundle);
            CFRelease(coreBundle);
            return version;
        }
        case LC32CoreFoundationOpLocaleGetSystem: {
            if(!RequireSlots(call, 0)) return 0;
            CFLocaleRef locale = CFLocaleGetSystem();
            return locale ? [(id)locale guest_self] : 0;
        }
        case LC32CoreFoundationOpStringLowercase: {
            if(!RequireSlots(call, 2)) return 0;
            CFMutableStringRef string =
                SlotHostObject<CFMutableStringRef>(call, 0);
            CFLocaleRef locale = SlotHostObject<CFLocaleRef>(call, 1);
            if(string) CFStringLowercase(string, locale);
            return 0;
        }
        case LC32CoreFoundationOpURLCopyPathExtension: {
            if(!RequireSlots(call, 1)) return 0;
            CFURLRef url = SlotHostObject<CFURLRef>(call, 0);
            return url ? GuestForCreatedObject(
                CFURLCopyPathExtension(url)) : 0;
        }
        case LC32CoreFoundationOpURLCopyFileSystemPath: {
            if(!RequireSlots(call, 2)) return 0;
            NSURL *url = SlotHostObject<NSURL *>(call, 0);
            const int32_t rawStyle = static_cast<int32_t>(SlotU32(call, 1));
            if(!url || rawStyle < kCFURLPOSIXPathStyle ||
               rawStyle > kCFURLWindowsPathStyle) return 0;
            CFStringRef path = CFURLCopyFileSystemPath(
                (__bridge CFURLRef)url,
                static_cast<CFURLPathStyle>(rawStyle));
            if(!path || rawStyle != kCFURLPOSIXPathStyle ||
               !sharedHandle.fs) {
                return GuestForCreatedObject(path);
            }

            char hostPath[PATH_MAX] = {};
            if(!CFStringGetFileSystemRepresentation(
                    path, hostPath, sizeof(hostPath)) || hostPath[0] != '/') {
                return GuestForCreatedObject(path);
            }
            char guestPath[PATH_MAX] = {};
            if(!sharedHandle.fs->pathHostToGuest(hostPath, guestPath)) {
                return GuestForCreatedObject(path);
            }
            CFRelease(path);
            return GuestForCreatedObject(
                CFStringCreateWithFileSystemRepresentation(
                    kCFAllocatorDefault, guestPath));
        }
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
        case LC32CoreFoundationOpBundleCopyBundleURL: {
            if(!RequireSlots(call, 1)) return 0;
            NSBundle *bundle = SlotHostObject<NSBundle *>(call, 0);
            NSURL *url = bundle.bundleURL;
            return url ? GuestForCreatedObject(
                reinterpret_cast<CFTypeRef>([url copy])) : 0;
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
        case LC32CoreFoundationOpRunLoopAddSource: {
            if(!RequireSlots(call, 3)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            CFRunLoopSourceRef source =
                SlotHostObject<CFRunLoopSourceRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!runLoop || !source || !mode) return 0;
            CFRunLoopAddSource(runLoop, source, mode);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopAddTimer: {
            if(!RequireSlots(call, 3)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            CFRunLoopTimerRef timer =
                SlotHostObject<CFRunLoopTimerRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!runLoop || !timer || !mode) return 0;
            CFRunLoopAddTimer(runLoop, timer, mode);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopCopyAllModes: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            return runLoop ? GuestForCreatedObject(
                CFRunLoopCopyAllModes(runLoop)) : 0;
        }
        case LC32CoreFoundationOpRunLoopRemoveSource: {
            if(!RequireSlots(call, 3)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            CFRunLoopSourceRef source =
                SlotHostObject<CFRunLoopSourceRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!runLoop || !source || !mode) return 0;
            CFRunLoopRemoveSource(runLoop, source, mode);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopRemoveTimer: {
            if(!RequireSlots(call, 3)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            CFRunLoopTimerRef timer =
                SlotHostObject<CFRunLoopTimerRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!runLoop || !timer || !mode) return 0;
            CFRunLoopRemoveTimer(runLoop, timer, mode);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopRun:
            if(!RequireSlots(call, 0)) return 0;
            CFRunLoopRun();
            return 1;
        case LC32CoreFoundationOpRunLoopRunInMode: {
            if(!RequireSlots(call, 3)) return 0;
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 0);
            return mode ? static_cast<u32>(static_cast<int32_t>(
                CFRunLoopRunInMode(mode, SlotDouble(call, 1),
                    SlotU32(call, 2) != 0))) : 0;
        }
        case LC32CoreFoundationOpRunLoopSourceInvalidate: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopSourceRef source =
                SlotHostObject<CFRunLoopSourceRef>(call, 0);
            if(!source) return 0;
            CFRunLoopSourceInvalidate(source);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopSourceCreate: {
            if(!RequireSlots(call, 5)) return 0;
            const u32 guestPerform = SlotU32(call, 1);
            const u32 guestInfo = SlotU32(call, 2);
            const u32 guestRelease = SlotU32(call, 3);
            const auto releaseIncomingContext = [&] {
                if(!guestRelease) return;
                const u32 arguments[] = {guestInfo};
                if(!InvokeGuestVoidFunction(
                        guestRelease, arguments, 1)) {
                    fprintf(stderr,
                        "LC32: could not release rejected CFRunLoopSource "
                        "context with 0x%08x\n", guestRelease);
                }
            };

            RunLoopSourceClientContext *context =
                new(std::nothrow) RunLoopSourceClientContext;
            if(!context) {
                releaseIncomingContext();
                return 0;
            }
            context->guestPerform = guestPerform;
            context->guestInfo = guestInfo;
            context->guestRelease = guestRelease;
            context->guestCopyDescription = SlotU32(call, 4);

            CFRunLoopSourceContext nativeContext = {
                0,
                context,
                RetainRunLoopSourceClientContext,
                ReleaseRunLoopSourceClientContext,
                context->guestCopyDescription
                    ? CopyRunLoopSourceClientContextDescription : nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                guestPerform ? RunLoopSourceClientPerform : nullptr,
            };
            CFRunLoopSourceRef source = CFRunLoopSourceCreate(
                kCFAllocatorDefault,
                static_cast<CFIndex>(SlotS32(call, 0)), &nativeContext);
            const u32 guestSource = GuestForCreatedObject(source);
            ReleaseRunLoopSourceClientContext(context);
            return guestSource;
        }
        case LC32CoreFoundationOpRunLoopSourceSignal: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopSourceRef source =
                SlotHostObject<CFRunLoopSourceRef>(call, 0);
            if(!source) return 0;
            CFRunLoopSourceSignal(source);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopStop: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            if(!runLoop) return 0;
            CFRunLoopStop(runLoop);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopTimerInvalidate: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopTimerRef timer =
                SlotHostObject<CFRunLoopTimerRef>(call, 0);
            if(!timer) return 0;
            CFRunLoopTimerInvalidate(timer);
            return 1;
        }
        case LC32CoreFoundationOpRunLoopTimerCreate: {
            if(!RequireSlots(call, 8)) return 0;
            const u32 guestCallback = SlotU32(call, 4);
            const u32 guestInfo = SlotU32(call, 5);
            const u32 guestRelease = SlotU32(call, 6);
            const auto releaseIncomingContext = [&] {
                if(!guestRelease) return;
                const u32 arguments[] = {guestInfo};
                if(!InvokeGuestVoidFunction(
                        guestRelease, arguments, 1)) {
                    fprintf(stderr,
                        "LC32: could not release rejected CFRunLoopTimer "
                        "context with 0x%08x\n", guestRelease);
                }
            };
            if(!guestCallback) {
                releaseIncomingContext();
                return 0;
            }

            RunLoopTimerClientContext *context =
                new(std::nothrow) RunLoopTimerClientContext;
            if(!context) {
                releaseIncomingContext();
                return 0;
            }
            context->guestCallback = guestCallback;
            context->guestInfo = guestInfo;
            context->guestRelease = guestRelease;
            context->guestCopyDescription = SlotU32(call, 7);

            CFRunLoopTimerContext nativeContext = {
                0,
                context,
                RetainRunLoopTimerClientContext,
                ReleaseRunLoopTimerClientContext,
                context->guestCopyDescription
                    ? CopyRunLoopTimerClientContextDescription : nullptr,
            };
            CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
                kCFAllocatorDefault, SlotDouble(call, 0),
                SlotDouble(call, 1),
                static_cast<CFOptionFlags>(SlotU32(call, 2)),
                static_cast<CFIndex>(SlotS32(call, 3)),
                RunLoopTimerClientCallback, &nativeContext);
            const u32 guestTimer = GuestForCreatedObject(timer);
            context->guestTimer.store(
                guestTimer, std::memory_order_release);
            ReleaseRunLoopTimerClientContext(context);
            return guestTimer;
        }
        case LC32CoreFoundationOpRunLoopTimerSetNextFireDate: {
            if(!RequireSlots(call, 2)) return 0;
            CFRunLoopTimerRef timer =
                SlotHostObject<CFRunLoopTimerRef>(call, 0);
            if(!timer) return 0;
            CFRunLoopTimerSetNextFireDate(timer, SlotDouble(call, 1));
            return 1;
        }
        case LC32CoreFoundationOpRunLoopWakeUp: {
            if(!RequireSlots(call, 1)) return 0;
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 0);
            if(!runLoop) return 0;
            CFRunLoopWakeUp(runLoop);
            return 1;
        }
        case LC32CoreFoundationOpSocketCreate: {
            if(!RequireSlots(call, 8)) return 0;
            const CFOptionFlags callbackTypes =
                static_cast<CFOptionFlags>(SlotU32(call, 3));
            const bool supportedCallbackTypes =
                callbackTypes == kCFSocketNoCallBack ||
                callbackTypes == kCFSocketDataCallBack ||
                callbackTypes == kCFSocketConnectCallBack ||
                callbackTypes ==
                    (kCFSocketDataCallBack |
                     kCFSocketConnectCallBack);
            const u32 guestCallback = SlotU32(call, 4);
            const u32 guestInfo = SlotU32(call, 5);
            const u32 guestRelease = SlotU32(call, 6);
            const auto releaseIncomingContext = [&] {
                if(!guestRelease) return;
                const u32 arguments[] = {guestInfo};
                if(!InvokeGuestVoidFunction(
                        guestRelease, arguments, 1)) {
                    fprintf(stderr,
                        "LC32: could not release rejected CFSocket "
                        "context with 0x%08x\n", guestRelease);
                }
            };
            if(!supportedCallbackTypes ||
               (callbackTypes != kCFSocketNoCallBack &&
                !guestCallback)) {
                releaseIncomingContext();
                return 0;
            }

            SocketClientContext *context =
                new(std::nothrow) SocketClientContext;
            if(!context) {
                releaseIncomingContext();
                return 0;
            }
            context->guestCallback = guestCallback;
            context->guestInfo = guestInfo;
            context->guestRelease = guestRelease;
            context->guestCopyDescription = SlotU32(call, 7);

            CFSocketContext nativeContext = {
                0,
                context,
                RetainSocketClientContext,
                ReleaseSocketClientContext,
                context->guestCopyDescription
                    ? CopySocketClientContextDescription : nullptr,
            };
            CFSocketRef socket = CFSocketCreate(
                kCFAllocatorDefault, SlotS32(call, 0),
                SlotS32(call, 1), SlotS32(call, 2), callbackTypes,
                guestCallback ? SocketClientCallback : nullptr,
                &nativeContext);
            const u32 guestSocket = GuestForCreatedObject(socket);
            context->guestSocket.store(
                guestSocket, std::memory_order_release);
            ReleaseSocketClientContext(context);
            return guestSocket;
        }
        case LC32CoreFoundationOpSocketConnectToAddress: {
            if(!RequireSlots(call, 3)) return static_cast<u32>(
                static_cast<int32_t>(kCFSocketError));
            CFSocketRef socket =
                SlotHostObject<CFSocketRef>(call, 0);
            CFDataRef address =
                SlotHostObject<CFDataRef>(call, 1);
            if(!socket || !address) return static_cast<u32>(
                static_cast<int32_t>(kCFSocketError));
            return static_cast<u32>(static_cast<int32_t>(
                CFSocketConnectToAddress(
                    socket, address, SlotDouble(call, 2))));
        }
        case LC32CoreFoundationOpSocketCreateRunLoopSource: {
            if(!RequireSlots(call, 2)) return 0;
            CFSocketRef socket =
                SlotHostObject<CFSocketRef>(call, 0);
            return socket ? GuestForCreatedObject(
                CFSocketCreateRunLoopSource(
                    kCFAllocatorDefault, socket,
                    static_cast<CFIndex>(SlotS32(call, 1)))) : 0;
        }
        case LC32CoreFoundationOpSocketGetNative: {
            if(!RequireSlots(call, 1)) return UINT32_MAX;
            CFSocketRef socket =
                SlotHostObject<CFSocketRef>(call, 0);
            return socket ? static_cast<u32>(static_cast<int32_t>(
                CFSocketGetNative(socket))) : UINT32_MAX;
        }
        case LC32CoreFoundationOpSocketInvalidate: {
            if(!RequireSlots(call, 1)) return 0;
            CFSocketRef socket =
                SlotHostObject<CFSocketRef>(call, 0);
            if(!socket) return 0;
            CFSocketInvalidate(socket);
            return 1;
        }
        case LC32CoreFoundationOpDictionaryGetValue: {
            if(!RequireSlots(call, 4)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const void *key = DictionaryOperand(call, 1, 2);
            if(!dictionary || !key) return 0;
            const void *value = CFDictionaryGetValue(dictionary, key);
            return GuestDictionaryOperand(value, SlotU32(call, 3));
        }
        case LC32CoreFoundationOpDictionarySetValue: {
            if(!RequireSlots(call, 5)) return 0;
            CFMutableDictionaryRef dictionary =
                SlotHostObject<CFMutableDictionaryRef>(call, 0);
            const void *key = DictionaryOperand(call, 1, 2);
            const void *value = DictionaryOperand(call, 3, 4);
            if(dictionary && key && value)
                CFDictionarySetValue(dictionary, key, value);
            return 0;
        }
        case LC32CoreFoundationOpDictionaryRemoveValue: {
            if(!RequireSlots(call, 3)) return 0;
            CFMutableDictionaryRef dictionary =
                SlotHostObject<CFMutableDictionaryRef>(call, 0);
            const void *key = DictionaryOperand(call, 1, 2);
            if(dictionary && key) CFDictionaryRemoveValue(dictionary, key);
            return 0;
        }
        case LC32CoreFoundationOpDictionaryContainsKey: {
            if(!RequireSlots(call, 3)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const void *key = DictionaryOperand(call, 1, 2);
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
            if(!RequireSlots(call, 5)) return 0;
            CFDictionaryRef dictionary =
                SlotHostObject<CFDictionaryRef>(call, 0);
            const u32 guestKeys = SlotU32(call, 1);
            const u32 guestValues = SlotU32(call, 2);
            const u32 keyMode = SlotU32(call, 3);
            const u32 valueMode = SlotU32(call, 4);
            if(!dictionary || (!guestKeys && !guestValues)) return 0;
            if(!DictionaryCallbacksModeIsValid(keyMode) ||
               !DictionaryCallbacksModeIsValid(valueMode)) return 0;

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
                    guestObjects[index] =
                        GuestDictionaryOperand(keys[index], keyMode);
                    if(keys[index] && !guestObjects[index]) return 0;
                }
                if(byteCount && Dynarmic_mem_1write(guestKeys, byteCount,
                        reinterpret_cast<char *>(guestObjects.data())) != 0) {
                    return 0;
                }
            }
            if(guestValues) {
                for(CFIndex index = 0; index < count; ++index) {
                    guestObjects[index] =
                        GuestDictionaryOperand(values[index], valueMode);
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
            if((call.slotCount != 2 && call.slotCount != 3) ||
               SlotU32(call, 1) > kMaximumSetEntries) return 0;
            const uint32_t mode = call.slotCount == 3 ?
                SlotU32(call, 2) : LC32CoreFoundationCallbacksCFType;
            const CFSetCallBacks *callbacks = SetCallbacks(mode);
            if(callbacks == reinterpret_cast<const CFSetCallBacks *>(
                    UINTPTR_MAX)) return 0;
            std::vector<const void *> values;
            if(!ReadGuestHostObjects(SlotU32(call, 0),
                                     SlotU32(call, 1), values)) return 0;
            return GuestForCreatedObject(CFSetCreate(
                kCFAllocatorDefault,
                values.empty() ? nullptr : values.data(), values.size(),
                callbacks));
        }
        case LC32CoreFoundationOpSetCreateCopy: {
            if(!RequireSlots(call, 1)) return 0;
            CFSetRef set = SlotHostObject<CFSetRef>(call, 0);
            return set ? GuestForCreatedObject(CFSetCreateCopy(
                kCFAllocatorDefault, set)) : 0;
        }
        case LC32CoreFoundationOpSetCreateMutable: {
            if((call.slotCount != 1 && call.slotCount != 2) ||
               SlotU32(call, 0) > kMaximumSetEntries) return 0;
            const uint32_t mode = call.slotCount == 2 ?
                SlotU32(call, 1) : LC32CoreFoundationCallbacksCFType;
            const CFSetCallBacks *callbacks = SetCallbacks(mode);
            if(callbacks == reinterpret_cast<const CFSetCallBacks *>(
                    UINTPTR_MAX)) return 0;
            return GuestForCreatedObject(CFSetCreateMutable(
                kCFAllocatorDefault, SlotU32(call, 0),
                callbacks));
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
        case LC32CoreFoundationOpAttributedStringCreate: {
            if(!RequireSlots(call, 2)) return 0;
            CFStringRef string = SlotHostObject<CFStringRef>(call, 0);
            return string ? GuestForCreatedObject(CFAttributedStringCreate(
                kCFAllocatorDefault, string,
                SlotHostObject<CFDictionaryRef>(call, 1))) : 0;
        }
        case LC32CoreFoundationOpAttributedStringCreateMutable: {
            if(!RequireSlots(call, 1)) return 0;
            const int32_t maximumLength = SlotS32(call, 0);
            return maximumLength >= 0 ? GuestForCreatedObject(
                CFAttributedStringCreateMutable(kCFAllocatorDefault,
                    static_cast<CFIndex>(maximumLength))) : 0;
        }
        case LC32CoreFoundationOpAttributedStringCreateWithSubstring: {
            if(!RequireSlots(call, 3)) return 0;
            CFAttributedStringRef string =
                SlotHostObject<CFAttributedStringRef>(call, 0);
            const int32_t location = SlotS32(call, 1);
            const int32_t length = SlotS32(call, 2);
            if(!AttributedStringRangeIsValid(string, location, length))
                return 0;
            return GuestForCreatedObject(
                CFAttributedStringCreateWithSubstring(kCFAllocatorDefault,
                    string, CFRangeMake(static_cast<CFIndex>(location),
                                        static_cast<CFIndex>(length))));
        }
        case LC32CoreFoundationOpAttributedStringGetLength: {
            if(!RequireSlots(call, 1)) return 0;
            CFAttributedStringRef string =
                SlotHostObject<CFAttributedStringRef>(call, 0);
            if(!string) return 0;
            const CFIndex length = CFAttributedStringGetLength(string);
            return length > INT32_MAX ? INT32_MAX : static_cast<u32>(length);
        }
        case LC32CoreFoundationOpAttributedStringReplaceAttributedString: {
            if(!RequireSlots(call, 4)) return 0;
            CFMutableAttributedStringRef string =
                SlotHostObject<CFMutableAttributedStringRef>(call, 0);
            const int32_t location = SlotS32(call, 1);
            const int32_t length = SlotS32(call, 2);
            CFAttributedStringRef replacement =
                SlotHostObject<CFAttributedStringRef>(call, 3);
            if(!replacement ||
               !AttributedStringRangeIsValid(string, location, length)) {
                return 0;
            }
            CFAttributedStringReplaceAttributedString(string,
                CFRangeMake(static_cast<CFIndex>(location),
                            static_cast<CFIndex>(length)), replacement);
            return 1;
        }
        case LC32CoreFoundationOpReadStreamOpen: {
            if(!RequireSlots(call, 1)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            return stream && CFReadStreamOpen(stream);
        }
        case LC32CoreFoundationOpReadStreamClose: {
            if(!RequireSlots(call, 1)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            if(!stream) return 0;
            CFReadStreamClose(stream);
            return 1;
        }
        case LC32CoreFoundationOpReadStreamGetStatus: {
            if(!RequireSlots(call, 1)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            return stream ? static_cast<u32>(static_cast<int32_t>(
                CFReadStreamGetStatus(stream))) : 0;
        }
        case LC32CoreFoundationOpReadStreamHasBytesAvailable: {
            if(!RequireSlots(call, 1)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            return stream && CFReadStreamHasBytesAvailable(stream);
        }
        case LC32CoreFoundationOpReadStreamRead: {
            if(!RequireSlots(call, 3)) return static_cast<u32>(-1);
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            const u32 guestBuffer = SlotU32(call, 1);
            const int32_t bufferLength = SlotS32(call, 2);
            if(!stream || bufferLength < 0 ||
               static_cast<uint32_t>(bufferLength) >
                    kMaximumReadStreamBytes ||
               (bufferLength && !GuestRangeIsValid(
                    guestBuffer, static_cast<u32>(bufferLength)))) {
                return static_cast<u32>(-1);
            }

            std::vector<UInt8> buffer(
                static_cast<size_t>(bufferLength));
            const CFIndex result = CFReadStreamRead(
                stream, buffer.empty() ? nullptr : buffer.data(),
                static_cast<CFIndex>(bufferLength));
            if(result < 0) return static_cast<u32>(-1);
            if(result > bufferLength || result > INT32_MAX) {
                return static_cast<u32>(-1);
            }
            if(result && Dynarmic_mem_1write(
                    guestBuffer, static_cast<u32>(result),
                    reinterpret_cast<char *>(buffer.data())) != 0) {
                return static_cast<u32>(-1);
            }
            return static_cast<u32>(static_cast<int32_t>(result));
        }
        case LC32CoreFoundationOpReadStreamCopyError: {
            if(!RequireSlots(call, 1)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            return stream ? GuestForCreatedObject(
                CFReadStreamCopyError(stream)) : 0;
        }
        case LC32CoreFoundationOpReadStreamCopyProperty: {
            if(!RequireSlots(call, 2)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            CFStreamPropertyKey property =
                SlotHostObject<CFStreamPropertyKey>(call, 1);
            return stream && property ? GuestForCreatedObject(
                CFReadStreamCopyProperty(stream, property)) : 0;
        }
        case LC32CoreFoundationOpReadStreamSetProperty: {
            if(!RequireSlots(call, 3)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            CFStreamPropertyKey property =
                SlotHostObject<CFStreamPropertyKey>(call, 1);
            CFTypeRef value = SlotHostObject<CFTypeRef>(call, 2);
            return stream && property && value &&
                CFReadStreamSetProperty(stream, property, value);
        }
        case LC32CoreFoundationOpReadStreamScheduleWithRunLoop: {
            if(!RequireSlots(call, 3)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!stream || !runLoop || !mode) return 0;
            CFReadStreamScheduleWithRunLoop(stream, runLoop, mode);
            return 1;
        }
        case LC32CoreFoundationOpReadStreamUnscheduleFromRunLoop: {
            if(!RequireSlots(call, 3)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!stream || !runLoop || !mode) return 0;
            CFReadStreamUnscheduleFromRunLoop(stream, runLoop, mode);
            return 1;
        }
        case LC32CoreFoundationOpReadStreamGetError: {
            if(!RequireSlots(call, 2)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            const u32 guestError = SlotU32(call, 1);
            if(!stream || !GuestRangeIsValid(
                    guestError, sizeof(LC32GuestCFStreamError))) {
                return 0;
            }
            const CFStreamError error = CFReadStreamGetError(stream);
            if(error.domain < INT32_MIN || error.domain > INT32_MAX) {
                return 0;
            }
            LC32GuestCFStreamError guestValue = {
                static_cast<int32_t>(error.domain),
                static_cast<int32_t>(error.error),
            };
            return Dynarmic_mem_1write(
                guestError, sizeof(guestValue),
                reinterpret_cast<char *>(&guestValue)) == 0;
        }
        case LC32CoreFoundationOpReadStreamSetClient: {
            if(!RequireSlots(call, 7)) return 0;
            CFReadStreamRef stream =
                SlotHostObject<CFReadStreamRef>(call, 0);
            const u32 guestStream = SlotU32(call, 1);
            const CFOptionFlags events =
                static_cast<CFOptionFlags>(SlotU32(call, 2));
            const u32 guestCallback = SlotU32(call, 3);
            if(!guestCallback) {
                return stream && CFReadStreamSetClient(
                    stream, events, nullptr, nullptr);
            }
            const u32 guestInfo = SlotU32(call, 4);
            const u32 guestRelease = SlotU32(call, 5);
            const auto releaseIncomingContext = [&] {
                if(!guestRelease) return;
                const u32 arguments[] = {guestInfo};
                if(!InvokeGuestVoidFunction(
                        guestRelease, arguments, 1)) {
                    fprintf(stderr,
                        "LC32: could not release rejected CFReadStream "
                        "client context with 0x%08x\n", guestRelease);
                }
            };
            if(!stream || !guestStream) {
                releaseIncomingContext();
                return 0;
            }

            ReadStreamClientContext *context =
                new(std::nothrow) ReadStreamClientContext;
            if(!context) {
                releaseIncomingContext();
                return 0;
            }
            context->guestStream = guestStream;
            context->guestCallback = guestCallback;
            context->guestInfo = guestInfo;
            context->guestRelease = guestRelease;
            context->guestCopyDescription = SlotU32(call, 6);

            CFStreamClientContext nativeContext = {
                0,
                context,
                RetainReadStreamClientContext,
                ReleaseReadStreamClientContext,
                context->guestCopyDescription
                    ? CopyReadStreamClientContextDescription : nullptr,
            };
            const Boolean result = CFReadStreamSetClient(
                stream, events, ReadStreamClientCallback,
                &nativeContext);
            ReleaseReadStreamClientContext(context);
            return result;
        }
        case LC32CoreFoundationOpWriteStreamOpen: {
            if(!RequireSlots(call, 1)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            return stream && CFWriteStreamOpen(stream);
        }
        case LC32CoreFoundationOpWriteStreamClose: {
            if(!RequireSlots(call, 1)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            if(!stream) return 0;
            CFWriteStreamClose(stream);
            return 1;
        }
        case LC32CoreFoundationOpWriteStreamGetStatus: {
            if(!RequireSlots(call, 1)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            return stream ? static_cast<u32>(static_cast<int32_t>(
                CFWriteStreamGetStatus(stream))) : 0;
        }
        case LC32CoreFoundationOpWriteStreamCanAcceptBytes: {
            if(!RequireSlots(call, 1)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            return stream && CFWriteStreamCanAcceptBytes(stream);
        }
        case LC32CoreFoundationOpWriteStreamWrite: {
            if(!RequireSlots(call, 3)) return static_cast<u32>(-1);
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            const u32 guestBuffer = SlotU32(call, 1);
            const int32_t bufferLength = SlotS32(call, 2);
            if(!stream || bufferLength < 0 ||
               static_cast<uint32_t>(bufferLength) >
                    kMaximumWriteStreamBytes ||
               (bufferLength && !GuestRangeIsValid(
                    guestBuffer, static_cast<u32>(bufferLength)))) {
                return static_cast<u32>(-1);
            }

            std::vector<UInt8> buffer(
                static_cast<size_t>(bufferLength));
            if(bufferLength && Dynarmic_mem_1read(
                    guestBuffer, static_cast<u32>(bufferLength),
                    reinterpret_cast<char *>(buffer.data())) != 0) {
                return static_cast<u32>(-1);
            }
            const CFIndex result = CFWriteStreamWrite(
                stream, buffer.empty() ? nullptr : buffer.data(),
                static_cast<CFIndex>(bufferLength));
            if(result < 0 || result > bufferLength || result > INT32_MAX) {
                return static_cast<u32>(-1);
            }
            return static_cast<u32>(static_cast<int32_t>(result));
        }
        case LC32CoreFoundationOpWriteStreamCopyError: {
            if(!RequireSlots(call, 1)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            return stream ? GuestForCreatedObject(
                CFWriteStreamCopyError(stream)) : 0;
        }
        case LC32CoreFoundationOpWriteStreamCopyProperty: {
            if(!RequireSlots(call, 2)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            CFStreamPropertyKey property =
                SlotHostObject<CFStreamPropertyKey>(call, 1);
            return stream && property ? GuestForCreatedObject(
                CFWriteStreamCopyProperty(stream, property)) : 0;
        }
        case LC32CoreFoundationOpWriteStreamSetProperty: {
            if(!RequireSlots(call, 3)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            CFStreamPropertyKey property =
                SlotHostObject<CFStreamPropertyKey>(call, 1);
            CFTypeRef value = SlotHostObject<CFTypeRef>(call, 2);
            return stream && property && value &&
                CFWriteStreamSetProperty(stream, property, value);
        }
        case LC32CoreFoundationOpWriteStreamScheduleWithRunLoop: {
            if(!RequireSlots(call, 3)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!stream || !runLoop || !mode) return 0;
            CFWriteStreamScheduleWithRunLoop(stream, runLoop, mode);
            return 1;
        }
        case LC32CoreFoundationOpWriteStreamUnscheduleFromRunLoop: {
            if(!RequireSlots(call, 3)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            CFRunLoopRef runLoop =
                SlotHostObject<CFRunLoopRef>(call, 1);
            CFRunLoopMode mode =
                SlotHostObject<CFRunLoopMode>(call, 2);
            if(!stream || !runLoop || !mode) return 0;
            CFWriteStreamUnscheduleFromRunLoop(stream, runLoop, mode);
            return 1;
        }
        case LC32CoreFoundationOpWriteStreamGetError: {
            if(!RequireSlots(call, 2)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            const u32 guestError = SlotU32(call, 1);
            if(!stream || !GuestRangeIsValid(
                    guestError, sizeof(LC32GuestCFStreamError))) {
                return 0;
            }
            const CFStreamError error = CFWriteStreamGetError(stream);
            if(error.domain < INT32_MIN || error.domain > INT32_MAX) {
                return 0;
            }
            LC32GuestCFStreamError guestValue = {
                static_cast<int32_t>(error.domain),
                static_cast<int32_t>(error.error),
            };
            return Dynarmic_mem_1write(
                guestError, sizeof(guestValue),
                reinterpret_cast<char *>(&guestValue)) == 0;
        }
        case LC32CoreFoundationOpWriteStreamSetClient: {
            if(!RequireSlots(call, 7)) return 0;
            CFWriteStreamRef stream =
                SlotHostObject<CFWriteStreamRef>(call, 0);
            const u32 guestStream = SlotU32(call, 1);
            const CFOptionFlags events =
                static_cast<CFOptionFlags>(SlotU32(call, 2));
            const u32 guestCallback = SlotU32(call, 3);
            if(!guestCallback) {
                return stream && CFWriteStreamSetClient(
                    stream, events, nullptr, nullptr);
            }
            const u32 guestInfo = SlotU32(call, 4);
            const u32 guestRelease = SlotU32(call, 5);
            const auto releaseIncomingContext = [&] {
                if(!guestRelease) return;
                const u32 arguments[] = {guestInfo};
                if(!InvokeGuestVoidFunction(
                        guestRelease, arguments, 1)) {
                    fprintf(stderr,
                        "LC32: could not release rejected CFWriteStream "
                        "client context with 0x%08x\n", guestRelease);
                }
            };
            if(!stream || !guestStream) {
                releaseIncomingContext();
                return 0;
            }

            WriteStreamClientContext *context =
                new(std::nothrow) WriteStreamClientContext;
            if(!context) {
                releaseIncomingContext();
                return 0;
            }
            context->guestStream = guestStream;
            context->guestCallback = guestCallback;
            context->guestInfo = guestInfo;
            context->guestRelease = guestRelease;
            context->guestCopyDescription = SlotU32(call, 6);

            CFStreamClientContext nativeContext = {
                0,
                context,
                RetainWriteStreamClientContext,
                ReleaseWriteStreamClientContext,
                context->guestCopyDescription
                    ? CopyWriteStreamClientContextDescription : nullptr,
            };
            const Boolean result = CFWriteStreamSetClient(
                stream, events, WriteStreamClientCallback,
                &nativeContext);
            ReleaseWriteStreamClientContext(context);
            return result;
        }
        case LC32CoreFoundationOpStreamCreatePairWithSocket: {
            if(!RequireSlots(call, 3)) return 0;
            const CFSocketNativeHandle socket =
                static_cast<CFSocketNativeHandle>(SlotS32(call, 0));
            const u32 guestReadStream = SlotU32(call, 1);
            const u32 guestWriteStream = SlotU32(call, 2);
            if((!guestReadStream && !guestWriteStream) ||
               (guestReadStream && guestWriteStream &&
                    guestReadStream == guestWriteStream)) {
                return 0;
            }
            if((guestReadStream &&
                    !WriteGuestValue(guestReadStream, static_cast<u32>(0))) ||
               (guestWriteStream &&
                    !WriteGuestValue(guestWriteStream, static_cast<u32>(0)))) {
                return 0;
            }

            CFReadStreamRef readStream = nullptr;
            CFWriteStreamRef writeStream = nullptr;
            CFStreamCreatePairWithSocket(kCFAllocatorDefault, socket,
                guestReadStream ? &readStream : nullptr,
                guestWriteStream ? &writeStream : nullptr);

            if(!WriteGuestCreatedObject(guestReadStream, readStream)) {
                if(writeStream) CFRelease(writeStream);
                return 0;
            }
            return WriteGuestCreatedObject(
                guestWriteStream, writeStream);
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
        case LC32CoreFoundationOpPropertyListCreateDeepCopy: {
            if(!RequireSlots(call, 2) ||
               SlotU32(call, 1) >
                    kCFPropertyListMutableContainersAndLeaves) {
                return 0;
            }
            CFPropertyListRef propertyList =
                SlotHostObject<CFPropertyListRef>(call, 0);
            return propertyList ? GuestForCreatedObject(
                CFPropertyListCreateDeepCopy(kCFAllocatorDefault,
                    propertyList,
                    static_cast<CFOptionFlags>(SlotU32(call, 1)))) : 0;
        }
        case LC32CoreFoundationOpBitVectorCreate: {
            if(!RequireSlots(call, 2) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            const u32 bitCount = SlotU32(call, 1);
            const u32 byteCount = (bitCount + 7u) / 8u;
            std::vector<UInt8> bytes;
            if(!ReadGuestBytes(SlotU32(call, 0), byteCount, bytes)) return 0;
            return GuestForCreatedObject(CFBitVectorCreate(
                kCFAllocatorDefault,
                bytes.empty() ? nullptr : bytes.data(), bitCount));
        }
        case LC32CoreFoundationOpBitVectorCreateMutableCopy: {
            if(!RequireSlots(call, 2) || SlotU32(call, 0) > INT32_MAX)
                return 0;
            CFBitVectorRef bitVector =
                SlotHostObject<CFBitVectorRef>(call, 1);
            return bitVector ? GuestForCreatedObject(
                CFBitVectorCreateMutableCopy(kCFAllocatorDefault,
                    static_cast<CFIndex>(SlotU32(call, 0)), bitVector)) : 0;
        }
        case LC32CoreFoundationOpBitVectorGetBitAtIndex: {
            if(!RequireSlots(call, 2) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            CFBitVectorRef bitVector =
                SlotHostObject<CFBitVectorRef>(call, 0);
            const CFIndex index = static_cast<CFIndex>(SlotU32(call, 1));
            return bitVector && index < CFBitVectorGetCount(bitVector)
                ? CFBitVectorGetBitAtIndex(bitVector, index) : 0;
        }
        case LC32CoreFoundationOpBitVectorSetBitAtIndex: {
            if(!RequireSlots(call, 3) || SlotU32(call, 1) > INT32_MAX)
                return 0;
            CFMutableBitVectorRef bitVector =
                SlotHostObject<CFMutableBitVectorRef>(call, 0);
            const CFIndex index = static_cast<CFIndex>(SlotU32(call, 1));
            if(!bitVector || index >= CFBitVectorGetCount(bitVector)) return 0;
            CFBitVectorSetBitAtIndex(bitVector, index,
                                     SlotU32(call, 2) != 0);
            return 1;
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
