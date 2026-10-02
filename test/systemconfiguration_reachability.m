#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <pthread.h>
#include <dlfcn.h>

static unsigned checks, failures;
static void check(const char *name, BOOL pass) {
    printf("reachability-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static char queueKey;
typedef struct {
    int references, callbacks;
    BOOL queueMatches, cancel, cancelled;
    void *expectedQueue;
} Context;
static const void *retainContext(const void *info) {
    ++((Context *)info)->references;
    return info;
}
static void releaseContext(const void *info) { --((Context *)info)->references; }
static void callback(SCNetworkReachabilityRef target,
                     SCNetworkReachabilityFlags flags, void *info) {
    Context *context = info;
    ++context->callbacks;
    context->queueMatches = dispatch_get_specific(&queueKey) == context->expectedQueue &&
        (flags & kSCNetworkReachabilityFlagsReachable);
    if(context->cancel) context->cancelled = SCNetworkReachabilitySetDispatchQueue(target, NULL);
}
static SCNetworkReachabilityRef create(Context *info) {
    SCNetworkReachabilityRef target = SCNetworkReachabilityCreateWithName(NULL, "example.invalid");
    SCNetworkReachabilityContext context = {0, info, retainContext, releaseContext, NULL};
    check("create-callback", target && SCNetworkReachabilitySetCallback(target, callback, &context));
    return target;
}
static void drain(void *unused) { (void)unused; }
static dispatch_queue_t newQueue(const char *label) {
    dispatch_queue_t queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue, &queueKey, queue, NULL);
    return queue;
}
static void testQueue(void) {
    dispatch_queue_t queue = newQueue("reachability.test");
    Context context = {.references=1, .expectedQueue=queue};
    SCNetworkReachabilityRef target = create(&context);
    dispatch_suspend(queue);
    check("schedule", SCNetworkReachabilitySetDispatchQueue(target, queue));
    check("deferred", context.callbacks == 0);
    check("duplicate-rejected", !SCNetworkReachabilitySetDispatchQueue(target, queue));
    check("duplicate-error", SCError() == kSCStatusInvalidArgument);
    CFErrorRef error = SCCopyLastError();
    check("copy-error", error && CFErrorGetCode(error) == kSCStatusInvalidArgument);
    if(error) CFRelease(error);
    check("mixed-runloop-rejected", !SCNetworkReachabilityScheduleWithRunLoop(target,
        CFRunLoopGetCurrent(), kCFRunLoopDefaultMode));
    check("wrong-unschedule-rejected", !SCNetworkReachabilityUnscheduleFromRunLoop(target,
        CFRunLoopGetCurrent(), kCFRunLoopDefaultMode));
    dispatch_resume(queue);
    dispatch_sync_f(queue, NULL, drain);
    check("delivered-on-queue", context.callbacks == 1 && context.queueMatches);
    check("context-snapshot-balanced", context.references == 2);
    SCNetworkReachabilityContext replacement = {0, &context, retainContext, releaseContext, NULL};
    check("same-context-replace", SCNetworkReachabilitySetCallback(target, callback, &replacement));
    dispatch_sync_f(queue, NULL, drain);
    check("replacement-delivered", context.callbacks == 2 && context.references == 2);
    check("remove-callback", SCNetworkReachabilitySetCallback(target, NULL, NULL));
    check("context-released", context.references == 1);
    check("cancel", SCNetworkReachabilitySetDispatchQueue(target, NULL));
    check("double-cancel-rejected", !SCNetworkReachabilitySetDispatchQueue(target, NULL));
    CFRelease(target);
    dispatch_release(queue);
}
static void testCancellation(void) {
    dispatch_queue_t a = newQueue("reachability.old"), b = newQueue("reachability.new");
    Context context = {.references=1, .expectedQueue=b};
    SCNetworkReachabilityRef target = create(&context);
    dispatch_suspend(a); dispatch_suspend(b);
    check("old-schedule", SCNetworkReachabilitySetDispatchQueue(target, a));
    check("pending-cancel", SCNetworkReachabilitySetDispatchQueue(target, NULL));
    check("new-schedule", SCNetworkReachabilitySetDispatchQueue(target, b));
    dispatch_resume(a); dispatch_sync_f(a, NULL, drain);
    check("old-generation-suppressed", context.callbacks == 0);
    dispatch_resume(b); dispatch_sync_f(b, NULL, drain);
    check("new-generation-delivered", context.callbacks == 1 && context.queueMatches);
    check("new-cancel", SCNetworkReachabilitySetDispatchQueue(target, NULL));
    CFRelease(target);
    check("cancel-context-balanced", context.references == 1);
    dispatch_release(a); dispatch_release(b);
}
static void testLifetime(void) {
    dispatch_queue_t queue = newQueue("reachability.lifetime");
    Context context = {.references=1, .expectedQueue=queue, .cancel=YES};
    SCNetworkReachabilityRef target = create(&context);
    dispatch_suspend(queue);
    check("lifetime-schedule", SCNetworkReachabilitySetDispatchQueue(target, queue));
    CFRelease(target); // The scheduled target and pending work own its lifetime.
    dispatch_resume(queue); dispatch_sync_f(queue, NULL, drain);
    check("self-cancel", context.callbacks == 1 && context.cancelled && context.queueMatches);
    check("final-context-release", context.references == 1);
    dispatch_release(queue);
}
static void testLateCallback(void) {
    dispatch_queue_t queue = newQueue("reachability.late");
    Context context = {.references=1, .expectedQueue=queue};
    SCNetworkReachabilityRef target = SCNetworkReachabilityCreateWithName(NULL, "example.invalid");
    check("schedule-before-callback", SCNetworkReachabilitySetDispatchQueue(target, queue));
    // A release-only context transfers one reference; dispatch delivery must
    // not release an extra snapshot reference that it never retained.
    SCNetworkReachabilityContext info = {0, &context, NULL, releaseContext, NULL};
    check("late-callback", SCNetworkReachabilitySetCallback(target, callback, &info));
    dispatch_sync_f(queue, NULL, drain);
    check("release-only-delivery", context.callbacks == 1 && context.references == 1);
    check("late-cancel", SCNetworkReachabilitySetDispatchQueue(target, NULL));
    CFRelease(target);
    check("release-only-destruction", context.references == 0);
    dispatch_release(queue);
}
static void *checkThreadError(void *info) {
    *(int *)info = SCError();
    SCNetworkReachabilitySetDispatchQueue(NULL, NULL);
    return NULL;
}
static void testErrorIsolation(void) {
    int otherError = -1;
    pthread_t thread;
    int result = pthread_create(&thread, NULL, checkThreadError, &otherError);
    check("error-thread-create", result == 0);
    if(result) return;
    pthread_join(thread, NULL);
    check("error-thread-local", otherError == kSCStatusOK && SCError() == kSCStatusInvalidArgument);
}
static void testRunLoop(void) {
    Context context = {.references=1};
    SCNetworkReachabilityRef target = create(&context);
    CFRunLoopRef loop = CFRunLoopGetCurrent();
    CFStringRef mode = CFSTR("LC32ReachabilityTest");
    check("runloop-schedule", SCNetworkReachabilityScheduleWithRunLoop(target, loop, mode));
    check("runloop-deferred", context.callbacks == 0);
    check("mixed-queue-rejected", !SCNetworkReachabilitySetDispatchQueue(target,
        dispatch_get_main_queue()));
    CFRunLoopRunInMode(mode, .2, true);
    check("runloop-delivered", context.callbacks == 1);
    check("runloop-unschedule", SCNetworkReachabilityUnscheduleFromRunLoop(target, loop, mode));
    CFRelease(target);
    check("runloop-context-balanced", context.references == 1);
}
#if LC32_TEST_COPY_QUERIES
static void testCopies(void) {
    const char *names[] = {"SCDynamicStoreCopyComputerName", "SCDynamicStoreCopyLocalHostName",
        "SCDynamicStoreCopyLocation", "SCDynamicStoreCopyProxies", "CNCopySupportedInterfaces",
        "CNCopyCurrentNetworkInfo"};
    CFTypeID types[] = {CFStringGetTypeID(), CFStringGetTypeID(), CFStringGetTypeID(),
        CFDictionaryGetTypeID(), CFArrayGetTypeID(), CFDictionaryGetTypeID()};
    for(unsigned i = 0; i < sizeof(names)/sizeof(*names); ++i) {
        void *symbol = dlsym(RTLD_DEFAULT, names[i]);
        check(names[i], symbol != NULL);
        if(!symbol) continue;
        CFTypeRef result;
        struct { CFStringEncoding encoding; uint32_t guard; } output = {0, 0xa5a5a5a5};
        if(i == 0) result = ((CFTypeRef (*)(CFTypeRef, CFStringEncoding *))symbol)(NULL, &output.encoding);
        else if(i == 4) result = ((CFTypeRef (*)(void))symbol)();
        else result = ((CFTypeRef (*)(CFTypeRef))symbol)(i == 5 ? CFSTR("en0") : NULL);
        // Privacy/entitlements or absent optional APIs may legitimately yield
        // NULL. Never print device names, SSIDs, or proxy configuration.
        check("copy-result-type", !result || CFGetTypeID(result) == types[i]);
        check("copy-output-guard", output.guard == 0xa5a5a5a5);
        if(result) { check("copy-success-error", SCError() == kSCStatusOK); CFRelease(result); }
    }
}
#endif
int main(void) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        check("null-target", !SCNetworkReachabilitySetDispatchQueue(NULL, dispatch_get_main_queue()));
        testErrorIsolation();
        testQueue(); testCancellation(); testLifetime(); testLateCallback(); testRunLoop();
#if LC32_TEST_COPY_QUERIES
        testCopies();
#endif
        printf("systemconfiguration-reachability: %u checks, %u failures\n", checks, failures);
    }
    return failures != 0;
}
