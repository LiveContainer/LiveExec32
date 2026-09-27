#import <CoreFoundation/CoreFoundation.h>

static inline Boolean LC32CFAllocatorIsBuiltin(CFAllocatorRef allocator) {
    return !allocator || allocator == kCFAllocatorSystemDefault ||
        allocator == kCFAllocatorMalloc || allocator == kCFAllocatorMallocZone ||
        allocator == kCFAllocatorNull;
}
