#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LC32.h"

#include <dlfcn.h>
#include <pthread.h>
#include <sched.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

extern id _objc_rootAutorelease(id object);
extern void _objc_rootRelease(id object);
extern BOOL _objc_rootReleaseWasZero(id object);
extern id _objc_rootRetain(id object);
extern uintptr_t _objc_rootRetainCount(id object);
extern int32_t OSAtomicAdd32Barrier(
    int32_t amount, volatile int32_t *value);
extern bool OSAtomicCompareAndSwap32Barrier(
    int32_t oldValue, int32_t newValue, volatile int32_t *value);

uint64_t LC32CachedHostSelector(
    uint64_t *cache __attribute__((align_value(8))), SEL selector,
                                BOOL returnsStruct) {
    uint64_t value = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if(value) return value;

    const uint64_t resolved = LC32GetHostSelector(selector) |
        (returnsStruct != NO
            ? LC32_HOST_SELECTOR_RETURN_STRUCT
            : UINT64_C(0));
    uint64_t expected = 0;
    if(__atomic_compare_exchange_n(cache, &expected, resolved, false,
            __ATOMIC_RELEASE, __ATOMIC_ACQUIRE)) {
        return resolved;
    }
    return expected;
}

static pthread_once_t LC32ObjCTraceOnce = PTHREAD_ONCE_INIT;
static BOOL LC32ObjCTraceIsEnabled;
static pthread_once_t LC32OperationTraceOnce = PTHREAD_ONCE_INIT;
static BOOL LC32OperationTraceIsEnabled;
static uint64_t LC32OperationTraceSequence;
static pthread_once_t LC32AutoreleaseSchedulerOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32AutoreleaseScheduler;

