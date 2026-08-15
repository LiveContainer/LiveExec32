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

static LC32SelectorValueStorage *LC32SelectorStorage(id value) {
    return value
        ? objc_getAssociatedObject(value, kLC32SelectorValueStorage)
        : nil;
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
    void (*convert)(const void *guest, void *host);
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

static void LC32ConvertNSRange(const void *guest, void *host) {
    const uint32_t *src = guest;
    uint64_t *dst = host;
    dst[0] = src[0];
    dst[1] = src[1];
}

static const LC32ValueLayout LC32ValueLayouts[] = {
    {
        .guestEncoding = "{CGPoint=ff}",
        .hostEncoding = "{CGPoint=dd}",
        .guestSize = 8,
        .hostSize = 16,
        .convert = LC32ConvertFloats2,
    },
    {
        .guestEncoding = "{CGSize=ff}",
        .hostEncoding = "{CGSize=dd}",
        .guestSize = 8,
        .hostSize = 16,
        .convert = LC32ConvertFloats2,
    },
    {
        .guestEncoding = "{CGRect={CGPoint=ff}{CGSize=ff}}",
        .hostEncoding = "{CGRect={CGPoint=dd}{CGSize=dd}}",
        .guestSize = 16,
        .hostSize = 32,
        .convert = LC32ConvertFloats4,
    },
    {
        .guestEncoding = "{UIEdgeInsets=ffff}",
        .hostEncoding = "{UIEdgeInsets=dddd}",
        .guestSize = 16,
        .hostSize = 32,
        .convert = LC32ConvertFloats4,
    },
    {
        .guestEncoding = "{_NSRange=II}",
        .hostEncoding = "{_NSRange=QQ}",
        .guestSize = 8,
        .hostSize = 16,
        .convert = LC32ConvertNSRange,
    },
    {
        .guestEncoding = "{NSRange=II}",
        .hostEncoding = "{_NSRange=QQ}",
        .guestSize = 8,
        .hostSize = 16,
        .convert = LC32ConvertNSRange,
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
        layout->convert(bytes, hostValueStorage);
        guestValueSize = layout->guestSize;
        hostEncoding = layout->hostEncoding;
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    const uint64_t hostType = LC32GuestToHostCString(hostEncoding, 0);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, command,
        LC32HostIndirectArgument(hostValueStorage), hostType, (uint64_t)0);
    LC32GuestToHostCStringFree(hostType);
    free(hostValueStorage);
    if(!result) return nil;

    LC32SelectorValueStorage *storage = [LC32SelectorValueStorage new];
    storage->_bytes = malloc(guestValueSize);
    if(!storage->_bytes) {
        [storage release];
        CRSetCrashLogMessage(
            "LC32: could not allocate NSValue storage");
        return nil;
    }
    storage->_capacity = guestValueSize;
    storage->_typeEncoding = strdup(unqualifiedType);
    if(!storage->_typeEncoding) {
        free(storage->_bytes);
        storage->_bytes = NULL;
        storage->_capacity = 0;
        [storage release];
        CRSetCrashLogMessage(
            "LC32: could not allocate NSValue type encoding");
        return nil;
    }
    memcpy(storage->_bytes, bytes, guestValueSize);
    objc_setAssociatedObject(result, kLC32SelectorValueStorage, storage,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [storage release];
    return LC32ReturnBorrowedGuestObject(result);
}

+ (instancetype)value:(const void *)value
          withObjCType:(const char *)type {
    return [self valueWithBytes:value objCType:type];
}

- (void)getValue:(void *)value {
    LC32SelectorValueStorage *storage = LC32SelectorStorage(self);
    if(!value || !storage || !storage->_bytes ||
       storage->_capacity == 0) {
        LC32RejectUnsupportedValueType("getValue:", NULL);
        return;
    }
    memcpy(value, storage->_bytes, storage->_capacity);
}

- (const char *)objCType {
    LC32SelectorValueStorage *storage = LC32SelectorStorage(self);
    if(!storage || !storage->_typeEncoding) {
        LC32RejectUnsupportedValueType("objCType", NULL);
        return NULL;
    }
    return storage->_typeEncoding;
}

@end
