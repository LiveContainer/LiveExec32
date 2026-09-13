#import <Foundation/Foundation+LC32.h>

#import <objc/runtime.h>

@interface NSObject (LC32NativeMethodSignature)
- (NSMethodSignature *)LC32_nativeMethodSignatureForSelector:(SEL)selector
                                           instanceMethods:(BOOL)instanceMethods;
@end

static NSMethodSignature *LC32NativeMethodSignature(
        id receiver, SEL selector, BOOL instanceMethods) {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t nativeSelector = LC32CachedHostSelector(&hostSelector,
        @selector(LC32_nativeMethodSignatureForSelector:instanceMethods:), NO);
    /* A native-only selector has no ARM32 implementation or encoding to
     * preserve. Keep its native signature intact: a native NSInvocation can
     * pass through a guest forwarding proxy and invoke the native target
     * without narrowing pointer, NSInteger, or floating-point arguments. */
    return LC32ReturnBorrowedGuestObject(LC32InvokeHostObjectSelector(
        [receiver host_self], nativeSelector, LC32GetHostSelector(selector),
        (uint64_t)instanceMethods, (uint64_t)0));
}

@implementation NSObject (LC32MethodSignature)

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)selector {
    if(!selector) return nil;

    /*
     * libobjc leaves this Foundation class hook as a fatal stub.  Resolve the
     * requested instance method in the guest runtime so callers receive the
     * ARM32 method encoding, including inherited methods.
     */
    const Method method = class_getInstanceMethod(self, selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types]
        : LC32NativeMethodSignature(self, selector, YES);
}

+ (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(!selector) return nil;

    /* Class receivers dispatch through a separate fatal libobjc stub. */
    const Method method = class_getClassMethod(self, selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types]
        : LC32NativeMethodSignature(self, selector, NO);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(!selector) return nil;

    /*
     * The restore-ramdisk libobjc deliberately leaves this Foundation hook
     * unimplemented.  Look up the method in the guest runtime so dynamic
     * guest code (notably NSInvocation users) receives the ARM32 encoding.
     * object_getClass also does the right thing when the receiver itself is
     * a Class: its metaclass method list contains the class methods.
     */
    const Method method = class_getInstanceMethod(
        object_getClass(self), selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types]
        : LC32NativeMethodSignature(self, selector, NO);
}

@end