static void LC32InitializeObjCTrace(void) {
    const char *value = getenv("LC32_OBJC_TRACE");
    LC32ObjCTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static void LC32InitializeOperationTrace(void) {
    const char *value = getenv("LC32_OPERATION_TRACE");
    LC32OperationTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static void LC32InitializeAutoreleaseScheduler(void) {
    LC32AutoreleaseScheduler =
        LC32Dlsym("LC32ScheduleGuestAutorelease", YES);
}

BOOL LC32ObjCTraceEnabled(void) {
    // pthread_once avoids the problematic inline ARMv7 CAS sequence clang
    // emits for a local atomic while remaining safe with native guest threads.
    pthread_once(&LC32ObjCTraceOnce, LC32InitializeObjCTrace);
    return LC32ObjCTraceIsEnabled;
}

void *LC32CreateHostObjectArray(const id *objects, uint32_t count,
                                uint32_t countArgumentIndex) {
    if(!objects) {
        if(count) abort();
        return NULL;
    }

    const size_t headerSize = sizeof(LC32HostObjectArrayDescriptor);
    if(count > LC32_HOST_OBJECT_ARRAY_MAX_COUNT ||
       count > (SIZE_MAX - headerSize) / sizeof(uint64_t)) abort();

    LC32HostObjectArrayDescriptor *descriptor =
        malloc(headerSize + (size_t)count * sizeof(uint64_t));
    if(!descriptor) abort();

    descriptor->count = count;
    descriptor->countArgumentIndex = countArgumentIndex;
    descriptor->magic = LC32_HOST_OBJECT_ARRAY_MAGIC;
    descriptor->reserved = 0;
    for(uint32_t index = 0; index < count; index++) {
        descriptor->objects[index] = [objects[index] host_self];
    }
    return descriptor;
}

void LC32DestroyHostObjectArray(void *storage) {
    free(storage);
}

// Framework: LC32

// Converts host class to guest class
Class LC32HostToGuestClass(uint64_t address) {
    char name[100];
    LC32HostToGuestCopyClassName(name, sizeof(name)-1, address);
    printf("DBG: LC32HostToGuestClass %s\n", name);
    return objc_getClass(name);
}

// Get the guest object pointer from host. The host may call back to guest with initWithHostSelf: and return it.
id LC32HostToGuestObject(uint64_t host_object) {
    if(!host_object) return nil;
    static uint64_t hostPtr = 0;
    uint64_t selector = LC32CachedHostSelector(
        &hostPtr, @selector(guest_self), NO);
    return (id)LC32InvokeHostSelector(host_object, selector);
}

id LC32HostToGuestOwnedObject(uint64_t host_object) {
    if(!host_object) return nil;
    return (id)LC32GuestObjectForOwnedHostObjectAddress(host_object);
}

id LC32DisposeFailedInit(id object) {
    [object setHost_self:0];
    return object_dispose(object);
}

static id LC32BindHostInitializerResult(id object, uint64_t hostResult) {
    if(!hostResult) return nil;

    static uint64_t bindGuestSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &bindGuestSelector,
        sel_registerName("LC32_bindGuestSelfIfAbsent:"), NO);
    return (id)(uintptr_t)(uint32_t)LC32InvokeHostSelector(
        hostResult, selector,
        (uint64_t)(uint32_t)(uintptr_t)object, (uint64_t)0);
}

id LC32AdoptHostInitializerResult(id object, uint64_t hostResult) {
    if(!hostResult) return LC32DisposeFailedInit(object);

    /*
     * Class-cluster alloc placeholders are shared objects. Passing the guest
     * pointer explicitly avoids a race where another guest thread overwrites
     * the placeholder's reverse association between alloc and init. If a
     * class-cluster initializer returns a shared singleton which already has
     * a proxy, transfer the caller's guest +1 to that canonical proxy without
     * retaining the host again: the initializer result already carries the
     * matching native +1.
     */
    id canonicalObject = LC32BindHostInitializerResult(object, hostResult);
    if(!canonicalObject) {
        return LC32DisposeFailedInit(object);
    }
    if(canonicalObject != object) {
        _objc_rootRetain(canonicalObject);
        [object setHost_self:0];
        object_dispose(object);
        return canonicalObject;
    }
    [object setHost_self:hostResult];
    return object;
}

id LC32AdoptHostInitializerResultARC(id object, uint64_t hostResult) {
    if(!hostResult) {
        /* ARC releases its strong `self` after this retained-result helper
         * returns. Detach the consumed native placeholder so that cleanup is
         * guest-only. */
        [object setHost_self:0];
        return nil;
    }

    id canonicalObject = LC32BindHostInitializerResult(object, hostResult);
    if(!canonicalObject) {
        [object setHost_self:0];
        return nil;
    }
    if(canonicalObject != object) {
        /* The native initializer's +1 already belongs to the return value.
         * Add only its guest half; ARC will release the abandoned allocation
         * after the initializer implementation returns. */
        _objc_rootRetain(canonicalObject);
        [object setHost_self:0];
        return canonicalObject;
    }

    [object setHost_self:hostResult];
    /* A retained-result C function must provide a +1 distinct from ARC's
     * strong `self`, which the compiler releases on return. This paired retain
     * is balanced by that release, leaving the initializer's original +1. */
    return [object retain];
}

/*
 * A guest object can gain ordinary or weak ownership while another native
 * guest thread is publishing its first host mirror.  The publisher snapshots
 * the guest retain count and seeds the corresponding native references, so no
 * ownership operation may cross that snapshot/publication interval.
 *
 * Readers are nonexclusive.  The publisher closes a packed striped gate by
 * setting its writer bit, waits for readers which entered first, then stores
 * host_self only after native ownership is fully seeded.  retainWeakReference
 * never waits while libobjc's weak SideTable stripe is locked: it simply
 * fails when a publisher has already closed the gate.  LC32's private weak
 * SVCs are not cooperative scheduling points, so a sole-JIT reader cannot be
 * suspended for a publisher which is waiting on it.
 */
enum {
    LC32OwnershipGateStripeCount = 64,
    LC32OwnershipGateWriterBit = UINT32_C(0x80000000),
    LC32OwnershipGateReaderMask = UINT32_C(0x7fffffff),
};

typedef struct {
    uint32_t state;
} LC32OwnershipGateStripe;

static LC32OwnershipGateStripe
    LC32OwnershipGateStripes[LC32OwnershipGateStripeCount];

static uint32_t LC32OwnershipGateStripeIndex(id object) {
    uintptr_t value = (uintptr_t)object >> 3;
    value ^= value >> 11;
    return (uint32_t)value & (LC32OwnershipGateStripeCount - 1);
}

static BOOL LC32OwnershipGateCompareExchange(
        uint32_t index, uint32_t *expected, uint32_t desired) {
    volatile int32_t *value = (volatile int32_t *)
        &LC32OwnershipGateStripes[index].state;
    if(OSAtomicCompareAndSwap32Barrier(
            (int32_t)*expected, (int32_t)desired, value)) {
        return YES;
    }
    *expected = __atomic_load_n(
        &LC32OwnershipGateStripes[index].state, __ATOMIC_ACQUIRE);
    return NO;
}

static uint32_t LC32EnterOwnershipReader(id object, BOOL waitForWriter) {
    const uint32_t index = LC32OwnershipGateStripeIndex(object);
    uint32_t state = __atomic_load_n(
        &LC32OwnershipGateStripes[index].state, __ATOMIC_ACQUIRE);
    for(;;) {
        if(state & LC32OwnershipGateWriterBit) {
            if(!waitForWriter) return 0;
            sched_yield();
            state = __atomic_load_n(
                &LC32OwnershipGateStripes[index].state,
                __ATOMIC_ACQUIRE);
            continue;
        }
        if((state & LC32OwnershipGateReaderMask) ==
                LC32OwnershipGateReaderMask) {
            abort();
        }
        const uint32_t desired = state + 1;
        if(LC32OwnershipGateCompareExchange(
                index, &state, desired)) {
            return index + 1;
        }
    }
}

static void LC32LeaveOwnershipReader(uint32_t token) {
    if(!token) return;
    const uint32_t index = token - 1;
    /* Keep the read-modify-write out of line.  Clang otherwise emits the
     * architecturally-unpredictable Thumb encoding `cmp r0, r1` (0x4508)
     * in its inline LDREX loop, which older ARM cores tolerated but Dynarmic
     * deliberately rejects.  A reader token always owns one count here. */
    (void)OSAtomicAdd32Barrier(-1, (volatile int32_t *)
        &LC32OwnershipGateStripes[index].state);
}

static uint32_t LC32EnterOwnershipWriter(id object) {
    const uint32_t index = LC32OwnershipGateStripeIndex(object);
    uint32_t state = __atomic_load_n(
        &LC32OwnershipGateStripes[index].state, __ATOMIC_ACQUIRE);
    for(;;) {
        if(state & LC32OwnershipGateWriterBit) {
            sched_yield();
            state = __atomic_load_n(
                &LC32OwnershipGateStripes[index].state,
                __ATOMIC_ACQUIRE);
            continue;
        }
        const uint32_t desired = state | LC32OwnershipGateWriterBit;
        if(LC32OwnershipGateCompareExchange(
                index, &state, desired)) {
            break;
        }
    }

    while(__atomic_load_n(
            &LC32OwnershipGateStripes[index].state,
            __ATOMIC_ACQUIRE) & LC32OwnershipGateReaderMask) {
        sched_yield();
    }
    return index + 1;
}

static void LC32LeaveOwnershipWriter(uint32_t token) {
    if(!token) abort();
    const uint32_t index = token - 1;
    const uint32_t state = __atomic_load_n(
        &LC32OwnershipGateStripes[index].state, __ATOMIC_ACQUIRE);
    if(state != LC32OwnershipGateWriterBit) abort();
    __atomic_store_n(
        &LC32OwnershipGateStripes[index].state, 0, __ATOMIC_RELEASE);
}

static uint64_t LC32ExistingHostSelf(id object) {
    return object
        ? LC32LookupHostMapping((uint32_t)(uintptr_t)object)
        : 0;
}

@implementation LC32GuestBuffer
- (void)dealloc {
    free(_bytes);
    [super dealloc];
}
@end

/*
 * Merely exchanging NSObject's retain/release implementations after libobjc
 * has realized the class is not enough for ARC.  The runtime caches that
 * NSObject uses its default reference-counting implementation and its
 * objc_retain/objc_release entry points then update the side table directly,
 * without messaging our bridge methods.  A guest proxy can consequently gain
 * an ARC strong reference while its native peer remains autoreleased.
 *
 * Defining these selectors in the category's method list makes libobjc mark
 * NSObject and its subclasses as custom-RR while the category is attached.
 * They intentionally start out as the ordinary root implementations.  The
 * constructor below first copies them to guest-only helper classes, then
 * exchanges them with LC32_* so normal proxies acquire paired guest/native
 * ownership and the helpers continue to stay entirely inside guest libobjc.
 */
uint32_t LC32ReleaseGuestLifetimePin(id object) {
    /* Host-first weak-retain tokens and the first-publication ownership gate
     * guarantee that a native mirror whose transferred guard is its sole +1
     * has either exactly the guest lifetime pin or a stable additional guest
     * owner.  Do not speculatively decrement and then restore the pin: the
     * other owner could disappear in that gap. */
    if(_objc_rootRetainCount(object) != 1) {
        return 0;
    }

    /* The count can only change here through an invalid unpaired strong race.
     * Fail loudly instead of continuing with a detached or double-released
     * lifetime pin.  The private primitive does not invoke -dealloc itself. */
    if(!_objc_rootReleaseWasZero(object)) abort();
    [object dealloc];
    return 1;
}

static BOOL LC32OperationTraceEnabled(void) {
    pthread_once(&LC32OperationTraceOnce, LC32InitializeOperationTrace);
    return LC32OperationTraceIsEnabled;
}

static BOOL LC32OperationTraceMatchesObject(id object) {
    for(Class cls = object_getClass(object); cls;
            cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if(name && strcmp(name, "NSOperation") == 0) return YES;
    }
    return NO;
}

static void LC32OperationTraceObject(const char *event, id object,
                                     uint64_t hostObject,
                                     const void *caller) {
    if(!LC32OperationTraceEnabled() ||
       !LC32OperationTraceMatchesObject(object)) return;

    const uint64_t sequence = __atomic_add_fetch(
        &LC32OperationTraceSequence, 1, __ATOMIC_RELAXED);
    fprintf(stderr,
        "LC32 operation guest trace #%llu %s host=0x%llx guest=0x%x "
        "class=%s guestRC=%lu caller=0x%x thread=%p\n",
        (unsigned long long)sequence, event,
        (unsigned long long)hostObject,
        (uint32_t)(uintptr_t)object,
        class_getName(object_getClass(object)),
        (unsigned long)_objc_rootRetainCount(object),
        (uint32_t)(uintptr_t)caller,
        (void *)pthread_self());
}

#define LC32_OPERATION_TRACE(event, object, hostObject) \
    LC32OperationTraceObject((event), (object), (hostObject), \
                             __builtin_return_address(0))

static const void *kLC32GuestBuffer = &kLC32GuestBuffer;

void *LC32GetAssociatedGuestBuffer(id object, uint32_t requiredCapacity) {
    if(!object || !requiredCapacity) return NULL;

    @synchronized(object) {
        LC32GuestBuffer *buffer =
            objc_getAssociatedObject(object, kLC32GuestBuffer);
        if(!buffer) {
            buffer = [LC32GuestBuffer new];
            objc_setAssociatedObject(object, kLC32GuestBuffer, buffer,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [buffer release];
        }

        if(buffer->_capacity < requiredCapacity) {
            void *grown = realloc(buffer->_bytes, requiredCapacity);
            if(!grown) return NULL;
            buffer->_bytes = grown;
            buffer->_capacity = requiredCapacity;
        }
        return buffer->_bytes;
    }
}

@implementation NSObject(LC32)

- (instancetype)autorelease {
    return _objc_rootAutorelease(self);
}

- (void)release {
    _objc_rootRelease(self);
}

- (instancetype)retain {
    return _objc_rootRetain(self);
}

- (NSUInteger)retainCount {
    return (NSUInteger)_objc_rootRetainCount(self);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)initWithHostSelf:(uint64_t)host_self {
    // [NSObject init] does nothing, we don't need to call it, consequently it also calls up to the overridden init function of the subclass causing recursive call
    //self = [super init];
    self.host_self = host_self;
    return self;
}
#pragma clang diagnostic pop

// Set the equivalent host pointer
// Called from guest's initializer shim methods (eg initWithFrame:) -> LC32HostToGuestObject -> host's guest_self -> initWithHostSelf if the object has not been known by guest before
// Only call this if host's guest_self has already been set
- (void)setHost_self:(uint64_t)ptr {
    @synchronized(self) {
        const uint32_t guestObject = (uint32_t)(uintptr_t)self;
        const uint64_t existing = LC32LookupHostMapping(guestObject);
        if(existing == ptr) return;
        if(ptr) {
            if(!LC32UpdateHostMapping(
                    guestObject,
                    LC32HostMappingPublishProvisional,
                    ptr)) abort();
        } else if(existing) {
            if(!LC32UpdateHostMapping(
                    guestObject,
                    LC32HostMappingClearIfEqual,
                    existing)) abort();
        }
    }
}

// Set the equivalent host pointer for statically-initialized object (eg NSString constants)
- (void)bindHostSelf:(uint64_t)ptr {
    if(!ptr) abort();
    @synchronized(self) {
        if(!LC32UpdateHostMapping(
                (uint32_t)(uintptr_t)self,
                LC32HostMappingPublishPermanent,
                ptr)) abort();
    }
    // make a trip to host to set guest_self
    static uint64_t hostPtr = 0;
    uint64_t selector = LC32CachedHostSelector(
        &hostPtr, @selector(setGuest_self:), NO);
    LC32InvokeHostSelector(ptr, selector, (uint64_t)self);
}

- (uint64_t)host_self {
    return [self LC32_rawHostSelf];
}

- (uint64_t)LC32_rawHostSelf {
    if(LC32ObjCTraceEnabled()) {
        printf("Calling from %s:0x%08x:0x%08x, isClass? = %d\n",
            class_getName(self.class), (uint32_t)self.class,
            (uint32_t)self, object_isClass(self));
    }
    uint64_t ptr = LC32ExistingHostSelf(self);
    if(!ptr) {
        @synchronized(self) {
            ptr = LC32ExistingHostSelf(self);
            if(!ptr) {
                const uint32_t writer =
                    LC32EnterOwnershipWriter(self);
                @try {
                    ptr = LC32ExistingHostSelf(self);
                    if(!ptr) {
                        /*
                         * Retains performed while an object is guest-only
                         * deliberately stay local. LC32GetHostObject returns
                         * the native peer at +1, which accounts for one of
                         * those logical guest references. Seed the remaining
                         * native references before ownership starts being
                         * mirrored.
                         *
                         * Capture this before LC32GetHostObject: dynamic guest
                         * classes acquire a separate guest lifetime pin while
                         * their peer is created, and that pin must not be
                         * mirrored to the host. The ownership writer excludes
                         * preexisting retain/release/weak readers from this
                         * snapshot.
                         */
                        const NSUInteger guestRetainCount = object_isClass(self)
                            ? 0 : [self LC32_retainCount];
                        ptr = LC32GetHostObject(
                            self, class_getName(self.class),
                            object_isClass(self));

                        if(guestRetainCount != NSUIntegerMax) {
                            static uint64_t retainSelector;
                            const uint64_t selector = LC32CachedHostSelector(
                                &retainSelector, @selector(retain), NO);
                            for(NSUInteger count = 1;
                                    count < guestRetainCount; count++) {
                                LC32InvokeHostSelector(ptr, selector);
                            }
                        }

                        /* Publish only after the peer contains every native +1
                         * represented by the captured guest retain count. */
                        const LC32HostMappingOperation operation =
                            object_isClass(self) ||
                                    guestRetainCount == NSUIntegerMax
                                ? LC32HostMappingPublishPermanent
                                : LC32HostMappingPublishProvisional;
                        if(!LC32UpdateHostMapping(
                                (uint32_t)(uintptr_t)self,
                                operation, ptr)) abort();
                    }
                } @finally {
                    LC32LeaveOwnershipWriter(writer);
                }
            }
        }
    }
    assert(ptr != 0);
    return ptr;
}

- (instancetype)LC32_autorelease {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    LC32_OPERATION_TRACE("autorelease", self, hostSelf);

    pthread_once(&LC32AutoreleaseSchedulerOnce,
        LC32InitializeAutoreleaseScheduler);
    assert(LC32AutoreleaseScheduler);

    LC32InvokeHostCRet32(LC32AutoreleaseScheduler,
        (uint32_t)hostSelf, (uint32_t)(hostSelf >> 32),
        (uint32_t)(uintptr_t)self);
    return self;
}

- (void)LC32_releaseGuestOwnershipOnly {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    LC32_OPERATION_TRACE(
        "release-guest-ownership-only", self, hostSelf);
    if(!hostSelf) {
        [self LC32_release];
        return;
    }

    // Unlike the lifetime-pin release, this is an ordinary guest ownership
    // decrement, but the native autorelease token owns the paired host +1.
    const uint32_t guestSelf = (uint32_t)(uintptr_t)self;
    const BOOL releasedToZero = _objc_rootReleaseWasZero(self);
    if(releasedToZero) {
        const uint32_t token = LC32UpdateHostMapping(
            guestSelf, LC32HostMappingBeginGuestTeardown, hostSelf);
        if(!token) abort();
        [self dealloc];
        if(!LC32UpdateHostMapping(
                guestSelf, LC32HostMappingFinishGuestTeardown,
                token)) abort();
    }
}
- (void)LC32_release {
    uint64_t hostSelf = LC32ExistingHostSelf(self);
    if(!hostSelf) {
        const uint32_t reader =
            LC32EnterOwnershipReader(self, YES);
        hostSelf = LC32ExistingHostSelf(self);
        if(!hostSelf) {
            LC32_OPERATION_TRACE("release-guest-only", self, 0);
            const BOOL releasedToZero =
                _objc_rootReleaseWasZero(self);
            LC32LeaveOwnershipReader(reader);
            /* Release the reservation before arbitrary subclass teardown.
             * The zeroing root primitive has already made new weak loads
             * fail, and a publisher cannot legitimately start for an object
             * whose final guest ownership was consumed. */
            if(releasedToZero) [self dealloc];
            return;
        }
        LC32LeaveOwnershipReader(reader);
    }

    LC32_OPERATION_TRACE("release", self, hostSelf);

    const uint32_t guestSelf = (uint32_t)(uintptr_t)self;
    /* The zero-reporting root primitive makes the final-release decision
     * atomic with racing strong/weak retains.  Keep the Retiring mapping
     * available through arbitrary guest -dealloc code, then erase only its
     * exact generation so a reused ARM address cannot lose its new peer. */
    const BOOL releasedToZero = _objc_rootReleaseWasZero(self);
    if(releasedToZero) {
        const uint32_t token = LC32UpdateHostMapping(
            guestSelf, LC32HostMappingBeginGuestTeardown, hostSelf);
        if(!token) abort();
        [self dealloc];
        if(!LC32UpdateHostMapping(
                guestSelf, LC32HostMappingFinishGuestTeardown,
                token)) abort();
    }

    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(release), NO);
    LC32InvokeHostSelector(hostSelf, host_cmd);
}

- (instancetype)LC32_retain {
    uint64_t hostSelf = LC32ExistingHostSelf(self);
    if(!hostSelf) {
        const uint32_t reader =
            LC32EnterOwnershipReader(self, YES);
        hostSelf = LC32ExistingHostSelf(self);
        if(!hostSelf) {
            id result = [self LC32_retain];
            LC32LeaveOwnershipReader(reader);
            LC32_OPERATION_TRACE("retain-guest-only", result, 0);
            return result;
        }
        LC32LeaveOwnershipReader(reader);
    }

    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(retain), NO);
    LC32InvokeHostSelector(hostSelf, host_cmd);
    id result = [self LC32_retain];
    LC32_OPERATION_TRACE("retain", result, hostSelf);
    return result;
}

