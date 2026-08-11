#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

/*
 * NSObject's guest-side -init is correct for ordinary guest-only classes, but
 * Foundation class clusters need to initialize the native object returned by
 * LC32GetHostObject. Their generated method lists do not contain plain -init,
 * so without these class-specific overrides the native peer remains an alloc
 * placeholder and crashes on its first real operation.
 *
 * Immutable empty clusters are intentionally excluded: several return shared
 * singletons, which require the initializer shim to return an existing
 * canonical guest proxy rather than the just-allocated self.
 */
static id LC32InitializeHostPeer(id self) {
    static uint64_t hostInitSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostInitSelector, @selector(init), NO);
    const uint64_t result = LC32InvokeHostSelector(
        [self host_self], selector, (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, result);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

#define LC32_IMPLEMENT_PLAIN_INIT(className) \
    @implementation className (LC32PlainInit) \
    - (instancetype)init { \
        return LC32InitializeHostPeer(self); \
    } \
    @end

LC32_IMPLEMENT_PLAIN_INIT(NSMutableArray)
LC32_IMPLEMENT_PLAIN_INIT(NSMutableDictionary)
LC32_IMPLEMENT_PLAIN_INIT(NSMutableSet)
LC32_IMPLEMENT_PLAIN_INIT(NSMutableOrderedSet)
LC32_IMPLEMENT_PLAIN_INIT(NSMutableData)
LC32_IMPLEMENT_PLAIN_INIT(NSMutableString)
LC32_IMPLEMENT_PLAIN_INIT(NSDate)

#pragma clang diagnostic pop
