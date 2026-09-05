#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Raw NSValue storage is ABI-dependent.  In particular, SEL is four bytes in
 * the ARMv7 guest and eight bytes in the ARM64 host, and CGFloat is a float in
 * the guest but a double on the host.  Keep the original guest bytes beside
 * the proxy so -getValue: writes only the amount the guest allocated, while
 * giving native Foundation a real host SEL rather than an opaque guest address
 * and widening guest geometry to the native layout.
 */
@interface LC32SelectorValueStorage : LC32GuestBuffer {
@public
    char *_typeEncoding;
    uint32_t _hostCapacity;
}
@end

@implementation LC32SelectorValueStorage
- (void)dealloc {
    free(_typeEncoding);
    [super dealloc];
}
@end

static const void *kLC32SelectorValueStorage =
    &kLC32SelectorValueStorage;

static const char *LC32UnqualifiedValueType(const char *type) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    return type;
}

/*
 * Guest callbacks can enter Foundation on more than one native thread.  Once
 * published, an objCType pointer must remain valid for the lifetime of the
 * value, so never replace an installed storage object.  Retaining while under
 * the object monitor also makes the read safe against a concurrent first
 * installation.
 */
static LC32SelectorValueStorage *LC32RetainedSelectorStorage(id value) {
    if(!value) return nil;
    @synchronized(value) {
        return [objc_getAssociatedObject(
            value, kLC32SelectorValueStorage) retain];
    }
}

