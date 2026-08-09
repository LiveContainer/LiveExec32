#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LC32.h"

#include <dlfcn.h>

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

@implementation NSObject(LC32)
static const void *kHostSelf = &kHostSelf;

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
    objc_setAssociatedObject(self, kHostSelf, [LC32HostObjectPointer pointerWithValue:ptr], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    printf("Calling from %s:0x%08x:0x%08x, isClass? = %d\n", class_getName(self.class), (uint32_t)self.class, (uint32_t)self, object_isClass(self));
    uint64_t ptr = ((LC32HostObjectPointer *)objc_getAssociatedObject(self, kHostSelf)).value;
    if(!ptr) {
        self.host_self = ptr = LC32GetHostObject(self, class_getName(self.class), object_isClass(self));
    }
    assert(ptr != 0);
    return ptr;
}

- (instancetype)LC32_autorelease {
    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(autorelease), NO);
    LC32InvokeHostSelector(self.host_self, host_cmd);
    return [self LC32_autorelease];
}
- (void)LC32_release {
    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(release), NO);
    LC32InvokeHostSelector(self.host_self, host_cmd);
    [self LC32_release];
}

- (instancetype)LC32_retain {
    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(retain), NO);
    LC32InvokeHostSelector(self.host_self, host_cmd);
    return [self LC32_retain];
}

// FIXME: need to hook this?
- (NSUInteger)LC32_retainCount {
    static uint64_t _host_cmd;
    uint64_t host_cmd = LC32CachedHostSelector(
        &_host_cmd, @selector(retainCount), NO);
    uint64_t host_ret = LC32InvokeHostSelector(self.host_self, host_cmd);
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

    // Swizzle ARC methods
    swizzle(clsNSObject, @selector(autorelease), @selector(LC32_autorelease));
    swizzle(clsNSObject, @selector(release), @selector(LC32_release));
    swizzle(clsNSObject, @selector(retain), @selector(LC32_retain));
    swizzle(clsNSObject, @selector(retainCount), @selector(LC32_retainCount));

    // Send dlsym and LC32InvokeGuestC pointers to the host
    LC32InvokeHostCRet32(LC32Dlsym("LC32SetInvokeGuestFuncPtr", YES), &dlsym, &LC32InvokeGuestC);
}
