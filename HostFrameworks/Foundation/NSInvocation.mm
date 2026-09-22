#import "../LC32/bridge.h"
#include "../LC32/dynarmic_internal.h"
#include "LC32PODType.h"
#import "../LC32/host_selector_hooks.h"

#include <array>

// Guest addresses are integer arguments, never native void* values. These
// methods are reached only by the guest bridge's per-class redirects.
@interface NSInvocation (LC32GuestStorage)
- (uint32_t)lc32_guestSelector;
- (void)lc32_getGuestArgument:(uint32_t)storage atIndex:(int32_t)index;
- (void)lc32_setGuestArgument:(uint32_t)storage atIndex:(int32_t)index;
- (void)lc32_getGuestReturnValue:(uint32_t)storage;
- (void)lc32_setGuestReturnValue:(uint32_t)storage;
@end

using LC32InvocationStorage = std::array<u8, LC32PODMaxSize>;

template<typename T>
static bool LC32ReadGuestInvocationValue(u32 guestStorage, T &value) {
    return guestStorage && u64(guestStorage) + sizeof(value) <= (UINT64_C(1) << 32) &&
        read_guest_memory_with_permissions(guestStorage, &value, sizeof(value), PROT_READ);
}

template<typename T>
static void LC32StoreHostInvocationValue(
        LC32InvocationStorage &storage, T value) {
    static_assert(sizeof(value) <= LC32PODMaxSize, "invocation value exceeds staging");
    memcpy(storage.data(), &value, sizeof(value));
}

/*
 * -[NSInvocation setArgument:atIndex:] copies bytes using native type sizes.
 * The supplied pointer, however, names raw ARM32 storage. Rebuild the value
 * into host-owned aligned storage instead of exposing a guest address or
 * letting Foundation read eight-byte pointers from four-byte guest values.
 */
