#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LC32.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

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
    return object_dispose(object);
}

id LC32AdoptHostInitializerResult(id object, uint64_t hostResult) {
    if(!hostResult) return LC32DisposeFailedInit(object);

    /*
     * Class-cluster alloc placeholders are shared objects. Passing the guest
     * pointer explicitly avoids a race where another guest thread overwrites
     * the placeholder's reverse association between alloc and init. Preserve
     * an existing association for immutable singleton results. The helper's
     * object return type leaves room to return that canonical guest proxy once
     * its guest-only +1 ownership transfer is implemented.
     */
    static uint64_t bindGuestSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &bindGuestSelector,
        sel_registerName("LC32_bindGuestSelfIfAbsent:"), NO);
    LC32InvokeHostSelector(hostResult, selector,
        (uint64_t)(uint32_t)(uintptr_t)object, (uint64_t)0);
    [object setHost_self:hostResult];
    return object;
}

// We cannot use NSValue or NSInteger here since they're proxied aswell
@interface LC32HostObjectPointer : NSObject
@property(nonatomic) uint64_t value;
@end
@implementation LC32HostObjectPointer
+ (instancetype)pointerWithValue:(uint64_t)value {
    LC32HostObjectPointer *pointer = [LC32HostObjectPointer new];
    pointer.value = value;
    return pointer;
}
@end

static const void *kHostSelf = &kHostSelf;

static uint64_t LC32ExistingHostSelf(id object) {
    LC32HostObjectPointer *pointer =
        objc_getAssociatedObject(object, kHostSelf);
    return pointer.value;
}

static LC32HostObjectPointer *LC32HostObjectState(id object, BOOL create) {
    LC32HostObjectPointer *pointer =
        objc_getAssociatedObject(object, kHostSelf);
    if(!pointer && create) {
        pointer = [LC32HostObjectPointer new];
        objc_setAssociatedObject(object, kHostSelf, pointer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [pointer release];
    }
    return pointer;
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
extern id _objc_rootAutorelease(id object);
extern void _objc_rootRelease(id object);
extern id _objc_rootRetain(id object);
extern uintptr_t _objc_rootRetainCount(id object);

/*
 * Balance a guest try-retain without entering the public autorelease bridge.
 * Keep work after the root call so libobjc cannot mistake this call site for
 * an autorelease-return-value handshake.  The actual guest release occurs
 * after objc_loadWeakRetained drops its side-table stripe lock.
 */
__attribute__((noinline))
static void LC32AutoreleaseGuestWeakRetainRollback(id object) {
    id result = _objc_rootAutorelease(object);
    __asm__ volatile("" : : "r"(result) : "memory");
}

uint32_t LC32ReleaseGuestLifetimePin(id object) {
    const BOOL isFinalReference = _objc_rootRetainCount(object) == 1;
    _objc_rootRelease(object);
    return isFinalReference;
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
        LC32HostObjectState(self, YES).value = ptr;
    }
}

// Set the equivalent host pointer for statically-initialized object (eg NSString constants)
- (void)bindHostSelf:(uint64_t)ptr {
    self.host_self = ptr;
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
            LC32HostObjectPointer *state = LC32HostObjectState(self, YES);
            ptr = state.value;
            if(!ptr) {
                /*
                 * Retains performed while an object is guest-only deliberately
                 * stay local.  LC32GetHostObject returns the native peer at +1,
                 * which accounts for one of those logical guest references.
                 * Seed the remaining native references before ownership starts
                 * being mirrored, otherwise releasing a pre-retained object can
                 * destroy its peer while a native collection still owns it.
                 *
                 * Capture this before LC32GetHostObject: dynamic guest classes
                 * acquire a separate guest lifetime pin while their peer is
                 * created, and that pin must not be mirrored to the host.
                 */
                const NSUInteger guestRetainCount = object_isClass(self)
                    ? 0 : [self LC32_retainCount];
                ptr = LC32GetHostObject(self, class_getName(self.class),
                                        object_isClass(self));
                state.value = ptr;

                if(guestRetainCount != NSUIntegerMax) {
                    static uint64_t retainSelector;
                    const uint64_t selector = LC32CachedHostSelector(
                        &retainSelector, @selector(retain), NO);
                    for(NSUInteger count = 1;
                            count < guestRetainCount; count++) {
                        LC32InvokeHostSelector(ptr, selector);
                    }
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
    // decrement. Clear a surviving native mirror's reverse mapping if this is
    // the guest object's final logical reference, but do not decrement the
    // host here: the native autorelease token owns that paired operation.
    if([self LC32_retainCount] == 1) {
        static uint64_t _clear_guest_cmd;
        uint64_t clear_guest_cmd = LC32CachedHostSelector(
            &_clear_guest_cmd, @selector(LC32_clearGuestSelfIfEqual:), NO);
        LC32InvokeHostSelector(hostSelf, clear_guest_cmd,
                               (uint64_t)(uintptr_t)self);
    }
    [self LC32_release];
}
- (void)LC32_release {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    LC32_OPERATION_TRACE("release", self, hostSelf);
    if(!hostSelf) {
        [self LC32_release];
        return;
    }

    /*
     * The host can keep cached/singleton objects alive after the guest drops
     * its last reference.  Clear its reverse mapping before the guest proxy is
     * deallocated, otherwise a later host-to-guest conversion can return a
     * dangling ARM pointer.  LC32_retainCount is the original guest
     * implementation after method_exchangeImplementations below.
     */
    if([self LC32_retainCount] == 1) {
        static uint64_t _clear_guest_cmd;
        uint64_t clear_guest_cmd = LC32CachedHostSelector(
            &_clear_guest_cmd, @selector(LC32_clearGuestSelfIfEqual:), NO);
        LC32InvokeHostSelector(hostSelf, clear_guest_cmd,
                               (uint64_t)(uintptr_t)self);
    }

    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(release), NO);
    LC32InvokeHostSelector(hostSelf, host_cmd);
    [self LC32_release];
}

- (instancetype)LC32_retain {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    if(!hostSelf) {
        id result = [self LC32_retain];
        LC32_OPERATION_TRACE("retain-guest-only", result, 0);
        return result;
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
 * weak side-table stripe.  The original implementation performs the guest
 * try-retain under that lock.  SVC 1019 then loads a host-side registered weak
 * slot under the native runtime's lock and transfers the matching native +1.
 *
 * Do not inspect associated objects, query retainCount, or synchronously
 * release either object here: each can recursively acquire the guest stripe.
 */
- (BOOL)LC32_retainWeakReference {
    if(![self LC32_retainWeakReference]) return NO;

    const LC32HostWeakRetainStatus status =
        LC32TryRetainHostWeakReference((uint32_t)(uintptr_t)self);
    if(status == LC32HostWeakRetainNoMapping ||
       status == LC32HostWeakRetainRetained) {
        return YES;
    }

    LC32AutoreleaseGuestWeakRetainRollback(self);
    return NO;
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
    // Ensure LC32HostObjectPointer doesn't inherit swizzled ARC methods
    Class clsLC32HostObjectPointer = objc_getClass("LC32HostObjectPointer");
    Class clsNSObject = objc_getClass("NSObject");
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(autorelease)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(release)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(retain)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(retainCount)));
    addMethodToClass(clsLC32HostObjectPointer,
        class_getInstanceMethod(clsNSObject,
            sel_registerName("retainWeakReference")));

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
