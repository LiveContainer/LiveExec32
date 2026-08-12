#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    LC32MaximumSetEntries = 1024 * 1024,
};

static Boolean LC32SetUsesCFTypeCallbacks(
        const CFSetCallBacks *callbacks) {
    return callbacks &&
        (callbacks == &kCFTypeSetCallBacks ||
         memcmp(callbacks, &kCFTypeSetCallBacks,
                sizeof(*callbacks)) == 0);
}

static Boolean LC32SetValidateCallbacks(const CFSetCallBacks *callbacks) {
    if(LC32SetUsesCFTypeCallbacks(callbacks)) return true;
    CRSetCrashLogMessage(
        "LC32: CFSet creation requires kCFTypeSetCallBacks");
    HALT;
    return false;
}

static Boolean LC32SetValidCount(CFIndex count) {
    return count >= 0 && (uint64_t)count <= LC32MaximumSetEntries;
}

static uint64_t *LC32CopySetHostValues(const void **values,
                                        CFIndex count) {
    if(!count) return NULL;
    if(!values || !LC32SetValidCount(count) ||
       (uint64_t)count > SIZE_MAX / sizeof(uint64_t)) return NULL;

    uint64_t *hostValues = malloc((size_t)count * sizeof(*hostValues));
    if(!hostValues) return NULL;
    for(CFIndex index = 0; index < count; ++index) {
        if(!values[index] ||
           !(hostValues[index] = LC32_CF_HOST(values[index]))) {
            free(hostValues);
            return NULL;
        }
    }
    return hostValues;
}

CFSetRef CFSetCreate(CFAllocatorRef allocator, const void **values,
                     CFIndex numValues,
                     const CFSetCallBacks *callbacks) {
    (void)allocator;
    if(!LC32SetValidCount(numValues) ||
       (numValues && !values) ||
       !LC32SetValidateCallbacks(callbacks)) return NULL;

    uint64_t *hostValues = LC32CopySetHostValues(values, numValues);
    if(numValues && !hostValues) return NULL;
    CFSetRef result = (CFSetRef)LC32_CF_CALL(
        LC32CoreFoundationOpSetCreate,
        LC32_CF_U32((uintptr_t)hostValues), LC32_CF_U32(numValues));
    free(hostValues);
    return result;
}

CFSetRef CFSetCreateCopy(CFAllocatorRef allocator, CFSetRef set) {
    (void)allocator;
    return set ? (CFSetRef)LC32_CF_CALL(
        LC32CoreFoundationOpSetCreateCopy, LC32_CF_HOST(set)) : NULL;
}

CFMutableSetRef CFSetCreateMutable(CFAllocatorRef allocator,
                                   CFIndex capacity,
                                   const CFSetCallBacks *callbacks) {
    (void)allocator;
    if(!LC32SetValidCount(capacity) ||
       !LC32SetValidateCallbacks(callbacks)) {
        return NULL;
    }
    return (CFMutableSetRef)LC32_CF_CALL(
        LC32CoreFoundationOpSetCreateMutable, LC32_CF_U32(capacity));
}

CFMutableSetRef CFSetCreateMutableCopy(CFAllocatorRef allocator,
                                       CFIndex capacity, CFSetRef set) {
    (void)allocator;
    if(!set || !LC32SetValidCount(capacity)) return NULL;
    return (CFMutableSetRef)LC32_CF_CALL(
        LC32CoreFoundationOpSetCreateMutableCopy,
        LC32_CF_U32(capacity), LC32_CF_HOST(set));
}

CFIndex CFSetGetCount(CFSetRef set) {
    return set ? (CFIndex)LC32_CF_CALL(
        LC32CoreFoundationOpSetGetCount, LC32_CF_HOST(set)) : 0;
}

Boolean CFSetContainsValue(CFSetRef set, const void *value) {
    return set && value && LC32_CF_CALL(
        LC32CoreFoundationOpSetContainsValue,
        LC32_CF_HOST(set), LC32_CF_HOST(value)) != 0;
}

CFIndex CFSetGetCountOfValue(CFSetRef set, const void *value) {
    return CFSetContainsValue(set, value) ? 1 : 0;
}

const void *CFSetGetValue(CFSetRef set, const void *value) {
    if(!set || !value) return NULL;
    return (const void *)LC32_CF_CALL(LC32CoreFoundationOpSetGetValue,
        LC32_CF_HOST(set), LC32_CF_HOST(value));
}

Boolean CFSetGetValueIfPresent(CFSetRef set, const void *candidate,
                               const void **value) {
    const void *result = CFSetGetValue(set, candidate);
    if(!result) return false;
    if(value) *value = result;
    return true;
}

void CFSetGetValues(CFSetRef set, const void **values) {
    if(!set || !values) return;
    LC32_CF_CALL(LC32CoreFoundationOpSetGetValues,
        LC32_CF_HOST(set), LC32_CF_U32((uintptr_t)values));
}

void CFSetApplyFunction(CFSetRef set, CFSetApplierFunction applier,
                        void *context) {
    if(!set || !applier) return;

    /*
     * The callback is ARM32 code and cannot be forwarded to native CF.  Take
     * a guest-pointer snapshot through the existing bridge, then invoke the
     * callback entirely on the guest side.
     */
    const CFIndex count = CFSetGetCount(set);
    if(count <= 0) return;
    if(!LC32SetValidCount(count) ||
       (uint64_t)count > SIZE_MAX / sizeof(void *)) return;

    const void **values = calloc((size_t)count, sizeof(*values));
    if(!values) return;
    CFSetGetValues(set, values);

    /* kCFTypeSetCallBacks cannot hold NULL, so a zero entry means the host
     * bridge declined or could not complete the snapshot. */
    for(CFIndex index = 0; index < count; ++index) {
        if(!values[index]) {
            free(values);
            return;
        }
    }
    for(CFIndex index = 0; index < count; ++index)
        applier(values[index], context);
    free(values);
}

void CFSetAddValue(CFMutableSetRef set, const void *value) {
    if(!set || !value) return;
    LC32_CF_CALL(LC32CoreFoundationOpSetAddValue,
        LC32_CF_HOST(set), LC32_CF_HOST(value));
}

void CFSetSetValue(CFMutableSetRef set, const void *value) {
    if(!set || !value) return;
    LC32_CF_CALL(LC32CoreFoundationOpSetSetValue,
        LC32_CF_HOST(set), LC32_CF_HOST(value));
}

void CFSetRemoveValue(CFMutableSetRef set, const void *value) {
    if(!set || !value) return;
    LC32_CF_CALL(LC32CoreFoundationOpSetRemoveValue,
        LC32_CF_HOST(set), LC32_CF_HOST(value));
}

void CFSetRemoveAllValues(CFMutableSetRef set) {
    if(!set) return;
    LC32_CF_CALL(LC32CoreFoundationOpSetRemoveAllValues,
        LC32_CF_HOST(set));
}