/*
 * objc_loadWeakRetained invokes this method while holding the guest object's
 * weak side-table stripe. SVC 1019 first acquires the matching native +1;
 * that ownership prevents native mirror retirement while the original guest
 * implementation performs its root try-retain under the guest lock.
 *
 * Do not inspect associated objects, query retainCount, or synchronously
 * release either object here: each can recursively acquire the guest stripe.
 */
- (BOOL)LC32_retainWeakReference {
    const uint32_t reader =
        LC32EnterOwnershipReader(self, NO);
    if(!reader) return NO;

    const LC32HostWeakRetainResult retainedHost =
        LC32TryRetainHostWeakReference((uint32_t)(uintptr_t)self);
    if(retainedHost == LC32HostWeakRetainNoMapping) {
        const BOOL retainedGuest =
            [self LC32_retainWeakReference];
        LC32LeaveOwnershipReader(reader);
        return retainedGuest;
    }
    if(retainedHost == LC32HostWeakRetainMappedDead) {
        LC32LeaveOwnershipReader(reader);
        return NO;
    }

    const BOOL retainedGuest = [self LC32_retainWeakReference];
    /* Finalizing the token only mutates host bookkeeping. A failed guest
     * try-retain defers its exact native rollback away from this guest weak
     * side-table critical section. */
    const BOOL finished = LC32FinishHostWeakRetain(
            retainedHost, (uint32_t)(uintptr_t)self,
            retainedGuest != NO) != 0;
    LC32LeaveOwnershipReader(reader);
    if(!finished) abort();
    return retainedGuest;
}

