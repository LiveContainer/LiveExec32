#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    LC32MaximumDictionaryApplyEntries = 1024 * 1024,
};

extern const void *__CFTypeCollectionRetain(CFAllocatorRef allocator,
                                             const void *ptr);
extern void __CFTypeCollectionRelease(CFAllocatorRef allocator,
                                      const void *ptr);

static CFHashCode LC32CFTypeCollectionHash(const void *ptr) {
    return [(id)ptr hash];
}

const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    (CFDictionaryCopyDescriptionCallBack)CFCopyDescription,
    (CFDictionaryEqualCallBack)CFEqual,
    LC32CFTypeCollectionHash,
};

const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    (CFDictionaryCopyDescriptionCallBack)CFCopyDescription,
    (CFDictionaryEqualCallBack)CFEqual,
};

static LC32CoreFoundationCallbacksMode LC32DictionaryKeyCallbacksMode(
        const CFDictionaryKeyCallBacks *callbacks) {
    if(!callbacks) return LC32CoreFoundationCallbacksNull;
    const CFDictionaryKeyCallBacks zeroCallbacks = {};
    if(memcmp(callbacks, &zeroCallbacks, sizeof(*callbacks)) == 0)
        return LC32CoreFoundationCallbacksNull;
    if(callbacks == &kCFTypeDictionaryKeyCallBacks ||
       memcmp(callbacks, &kCFTypeDictionaryKeyCallBacks,
              sizeof(*callbacks)) == 0) {
        return LC32CoreFoundationCallbacksCFType;
    }
    if(callbacks == &kCFCopyStringDictionaryKeyCallBacks ||
       memcmp(callbacks, &kCFCopyStringDictionaryKeyCallBacks,
              sizeof(*callbacks)) == 0) {
        return LC32CoreFoundationCallbacksCopyString;
    }
    if(callbacks->version == 0 && !callbacks->retain &&
       !callbacks->release &&
       callbacks->equal == (CFDictionaryEqualCallBack)CFEqual &&
       callbacks->hash == LC32CFTypeCollectionHash) {
        if(callbacks->copyDescription ==
                (CFDictionaryCopyDescriptionCallBack)CFCopyDescription) {
            return LC32CoreFoundationCallbacksWeakCFType;
        }
        if(!callbacks->copyDescription)
            return LC32CoreFoundationCallbacksWeakCFTypeNoDescription;
    }
    return LC32CoreFoundationCallbacksInvalid;
}

CFDictionaryRef CFDictionaryCreate(
        CFAllocatorRef allocator, const void **keys, const void **values,
        CFIndex numValues, const CFDictionaryKeyCallBacks *keyCallbacks,
        const CFDictionaryValueCallBacks *valueCallbacks) {
    if(numValues < 0 || (numValues && (!keys || !values))) return NULL;

    CFMutableDictionaryRef mutableDictionary = CFDictionaryCreateMutable(
        allocator, numValues, keyCallbacks, valueCallbacks);
    if(!mutableDictionary) return NULL;
    for(CFIndex index = 0; index < numValues; ++index) {
        if(!keys[index] || !values[index]) {
            CFRelease(mutableDictionary);
            return NULL;
        }
        CFDictionarySetValue(mutableDictionary, keys[index], values[index]);
    }

    CFDictionaryRef dictionary =
        (CFDictionaryRef)[(NSDictionary *)mutableDictionary copy];
    CFRelease(mutableDictionary);
    return dictionary;
}

static LC32CoreFoundationCallbacksMode LC32DictionaryValueCallbacksMode(
        const CFDictionaryValueCallBacks *callbacks) {
    if(!callbacks) return LC32CoreFoundationCallbacksNull;
    const CFDictionaryValueCallBacks zeroCallbacks = {};
    if(memcmp(callbacks, &zeroCallbacks, sizeof(*callbacks)) == 0)
        return LC32CoreFoundationCallbacksNull;
    if(callbacks == &kCFTypeDictionaryValueCallBacks ||
       memcmp(callbacks, &kCFTypeDictionaryValueCallBacks,
              sizeof(*callbacks)) == 0) {
        return LC32CoreFoundationCallbacksCFType;
    }
    if(callbacks->version == 0 && !callbacks->retain &&
       !callbacks->release &&
       callbacks->equal == (CFDictionaryEqualCallBack)CFEqual) {
        if(callbacks->copyDescription ==
                (CFDictionaryCopyDescriptionCallBack)CFCopyDescription) {
            return LC32CoreFoundationCallbacksWeakCFType;
        }
        if(!callbacks->copyDescription)
            return LC32CoreFoundationCallbacksWeakCFTypeNoDescription;
    }
    return LC32CoreFoundationCallbacksInvalid;
}

CFMutableDictionaryRef CFDictionaryCreateMutable(
        CFAllocatorRef allocator, CFIndex capacity,
        const CFDictionaryKeyCallBacks *keyCallbacks,
        const CFDictionaryValueCallBacks *valueCallbacks) {
    (void)allocator;
    if(capacity < 0) return NULL;
    const LC32CoreFoundationCallbacksMode keyMode =
        LC32DictionaryKeyCallbacksMode(keyCallbacks);
    const LC32CoreFoundationCallbacksMode valueMode =
        LC32DictionaryValueCallbacksMode(valueCallbacks);
    if(keyMode == LC32CoreFoundationCallbacksInvalid ||
       valueMode == LC32CoreFoundationCallbacksInvalid) {
        CRSetCrashLogMessage(
            "LC32: CFDictionaryCreateMutable called with custom callbacks");
        HALT;
    }
    return (CFMutableDictionaryRef)LC32_CF_CALL(
        LC32CoreFoundationOpDictionaryCreateMutable,
        LC32_CF_U32(capacity), LC32_CF_U32(keyMode),
        LC32_CF_U32(valueMode));
}

CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef allocator,
                                       CFDictionaryRef dictionary) {
    (void)allocator;
    return dictionary
        ? (CFDictionaryRef)[(NSDictionary *)dictionary copy]
        : NULL;
}

CFMutableDictionaryRef CFDictionaryCreateMutableCopy(
        CFAllocatorRef allocator, CFIndex capacity,
        CFDictionaryRef dictionary) {
    (void)allocator;
    if(capacity < 0 || !dictionary) return NULL;
    return (CFMutableDictionaryRef)
        [(NSDictionary *)dictionary mutableCopy];
}

CFIndex CFDictionaryGetCount(CFDictionaryRef dictionary) {
    return dictionary ? (CFIndex)LC32_CF_CALL(
        LC32CoreFoundationOpDictionaryGetCount,
        LC32_CF_HOST(dictionary)) : 0;
}

Boolean CFDictionaryContainsKey(CFDictionaryRef dictionary,
                                const void *key) {
    if(!dictionary || !key) return false;
    return LC32_CF_CALL(LC32CoreFoundationOpDictionaryContainsKey,
        LC32_CF_HOST(dictionary), LC32_CF_HOST(key)) != 0;
}

const void *CFDictionaryGetValue(CFDictionaryRef dictionary,
                                 const void *key) {
    if(!dictionary || !key) return NULL;
    return (const void *)LC32_CF_CALL(
        LC32CoreFoundationOpDictionaryGetValue,
        LC32_CF_HOST(dictionary), LC32_CF_HOST(key));
}

Boolean CFDictionaryGetValueIfPresent(CFDictionaryRef dictionary,
                                      const void *key,
                                      const void **value) {
    const void *result = CFDictionaryGetValue(dictionary, key);
    if(!result) return false;
    if(value) *value = result;
    return true;
}

void CFDictionaryGetKeysAndValues(CFDictionaryRef dictionary,
                                  const void **keys,
                                  const void **values) {
    if(!dictionary || (!keys && !values)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDictionaryGetKeysAndValues,
        LC32_CF_HOST(dictionary), LC32_CF_U32((uintptr_t)keys),
        LC32_CF_U32((uintptr_t)values));
}

void CFDictionaryApplyFunction(CFDictionaryRef dictionary,
                               CFDictionaryApplierFunction applier,
                               void *context) {
    if(!dictionary || !applier) return;

    const CFIndex count = CFDictionaryGetCount(dictionary);
    if(count <= 0) return;
    if((uint64_t)count > LC32MaximumDictionaryApplyEntries ||
       (uint64_t)count > SIZE_MAX / (2 * sizeof(void *))) {
        CRSetCrashLogMessage(
            "LC32: CFDictionaryApplyFunction collection is too large");
        HALT;
    }

    /*
     * The applier is an ARM32 function pointer, so it must never cross the
     * bridge into the native CoreFoundation implementation.  Snapshot the
     * bridged guest object pointers, then invoke the callback in guest code.
     */
    const size_t bytes = (size_t)count * sizeof(void *);
    const void **entries = calloc(1, bytes * 2);
    if(!entries) {
        CRSetCrashLogMessage(
            "LC32: CFDictionaryApplyFunction allocation failed");
        HALT;
    }
    const void **keys = entries;
    const void **values = (const void **)((uint8_t *)entries + bytes);

    CFRetain(dictionary);
    const uint32_t snapshotOK = LC32_CF_CALL(
        LC32CoreFoundationOpDictionaryGetKeysAndValues,
        LC32_CF_HOST(dictionary), LC32_CF_U32((uintptr_t)keys),
        LC32_CF_U32((uintptr_t)values));
    if(!snapshotOK) {
        CFRelease(dictionary);
        free(entries);
        CRSetCrashLogMessage(
            "LC32: CFDictionaryApplyFunction snapshot failed");
        HALT;
    }
    for(CFIndex index = 0; index < count; ++index)
        applier(keys[index], values[index], context);
    CFRelease(dictionary);
    free(entries);
}

void CFDictionaryAddValue(CFMutableDictionaryRef dictionary,
                          const void *key, const void *value) {
    CFDictionarySetValue(dictionary, key, value);
}

void CFDictionarySetValue(CFMutableDictionaryRef dictionary,
                          const void *key, const void *value) {
    if(!dictionary || !key || !value) return;
    LC32_CF_CALL(LC32CoreFoundationOpDictionarySetValue,
        LC32_CF_HOST(dictionary), LC32_CF_HOST(key), LC32_CF_HOST(value));
}

void CFDictionaryRemoveValue(CFMutableDictionaryRef dictionary,
                             const void *key) {
    if(!dictionary || !key) return;
    LC32_CF_CALL(LC32CoreFoundationOpDictionaryRemoveValue,
        LC32_CF_HOST(dictionary), LC32_CF_HOST(key));
}

void CFDictionaryRemoveAllValues(CFMutableDictionaryRef dictionary) {
    if(dictionary) [(NSMutableDictionary *)dictionary removeAllObjects];
}
