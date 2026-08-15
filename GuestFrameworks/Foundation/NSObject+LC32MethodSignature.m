#import <Foundation/Foundation+LC32.h>

#import <objc/runtime.h>

@implementation NSObject (LC32MethodSignature)

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
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

@end