// FIXME: need to hook this?
- (NSUInteger)LC32_retainCount {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    if(!hostSelf) return [self LC32_retainCount];

    LC32_OPERATION_TRACE("retain-count", self, hostSelf);

    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(retainCount), NO);
    uint64_t host_ret = LC32InvokeHostSelector(hostSelf, host_cmd);
    return (NSUInteger)host_ret;
}

#if 0
// Can't hook this, host crashes with: Application circumvented Objective-C runtime dealloc initiation for <NSObject-like> object.
- (void)dealloc {
    static uint64_t _host_cmd;
    if(!_host_cmd) _host_cmd = LC32GetHostSelector(_cmd);
    uint64_t host_ret = LC32InvokeHostSelector(self.host_self, _host_cmd);
    object_dispose(self);
}
#endif
@end

static void addMethodToClass(Class cls, Method method) {
    class_addMethod(cls, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method));
}

static void swizzle(Class cls, SEL originalAction, SEL swizzledAction) {
    method_exchangeImplementations(class_getInstanceMethod(cls, originalAction), class_getInstanceMethod(cls, swizzledAction));
}

extern void _Block_release(const void *block);
extern uint64_t LC32InvokeGuestBlockWords(
    uint32_t invoke, const uint32_t *words, uint32_t wordCount);

