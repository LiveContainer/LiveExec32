#import <Foundation/Foundation+LC32.h>

#import <objc/message.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * NSProxy is a second Objective-C root class rather than an NSObject
 * subclass.  The generated Foundation shims intentionally only describe
 * host methods, so they cannot synthesize the class and metaclass records
 * required by binaries which subclass NSProxy directly.
 *
 * Use libobjc's root allocation entry points just like the system NSProxy.
 * These declarations are private to the Objective-C runtime but exported by
 * the iOS 10 libobjc shipped in the guest ramdisk.
 */
extern id _objc_rootAlloc(Class cls);
extern id _objc_rootAllocWithZone(Class cls, NSZone *zone);
extern void _objc_rootDealloc(id object);

@implementation NSProxy

+ (id)alloc {
    return _objc_rootAlloc(self);
}

+ (id)allocWithZone:(NSZone *)zone {
    return _objc_rootAllocWithZone(self, zone);
}

+ (Class)class {
    return self;
}

+ (BOOL)respondsToSelector:(SEL)selector {
    return selector &&
        class_respondsToSelector(object_getClass(self), selector);
}

- (Class)class {
    return object_getClass(self);
}

- (Class)superclass {
    return class_getSuperclass(object_getClass(self));
}

- (instancetype)self {
    return self;
}

- (BOOL)isEqual:(id)object {
    return self == object;
}

- (NSUInteger)hash {
    return (NSUInteger)(uintptr_t)self;
}

- (BOOL)isProxy {
    return YES;
}

- (BOOL)isKindOfClass:(Class)candidate {
    for(Class cls = object_getClass(self); cls;
            cls = class_getSuperclass(cls)) {
        if(cls == candidate) return YES;
    }
    return NO;
}

- (BOOL)isMemberOfClass:(Class)candidate {
    return object_getClass(self) == candidate;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    return protocol &&
        class_conformsToProtocol(object_getClass(self), protocol);
}

- (BOOL)respondsToSelector:(SEL)selector {
    return selector &&
        class_respondsToSelector(object_getClass(self), selector);
}

- (id)performSelector:(SEL)selector {
    return ((id (*)(id, SEL))objc_msgSend)(self, selector);
}

- (id)performSelector:(SEL)selector withObject:(id)object {
    return ((id (*)(id, SEL, id))objc_msgSend)(self, selector, object);
}

- (id)performSelector:(SEL)selector
            withObject:(id)object1
            withObject:(id)object2 {
    return ((id (*)(id, SEL, id, id))objc_msgSend)(
        self, selector, object1, object2);
}

- (NSZone *)zone {
    return NULL;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [self doesNotRecognizeSelector:invocation.selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(!selector) return nil;
    const Method method = class_getInstanceMethod(
        object_getClass(self), selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

- (void)doesNotRecognizeSelector:(SEL)selector {
    fprintf(stderr, "NSProxy %p does not recognize selector %s\n", self,
        selector ? sel_getName(selector) : "(null)");
    abort();
}

- (void)dealloc {
    _objc_rootDealloc(self);
}

- (void)finalize {
}

- (NSString *)description {
    return @"<NSProxy>";
}

- (NSString *)debugDescription {
    return self.description;
}

@end

static void LC32CopyNSObjectMethodToProxy(Class proxyClass,
                                          Class objectClass,
                                          const char *name) {
    const SEL selector = sel_registerName(name);
    const Method method = class_getInstanceMethod(objectClass, selector);
    if(!method) {
        fprintf(stderr, "LC32: missing NSObject bridge method %s for NSProxy\n",
            name);
        abort();
    }
    if(!class_addMethod(proxyClass, selector,
            method_getImplementation(method),
            method_getTypeEncoding(method))) {
        fprintf(stderr, "LC32: failed to install NSProxy bridge method %s\n",
            name);
        abort();
    }
}

__attribute__((constructor)) static void LC32InitializeNSProxy(void) {
    const Class proxyClass = objc_getClass("NSProxy");
    const Class objectClass = objc_getClass("NSObject");

    /*
     * LC32's NSObject category stores the native peer and pairs guest/native
     * ownership.  Categories on NSObject are not inherited by the independent
     * NSProxy root hierarchy, so install that deliberately small bridge set.
     * LC32 is a dependency of Foundation and its constructor has already
     * swapped NSObject's public ownership selectors, making both sides of each
     * ownership pair available to copy here.
     */
    static const char * const selectors[] = {
        "initWithHostSelf:",
        "bindHostSelf:",
        "host_self",
        "LC32_rawHostSelf",
        "setHost_self:",
        "autorelease",
        "release",
        "retain",
        "retainCount",
        "LC32_autorelease",
        "LC32_release",
        "LC32_releaseGuestOwnershipOnly",
        "LC32_retain",
        "LC32_retainCount",
    };

    for(size_t index = 0;
            index < sizeof(selectors) / sizeof(selectors[0]); index++) {
        LC32CopyNSObjectMethodToProxy(
            proxyClass, objectClass, selectors[index]);
    }
}
