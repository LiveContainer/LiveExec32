#import "../LC32/bridge.h"
#import "../LC32/host_selector_hooks.h"
#include <mutex>
#include <unordered_map>

static SEL LC32ObjectCallbackSelector(id observer, SEL selector) {
    if(!observer || !selector) return selector;
    Class cls = object_getClass(observer);
    Method method = class_getInstanceMethod(cls, selector);
    if(!method || method_getImplementation(method) != (IMP)&LC32InvokeGuestSelector ||
            method_getNumberOfArguments(method) != 3) return selector;

    char *argument = method_copyArgumentType(method, 2);
    char *result = method_copyReturnType(method);
    const char *argumentType = argument, *resultType = result;
    while(*argumentType && strchr("rnNoORVA", *argumentType)) ++argumentType;
    while(*resultType && strchr("rnNoORVA", *resultType)) ++resultType;
    const bool needsAdapter = *resultType == 'v' &&
        !(argumentType[0] == '@' && argumentType[1] != '?');
    free(argument);
    free(result);
    if(!needsAdapter) return selector;

    /* NotificationCenter and performSelector:...withObject: always send one
     * object, regardless of the callback's declared argument type. Legacy
     * libraries sometimes declare int* or id* instead. Use a private, typed
     * selector at these API boundaries, not a general pointer conversion.
     *
     * Keep the original observer, center, name and sender: native weak
     * storage, duplicate registrations and removeObserver: filters continue
     * to work. The process-lifetime IMP captures only the original selector,
     * never the observer or center, and passes the original _cmd to the guest.
     */
    static std::mutex mutex;
    static std::unordered_map<Class, std::unordered_map<SEL, SEL>> aliases;
    static uint64_t nextAlias = 0;
    std::lock_guard<std::mutex> lock(mutex);
    auto &classAliases = aliases[cls];
    auto existing = classAliases.find(selector);
    if(existing != classAliases.end()) return existing->second;

    IMP implementation = imp_implementationWithBlock(
        ^(id target, id argument) {
            LC32InvokeGuestObjectCallback(target, selector, argument);
        });
    if(!implementation) abort();
    SEL alias;
    do {
        char name[64];
        snprintf(name, sizeof(name), "__lc32_object_callback_%llu:",
            (unsigned long long)++nextAlias);
        alias = sel_registerName(name);
    } while(!class_addMethod(cls, alias, implementation, "v24@0:8@16"));
    classAliases.emplace(selector, alias);
    return alias;
}

@interface NSNotificationCenter (LC32GuestRegistration)
- (void)lc32_guestAddObserver:(id)observer selector:(SEL)selector
    name:(NSNotificationName)name object:(id)object;
@end

@implementation NSNotificationCenter (LC32GuestRegistration)
+ (void)load {
    LC32RegisterHostSelectorHook(self, @selector(addObserver:selector:name:object:),
        {@selector(lc32_guestAddObserver:selector:name:object:), nullptr});
}

- (void)lc32_guestAddObserver:(id)observer selector:(SEL)selector
        name:(NSNotificationName)name object:(id)object {
    selector = LC32ObjectCallbackSelector(observer, selector);
    const SEL original = @selector(addObserver:selector:name:object:);
    using AddObserver = void (*)(id, SEL, id, SEL, NSNotificationName, id);
    ((AddObserver)LC32NativeHostMethod(self, original))(self, original,
        observer, selector, name, object);
}
@end

@interface NSObject (LC32GuestThreadPerforming)
- (void)lc32_guestPerformSelector:(SEL)selector onThread:(NSThread *)thread
    withObject:(id)object waitUntilDone:(BOOL)wait modes:(NSArray *)modes;
@end

@implementation NSObject (LC32GuestThreadPerforming)
+ (void)load {
    LC32RegisterHostSelectorHook(self,
        @selector(performSelector:onThread:withObject:waitUntilDone:modes:),
        {@selector(lc32_guestPerformSelector:onThread:withObject:waitUntilDone:modes:),
         nullptr});
}

- (void)lc32_guestPerformSelector:(SEL)selector onThread:(NSThread *)thread
        withObject:(id)object waitUntilDone:(BOOL)wait modes:(NSArray *)modes {
    selector = LC32ObjectCallbackSelector(self, selector);
    const SEL original =
        @selector(performSelector:onThread:withObject:waitUntilDone:modes:);
    using Perform = void (*)(id, SEL, SEL, NSThread *, id, BOOL, NSArray *);
    ((Perform)LC32NativeHostMethod(self, original))(
        self, original, selector, thread, object, wait, modes);
}
@end
