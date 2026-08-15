#import <CoreFoundation/CoreFoundation+LC32.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <string.h>

static_assert(sizeof(CFPropertyListFormat) == sizeof(int32_t));
static_assert(sizeof(CFErrorRef) == sizeof(uint32_t));

static BOOL LC32IsDispatchData(id object) {
    for(Class cls = object_getClass(object); cls;
            cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if(name && strcmp(name, "OS_dispatch_data") == 0) return YES;
    }
    return NO;
}

CFPropertyListRef CFPropertyListCreateDeepCopy(
        CFAllocatorRef allocator, CFPropertyListRef propertyList,
        CFOptionFlags mutabilityOption) {
    (void)allocator;
    if(!propertyList ||
       mutabilityOption > kCFPropertyListMutableContainersAndLeaves) {
        return NULL;
    }
    return (CFPropertyListRef)LC32_CF_CALL(
        LC32CoreFoundationOpPropertyListCreateDeepCopy,
        LC32_CF_HOST(propertyList), LC32_CF_U32(mutabilityOption));
}

CFPropertyListRef CFPropertyListCreateWithData(
        CFAllocatorRef allocator, CFDataRef data, CFOptionFlags options,
        CFPropertyListFormat *format, CFErrorRef *error) {
    /* Host allocators cannot be used with guest objects. */
    (void)allocator;
    if(!data) {
        if(error) *error = NULL;
        return NULL;
    }

    const void *bytes = NULL;
    size_t length = 0;
    dispatch_data_t mappedData = NULL;
    if(LC32IsDispatchData((id)data)) {
        /*
         * Security on iOS 10 passes dispatch_data_t to this API. That object
         * is native to the guest libdispatch and has no host Objective-C
         * peer; asking for host_self would manufacture an uninitialized
         * OS_dispatch_data on the host. Flatten it while the returned map is
         * alive, then let the synchronous bridge copy those guest bytes.
         */
        mappedData = dispatch_data_create_map(
            (dispatch_data_t)data, &bytes, &length);
        if(!mappedData) {
            if(error) *error = NULL;
            return NULL;
        }
    } else {
        const CFIndex dataLength = CFDataGetLength(data);
        if(dataLength < 0) {
            if(error) *error = NULL;
            return NULL;
        }
        length = (size_t)dataLength;
        bytes = CFDataGetBytePtr(data);
    }

    CFPropertyListRef result = NULL;
    if(length <= UINT32_MAX && (!length || bytes)) {
        result = (CFPropertyListRef)LC32_CF_CALL(
            LC32CoreFoundationOpPropertyListCreateWithData,
            LC32_CF_U32((uintptr_t)bytes), LC32_CF_U32(length),
            LC32_CF_U32(options), LC32_CF_U32((uintptr_t)format),
            LC32_CF_U32((uintptr_t)error));
    } else if(error) {
        *error = NULL;
    }

    if(mappedData) dispatch_release(mappedData);
    return result;
}
