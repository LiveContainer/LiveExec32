#import "host_selector_hooks.h"
#include <mutex>
#include <unordered_map>

@interface NSObject (LC32HostMethodDispatch)
- (BOOL)isGuestClass;
@end

namespace {
struct Registry {
    std::mutex mutex;
    std::unordered_map<SEL, std::unordered_map<Class, LC32HostSelectorHook>> selectors;
};
Registry &Hooks() {
    static auto *registry = new Registry;
    return *registry;
}
}

void LC32RegisterHostSelectorHook(Class cls, SEL selector,
        LC32HostSelectorHook hook) {
    if(!cls || !selector) return;
    auto &registry = Hooks();
    const std::lock_guard<std::mutex> lock(registry.mutex);
    registry.selectors[selector][cls] = hook;
}

LC32HostSelectorHook LC32FindHostSelectorHook(Class cls, SEL selector) {
    auto &registry = Hooks();
    const std::lock_guard<std::mutex> lock(registry.mutex);
    const auto methods = registry.selectors.find(selector);
    if(methods == registry.selectors.end()) return {};
    for(; cls; cls = class_getSuperclass(cls)) {
        const auto hook = methods->second.find(cls);
        if(hook != methods->second.end()) return hook->second;
    }
    return {};
}

IMP LC32NativeHostMethod(id receiver, SEL selector) {
    Class cls = object_getClass(receiver);
    while(cls && [(id)cls isGuestClass]) cls = class_getSuperclass(cls);
    return class_getMethodImplementation(cls, selector);
}
