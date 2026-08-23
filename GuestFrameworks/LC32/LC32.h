@import ObjectiveC;
#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <LC32BlockBridgeABI.h>
#include <LC32FoundationBridgeABI.h>
#include <LC32ObjCBridgeABI.h>

#define CRSetCrashLogMessage(msg) __assert_rtn(NULL, __FILE__, __LINE__, msg)
#define HALT __builtin_trap()

/* Darwin Clang does not support __attribute__((alias)) for Mach-O symbols.
 * Emit a public assembler alias instead so both exported spellings have the
 * same address and no forwarding thunk is introduced. */
#define LC32_ASM_STRINGIFY_INNER(value) #value
#define LC32_ASM_STRINGIFY(value) LC32_ASM_STRINGIFY_INNER(value)
#define LC32_ASM_GLOBAL_ALIAS(alias, target) \
    __asm__(".globl _" LC32_ASM_STRINGIFY(alias) "\n" \
            "_" LC32_ASM_STRINGIFY(alias) " = _" \
            LC32_ASM_STRINGIFY(target))

@interface NSObject(LC32)
- (instancetype)initWithHostSelf:(uint64_t)host_self;
- (void)bindHostSelf:(uint64_t)ptr;
- (uint64_t)host_self;
- (uint64_t)LC32_rawHostSelf;
- (void)setHost_self:(uint64_t)ptr;
@end

/*
 * Base class for guest-only associated storage. LC32 installs the original
 * NSObject ownership methods directly on this class before globally
 * swizzling proxy ownership, so subclasses never acquire a host peer.
 */
@interface LC32GuestBuffer : NSObject {
@public
    void *_bytes;
    uint32_t _capacity;
}
@end

uint64_t LC32Dlsym(const char *name, BOOL isFunction);

// Generated Objective-C call tracing is intentionally opt-in; high-frequency
// selectors such as view/render loops otherwise overwhelm stderr and can
// materially perturb guest scheduling. Enable it with LC32_OBJC_TRACE=1.
BOOL LC32ObjCTraceEnabled(void);

uint32_t LC32InvokeHostCRet32(uint64_t hostPtr, ...);

// Used to make guest call from host. r12 is guest function pointer. It then issues svc 1009 to halt itself to return execution back to the host
uint64_t LC32InvokeGuestC();

// Private native-thread callback dispatcher. The host blocks in Wait until a
// native block invocation is available, then the guest acknowledges it after
// running the block in ordinary emulated execution.
uint32_t LC32GuestCallbackExecutorWait(
    LC32GuestBlockCallbackDescriptor *descriptor);
uint32_t LC32GuestCallbackExecutorComplete(uint32_t identifier);

// Acquire the native +1 before objc_loadWeakRetained attempts its guest +1.
// A result above the LC32HostWeakRetain* sentinels is an opaque pending token.
// Implemented by private SVC 1019.
LC32HostWeakRetainResult LC32TryRetainHostWeakReference(
    uint32_t guest_object);
// Commit or roll back the exact native +1 represented by a SVC 1019 token.
// Implemented by private SVC 1021.
uint32_t LC32FinishHostWeakRetain(uint32_t token, uint32_t guest_object,
                                 uint32_t commit);

// The native generation-checked registry is authoritative for guest-to-host
// identity. Keeping this state out of guest objc associations avoids making
// every bridged object mutate the guest runtime's global association table.
// Implemented by private SVCs 1022 and 1023.
uint64_t LC32LookupHostMapping(uint32_t guest_object);
uint32_t LC32UpdateHostMapping(uint32_t guest_object,
                              LC32HostMappingOperation operation,
                              uint64_t host_object);

// Host lifetime pins call this guest-only root release and use the return
// value to decide whether a retiring weak-registry tombstone can be removed.
uint32_t LC32ReleaseGuestLifetimePin(id guest_object);

// Returns an address pointing to either direct memory mapped to the guest, or copied in case its boundary exceeds a guest page
// TODO: For now, this should be read-only. There is currently no mechanism to flush the copied buffer back
uint64_t LC32GuestToHostCString(const char *string, size_t length);

// Free the C string if it was copied
void LC32GuestToHostCStringFree(uint64_t string);

// Copy class name from host to guest
uint32_t LC32HostToGuestCopyClassName(char *output, size_t length, uint64_t host_input);

// Copies a raw host C string into guest memory and returns the required byte
// count, including its terminating NUL.
uint32_t LC32CopyHostCString(uint64_t host_cstring, char *output,
                            uint32_t capacity);

