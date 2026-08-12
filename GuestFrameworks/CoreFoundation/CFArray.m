#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    LC32MaximumArraySortEntries = 1024 * 1024,
};

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

CFArrayRef CFArrayCreateCopy(CFAllocatorRef allocator,
                             CFArrayRef array) {
    (void)allocator;
    return array ? (CFArrayRef)[(NSArray *)array copy] : NULL;
}

CFMutableArrayRef CFArrayCreateMutableCopy(CFAllocatorRef allocator,
                                           CFIndex capacity,
                                           CFArrayRef array) {
    (void)allocator;
    if(capacity < 0 || !array) return NULL;
    return (CFMutableArrayRef)[(NSArray *)array mutableCopy];
}

void CFArrayAppendValue(CFMutableArrayRef array, const void *value) {
    if(array && value) [(NSMutableArray *)array addObject:(id)value];
}

void CFArrayAppendArray(CFMutableArrayRef array, CFArrayRef otherArray,
                        CFRange otherRange) {
    if(!array || !otherArray || otherRange.location < 0 ||
       otherRange.length < 0) return;
    const CFIndex count = CFArrayGetCount(otherArray);
    if(otherRange.location > count ||
       otherRange.length > count - otherRange.location) return;
    for(CFIndex index = 0; index < otherRange.length; ++index) {
        CFArrayAppendValue(array, CFArrayGetValueAtIndex(
            otherArray, otherRange.location + index));
    }
}

void CFArrayInsertValueAtIndex(CFMutableArrayRef array, CFIndex index,
                               const void *value) {
    if(array && value && index >= 0)
        [(NSMutableArray *)array insertObject:(id)value
                                     atIndex:(NSUInteger)index];
}

void CFArrayRemoveAllValues(CFMutableArrayRef array) {
    if(array) [(NSMutableArray *)array removeAllObjects];
}

void CFArrayRemoveValueAtIndex(CFMutableArrayRef array, CFIndex index) {
    if(array && index >= 0)
        [(NSMutableArray *)array removeObjectAtIndex:(NSUInteger)index];
}

void CFArraySetValueAtIndex(CFMutableArrayRef array, CFIndex index,
                            const void *value) {
    if(array && value && index >= 0)
        [(NSMutableArray *)array replaceObjectAtIndex:(NSUInteger)index
                                           withObject:(id)value];
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

void CFArrayApplyFunction(CFArrayRef array, CFRange range,
                          CFArrayApplierFunction applier,
                          void *context) {
    /*
     * applier is an ARM32 code pointer.  Keep invocation in the guest rather
     * than passing it to native CoreFoundation, where it would be mistaken
     * for an arm64 callback.  Subtraction-based bounds checks avoid overflow
     * when validating the two signed, 32-bit CFIndex range fields.
     */
    if(!array || !applier || range.location < 0 || range.length < 0)
        return;

    const CFIndex count = CFArrayGetCount(array);
    if(count < 0 || range.location > count ||
       range.length > count - range.location) return;

    for(CFIndex offset = 0; offset < range.length; ++offset) {
        const void *value = CFArrayGetValueAtIndex(
            array, range.location + offset);
        applier(value, context);
    }
}

void CFArraySortValues(CFMutableArrayRef array, CFRange range,
                       CFComparatorFunction comparator, void *context) {
    if(!array || !comparator || range.location < 0 || range.length < 0)
        return;

    const CFIndex arrayCount = CFArrayGetCount(array);
    if(arrayCount < 0 || range.location > arrayCount ||
       range.length > arrayCount - range.location || range.length < 2) {
        return;
    }
    if((uint64_t)range.length > LC32MaximumArraySortEntries ||
       (uint64_t)range.length > SIZE_MAX / (2 * sizeof(void *))) {
        CRSetCrashLogMessage("LC32: CFArraySortValues range is too large");
        HALT;
    }

    /*
     * comparator is ARM32 code. Snapshot guest object pointers and perform a
     * stable bottom-up merge sort here, never passing the callback to arm64
     * CoreFoundation. The original array is updated only after sorting, so a
     * comparator observes the same collection contents throughout the sort.
     */
    const size_t count = (size_t)range.length;
    const size_t bytes = count * sizeof(void *);
    const void **storage = malloc(bytes * 2);
    if(!storage) {
        CRSetCrashLogMessage("LC32: CFArraySortValues allocation failed");
        HALT;
    }
    const void **source = storage;
    const void **destination = (const void **)((uint8_t *)storage + bytes);
    for(size_t index = 0; index < count; ++index) {
        const void *value = CFArrayGetValueAtIndex(
            array, range.location + (CFIndex)index);
        /*
         * Replacing an entry can drop its host object's final array retain,
         * which in turn can dispose the associated guest proxy. Keep every
         * snapshot value alive until all replacements have completed; the
         * merge buffers themselves contain only unowned pointer copies.
         */
        source[index] = value ? CFRetain((CFTypeRef)value) : NULL;
    }

    for(size_t width = 1; width < count;) {
        for(size_t start = 0; start < count;) {
            const size_t middle = start +
                (width < count - start ? width : count - start);
            const size_t remaining = count - middle;
            const size_t end = middle +
                (width < remaining ? width : remaining);
            size_t left = start;
            size_t right = middle;
            size_t output = start;
            while(left < middle && right < end) {
                if(comparator(source[left], source[right], context) <= 0)
                    destination[output++] = source[left++];
                else
                    destination[output++] = source[right++];
            }
            while(left < middle) destination[output++] = source[left++];
            while(right < end) destination[output++] = source[right++];
            start = end;
        }
        const void **temporary = source;
        source = destination;
        destination = temporary;
        if(width > count / 2) break;
        width *= 2;
    }

    for(size_t index = 0; index < count; ++index) {
        CFArraySetValueAtIndex(array, range.location + (CFIndex)index,
                               source[index]);
    }
    for(size_t index = 0; index < count; ++index) {
        if(source[index]) CFRelease((CFTypeRef)source[index]);
    }
    free(storage);
}
