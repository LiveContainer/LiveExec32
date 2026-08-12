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
        ((uint64_t)(returnsStruct != NO) << 63);
    uint64_t expected = 0;
    if(__atomic_compare_exchange_n(cache, &expected, resolved, false,
            __ATOMIC_RELEASE, __ATOMIC_ACQUIRE)) {
        return resolved;
    }
    return expected;
}

static pthread_once_t LC32ObjCTraceOnce = PTHREAD_ONCE_INIT;
static BOOL LC32ObjCTraceIsEnabled;
static pthread_once_t LC32AutoreleaseSchedulerOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32AutoreleaseScheduler;

static void LC32InitializeObjCTrace(void) {
    const char *value = getenv("LC32_OBJC_TRACE");
    LC32ObjCTraceIsEnabled =
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
    static uint64_t hostPtr = 0;
    uint64_t selector = LC32CachedHostSelector(
        &hostPtr, @selector(guest_self), NO);
    return (id)LC32InvokeHostSelector(host_object, selector);
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
    if(!hostSelf) return [self LC32_retain];

    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(retain), NO);
    LC32InvokeHostSelector(hostSelf, host_cmd);
    return [self LC32_retain];
}

// FIXME: need to hook this?
- (NSUInteger)LC32_retainCount {
    const uint64_t hostSelf = LC32ExistingHostSelf(self);
    if(!hostSelf) return [self LC32_retainCount];

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

__attribute__((constructor)) void LC32FrameworkInit() {
    // Ensure LC32HostObjectPointer doesn't inherit swizzled ARC methods
    Class clsLC32HostObjectPointer = objc_getClass("LC32HostObjectPointer");
    Class clsNSObject = objc_getClass("NSObject");
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(autorelease)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(release)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(retain)));
    addMethodToClass(clsLC32HostObjectPointer, class_getInstanceMethod(clsNSObject, @selector(retainCount)));

    // Associated guest buffers are native guest-only objects as well. Keep
    // their ownership traffic out of the host proxy retain/release bridge.
    Class clsLC32GuestBuffer = objc_getClass("LC32GuestBuffer");
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(autorelease)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(release)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(retain)));
    addMethodToClass(clsLC32GuestBuffer, class_getInstanceMethod(clsNSObject, @selector(retainCount)));

    // Swizzle ARC methods
    swizzle(clsNSObject, @selector(autorelease), @selector(LC32_autorelease));
    swizzle(clsNSObject, @selector(release), @selector(LC32_release));
    swizzle(clsNSObject, @selector(retain), @selector(LC32_retain));
    swizzle(clsNSObject, @selector(retainCount), @selector(LC32_retainCount));

    // Send dlsym and LC32InvokeGuestC pointers to the host
    LC32InvokeHostCRet32(LC32Dlsym("LC32SetInvokeGuestFuncPtr", YES), &dlsym, &LC32InvokeGuestC);
}
