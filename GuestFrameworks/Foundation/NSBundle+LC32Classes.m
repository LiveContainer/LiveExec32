#import <Foundation/Foundation.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>
#include <dlfcn.h>

static char LC32BundleGuestExecutableLoaded;

@implementation NSBundle (LC32GuestClasses)
- (Class)classNamed:(NSString *)className {
    if(!className) return Nil;
    const char *name = className.UTF8String;
    if(!name) return Nil;

    // Preserve native bundle membership/loading semantics, but keep the
    // returned Class as an opaque host pointer, not a guest object proxy.
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, @selector(classNamed:), NO);
    if(!LC32InvokeHostSelector(self.host_self, selector,
            className.host_self, (uint64_t)0)) return Nil;

    Class cls = objc_lookUpClass(name);
    if(cls) return cls;

    /* Native -classNamed: loads only the ARM64 image. Converting that Class
     * back through the object bridge can pick a guest superclass (NSObject
     * for CTTelephonyNetworkInfo), which is not the requested class. Load
     * the executable through guest dyld and resolve its actual guest class.
     * Keep successful handles open: registered Objective-C classes must not
     * outlive their executable. Cache the load even for a missing class. */
    @synchronized(self) {
        if(!objc_getAssociatedObject(self, &LC32BundleGuestExecutableLoaded)) {
            const char *path = self.executablePath.fileSystemRepresentation;
            if(!path || !dlopen(path, RTLD_LAZY | RTLD_LOCAL)) return Nil;
            objc_setAssociatedObject(self, &LC32BundleGuestExecutableLoaded,
                @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return objc_lookUpClass(name);
}
@end
