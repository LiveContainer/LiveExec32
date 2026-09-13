#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

@implementation NSInvocation (LC32ArgumentMarshalling)

- (SEL)selector {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    // The invocation bridge returns a guest selector, not a native address.
    return (SEL)(uintptr_t)LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0);
}

- (void)getArgument:(void *)argumentLocation atIndex:(NSInteger)index {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
        LC32HostInvocationArgument(argumentLocation),
        (uint64_t)(uint32_t)index, (uint64_t)0);
}

- (void)getReturnValue:(void *)returnLocation {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
        LC32HostInvocationArgument(returnLocation), (uint64_t)0);
}

- (void)setReturnValue:(void *)returnLocation {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
        LC32HostInvocationArgument(returnLocation), (uint64_t)0);
}

- (void)setArgument:(void *)argumentLocation atIndex:(NSInteger)index {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(
        self.host_self, selector,
        LC32HostInvocationArgument(argumentLocation),
        (uint64_t)(uint32_t)index, (uint64_t)0);
}

@end
