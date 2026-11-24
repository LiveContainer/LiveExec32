#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

// Use the production guest method with an isolated bundle receiver. The
// loader registers the requested class only when its guest image is loaded;
// A native lookup alone or a superclass proxy cannot substitute for this step.
@interface LC32TestBundle : NSObject
@property(copy) NSString *executablePath;
- (Class)classNamed:(NSString *)name;
@end
@implementation LC32TestBundle
@end

@interface NSObject (LC32TestHostSelf)
- (uint64_t)host_self;
@end
@implementation NSObject (LC32TestHostSelf)
- (uint64_t)host_self { return (uintptr_t)self; }
@end

static unsigned loads, failures;
static BOOL failLoad;
static Class carrierClass;
static id subscriber(id self, SEL command) {
    (void)self; (void)command;
    return @"test carrier";
}
static void check(BOOL pass, const char *message) {
    if(!pass) { fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
static uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL structure) {
    check(sel_isEqual(selector, @selector(classNamed:)) && !structure, "bundle selector");
    if(!*cache) memcpy(cache, &selector, sizeof(selector));
    return *cache;
}
static uint64_t LC32InvokeHostSelector(uint64_t receiver, uint64_t selector, ...) {
    (void)selector;
    check(receiver != 0, "bundle receiver");
    va_list arguments;
    va_start(arguments, selector);
    NSString *name = (__bridge NSString *)(void *)(uintptr_t)va_arg(arguments, uint64_t);
    check(va_arg(arguments, uint64_t) == 0, "bridge terminator");
    va_end(arguments);
    // Native framework has these classes, but the guest has neither yet.
    // NSObject belongs to another bundle and must be rejected even though
    // its guest class is already registered.
    return [name isEqualToString:@"LC32LazyTelephonyInfo"] ||
        [name isEqualToString:@"LC32NativeOnlyTelephonyInfo"] ? UINT64_C(0x123456789) : 0;
}
static void *loadGuest(const char *path, int flags) {
    ++loads;
    check(!strcmp(path, "/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony"), "guest executable path");
    check(flags == (RTLD_LAZY | RTLD_LOCAL), "guest loader flags");
    if(failLoad) return NULL;
    carrierClass = objc_allocateClassPair(NSObject.class, "LC32LazyTelephonyInfo", 0);
    check(carrierClass != Nil, "allocate fixture class");
    class_addMethod(carrierClass, @selector(subscriberCellularProvider), (IMP)subscriber, "@@:");
    objc_registerClassPair(carrierClass);
    return (void *)1;
}

#define NSBundle LC32TestBundle
#define dlopen loadGuest
#include "../GuestFrameworks/Foundation/NSBundle+LC32Classes.m"
#undef dlopen
#undef NSBundle

int main(void) {
    @autoreleasepool {
        LC32TestBundle *bundle = [LC32TestBundle new];
        check([bundle classNamed:nil] == Nil && loads == 0, "nil class name");
        check([bundle classNamed:@"NSObject"] == Nil && loads == 0, "unrelated loaded class must not bypass bundle membership");
        check([bundle classNamed:@"LC32LazyTelephonyInfo"] == Nil && loads == 0, "missing executable");
        bundle.executablePath = @"/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony";
        failLoad = YES;
        check([bundle classNamed:@"LC32LazyTelephonyInfo"] == Nil && loads == 1, "failed load must not return superclass");
        failLoad = NO;
        Class cls = [bundle classNamed:@"LC32LazyTelephonyInfo"];
        check(cls == carrierClass && cls != NSObject.class && loads == 2, "retry returns exact guest class");
        id object = [cls new];
        check([[object performSelector:@selector(subscriberCellularProvider)] isEqual:@"test carrier"], "allocated receiver has requested getter");
        check([bundle classNamed:@"LC32LazyTelephonyInfo"] == cls && loads == 2, "repeat lookup does not reload");
        check([bundle classNamed:@"LC32NativeOnlyTelephonyInfo"] == Nil && loads == 2, "host-only class does not become a superclass or reload");
        check([bundle classNamed:@"LC32MissingTelephonyInfo"] == Nil && loads == 2, "missing class does not fall back or leak a load handle");
        puts(failures ? "bundle guest class lookup: FAIL" : "bundle guest class lookup: PASS");
    }
    return failures != 0;
}