#define LC32_GUEST_BLOCK_CALLBACK_MAX_WORDS 16

static uint64_t LC32TypedGuestBlockCompletionFunction;

static BOOL LC32AppendGuestBlockWord(
        uint32_t *words, uint32_t *wordCount, uint32_t value) {
    if(*wordCount >= LC32_GUEST_BLOCK_CALLBACK_MAX_WORDS) return NO;
    words[(*wordCount)++] = value;
    return YES;
}

static BOOL LC32InvokeGuestBlockCallback(
        LC32GuestBlockCallbackDescriptor *descriptor) {
    if(!descriptor || !descriptor->guestBlock || !descriptor->guestInvoke ||
       descriptor->argumentCount >
           LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS) {
        return NO;
    }

    uint32_t words[LC32_GUEST_BLOCK_CALLBACK_MAX_WORDS] = {
        descriptor->guestBlock
    };
    uint32_t wordCount = 1;
    char pointerValues[LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS] = {};

    for(uint32_t index = 0; index < descriptor->argumentCount; index++) {
        LC32GuestBlockCallbackArgument *argument =
            &descriptor->arguments[index];
        if(argument->reserved != 0) return NO;

        switch((LC32GuestBlockValueKind)argument->kind) {
            case LC32GuestBlockValueObject:
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)(uintptr_t)LC32HostToGuestObject(
                            argument->value))) return NO;
                break;
            case LC32GuestBlockValueSignedChar:
            case LC32GuestBlockValueSigned32:
            case LC32GuestBlockValueUnsigned32:
                if(!LC32AppendGuestBlockWord(
                        words, &wordCount, (uint32_t)argument->value)) {
                    return NO;
                }
                break;
            case LC32GuestBlockValueSigned64:
            case LC32GuestBlockValueUnsigned64:
                /* Apple's 32-bit ABI packs integer argument words without
                 * natural-alignment holes and may split a 64-bit value
                 * between r3 and the stack. */
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)argument->value) ||
                   !LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)(argument->value >> 32))) return NO;
                break;
            case LC32GuestBlockValueRange:
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)argument->value) ||
                   !LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)argument->value2)) return NO;
                break;
            case LC32GuestBlockValueCharPointer:
                pointerValues[index] = (char)argument->value;
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        argument->value2
                            ? (uint32_t)(uintptr_t)&pointerValues[index]
                            : 0)) return NO;
                break;
            case LC32GuestBlockValueVoid:
            default:
                return NO;
        }
    }

    const uint64_t result = LC32InvokeGuestBlockWords(
        descriptor->guestInvoke, words, wordCount);
    switch((LC32GuestBlockValueKind)descriptor->resultKind) {
        case LC32GuestBlockValueVoid:
            descriptor->result = 0;
            break;
        case LC32GuestBlockValueObject: {
            id guestResult = (id)(uintptr_t)(uint32_t)result;
            descriptor->result = guestResult
                ? [guestResult host_self]
                : 0;
            break;
        }
        case LC32GuestBlockValueSignedChar:
        case LC32GuestBlockValueSigned32:
        case LC32GuestBlockValueUnsigned32:
            descriptor->result = (uint32_t)result;
            break;
        case LC32GuestBlockValueSigned64:
        case LC32GuestBlockValueUnsigned64:
            descriptor->result = result;
            break;
        case LC32GuestBlockValueRange:
        case LC32GuestBlockValueCharPointer:
        default:
            return NO;
    }

    for(uint32_t index = 0; index < descriptor->argumentCount; index++) {
        if(descriptor->arguments[index].kind ==
                LC32GuestBlockValueCharPointer &&
           descriptor->arguments[index].value2) {
            descriptor->arguments[index].value =
                (uint8_t)pointerValues[index];
        }
    }
    return YES;
}

