#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <stdlib.h>

CFTypeID CFErrorGetTypeID(void) {
    NSError *error = [NSError errorWithDomain:@"LC32.CFErrorType"
                                         code:0 userInfo:nil];
    return CFGetTypeID((CFTypeRef)error);
}

CFErrorRef CFErrorCreate(CFAllocatorRef allocator, CFErrorDomain domain,
                         CFIndex code, CFDictionaryRef userInfo) {
    (void)allocator;
    if(!domain) return NULL;
    return (CFErrorRef)LC32_CF_CALL(LC32CoreFoundationOpErrorCreate,
        LC32_CF_HOST(domain), LC32_CF_U32(code),
        LC32_CF_HOST(userInfo));
}

CFErrorRef CFErrorCreateWithUserInfoKeysAndValues(
        CFAllocatorRef allocator, CFErrorDomain domain, CFIndex code,
        const void *const *userInfoKeys, const void *const *userInfoValues,
        CFIndex numUserInfoValues) {
    (void)allocator;
    if(!domain || numUserInfoValues < 0 ||
       (numUserInfoValues && (!userInfoKeys || !userInfoValues)) ||
       (uint32_t)numUserInfoValues > UINT32_MAX / sizeof(uint64_t)) {
        return NULL;
    }

    const size_t count = (size_t)numUserInfoValues;
    uint64_t *hostKeys = count
        ? (uint64_t *)malloc(count * sizeof(*hostKeys)) : NULL;
    uint64_t *hostValues = count
        ? (uint64_t *)malloc(count * sizeof(*hostValues)) : NULL;
    if(count && (!hostKeys || !hostValues)) {
        free(hostKeys);
        free(hostValues);
        return NULL;
    }

    for(size_t index = 0; index < count; ++index) {
        if(!userInfoKeys[index] || !userInfoValues[index]) {
            free(hostKeys);
            free(hostValues);
            return NULL;
        }
        hostKeys[index] = LC32_CF_HOST(userInfoKeys[index]);
        hostValues[index] = LC32_CF_HOST(userInfoValues[index]);
    }

    CFErrorRef result = (CFErrorRef)LC32_CF_CALL(
        LC32CoreFoundationOpErrorCreateWithUserInfoKeysAndValues,
        LC32_CF_HOST(domain), LC32_CF_U32(code),
        LC32_CF_U32((uintptr_t)hostKeys),
        LC32_CF_U32((uintptr_t)hostValues), LC32_CF_U32(count));
    free(hostKeys);
    free(hostValues);
    return result;
}

CFErrorDomain CFErrorGetDomain(CFErrorRef error) {
    return error ? (CFErrorDomain)LC32_CF_CALL(
        LC32CoreFoundationOpErrorGetDomain, LC32_CF_HOST(error)) : NULL;
}

CFIndex CFErrorGetCode(CFErrorRef error) {
    return error ? (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpErrorGetCode, LC32_CF_HOST(error)) : 0;
}

CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef error) {
    return error ? (CFDictionaryRef)LC32_CF_CALL(
        LC32CoreFoundationOpErrorCopyUserInfo, LC32_CF_HOST(error)) : NULL;
}

CFStringRef CFErrorCopyDescription(CFErrorRef error) {
    return error ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpErrorCopyDescription, LC32_CF_HOST(error)) : NULL;
}

CFStringRef CFErrorCopyFailureReason(CFErrorRef error) {
    return error ? (CFStringRef)[[(NSError *)error localizedFailureReason] copy]
                 : NULL;
}

CFStringRef CFErrorCopyRecoverySuggestion(CFErrorRef error) {
    return error
        ? (CFStringRef)[[(NSError *)error localizedRecoverySuggestion] copy]
        : NULL;
}
