#import "../HostFrameworks/LC32/host_selector_hooks.h"
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

@interface NSObject (LC32HookTestBridge)
- (BOOL)isGuestClass;
@end
@implementation NSObject (LC32HookTestBridge)
- (BOOL)isGuestClass { return NO; }
@end

@interface HookBase : NSObject
- (int)value;
- (int)replacement;
@end
@implementation HookBase
- (int)value { return 17; }
- (int)replacement { return 29; }
@end
@interface HookChild : HookBase
@end
@implementation HookChild
- (int)value { return 41; }
@end
@interface HookGuestMirror : HookChild
@end
@implementation HookGuestMirror
+ (BOOL)isGuestClass { return YES; }
- (int)value { return 99; }
@end

static unsigned checks, failures, afterCalls;
static void check(const char *name, bool pass) {
    std::printf("selector-hooks-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static void after(id, const uint64_t *) { ++afterCalls; }

int main() {
    @autoreleasepool {
        const SEL value = @selector(value), replacement = @selector(replacement);
        check("unregistered", !LC32FindHostSelectorHook(HookChild.class, value).replacement);
        LC32RegisterHostSelectorHook(HookBase.class, value, {replacement, after});
        auto inherited = LC32FindHostSelectorHook(HookChild.class, value);
        check("inheritance", inherited.replacement == replacement && inherited.didInvoke == after);
        check("unrelated-class", !LC32FindHostSelectorHook(NSNumber.class, value).replacement);
        check("unrelated-selector", !LC32FindHostSelectorHook(HookChild.class, @selector(description)).replacement);
        HookChild *child = [HookChild new];
        check("native-method-not-swizzled", child.value == 41 && afterCalls == 0);
        using Getter = int (*)(id, SEL);
        check("native-subclass-override", ((Getter)LC32NativeHostMethod(child, value))(child, value) == 41);
        HookGuestMirror *guest = [HookGuestMirror new];
        check("bypass-only-guest-mirror", ((Getter)LC32NativeHostMethod(guest, value))(guest, value) == 41);
        // Calling a looked-up hook may itself look up/register hooks: never
        // hold the registry lock while dispatching framework code.
        inherited.didInvoke(child, nullptr);
        LC32RegisterHostSelectorHook(HookChild.class, value, {nullptr, after});
        auto overridden = LC32FindHostSelectorHook(HookChild.class, value);
        check("nearest-class-wins", !overridden.replacement && overridden.didInvoke == after);
        check("base-unchanged", LC32FindHostSelectorHook(HookBase.class, value).replacement == replacement);
        std::vector<std::thread> workers;
        for(unsigned i = 0; i < 4; ++i) workers.emplace_back([=] {
            for(unsigned j = 0; j < 1000; ++j) {
                LC32RegisterHostSelectorHook(HookBase.class, value, {replacement, after});
                if(LC32FindHostSelectorHook(HookBase.class, value).replacement != replacement)
                    std::abort();
            }
        });
        for(auto &worker : workers) worker.join();
        check("concurrent-registration-and-lookup", true);
    }
    std::printf("selector hooks: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
