#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int retains, releases, allocations, reallocations, frees; } Counts;
static int failures;
static void check(const char *name, BOOL passed) {
    printf("cfallocator-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static const void *retainInfo(const void *info) {
    ((Counts *)info)->retains++;
    return info;
}
static void releaseInfo(const void *info) { ((Counts *)info)->releases++; }
static void *allocateBytes(CFIndex size, CFOptionFlags hint, void *info) {
    (void)hint;
    ((Counts *)info)->allocations++;
    return malloc(size);
}
static void *reallocateBytes(void *bytes, CFIndex size, CFOptionFlags hint, void *info) {
    (void)hint;
    ((Counts *)info)->reallocations++;
    return realloc(bytes, size);
}
static void freeBytes(void *bytes, void *info) {
    ((Counts *)info)->frees++;
    free(bytes);
}
static CFIndex preferredSize(CFIndex size, CFOptionFlags hint, void *info) {
    (void)hint; (void)info;
    return size + 16;
}

int main(void) {
    @autoreleasepool {
        Counts counts = {};
        CFAllocatorContext context = {0, &counts, retainInfo, releaseInfo, NULL,
            allocateBytes, reallocateBytes, freeBytes, preferredSize};
        CFAllocatorRef allocator = CFAllocatorCreate(NULL, &context);
        check("create-type-and-retain", allocator && counts.retains == 1 &&
            CFGetTypeID(allocator) == CFAllocatorGetTypeID());
        if(!allocator) return 1;
        struct { CFAllocatorContext context; uint32_t guard; } copy = {{}, 0x12345678};
        CFAllocatorGetContext(allocator, &copy.context);
        check("context-layout", copy.guard == 0x12345678 &&
            copy.context.info == &counts && copy.context.retain == retainInfo &&
            copy.context.deallocate == freeBytes && copy.context.allocate == allocateBytes);
        context.info = NULL;
        check("preferred-size", CFAllocatorGetPreferredSizeForSize(allocator, 8, 0) == 24);
        char *bytes = CFAllocatorAllocate(allocator, 8, 0);
        if(!bytes) return 1;
        memcpy(bytes, "abc", 4);
        bytes = CFAllocatorReallocate(allocator, bytes, 16, 0);
        check("allocate-reallocate", bytes && !strcmp(bytes, "abc") &&
            counts.allocations == 1 && counts.reallocations == 1);
        if(!bytes) return 1;
        CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, (UInt8 *)bytes, 4, allocator);
        CFDataRef duplicate = data ? CFDataCreateCopy(NULL, data) : NULL;
        CFRelease(allocator);
        check("data-retains-owner", data && duplicate && !counts.releases && !counts.frees);
        if(data) CFRelease(data);
        check("data-releases-owner-once", counts.frees == 1 && counts.releases == 1);
        check("copied-data-independent", duplicate && CFDataGetLength(duplicate) == 4 &&
            !memcmp(CFDataGetBytePtr(duplicate), "abc", 4));
        if(duplicate) CFRelease(duplicate);
        check("no-double-free", counts.frees == 1 && counts.releases == 1);

        Counts emptyCounts = {};
        context.info = &emptyCounts;
        allocator = CFAllocatorCreate(NULL, &context);
        bytes = CFAllocatorAllocate(allocator, 1, 0);
        data = CFDataCreateWithBytesNoCopy(NULL, (UInt8 *)bytes, 0, allocator);
        CFRelease(allocator);
        if(data) CFRelease(data);
        check("empty-data-ownership", data && emptyCounts.frees == 1 &&
            emptyCounts.retains == 1 && emptyCounts.releases == 1);

        UInt8 stackBytes[] = {1, 2, 3};
        data = CFDataCreateWithBytesNoCopy(NULL, stackBytes, 3, kCFAllocatorNull);
        check("null-deallocator", data && CFDataGetLength(data) == 3);
        if(data) CFRelease(data);
        check("null-allocator", CFAllocatorAllocate(kCFAllocatorNull, 4, 0) == NULL);
        void *defaultBytes = CFAllocatorAllocate(NULL, 4, 0);
        check("default-allocator", defaultBytes != NULL);
        CFAllocatorDeallocate(NULL, defaultBytes);
#if defined(__arm__)
        context.version = 1;
        check("unsupported-context-version", CFAllocatorCreate(NULL, &context) == NULL);
#endif
    }
    return failures ? 1 : 0;
}
