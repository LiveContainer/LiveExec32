#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

#include <string.h>

extern const void *__CFTypeCollectionRetain(CFAllocatorRef allocator, const void *ptr);
extern void __CFTypeCollectionRelease(CFAllocatorRef allocator, const void *ptr);
const CFArrayCallBacks kCFTypeArrayCallBacks = {0, __CFTypeCollectionRetain, __CFTypeCollectionRelease, CFCopyDescription, CFEqual};

const void *__CFTypeCollectionRetain(CFAllocatorRef allocator, const void *ptr) {
    if (!ptr) { CRSetCrashLogMessage("*** __CFTypeCollectionRetain() called with NULL; likely a collection has been corrupted ***"); HALT; }
    CFTypeRef cf = (CFTypeRef)ptr;
    return CFRetain(cf);
}

void __CFTypeCollectionRelease(CFAllocatorRef allocator, const void *ptr) {
    if (!ptr) { CRSetCrashLogMessage("*** __CFTypeCollectionRelease() called with NULL; likely a collection has been corrupted ***"); HALT; }
    CFTypeRef cf = (CFTypeRef)ptr;
    CFRelease(cf);
}

CFStringRef CFCopyDescription(CFTypeRef cf) {
    return (CFStringRef)[[(id)cf description] copy];
}

Boolean CFEqual(CFTypeRef cf1, CFTypeRef cf2) {
    if (!cf1) { CRSetCrashLogMessage("*** CFEqual() called with NULL first argument ***"); HALT; }
    if (cf1 == cf2) return true;
    if (!cf2) { CRSetCrashLogMessage("*** CFEqual() called with NULL second argument ***"); HALT; }
    return [(__bridge id)cf1 isEqual:(__bridge id)cf2];
}

CFArrayRef CFArrayCreate(CFAllocatorRef allocator, const void **values, CFIndex numValues, const CFArrayCallBacks *callBacks) {
    if(!callBacks || (callBacks != &kCFTypeArrayCallBacks &&
            memcmp(callBacks, &kCFTypeArrayCallBacks,
                   sizeof(*callBacks)) != 0)) {
        CRSetCrashLogMessage("LC32: CFArrayCreate called with unhandled callback\n"); HALT;
    }
    if(numValues < 0) return NULL;
    NSMutableArray *array = [[NSMutableArray alloc]
        initWithCapacity:(NSUInteger)numValues];
    for(CFIndex index = 0; index < numValues; ++index) {
        [array addObject:(id)values[index]];
    }
    NSArray *result = [[NSArray alloc] initWithArray:array];
    [array release];
    return (CFArrayRef)result;
}

static LC32CoreFoundationCallbacksMode LC32ArrayCallbacksMode(
        const CFArrayCallBacks *callbacks) {
    if(!callbacks) return LC32CoreFoundationCallbacksNull;
    const CFArrayCallBacks zeroCallbacks = {};
    if(memcmp(callbacks, &zeroCallbacks, sizeof(*callbacks)) == 0)
        return LC32CoreFoundationCallbacksNull;
    if(callbacks == &kCFTypeArrayCallBacks ||
       memcmp(callbacks, &kCFTypeArrayCallBacks,
              sizeof(*callbacks)) == 0) {
        return LC32CoreFoundationCallbacksCFType;
    }
    /*
     * CF uses this shape for pointer arrays which compare their elements as
     * CF objects without owning them.  The callback function addresses are
     * guest addresses, so classify the semantics here and let the host use
     * its native CFCopyDescription/CFEqual implementations.
     */
    if(callbacks->version == 0 && !callbacks->retain &&
       !callbacks->release &&
       callbacks->equal == CFEqual) {
        if(callbacks->copyDescription == CFCopyDescription)
            return LC32CoreFoundationCallbacksWeakCFType;
        if(!callbacks->copyDescription)
            return LC32CoreFoundationCallbacksWeakCFTypeNoDescription;
    }
    return LC32CoreFoundationCallbacksInvalid;
}

CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef allocator,
                                       CFIndex capacity,
                                       const CFArrayCallBacks *callbacks) {
    (void)allocator;
    if(capacity < 0) return NULL;
    const LC32CoreFoundationCallbacksMode mode =
        LC32ArrayCallbacksMode(callbacks);
    if(mode == LC32CoreFoundationCallbacksInvalid) {
        CRSetCrashLogMessage(
            "LC32: CFArrayCreateMutable called with custom callbacks");
        HALT;
    }
    return (CFMutableArrayRef)LC32_CF_CALL(
        LC32CoreFoundationOpArrayCreateMutable,
        LC32_CF_U32(capacity), LC32_CF_U32(mode));
}

Boolean CFArrayContainsValue(CFArrayRef theArray, CFRange range, const void *value) {
    static_assert(sizeof(CFRange) == sizeof(NSRange));
    return [(NSArray *)theArray indexOfObject:(id)value
                                      inRange:*(NSRange *)&range] != NSNotFound;
}

CFIndex CFArrayGetCount(CFArrayRef theArray) {
    return [(__bridge id)theArray count];
}

const void * CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    return ((NSArray *)theArray)[idx];
}
