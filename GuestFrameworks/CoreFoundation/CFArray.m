#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

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
    return (__bridge CFStringRef)[(__bridge id)cf description];
}

Boolean CFEqual(CFTypeRef cf1, CFTypeRef cf2) {
    if (!cf1) { CRSetCrashLogMessage("*** CFEqual() called with NULL first argument ***"); HALT; }
    if (cf1 == cf2) return true;
    if (!cf2) { CRSetCrashLogMessage("*** CFEqual() called with NULL second argument ***"); HALT; }
    return [(__bridge id)cf1 isEqual:(__bridge id)cf2];
}

CFArrayRef CFArrayCreate(CFAllocatorRef allocator, const void **values, CFIndex numValues, const CFArrayCallBacks *callBacks) {
    if(!callBacks || callBacks != &kCFTypeArrayCallBacks) {
        CRSetCrashLogMessage("LC32: CFArrayCreate called with unhandled callback\n"); HALT;
    }
    return (CFArrayRef)[NSArray arrayWithObjects:(id *)values count:numValues];
}

Boolean CFArrayContainsValue(CFArrayRef theArray, CFRange range, const void *value) {
    static_assert(sizeof(CFRange) == sizeof(NSRange));
    return [(NSArray *)theArray indexOfObject:(id)value inRange:*(NSRange*)&range];
}

CFIndex CFArrayGetCount(CFArrayRef theArray) {
    return [(__bridge id)theArray count];
}

const void * CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    return ((NSArray *)theArray)[idx];
}