static BOOL LC32InvokeGuestFunctionCallback(
        LC32GuestBlockCallbackDescriptor *descriptor) {
    if(!descriptor || descriptor->guestBlock || !descriptor->guestInvoke ||
       !descriptor->argumentCount ||
       descriptor->argumentCount >
           LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS ||
       descriptor->resultKind != LC32GuestBlockValueVoid) {
        return NO;
    }

    uint32_t words[LC32_GUEST_BLOCK_CALLBACK_MAX_WORDS] = {};
    uint32_t wordCount = 0;
    for(uint32_t index = 0; index < descriptor->argumentCount; index++) {
        LC32GuestBlockCallbackArgument *argument =
            &descriptor->arguments[index];
        if(argument->reserved != 0) return NO;
        switch((LC32GuestBlockValueKind)argument->kind) {
            case LC32GuestBlockValueSignedChar:
            case LC32GuestBlockValueSigned32:
            case LC32GuestBlockValueUnsigned32:
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)argument->value)) return NO;
                break;
            case LC32GuestBlockValueSigned64:
            case LC32GuestBlockValueUnsigned64:
                if(!LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)argument->value) ||
                   !LC32AppendGuestBlockWord(words, &wordCount,
                        (uint32_t)(argument->value >> 32))) return NO;
                break;
            case LC32GuestBlockValueVoid:
            case LC32GuestBlockValueObject:
            case LC32GuestBlockValueRange:
            case LC32GuestBlockValueCharPointer:
            default:
                return NO;
        }
    }

    (void)LC32InvokeGuestBlockWords(
        descriptor->guestInvoke, words, wordCount);
    descriptor->result = 0;
    return YES;
}

