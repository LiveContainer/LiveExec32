#import <CoreFoundation/CoreFoundation+LC32.h>

#include <string.h>

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
