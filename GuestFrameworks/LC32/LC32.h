@import ObjectiveC;
#import <Foundation/Foundation.h>

#include <stdarg.h>

#define CRSetCrashLogMessage(msg) __assert_rtn(NULL, __FILE__, __LINE__, msg)
#define HALT __builtin_trap()

@interface NSObject(LC32)
- (instancetype)initWithHostSelf:(uint64_t)host_self;
- (void)bindHostSelf:(uint64_t)ptr;
- (uint64_t)host_self;
- (void)setHost_self:(uint64_t)ptr;
@end

uint64_t LC32Dlsym(const char *name, BOOL isFunction);

// Generated Objective-C call tracing is intentionally opt-in; high-frequency
// selectors such as view/render loops otherwise overwhelm stderr and can
// materially perturb guest scheduling. Enable it with LC32_OBJC_TRACE=1.
BOOL LC32ObjCTraceEnabled(void);

uint32_t LC32InvokeHostCRet32(uint64_t hostPtr, ...);

// Used to make guest call from host. r12 is guest function pointer. It then issues svc 1009 to halt itself to return execution back to the host
uint64_t LC32InvokeGuestC();

// Returns an address pointing to either direct memory mapped to the guest, or copied in case its boundary exceeds a guest page
// TODO: For now, this should be read-only. There is currently no mechanism to flush the copied buffer back
uint64_t LC32GuestToHostCString(const char *string, size_t length);

// Free the C string if it was copied
void LC32GuestToHostCStringFree(uint64_t string);

// Copy class name from host to guest
uint32_t LC32HostToGuestCopyClassName(char *output, size_t length, uint64_t host_input);

// Copies a native host NSString's UTF-8 representation into guest memory and
// returns the required byte count, including its terminating NUL.
uint32_t LC32CopyHostStringUTF8(uint64_t host_string, char *output,
                               uint32_t capacity);

// Returns guest-owned storage associated with an Objective-C proxy. The
// storage is released with the proxy and grows as needed, so pointer-returning
// Foundation methods do not expose inaccessible host addresses.
void *LC32GetAssociatedGuestBuffer(id object, uint32_t requiredCapacity);

// Copies a range of a native host NSData into guest memory and returns the
// number of bytes copied, or UINT32_MAX on failure.
uint32_t LC32CopyHostDataBytes(uint64_t host_data, void *output,
                              uint32_t length, uint32_t offset);

// Converts host class to guest class
Class LC32HostToGuestClass(uint64_t address);

// Get the guest object pointer from host
id LC32HostToGuestObject(uint64_t host_object);

// Dispose an allocated guest proxy when its corresponding host initializer
// returns nil. This lives in the non-ARC LC32 framework so generated ARC and
// non-ARC shims can share the same failed-initializer path.
id LC32DisposeFailedInit(id object);

// Returns host SEL address
uint64_t LC32GetHostSelector(SEL selector);
uint64_t LC32CachedHostSelector(
    uint64_t *cache __attribute__((align_value(8))), SEL selector,
    BOOL returnsStruct);

// Invoke host objc_msgSend. All arguments must be 64-bit aligned with an exception below:
// If the most significant bit of selector is set, 2 additional uint32_t arguments are reserved for return struct pointer and size
uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);

// Marks guest-owned temporary storage for a pointer argument. The host bridge
// replaces the tagged ARM address with a native pointer for the duration of
// objc_msgSend, then copies the 64-bit temporary back into guest memory.
static inline uint64_t LC32HostIndirectArgument(const void *storage) {
    return storage
        ? (UINT64_C(1) << 63) |
            (uint64_t)(uint32_t)(uintptr_t)storage
        : 0;
}

// Floating Objective-C results are returned by the ARM64 host in FP
// registers. The host bridge stores the result as IEEE-754 double bits so a
// generated ARM32 shim can reconstruct it before narrowing to float/CGFloat.
static inline double LC32HostFloatingResult(uint64_t bits) {
    union {
        uint64_t bits;
        double value;
    } result = { .bits = bits };
    return result.value;
}

typedef NS_OPTIONS(uint32_t, LC32NSStringFormatOptions) {
    LC32NSStringFormatOptionHasLocale = 1 << 0,
    LC32NSStringFormatOptionArgumentsList = 1 << 1,
};

// Rebuild an ARM32 NSString format argument list for the ARM64 host. A guest
// va_list cannot be passed directly because the two ABIs use different slot
// sizes and pointer widths.
uint64_t LC32InvokeHostNSStringFormat(uint64_t object,
                                      uint64_t selector,
                                      uint64_t format,
                                      uint64_t locale,
                                      va_list arguments,
                                      LC32NSStringFormatOptions options);

// Get the host class pointer. If returnClass is false, it returns [clsss alloc]
uint64_t LC32GetHostObject(id self, const char *name, bool returnClass);