// Copies a native host NSString's UTF-8 representation into guest memory and
// returns the required byte count, including its terminating NUL.
uint32_t LC32CopyHostStringUTF8(uint64_t host_string, char *output,
                               uint32_t capacity);

// Copies a native NSString in the requested NSStringEncoding into guest
// storage. The returned size includes a terminating NUL.
uint32_t LC32CopyHostStringBytes(uint64_t host_string, uint32_t encoding,
                                char *output, uint32_t capacity);

// Performs NSString rangeOfString: variants with explicit ARM32 ranges. The
// low and high result words contain location and length, respectively.
uint64_t LC32HostStringRangeOfString(
    const LC32FoundationStringRangeRequest *request);

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

// Convert an Objective-C +1 result (alloc/new/copy/mutableCopy family) and
// transfer that ownership to the guest proxy.
id LC32HostToGuestOwnedObject(uint64_t host_object) NS_RETURNS_RETAINED;

// Dispose an allocated guest proxy when its corresponding host initializer
// returns nil. This lives in the non-ARC LC32 framework so generated ARC and
// non-ARC shims can share the same failed-initializer path.
id LC32DisposeFailedInit(id object);

// Complete a host initializer using the explicit guest receiver. Foundation
// alloc placeholders can be shared across threads, so the host result must not
// infer its reverse mapping from the placeholder's mutable association.
//
// The MRC entry point consumes the allocated guest receiver itself. ARC keeps
// `self` strong until the initializer implementation returns, so its entry
// point leaves that cleanup to the compiler and returns a separate +1. Select
// the matching ownership contract at compile time while keeping generated
// initializer bodies identical.
id LC32AdoptHostInitializerResult(id object, uint64_t hostResult)
    NS_RETURNS_RETAINED;
id LC32AdoptHostInitializerResultARC(id object, uint64_t hostResult)
    NS_RETURNS_RETAINED;
#if __has_feature(objc_arc)
#define LC32AdoptHostInitializerResult(object, hostResult) \
    LC32AdoptHostInitializerResultARC((object), (hostResult))
#endif

// Returns host SEL address
uint64_t LC32GetHostSelector(SEL selector);
uint64_t LC32CachedHostSelector(
    uint64_t *cache __attribute__((align_value(8))), SEL selector,
    BOOL returnsStruct);

// Invoke host objc_msgSend. All arguments must be 64-bit aligned with an exception below:
// If the most significant bit of selector is set, 2 additional uint32_t arguments are reserved for return struct pointer and size
uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);

// Invoke a host Objective-C method whose borrowed (+0) object result must be
// converted to its guest proxy before returning from the same SVC.  Keep this
// entry point object-typed so ARC applies the callee's +0 ownership contract
// instead of inferring ownership from an integer-to-object cast.
id LC32InvokeHostObjectSelector(uint64_t object, uint64_t selector, ...)
    NS_RETURNS_NOT_RETAINED;

/*
 * Borrowed host results already remain valid through the native method's
 * autorelease lifetime, and their reverse mapping pins the guest proxy until
 * that host object dies.  Returning the proxy directly is also the correct
 * MRC-to-ARC boundary: without a return-value handshake an ARC caller falls
 * back to an ordinary retain, which reaches the bridge's paired ownership
 * implementation.
 *
 * Do not manufacture a guest retain/autorelease here.  Direct objc_retain can
 * use libobjc's cached root-RR fast path and bypass the category method which
 * mirrors ownership to the host.  The later guest autorelease token would then
 * consume the native method's original +0 ownership and leave its original
 * autorelease-pool entry pointing at a deallocated object.
 */
#define LC32ReturnBorrowedGuestObject(object) (object)

// Mark a selector whose +0 Objective-C result must be converted to a guest
// proxy atomically with its host invocation.
static inline uint64_t LC32HostSelectorReturningGuestObject(
        uint64_t selector) {
    return selector | LC32_HOST_SELECTOR_RETURN_GUEST_OBJECT;
}

// Marks guest-owned temporary storage for a pointer argument. The host bridge
// replaces the tagged ARM address with a native pointer for the duration of
// objc_msgSend, then copies the 64-bit temporary back into guest memory.
static inline uint64_t LC32HostIndirectArgument(const void *storage) {
    return storage
        ? LC32_GUEST_INDIRECT_ARGUMENT_TAG |
            (uint64_t)(uint32_t)(uintptr_t)storage
        : 0;
}

// Marks an eight-byte canonical floating-point cell. The host bridge uses the
// native Objective-C method encoding to expose it as either float * or
// double *, then widens the result back into the canonical double cell. This
// is required when an ARM32 CGFloat * (`^f`) calls an ARM64 CGFloat * (`^d`).
static inline uint64_t LC32HostFloatingIndirectArgument(
        const void *storage) {
    return storage
        ? LC32_GUEST_FLOATING_INDIRECT_ARGUMENT_TAG |
            (uint64_t)(uint32_t)(uintptr_t)storage
        : 0;
}