/* Returns a retained installed storage object. */
static LC32SelectorValueStorage *LC32InstallSelectorStorageIfAbsent(
        id value, LC32SelectorValueStorage *candidate) {
    if(!value || !candidate) return nil;
    @synchronized(value) {
        LC32SelectorValueStorage *storage = objc_getAssociatedObject(
            value, kLC32SelectorValueStorage);
        if(!storage) {
            objc_setAssociatedObject(value, kLC32SelectorValueStorage,
                                     candidate,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            storage = candidate;
        }
        return [storage retain];
    }
}

static void LC32RejectUnsupportedValueType(const char *operation,
                                            const char *type) {
    char message[256];
    snprintf(message, sizeof(message),
        "LC32: unsupported NSValue %s encoding %s", operation,
        type ?: "(null)");
    CRSetCrashLogMessage(message);
}

/* Guest (ARM32) struct encodings whose layout differs on the ARM64 host. */
typedef struct LC32ValueLayout {
    const char *guestEncoding;
    const char *hostEncoding;
    uint32_t guestSize;
    uint32_t hostSize;
    void (*guestToHost)(const void *guest, void *host);
    void (*hostToGuest)(const void *host, void *guest);
} LC32ValueLayout;

static void LC32ConvertFloats2(const void *guest, void *host) {
    const float *src = guest;
    double *dst = host;
    dst[0] = src[0];
    dst[1] = src[1];
}

static void LC32ConvertFloats4(const void *guest, void *host) {
    const float *src = guest;
    double *dst = host;
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
    dst[3] = src[3];
}

static void LC32NarrowFloats2(const void *host, void *guest) {
    const double *src = host;
    float *dst = guest;
    dst[0] = (float)src[0];
    dst[1] = (float)src[1];
}

static void LC32NarrowFloats4(const void *host, void *guest) {
    const double *src = host;
    float *dst = guest;
    dst[0] = (float)src[0];
    dst[1] = (float)src[1];
    dst[2] = (float)src[2];
    dst[3] = (float)src[3];
}

static void LC32ConvertNSRange(const void *guest, void *host) {
    const uint32_t *src = guest;
    uint64_t *dst = host;
    dst[0] = src[0] == UINT32_C(0x7fffffff)
        ? UINT64_C(0x7fffffffffffffff)
        : src[0];
    dst[1] = src[1];
}

static void LC32NarrowNSRangeValue(const void *host, void *guest) {
    const uint64_t *src = host;
    uint32_t *dst = guest;
    dst[0] = src[0] == UINT64_C(0x7fffffffffffffff)
        ? UINT32_C(0x7fffffff)
        : (uint32_t)src[0];
    dst[1] = (uint32_t)src[1];
}

static const LC32ValueLayout LC32ValueLayouts[] = {
    {
        .guestEncoding = "{CGPoint=ff}",
        .hostEncoding = "{CGPoint=dd}",
        .guestSize = 8,
        .hostSize = 16,
        .guestToHost = LC32ConvertFloats2,
        .hostToGuest = LC32NarrowFloats2,
    },
    {
        .guestEncoding = "{CGSize=ff}",
        .hostEncoding = "{CGSize=dd}",
        .guestSize = 8,
        .hostSize = 16,
        .guestToHost = LC32ConvertFloats2,
        .hostToGuest = LC32NarrowFloats2,
    },
    {
        .guestEncoding = "{CGRect={CGPoint=ff}{CGSize=ff}}",
        .hostEncoding = "{CGRect={CGPoint=dd}{CGSize=dd}}",
        .guestSize = 16,
        .hostSize = 32,
        .guestToHost = LC32ConvertFloats4,
        .hostToGuest = LC32NarrowFloats4,
    },
    {
        .guestEncoding = "{UIEdgeInsets=ffff}",
        .hostEncoding = "{UIEdgeInsets=dddd}",
        .guestSize = 16,
        .hostSize = 32,
        .guestToHost = LC32ConvertFloats4,
        .hostToGuest = LC32NarrowFloats4,
    },
    {
        .guestEncoding = "{_NSRange=II}",
        .hostEncoding = "{_NSRange=QQ}",
        .guestSize = 8,
        .hostSize = 16,
        .guestToHost = LC32ConvertNSRange,
        .hostToGuest = LC32NarrowNSRangeValue,
    },
    {
        .guestEncoding = "{NSRange=II}",
        .hostEncoding = "{_NSRange=QQ}",
        .guestSize = 8,
        .hostSize = 16,
        .guestToHost = LC32ConvertNSRange,
        .hostToGuest = LC32NarrowNSRangeValue,
    },
};

static const LC32ValueLayout *LC32ValueLayoutForEncoding(
        const char *unqualifiedType) {
    if(!unqualifiedType || !*unqualifiedType) return NULL;
    for(size_t i = 0; i < sizeof(LC32ValueLayouts) /
            sizeof(LC32ValueLayouts[0]); i++) {
        if(strcmp(unqualifiedType, LC32ValueLayouts[i].guestEncoding) == 0) {
            return &LC32ValueLayouts[i];
        }
    }
    return NULL;
}

/* Host NSValues created outside the guest adapter (e.g. NSNumber, or values
 * returned by native code) have no LC32SelectorValueStorage.  The host
 * reports its own ABI encoding; map it back to the guest layout so callers
 * see the same encoding a guest-created value would report. */
static const LC32ValueLayout *LC32ValueLayoutForHostEncoding(
        const char *hostEncoding) {
    if(!hostEncoding || !*hostEncoding) return NULL;
    for(size_t i = 0; i < sizeof(LC32ValueLayouts) /
            sizeof(LC32ValueLayouts[0]); i++) {
        if(strcmp(hostEncoding, LC32ValueLayouts[i].hostEncoding) == 0) {
            return &LC32ValueLayouts[i];
        }
    }
    return NULL;
}

/* Native Darwin keeps these scalar widths identical to ARM32 except for
 * long/unsigned long.  Pointer-like encodings deliberately are not accepted:
 * narrowing a native address (or SEL) would not produce a valid guest value. */
static BOOL LC32ScalarValueSizes(const char *type, uint32_t *guestSize,
                                 uint32_t *hostSize) {
    type = LC32UnqualifiedValueType(type);
    if(!type || !*type) return NO;

    uint32_t guest = 0;
    uint32_t host = 0;
    switch(*type) {
        case 'B':
        case 'C':
        case 'c':
            guest = host = 1;
            break;
        case 'S':
        case 's':
            guest = host = 2;
            break;
        case 'I':
        case 'i':
        case 'f':
            guest = host = 4;
            break;
        case 'L':
        case 'l':
            guest = 4;
            host = 8;
            break;
        case 'D':
        case 'Q':
        case 'd':
        case 'q':
            guest = host = 8;
            break;
        default:
            return NO;
    }
    if(guestSize) *guestSize = guest;
    if(hostSize) *hostSize = host;
    return YES;
}

static BOOL LC32ConvertHostScalarToGuest(const char *type,
                                         const void *host,
                                         void *guest) {
    type = LC32UnqualifiedValueType(type);
    uint32_t guestSize = 0;
    if(!LC32ScalarValueSizes(type, &guestSize, NULL)) return NO;

    if(*type == 'l') {
        int64_t source = 0;
        int32_t destination = 0;
        memcpy(&source, host, sizeof(source));
        destination = (int32_t)source;
        memcpy(guest, &destination, sizeof(destination));
    } else if(*type == 'L') {
        uint64_t source = 0;
        uint32_t destination = 0;
        memcpy(&source, host, sizeof(source));
        destination = (uint32_t)source;
        memcpy(guest, &destination, sizeof(destination));
    } else {
        memcpy(guest, host, guestSize);
    }
    return YES;
}

/* Fetch the host's objCType for an NSValue that lacks guest storage and
 * return the guest-facing encoding, or NULL on failure. */
static const char *LC32CanonicalGuestNumberEncoding(
        id value, const char *hostEncoding) {
    if(!hostEncoding || ![value isKindOfClass:[NSNumber class]]) return NULL;

    /*
     * NSNumber's class cluster canonicalizes native-word integer boxes to `q`
     * on ARM64.  ARM32's native NSInteger/NSUInteger values are only 32 bits,
     * and exposing the host canonical width makes -getValue: overwrite a
     * guest-sized destination.  Pick the narrowest lossless ARM32 integer
     * representation.  Values outside ARM32's integer range remain 64-bit.
     */
    if(strcmp(hostEncoding, "q") == 0) {
        static uint64_t hostSelector __attribute__((aligned(8)));
        const uint64_t selector = LC32CachedHostSelector(
            &hostSelector, @selector(longLongValue), NO);
        const int64_t number = (int64_t)LC32InvokeHostSelector(
            [value host_self], selector, (uint64_t)0);
        if(number >= INT32_MIN && number <= INT32_MAX) return "i";
        if(number >= 0 && (uint64_t)number <= UINT32_MAX) return "I";
    } else if(strcmp(hostEncoding, "Q") == 0) {
        static uint64_t hostSelector __attribute__((aligned(8)));
        const uint64_t selector = LC32CachedHostSelector(
            &hostSelector, @selector(unsignedLongLongValue), NO);
        const uint64_t number = LC32InvokeHostSelector(
            [value host_self], selector, (uint64_t)0);
        if(number <= UINT32_MAX) return "I";
    }
    return NULL;
}

static char *LC32HostValueTypeEncoding(id value, uint32_t *hostCapacity) {
    if(hostCapacity) *hostCapacity = 0;
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(objCType), NO);
    const uint64_t hostType = LC32InvokeHostSelector(
        [value host_self], selector, (uint64_t)0);
    if(!hostType) return NULL;
    uint32_t required = LC32CopyHostCString(hostType, NULL, 0);
    if(!required) return NULL;
    char *type = malloc(required);
    if(!type) return NULL;
    if(LC32CopyHostCString(hostType, type, required) != required) {
        free(type);
        return NULL;
    }
    const char *unqualifiedType = LC32UnqualifiedValueType(type);
    const LC32ValueLayout *layout = LC32ValueLayoutForHostEncoding(
        unqualifiedType);
    if(layout) {
        if(hostCapacity) *hostCapacity = layout->hostSize;
        free(type);
        type = strdup(layout->guestEncoding);
        if(!type) return NULL;
    } else {
        uint32_t nativeSize = 0;
        if(LC32ScalarValueSizes(unqualifiedType, NULL, &nativeSize) &&
           hostCapacity) {
            *hostCapacity = nativeSize;
        }
        const char *numberEncoding = LC32CanonicalGuestNumberEncoding(
            value, unqualifiedType);
        if(numberEncoding) {
            char *guestType = strdup(numberEncoding);
            if(!guestType) {
                free(type);
                return NULL;
            }
            free(type);
            type = guestType;
        }
    }
    return type;
}

