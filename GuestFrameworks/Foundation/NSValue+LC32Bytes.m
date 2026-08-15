#import <Foundation/Foundation.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Raw NSValue storage is ABI-dependent.  In particular, SEL is four bytes in
 * the ARMv7 guest and eight bytes in the ARM64 host.  Keep the original guest
 * word beside the proxy so -getValue: writes only the amount the guest
 * allocated, while giving native Foundation a real host SEL rather than an
 * opaque guest address.
 *
 * Other encodings need their own layout conversion before they can safely use
 * these APIs.  Known geometry types already use the generated typed NSValue
 * methods, so reject unknown raw layouts instead of silently corrupting them.
 */
@interface LC32SelectorValueStorage : LC32GuestBuffer
@end

@implementation LC32SelectorValueStorage
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

@implementation NSValue (LC32Bytes)

+ (instancetype)valueWithBytes:(const void *)bytes
                       objCType:(const char *)type {
    const char *unqualifiedType = LC32UnqualifiedValueType(type);
    if(!bytes || !unqualifiedType || strcmp(unqualifiedType, ":") != 0) {
        LC32RejectUnsupportedValueType("valueWithBytes:objCType:", type);
        return nil;
    }

    uint32_t guestSelector = 0;
    memcpy(&guestSelector, bytes, sizeof(guestSelector));
    uint64_t hostSelector = guestSelector
        ? LC32GetHostSelector((SEL)(uintptr_t)guestSelector)
        : 0;

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    const uint64_t hostType = LC32GuestToHostCString(type, 0);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, command,
        LC32HostIndirectArgument(&hostSelector), hostType, (uint64_t)0);
    LC32GuestToHostCStringFree(hostType);
    if(!result) return nil;

    LC32SelectorValueStorage *storage = [LC32SelectorValueStorage new];
    storage->_bytes = malloc(sizeof(guestSelector));
    if(!storage->_bytes) {
        [storage release];
        CRSetCrashLogMessage(
            "LC32: could not allocate NSValue selector storage");
        return nil;
    }
    storage->_capacity = sizeof(guestSelector);
    memcpy(storage->_bytes, &guestSelector, sizeof(guestSelector));
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
    if(!value || !storage || storage->_capacity != sizeof(uint32_t) ||
       !storage->_bytes) {
        LC32RejectUnsupportedValueType("getValue:", NULL);
        return;
    }
    memcpy(value, storage->_bytes, sizeof(uint32_t));
}

- (const char *)objCType {
    LC32SelectorValueStorage *storage = LC32SelectorStorage(self);
    if(!storage) {
        LC32RejectUnsupportedValueType("objCType", NULL);
        return NULL;
    }
    return @encode(SEL);
}

@end