static bool LC32PrepareHostInvocationValue(const char *type, u32 guestStorage,
        LC32InvocationStorage &hostStorage) {
    if(!guestStorage) return false;
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type || !*type) return false;
    if(type[0] == '@' && type[1] == '?') return false;

    if(*type == '{') {
        LC32PODType guest, host;
        LC32InvocationStorage input = {};
        if(!LC32PODStructType(type, 0, &guest) ||
           !LC32PODStructType(type, 1, &host) ||
           u64(guestStorage) + guest.size > (UINT64_C(1) << 32) ||
           !read_guest_memory_with_permissions(guestStorage, input.data(), guest.size, PROT_READ))
            return false;
        hostStorage.fill(0);
        for(unsigned i = 0; i < guest.count; ++i)
            memcpy(hostStorage.data() + host.fields[i].offset,
                input.data() + guest.fields[i].offset,
                LC32PODScalarSize(guest.fields[i].kind));
        return true;
    }

    NSUInteger nativeSize = 0;
    NSUInteger nativeAlignment = 0;
    NSGetSizeAndAlignment(type, &nativeSize, &nativeAlignment);
    if(!nativeSize || nativeSize > hostStorage.size()) return false;
    hostStorage.fill(0);

    switch(*type) {
        case '@':
        case '#': {
            u32 guestObject = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestObject))
                return false;
            const u64 hostObject = guestObject
                ? LC32GuestToHostReturnType(
                    const_cast<char *>(type), guestObject)
                : 0;
            LC32StoreHostInvocationValue(hostStorage, hostObject);
            return nativeSize == sizeof(hostObject);
        }
        case ':': {
            u32 guestSelector = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestSelector))
                return false;
            const u64 hostSelector = guestSelector
                ? LC32GetHostSelector(guestSelector)
                : 0;
            LC32StoreHostInvocationValue(hostStorage, hostSelector);
            return nativeSize == sizeof(hostSelector);
        }
        case 'B':
        case 'C': {
            uint8_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'c': {
            int8_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'S': {
            uint16_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 's': {
            int16_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'I': {
            uint32_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'i': {
            int32_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'L': {
            uint32_t guestValue = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestValue))
                return false;
            // Objective-C l/L encodings remain 32-bit in native Foundation;
            // LP64 long/NSInteger methods use q/Q instead.
            const uint32_t hostValue = guestValue;
            LC32StoreHostInvocationValue(hostStorage, hostValue);
            return nativeSize == sizeof(hostValue);
        }
        case 'l': {
            int32_t guestValue = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestValue))
                return false;
            const int32_t hostValue = guestValue;
            LC32StoreHostInvocationValue(hostStorage, hostValue);
            return nativeSize == sizeof(hostValue);
        }
        case 'Q': {
            uint64_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'q': {
            int64_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'f': {
            float value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'd': {
            double value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        default:
            return false;
    }
}

static bool LC32PrepareHostInvocationArgument(
        NSInvocation *invocation, u32 guestStorage, int32_t argumentIndex,
        LC32InvocationStorage &hostStorage) {
    if(!invocation || argumentIndex < 0) return false;
    NSMethodSignature *signature = invocation.methodSignature;
    return signature &&
        (NSUInteger)argumentIndex < signature.numberOfArguments &&
        LC32PrepareHostInvocationValue([signature getArgumentTypeAtIndex:
            (NSUInteger)argumentIndex], guestStorage, hostStorage);
}

// NSInvocation's buffers use native ABI sizes even when the original method
// signature came from guest metadata. Numeric aggregates are copied field by
// field: ARM32's four-byte double alignment differs from native alignment.
static bool LC32CopyHostInvocationValueToGuest(const char *type,
        const LC32InvocationStorage &hostStorage, u32 guestStorage) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type || !*type) return false;
    if(*type == '{') {
        LC32PODType guest, host;
        LC32InvocationStorage output = {};
        if(!LC32PODStructType(type, 0, &guest) ||
           !LC32PODStructType(type, 1, &host) || !guestStorage ||
           u64(guestStorage) + guest.size > (UINT64_C(1) << 32)) return false;
        for(unsigned i = 0; i < guest.count; ++i)
            memcpy(output.data() + guest.fields[i].offset,
                hostStorage.data() + host.fields[i].offset,
                LC32PODScalarSize(guest.fields[i].kind));
        return write_guest_memory_with_permissions(guestStorage,
            output.data(), guest.size, PROT_WRITE);
    }
    u64 bits = 0;
    memcpy(&bits, hostStorage.data(), sizeof(bits));
    size_t guestSize;
    switch(*type) {
        case 'v': return true;
        case '@':
        case '#':
            bits = LC32GuestObjectForBorrowedHostResult((id)(uintptr_t)bits);
            guestSize = 4;
            break;
        case ':':
            bits = bits ? guest_sel_registerName(sel_getName((SEL)bits)) : 0;
            guestSize = 4;
            break;
        case 'B': case 'c': case 'C': guestSize = 1; break;
        case 's': case 'S': guestSize = 2; break;
        case 'i': case 'I': case 'l': case 'L': case 'f':
            guestSize = 4; break;
        case 'q': case 'Q': case 'd': guestSize = 8; break;
        default: return false;
    }
    return guestStorage && u64(guestStorage) + guestSize <= (UINT64_C(1) << 32) &&
        write_guest_memory_with_permissions(guestStorage, &bits, guestSize, PROT_WRITE);
}

static bool LC32TransferHostInvocationValue(NSInvocation *invocation,
        SEL selector, u32 guestStorage, int32_t argumentIndex) {
    const bool argument = selector == @selector(getArgument:atIndex:);
    NSMethodSignature *signature = invocation.methodSignature;
    if(!signature || (argument && (argumentIndex < 0 ||
            (NSUInteger)argumentIndex >= signature.numberOfArguments))) return false;
    const char *type = argument ? [signature getArgumentTypeAtIndex:argumentIndex]
        : signature.methodReturnType;
    const char *unqualified = type;
    while(unqualified && *unqualified && strchr("rnNoORVA", *unqualified)) unqualified++;
    if(!argument && unqualified && *unqualified == 'v') return true;
    if(!unqualified || !*unqualified || !strchr("@#:BcCsSiIlLqQfd{", *unqualified))
        return false;
    if(unqualified[0] == '@' && unqualified[1] == '?') return false;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, nullptr);
    alignas(16) LC32InvocationStorage storage = {};
    if(!size || size > storage.size()) return false;
    if(selector == @selector(setReturnValue:)) {
        if(!LC32PrepareHostInvocationValue(type, guestStorage, storage)) return false;
        [invocation setReturnValue:storage.data()];
        return true;
    }
    if(argument) [invocation getArgument:storage.data() atIndex:argumentIndex];
    else [invocation getReturnValue:storage.data()];
    return LC32CopyHostInvocationValueToGuest(type, storage, guestStorage);
}

@implementation NSInvocation (LC32GuestStorage)

+ (void)load {
    const SEL original[] = {@selector(selector), @selector(getArgument:atIndex:),
        @selector(setArgument:atIndex:), @selector(getReturnValue:), @selector(setReturnValue:)};
    const SEL replacement[] = {@selector(lc32_guestSelector), @selector(lc32_getGuestArgument:atIndex:),
        @selector(lc32_setGuestArgument:atIndex:), @selector(lc32_getGuestReturnValue:),
        @selector(lc32_setGuestReturnValue:)};
    for(unsigned i = 0; i < sizeof(original) / sizeof(*original); ++i)
        LC32RegisterHostSelectorHook(self, original[i], {replacement[i], nullptr});
}

// Only guest shims call these entry points. Foundation's public NSInvocation
// methods always keep their native buffers and native selector return value.
- (uint32_t)lc32_guestSelector {
    SEL selector = self.selector;
    return selector ? guest_sel_registerName(sel_getName(selector)) : 0;
}

- (void)lc32_getGuestArgument:(uint32_t)storage atIndex:(int32_t)index {
    if(!LC32TransferHostInvocationValue(self, @selector(getArgument:atIndex:), storage, index))
        [NSException raise:NSInvalidArgumentException
            format:@"LC32: unsupported type or invalid guest buffer for NSInvocation getArgument:atIndex:"];
}

- (void)lc32_getGuestReturnValue:(uint32_t)storage {
    if(!LC32TransferHostInvocationValue(self, @selector(getReturnValue:), storage, 0))
        [NSException raise:NSInvalidArgumentException
            format:@"LC32: unsupported type or invalid guest buffer for NSInvocation getReturnValue:"];
}

- (void)lc32_setGuestReturnValue:(uint32_t)storage {
    if(!LC32TransferHostInvocationValue(self, @selector(setReturnValue:), storage, 0))
        [NSException raise:NSInvalidArgumentException
            format:@"LC32: unsupported type or invalid guest buffer for NSInvocation setReturnValue:"];
}

- (void)lc32_setGuestArgument:(uint32_t)address atIndex:(int32_t)index {
    alignas(16) LC32InvocationStorage storage = {};
    if(!LC32PrepareHostInvocationArgument(self, address, index, storage))
        [NSException raise:NSInvalidArgumentException
            format:@"LC32: unsupported type or invalid guest buffer for NSInvocation argument %d", index];
    const SEL original = @selector(setArgument:atIndex:);
    using SetArgument = void (*)(id, SEL, void *, NSInteger);
    ((SetArgument)LC32NativeHostMethod(self, original))(self, original, storage.data(), index);
}

@end
