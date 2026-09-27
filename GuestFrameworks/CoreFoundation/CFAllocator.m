#import <CoreFoundation/CoreFoundation+LC32.h>
#import "LC32CFAllocator.h"
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(CFAllocatorContext) == 9 * sizeof(uint32_t),
    "CFAllocatorContext must retain its ARM32 layout");

CFTypeID CFAllocatorGetTypeID(void) {
    return LC32_CF_CALL(LC32CoreFoundationOpGetKnownTypeID,
        LC32_CF_U32(LC32CoreFoundationTypeAllocator));
}

CFAllocatorRef CFAllocatorCreate(CFAllocatorRef allocator,
                                  CFAllocatorContext *context) {
    /* Custom allocation of the allocator object itself (including
     * kCFAllocatorUseContext) is not supported by the native-object bridge. */
    if(!LC32CFAllocatorIsBuiltin(allocator) || allocator == kCFAllocatorNull ||
       !context || context->version != 0) return NULL;
    CFAllocatorContext snapshot = *context;
    if(snapshot.retain) snapshot.info = (void *)snapshot.retain(snapshot.info);
    CFAllocatorRef result = (CFAllocatorRef)LC32_CF_CALL(
        LC32CoreFoundationOpAllocatorCreate,
        LC32_CF_U32((uintptr_t)&snapshot));
    if(!result && snapshot.release) snapshot.release(snapshot.info);
    return result;
}

static void *LC32DefaultAllocate(CFIndex size, CFOptionFlags hint, void *info) {
    (void)hint; (void)info;
    return size > 0 ? malloc((size_t)size) : NULL;
}
static void *LC32DefaultReallocate(void *ptr, CFIndex size,
                                  CFOptionFlags hint, void *info) {
    (void)hint; (void)info;
    return realloc(ptr, (size_t)size);
}
static void LC32DefaultDeallocate(void *ptr, void *info) {
    (void)info;
    free(ptr);
}

void CFAllocatorGetContext(CFAllocatorRef allocator, CFAllocatorContext *context) {
    if(!context) return;
    memset(context, 0, sizeof(*context));
    if(LC32CFAllocatorIsBuiltin(allocator)) {
        if(allocator != kCFAllocatorNull) {
            context->allocate = LC32DefaultAllocate;
            context->reallocate = LC32DefaultReallocate;
            context->deallocate = LC32DefaultDeallocate;
        }
    } else {
        LC32_CF_CALL(LC32CoreFoundationOpAllocatorGetContext,
            LC32_CF_HOST(allocator), LC32_CF_U32((uintptr_t)context));
    }
}

void *CFAllocatorAllocate(CFAllocatorRef allocator, CFIndex size,
                          CFOptionFlags hint) {
    if(size <= 0) return NULL;
    CFAllocatorContext context;
    CFAllocatorGetContext(allocator, &context);
    return context.allocate ? context.allocate(size, hint, context.info) : NULL;
}

void CFAllocatorDeallocate(CFAllocatorRef allocator, void *ptr) {
    if(!ptr) return;
    CFAllocatorContext context;
    CFAllocatorGetContext(allocator, &context);
    if(context.deallocate) context.deallocate(ptr, context.info);
}

void *CFAllocatorReallocate(CFAllocatorRef allocator, void *ptr,
                            CFIndex size, CFOptionFlags hint) {
    if(size < 0) return NULL;
    if(!ptr) return CFAllocatorAllocate(allocator, size, hint);
    if(!size) {
        CFAllocatorDeallocate(allocator, ptr);
        return NULL;
    }
    CFAllocatorContext context;
    CFAllocatorGetContext(allocator, &context);
    return context.reallocate
        ? context.reallocate(ptr, size, hint, context.info) : NULL;
}

CFIndex CFAllocatorGetPreferredSizeForSize(CFAllocatorRef allocator,
                                          CFIndex size, CFOptionFlags hint) {
    if(size <= 0) return 0;
    CFAllocatorContext context;
    CFAllocatorGetContext(allocator, &context);
    CFIndex preferred = context.preferredSize
        ? context.preferredSize(size, hint, context.info) : size;
    return preferred > size ? preferred : size;
}