static void *LC32GuestCallbackExecutorMain(
        void *unused __attribute__((unused))) {
    for(;;) {
        LC32GuestBlockCallbackDescriptor descriptor = {};
        const uint32_t waitResult =
            LC32GuestCallbackExecutorWait(&descriptor);
        if(waitResult == LC32GuestBlockCallbackWaitResultStop) break;
        if(waitResult == LC32GuestBlockCallbackWaitResultRetry) continue;
        if(waitResult != LC32GuestBlockCallbackWaitResultJob) abort();

        @autoreleasepool {
            switch((LC32GuestBlockCallbackKind)descriptor.kind) {
                case LC32GuestBlockCallbackKindInvoke:
                    if(!LC32InvokeGuestBlockCallback(&descriptor)) {
                        fprintf(stderr,
                            "LC32: invalid typed guest block callback "
                            "descriptor for 0x%x\n",
                            descriptor.guestBlock);
                    }
                    if(!LC32TypedGuestBlockCompletionFunction ||
                       !LC32InvokeHostCRet32(
                            LC32TypedGuestBlockCompletionFunction,
                            (uint32_t)(uintptr_t)&descriptor, 0, 0)) {
                        fprintf(stderr,
                            "LC32: could not return typed result for guest "
                            "block 0x%x\n", descriptor.guestBlock);
                    }
                    break;
                case LC32GuestBlockCallbackKindRelease:
                    _Block_release(
                        (const void *)(uintptr_t)descriptor.guestBlock);
                    break;
                case LC32GuestBlockCallbackKindFunction:
                    if(!LC32InvokeGuestFunctionCallback(&descriptor)) {
                        fprintf(stderr,
                            "LC32: invalid guest C callback descriptor "
                            "for 0x%x\n", descriptor.guestInvoke);
                    }
                    break;
                default:
                    abort();
            }
        }

        if(!LC32GuestCallbackExecutorComplete(descriptor.identifier)) {
            break;
        }
    }
    return NULL;
}