static LC32SelectorValueStorage *LC32CreateHostValueStorage(id value) {
    uint32_t hostCapacity = 0;
    char *typeEncoding = LC32HostValueTypeEncoding(value, &hostCapacity);
    if(!typeEncoding) return nil;
    LC32SelectorValueStorage *storage = [LC32SelectorValueStorage new];
    storage->_typeEncoding = typeEncoding;
    storage->_hostCapacity = hostCapacity;
    return storage;
}

/* Returns a retained storage object, creating it from the native value once. */
static LC32SelectorValueStorage *LC32RetainedStorageForHostValue(id value) {
    LC32SelectorValueStorage *storage = LC32RetainedSelectorStorage(value);
    if(storage) return storage;

    LC32SelectorValueStorage *candidate = LC32CreateHostValueStorage(value);
    if(!candidate) return nil;
    storage = LC32InstallSelectorStorageIfAbsent(value, candidate);
    [candidate release];
    return storage;
}

/*
 * Publish the ARM32 representation alongside the native NSValue.  Native
 * Foundation stores pointers and selectors at the host width, while callers
 * of -getValue: have allocated only the width described by the guest SDK.
 */
static id LC32InstallGuestValueStorage(id value, const void *bytes,
                                       uint32_t guestSize,
                                       uint32_t hostSize,
                                       const char *type) {
    if(!value || !bytes || !guestSize || !hostSize || !type || !*type) {
        return nil;
    }

    LC32SelectorValueStorage *storage = [LC32SelectorValueStorage new];
    storage->_bytes = malloc(guestSize);
    if(!storage->_bytes) {
        [storage release];
        CRSetCrashLogMessage(
            "LC32: could not allocate NSValue storage");
        return nil;
    }
    storage->_capacity = guestSize;
    storage->_hostCapacity = hostSize;
    storage->_typeEncoding = strdup(type);
    if(!storage->_typeEncoding) {
        free(storage->_bytes);
        storage->_bytes = NULL;
        storage->_capacity = 0;
        [storage release];
        CRSetCrashLogMessage(
            "LC32: could not allocate NSValue type encoding");
        return nil;
    }
    memcpy(storage->_bytes, bytes, guestSize);
    LC32SelectorValueStorage *installed =
        LC32InstallSelectorStorageIfAbsent(value, storage);
    [installed release];
    [storage release];
    return LC32ReturnBorrowedGuestObject(value);
}

