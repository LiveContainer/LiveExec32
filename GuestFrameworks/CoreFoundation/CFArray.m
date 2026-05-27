#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

const CFArrayCallBacks kCFTypeArrayCallBacks = (CFArrayCallBacks)&kCFTypeArrayCallBacks;

CFArrayRef CFArrayCreate(CFAllocatorRef allocator, const void **values, CFIndex numValues, const CFArrayCallBacks *callBacks) {
    if(!callBacks || callBacks != kCFTypeArrayCallBacks) {
        printf("LC32: CFArrayCreate called with unhandled callback\n");
        abort();
    }
    return (CFArrayRef)[NSArray arrayWithObjects:(id *)values count:count];
}

Boolean CFArrayContainsValue(CFArrayRef theArray, CFRange range, const void *value) {
    static_assert(sizeof(CFRange) == sizeof(NSRange));
    return [(NSArray *)theArray indexOfObject:(id)value inRange:(NSRange)range];
}

CFIndex CFArrayGetCount(CFArrayRef theArray) {
    return [theArray count];
}

const void * CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    return ((NSArray *)theArray)[idx];
}
