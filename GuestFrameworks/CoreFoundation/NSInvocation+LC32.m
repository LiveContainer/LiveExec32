#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

@implementation NSInvocation (LC32ArgumentMarshalling)

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