@implementation NSValue (LC32Bytes)

+ (instancetype)valueWithBytes:(const void *)bytes
                       objCType:(const char *)type {
    const char *unqualifiedType = LC32UnqualifiedValueType(type);
    if(!bytes || !unqualifiedType || !*unqualifiedType) {
        LC32RejectUnsupportedValueType("valueWithBytes:objCType:", type);
        return nil;
    }

    void *hostValueStorage = NULL;
    uint32_t guestValueSize = 0;
    uint32_t hostValueSize = 0;
    const char *hostEncoding = NULL;
    if(strcmp(unqualifiedType, ":") == 0) {
        uint32_t guestSelector = 0;
        memcpy(&guestSelector, bytes, sizeof(guestSelector));
        uint64_t hostSelector = guestSelector
            ? LC32GetHostSelector((SEL)(uintptr_t)guestSelector)
            : 0;
        hostValueStorage = malloc(sizeof(hostSelector));
        if(!hostValueStorage) return nil;
        memcpy(hostValueStorage, &hostSelector, sizeof(hostSelector));
        guestValueSize = sizeof(guestSelector);
        hostValueSize = sizeof(hostSelector);
        hostEncoding = ":";
    } else {
        const LC32ValueLayout *layout =
            LC32ValueLayoutForEncoding(unqualifiedType);
        if(!layout) {
            LC32RejectUnsupportedValueType(
                "valueWithBytes:objCType:", type);
            return nil;
        }
        hostValueStorage = malloc(layout->hostSize);
        if(!hostValueStorage) return nil;
        layout->guestToHost(bytes, hostValueStorage);
        guestValueSize = layout->guestSize;
        hostValueSize = layout->hostSize;
        hostEncoding = layout->hostEncoding;
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    const uint64_t hostType = LC32GuestToHostCString(hostEncoding, 0);
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(
        &descriptor, hostValueStorage, hostValueSize);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, command,
        LC32HostSizedIndirectArgument(&descriptor), hostType, (uint64_t)0);
    LC32GuestToHostCStringFree(hostType);
    free(hostValueStorage);
    if(!result) return nil;
    return LC32InstallGuestValueStorage(
        result, bytes, guestValueSize, hostValueSize, unqualifiedType);
}

+ (instancetype)value:(const void *)value
          withObjCType:(const char *)type {
    return [self valueWithBytes:value objCType:type];
}

