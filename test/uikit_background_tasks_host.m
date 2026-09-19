// Compile the real guest shim against a small fake host. No UIKit process or
// timers are needed: expiration, normal completion, and invalidation are exact.
#import <UIKit/UIKit.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>

@implementation UIApplication
@end
@implementation NSObject (LC32BackgroundTaskTestBridge)
- (uint64_t)host_self { return (uintptr_t)(__bridge void *)self; }
@end

static NSMutableDictionary *handlers;
static NSMutableDictionary *endCounts;
static NSString *lastName;
static uint32_t nextIdentifier = 1;
static BOOL failBegin;
static unsigned failures, checks, invalidEnds;

uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL superCall) {
    (void)superCall;
    return *cache = sel_isEqual(selector,
        @selector(beginBackgroundTaskWithName:expirationHandler:)) ? 1 : 2;
}

uint64_t LC32InvokeHostSelector(uint64_t receiver, uint64_t command, ...) {
    (void)receiver;
    va_list args;
    va_start(args, command);
    if(command == 1) {
        lastName = (__bridge NSString *)(void *)(uintptr_t)va_arg(args, uint64_t);
        void (^handler)(void) = (__bridge id)(void *)(uintptr_t)va_arg(args, uint64_t);
        va_end(args);
        if(failBegin) return UIBackgroundTaskInvalid;
        uint32_t identifier = nextIdentifier++;
        handlers[@(identifier)] = [handler copy];
        return identifier;
    }
    if(command == 2) {
        uint32_t identifier = (uint32_t)va_arg(args, uint64_t);
        va_end(args);
        if(!handlers[@(identifier)]) invalidEnds++;
        endCounts[@(identifier)] = @([endCounts[@(identifier)] unsignedIntValue] + 1);
        [handlers removeObjectForKey:@(identifier)];
        return 0;
    }
    va_end(args);
    abort();
}

static void check(BOOL condition, const char *description) {
    checks++;
    if(!condition) failures++;
    printf("%s %s\n", condition ? "PASS" : "FAIL", description);
}

static void expire(uint32_t identifier) {
    void (^handler)(void) = handlers[@(identifier)];
    check(handler != nil, "host has an expiration callback");
    if(handler) handler();
}

int main(void) {
    @autoreleasepool {
        handlers = [NSMutableDictionary new];
        endCounts = [NSMutableDictionary new];
        UIApplication *app = [UIApplication new];
        __block unsigned calls = 0;
        uint32_t logging = [app beginBackgroundTaskWithExpirationHandler:^{ calls++; }];
        check(logging != 0 && lastName == nil, "anonymous task starts normally");
        expire(logging);
        check(calls == 1 && [endCounts[@(logging)] intValue] == 1,
              "log-only legacy handler runs and its expired task ends");
        [app endBackgroundTask:logging];
        check([endCounts[@(logging)] intValue] == 1, "late completion does not double-end");

        __block uint32_t selfEnding = 0;
        selfEnding = [app beginBackgroundTaskWithExpirationHandler:^{
            calls++;
            [app endBackgroundTask:selfEnding];
        }];
        expire(selfEnding);
        check(calls == 2 && [endCounts[@(selfEnding)] intValue] == 1,
              "well-behaved handler ends exactly once");

        uint32_t normal = [app beginBackgroundTaskWithName:@"save" expirationHandler:^{ calls++; }];
        check([lastName isEqualToString:@"save"], "named task preserves its name");
        [app endBackgroundTask:normal];
        [app endBackgroundTask:normal];
        check(calls == 2 && [endCounts[@(normal)] intValue] == 1,
              "normal completion cancels expiration and tolerates duplicate end");

        uint32_t first = [app beginBackgroundTaskWithExpirationHandler:nil];
        uint32_t second = [app beginBackgroundTaskWithName:@"other" expirationHandler:nil];
        expire(first);
        check(!handlers[@(first)] && handlers[@(second)], "expiring nil handler leaves other task active");
        expire(second);
        check([endCounts[@(second)] intValue] == 1, "named nil handler also releases expiration");

        __block uint32_t nested = 0;
        uint32_t parent = [app beginBackgroundTaskWithExpirationHandler:^{
            nested = [app beginBackgroundTaskWithExpirationHandler:nil];
        }];
        expire(parent);
        check(handlers[@(nested)] && !handlers[@(parent)], "handler may create a different task reentrantly");
        [app endBackgroundTask:nested];

        uint32_t concurrent = [app beginBackgroundTaskWithExpirationHandler:nil];
        dispatch_apply(32, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
            (void)index;
            [app endBackgroundTask:concurrent];
        });
        check([endCounts[@(concurrent)] intValue] == 1,
              "racing completion calls consume one native task");

        failBegin = YES;
        check([app beginBackgroundTaskWithExpirationHandler:nil] == UIBackgroundTaskInvalid,
              "host refusal returns invalid without registering a task");
        [app endBackgroundTask:UIBackgroundTaskInvalid];
        check(handlers.count == 0 && invalidEnds == 0, "no leaked registrations or invalid native ends");
    }
    printf("%u/%u background-task checks passed\n", checks-failures, checks);
    return failures ? 1 : 0;
}