/*
 * Stage an explicitly sized pointer argument.  This is used when `void *`
 * hides the native pointee size from the Objective-C method encoding, as it
 * does for NSValue's byte-oriented API.  The descriptor and its storage need
 * only remain alive for the synchronous host invocation.
 */
static inline void LC32InitializeHostSizedIndirectDescriptor(
        LC32HostSizedIndirectDescriptor *descriptor, void *storage,
        uint32_t size) {
    descriptor->storage = (uint32_t)(uintptr_t)storage;
    descriptor->size = size;
    descriptor->magic = LC32_HOST_SIZED_INDIRECT_MAGIC;
    descriptor->reserved = 0;
}

static inline uint64_t LC32HostSizedIndirectArgument(
        const LC32HostSizedIndirectDescriptor *descriptor) {
    return descriptor
        ? LC32_GUEST_SIZED_INDIRECT_ARGUMENT_TAG |
            (uint64_t)(uint32_t)(uintptr_t)descriptor
        : 0;
}

// Stage a counted ARM32 object-pointer array as native 64-bit object pointers.
// The storage is valid for one synchronous LC32InvokeHostSelector call.
void *LC32CreateHostObjectArray(const id *objects, uint32_t count,
                                uint32_t countArgumentIndex);
void LC32DestroyHostObjectArray(void *storage);

static inline uint64_t LC32HostObjectArrayArgument(const void *storage) {
    return storage
        ? LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG |
            (uint64_t)(uint32_t)(uintptr_t)storage
        : 0;
}

// Keep a converted ARM64 aggregate in guest-owned temporary storage and pass
// one tagged logical argument through the variadic SVC transport. The host
// consults the native method encoding to place the value in FP registers,
// expand integer composites such as NSRange into GPRs, or, for aggregates
// larger than 16 bytes, pass its native address indirectly.
static inline uint64_t LC32HostAggregateArgument(const void *storage) {
    return storage
        ? LC32_GUEST_AGGREGATE_ARGUMENT_TAG |
            (uint64_t)(uint32_t)(uintptr_t)storage
        : 0;
}

/*
 * NSRange changes width across this bridge: the ARM32 guest uses two
 * uint32_t fields, while the native host uses two uint64_t fields. Keep the
 * widened form in guest-owned storage so it can use the same tagged aggregate
 * transport as CoreGraphics values. NSNotFound is NSIntegerMax in each ABI,
 * so it needs an explicit width conversion in both directions.
 */
typedef struct LC32NSRange64 {
    uint64_t location;
    uint64_t length;
} LC32NSRange64;

static inline LC32NSRange64 LC32WidenNSRange(NSRange guest) {
    const uint32_t guestNotFound = UINT32_C(0x7fffffff);
    const uint64_t hostNotFound = UINT64_C(0x7fffffffffffffff);
    LC32NSRange64 result = {
        guest.location == guestNotFound ? hostNotFound : guest.location,
        guest.length,
    };
    return result;
}

static inline NSRange LC32NarrowNSRange(LC32NSRange64 host) {
    const uint64_t hostNotFound = UINT64_C(0x7fffffffffffffff);
    if(host.location == hostNotFound) {
        if(host.length > UINT32_MAX) return NSMakeRange(NSNotFound, 0);
        return NSMakeRange(NSNotFound, (NSUInteger)host.length);
    }
    if(host.location > UINT32_MAX || host.length > UINT32_MAX) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange((NSUInteger)host.location, (NSUInteger)host.length);
}

// NSInvocation receives a pointer to raw ARM32 argument storage. Unlike an
// ordinary indirect argument, the pointed-to value has not yet been widened
// or translated for the ARM64 host ABI; LC32InvokeHostSelector performs that
// conversion using the invocation's method signature.
static inline uint64_t LC32HostInvocationArgument(const void *storage) {
    return storage
        ? LC32_GUEST_INVOCATION_ARGUMENT_TAG |
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
    LC32NSStringFormatOptionReturnGuestObject = 1 << 2,
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

// Blocks must not use NSObject's cached host mirror: a native block owns a
// copied guest block only for its own lifetime and may be invoked later.
uint64_t LC32CreateHostBlock(id guestBlock);

// Host bridge for LC32HostToGuestOwnedObject.
uint32_t LC32GuestObjectForOwnedHostObjectAddress(uint64_t host_object);