+ (instancetype)valueWithPointer:(const void *)pointer {
    /* NSValue treats this as an opaque token, so zero-extension is sufficient
     * for the native box.  Preserve the original guest-width representation
     * for -pointerValue and -getValue: rather than exposing host pointer width
     * to the guest. */
    const uint32_t guestPointer = (uint32_t)(uintptr_t)pointer;
    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, command, (uint64_t)guestPointer, (uint64_t)0);
    return LC32InstallGuestValueStorage(
        result, &guestPointer, sizeof(guestPointer), sizeof(uint64_t),
        @encode(void *));
}

- (void)getValue:(void *)value {
    if(!value) {
        LC32RejectUnsupportedValueType("getValue:", NULL);
        return;
    }
    LC32SelectorValueStorage *storage =
        LC32RetainedStorageForHostValue(self);
    if(!storage) {
        LC32RejectUnsupportedValueType("getValue:", NULL);
        return;
    }
    if(storage && storage->_bytes && storage->_capacity) {
        memcpy(value, storage->_bytes, storage->_capacity);
        [storage release];
        return;
    }

    /* Host-created values do not carry the original ARM32 bytes.  Decode into
     * an explicitly sized native cell, then narrow into the caller's guest
     * allocation.  A prior -objCType call may already have cached just the
     * encoding, so the absence of `_bytes` (rather than of the association)
     * identifies this path. */
    const char *type = storage->_typeEncoding;
    if(!type) {
        [storage release];
        LC32RejectUnsupportedValueType("getValue:", NULL);
        return;
    }

    const char *unqualifiedType = LC32UnqualifiedValueType(type);
    const LC32ValueLayout *layout =
        LC32ValueLayoutForEncoding(unqualifiedType);
    uint32_t guestSize = 0;
    if(layout) {
        guestSize = layout->guestSize;
    } else if(!LC32ScalarValueSizes(
                  unqualifiedType, &guestSize, NULL)) {
        [storage release];
        LC32RejectUnsupportedValueType("getValue:", type);
        return;
    }
    const uint32_t hostSize = storage->_hostCapacity;
    if(!hostSize || hostSize > LC32_HOST_SIZED_INDIRECT_MAX_SIZE) {
        [storage release];
        LC32RejectUnsupportedValueType("getValue:", type);
        return;
    }
    if(!guestSize || hostSize < guestSize) {
        [storage release];
        LC32RejectUnsupportedValueType("getValue:", type);
        return;
    }

    void *hostBytes = calloc(1, hostSize);
    if(!hostBytes) {
        [storage release];
        LC32RejectUnsupportedValueType("getValue:", type);
        return;
    }
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(
        &descriptor, hostBytes, hostSize);
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(
        self.host_self, selector,
        LC32HostSizedIndirectArgument(&descriptor), (uint64_t)0);

    if(layout) {
        layout->hostToGuest(hostBytes, value);
    } else if(!LC32ConvertHostScalarToGuest(
                  unqualifiedType, hostBytes, value)) {
        LC32RejectUnsupportedValueType("getValue:", type);
    }
    free(hostBytes);
    [storage release];
}

- (const char *)objCType {
    LC32SelectorValueStorage *storage =
        LC32RetainedStorageForHostValue(self);
    if(!storage || !storage->_typeEncoding) {
        [storage release];
        LC32RejectUnsupportedValueType("objCType", NULL);
        return NULL;
    }
    const char *type = storage->_typeEncoding;
    [storage release];
    return type;
}

- (void *)pointerValue {
    LC32SelectorValueStorage *storage =
        LC32RetainedSelectorStorage(self);
    const char *type = storage
        ? LC32UnqualifiedValueType(storage->_typeEncoding)
        : NULL;
    if(type && (*type == '^' || *type == '*') &&
            storage->_bytes &&
            storage->_capacity >= sizeof(uint32_t)) {
        uint32_t guestPointer = 0;
        memcpy(&guestPointer, storage->_bytes, sizeof(guestPointer));
        [storage release];
        return (void *)(uintptr_t)guestPointer;
    }
    [storage release];

    /* A native-created NSValue can be returned to the guest as well.  Only
     * opaque values representable in the ARM32 address space are safe to
     * expose; never silently truncate an actual ARM64 address. */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostPointer = LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0);
    if(hostPointer != (uint64_t)(uint32_t)hostPointer) {
        LC32RejectUnsupportedValueType("pointerValue", @encode(void *));
        return NULL;
    }
    return (void *)(uintptr_t)(uint32_t)hostPointer;
}

@end
