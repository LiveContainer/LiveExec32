#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

/*
 * KVO registration is implemented by Foundation as an NSObject category.
 * The guest NSObject comes from libobjc, so it does not inherit these methods
 * from a generated framework class.  Keep the context as an opaque ARM32
 * token: native Foundation promises to return it unchanged and never needs to
 * dereference it.  The host callback bridge accepts zero-extended void *
 * values and restores the original guest pointer.
 */
@implementation NSObject (LC32KeyValueObserving)

- (void)addObserver:(NSObject *)observer
          forKeyPath:(NSString *)keyPath
             options:(NSKeyValueObservingOptions)options
             context:(void *)context {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(
        self.host_self, selector,
        observer.host_self, keyPath.host_self,
        (uint64_t)(uint32_t)options,
        (uint64_t)(uint32_t)(uintptr_t)context,
        (uint64_t)0);
}

- (void)removeObserver:(NSObject *)observer
             forKeyPath:(NSString *)keyPath
                context:(void *)context {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(
        self.host_self, selector,
        observer.host_self, keyPath.host_self,
        (uint64_t)(uint32_t)(uintptr_t)context,
        (uint64_t)0);
}

- (void)removeObserver:(NSObject *)observer
             forKeyPath:(NSString *)keyPath {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(
        self.host_self, selector,
        observer.host_self, keyPath.host_self,
        (uint64_t)0);
}

@end