static void LC32StartGuestCallbackExecutorIfSupported(void) {
    const uint64_t supportedFunction =
        LC32Dlsym("LC32GuestCallbackExecutorSupported", YES);
    const uint64_t creationResultFunction =
        LC32Dlsym("LC32GuestCallbackExecutorCreationResult", YES);
    LC32TypedGuestBlockCompletionFunction =
        LC32Dlsym("LC32CompleteTypedGuestBlock", YES);
    if(!supportedFunction || !creationResultFunction ||
       !LC32TypedGuestBlockCompletionFunction ||
       !LC32InvokeHostCRet32(supportedFunction, 0, 0, 0)) {
        return;
    }

    pthread_t thread;
    const int result = pthread_create(
        &thread, NULL, LC32GuestCallbackExecutorMain, NULL);
    LC32InvokeHostCRet32(
        creationResultFunction, (uint32_t)result, 0, 0);
    if(result == 0) {
        pthread_detach(thread);
    }
}

__attribute__((constructor)) void LC32FrameworkInit() {
    Class clsNSObject = objc_getClass("NSObject");

    // Associated guest buffers are native guest-only objects as well. Keep
    // their ownership traffic out of the host proxy retain/release bridge.
    Class clsLC32GuestBuffer = objc_getClass("LC32GuestBuffer");
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(autorelease)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(release)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(retain)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(retainCount)));
    addMethodToClass(clsLC32GuestBuffer,
        class_getInstanceMethod(clsNSObject,
            sel_registerName("retainWeakReference")));

    // Swizzle ARC methods
    swizzle(clsNSObject, @selector(autorelease), @selector(LC32_autorelease));
    swizzle(clsNSObject, @selector(release), @selector(LC32_release));
    swizzle(clsNSObject, @selector(retain), @selector(LC32_retain));
    swizzle(clsNSObject, @selector(retainCount), @selector(LC32_retainCount));
    swizzle(clsNSObject, sel_registerName("retainWeakReference"),
            @selector(LC32_retainWeakReference));

    // Send dlsym and LC32InvokeGuestC pointers to the host
    LC32InvokeHostCRet32(LC32Dlsym("LC32SetInvokeGuestFuncPtr", YES), &dlsym, &LC32InvokeGuestC);
    LC32StartGuestCallbackExecutorIfSupported();
}
