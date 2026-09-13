#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Native baseline: -DLC32_NOTIFICATION_NATIVE_CHECK=1 -fno-objc-arc
// Guest integration also links LC32 for the existing host-worker test helper.
#ifndef LC32_NOTIFICATION_NATIVE_CHECK
extern uint64_t LC32Dlsym(const char *name, BOOL isFunction);
extern uint32_t LC32InvokeHostCRet32(uint64_t hostPointer, ...);
#endif

static unsigned checks, failures;
static NSString *const primaryName = @"LC32MisdeclaredNotification";
static NSString *const otherName = @"LC32OtherSelectorNotification";

static void check(const char *name, BOOL passed) {
    printf("notification-selector-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

@interface LC32NotificationSelectorFixture : NSObject {
@public
    NSUInteger pointerCalls, objectCalls, badPayloads, badSelectors;
    NSString *expectedName;
    id expectedSender;
    NSDictionary *expectedInfo;
    pthread_t callbackThread;
    NSNotificationCenter *selfRemovalCenter;
    BOOL *deallocated;
}
- (void)misdeclared:(int *)notification;
- (void)normal:(NSNotification *)notification;
@end

@implementation LC32NotificationSelectorFixture
- (void)record:(NSNotification *)notification selector:(SEL)selector expected:(SEL)expected {
    callbackThread = pthread_self();
    badSelectors += selector != expected;
    BOOL infoMatches = expectedInfo ? [notification.userInfo isEqual:expectedInfo] :
        notification.userInfo == nil;
    badPayloads += !([notification isKindOfClass:[NSNotification class]] &&
        [notification.name isEqual:expectedName] && notification.object == expectedSender &&
        infoMatches);
    if(selfRemovalCenter) [selfRemovalCenter removeObserver:self];
}
- (void)misdeclared:(int *)notification {
    ++pointerCalls;
    // CritterImpl advertises ^i, although the callback consumes an object.
    [self record:(NSNotification *)(void *)notification selector:_cmd
        expected:@selector(misdeclared:)];
}
- (void)normal:(NSNotification *)notification {
    ++objectCalls;
    [self record:notification selector:_cmd expected:@selector(normal:)];
}
- (void)dealloc {
    if(deallocated) *deallocated = YES;
    [super dealloc];
}
@end

static void expect(LC32NotificationSelectorFixture *probe, NSString *name,
                   id sender, NSDictionary *info) {
    // Borrowed only for synchronous posts; the test owns the values throughout.
    probe->expectedName = name;
    probe->expectedSender = sender;
    probe->expectedInfo = info;
}

static void post(NSNotificationCenter *center, LC32NotificationSelectorFixture *probe,
                 NSString *name, id sender, NSDictionary *info) {
    expect(probe, name, sender, info);
    [center postNotificationName:name object:sender userInfo:info];
}

static void add(NSNotificationCenter *center, LC32NotificationSelectorFixture *probe,
                SEL selector, NSString *name, id sender) {
    [center addObserver:probe selector:selector name:name object:sender];
}

static void checkPayloads(LC32NotificationSelectorFixture *probe) {
    check("notification-class-name-sender-userInfo", probe->badPayloads == 0);
    check("original-callback-cmd", probe->badSelectors == 0);
}

static void basicAndDuplicateRegistration(void) {
    NSNotificationCenter *center = [NSNotificationCenter new];
    LC32NotificationSelectorFixture *probe = [LC32NotificationSelectorFixture new];
    NSObject *sender = [NSObject new], *otherSender = [NSObject new];
    NSDictionary *info = @{ @"value": @37, @"label": @"guest payload" };
    add(center, probe, @selector(misdeclared:), primaryName, sender);
    add(center, probe, @selector(normal:), primaryName, sender);
    post(center, probe, otherName, sender, info);
    post(center, probe, primaryName, otherSender, info);
    check("registration-name-and-sender-filter", probe->pointerCalls == 0 && probe->objectCalls == 0);
    post(center, probe, primaryName, sender, info);
    check("both-selectors-delivered-synchronously", probe->pointerCalls == 1 &&
        probe->objectCalls == 1 && pthread_equal(probe->callbackThread, pthread_self()));
    [center removeObserver:probe name:primaryName object:otherSender];
    post(center, probe, primaryName, sender, info);
    check("unmatched-removal-preserves-registrations", probe->pointerCalls == 2 && probe->objectCalls == 2);
    add(center, probe, @selector(misdeclared:), primaryName, sender);
    add(center, probe, @selector(misdeclared:), primaryName, sender);
    post(center, probe, primaryName, sender, info);
    check("duplicate-registrations-delivered", probe->pointerCalls == 5 && probe->objectCalls == 3);
    [center removeObserver:probe name:primaryName object:sender];
    post(center, probe, primaryName, sender, info);
    check("filtered-removal-removes-all-duplicates-and-selectors",
        probe->pointerCalls == 5 && probe->objectCalls == 3);
    checkPayloads(probe);
    [center removeObserver:probe];
    [probe release]; [sender release]; [otherSender release]; [center release];
}

static void filtersAndIndependentCenters(void) {
    NSNotificationCenter *first = [NSNotificationCenter new], *second = [NSNotificationCenter new];
    LC32NotificationSelectorFixture *probe = [LC32NotificationSelectorFixture new];
    NSObject *a = [NSObject new], *b = [NSObject new];
    add(first, probe, @selector(misdeclared:), primaryName, a);
    add(first, probe, @selector(normal:), otherName, a);
    add(first, probe, @selector(misdeclared:), primaryName, b);
    add(second, probe, @selector(misdeclared:), primaryName, a);
    add(second, probe, @selector(normal:), otherName, a);
    [first removeObserver:probe name:primaryName object:a];
    post(first, probe, primaryName, a, nil);
    post(first, probe, primaryName, b, nil);
    post(first, probe, otherName, a, nil);
    post(second, probe, primaryName, a, nil);
    post(second, probe, otherName, a, nil);
    check("exact-filter-keeps-other-name-sender-center", probe->pointerCalls == 2 && probe->objectCalls == 2);
    add(first, probe, @selector(misdeclared:), primaryName, a);
    [first removeObserver:probe name:nil object:a];
    post(first, probe, primaryName, a, nil);
    post(first, probe, otherName, a, nil);
    post(first, probe, primaryName, b, nil);
    check("nil-name-removal-matches-sender-only", probe->pointerCalls == 3 && probe->objectCalls == 2);
    [first removeObserver:probe name:primaryName object:nil];
    post(first, probe, primaryName, b, nil);
    post(second, probe, primaryName, a, nil);
    check("nil-sender-removal-keeps-other-center", probe->pointerCalls == 4 && probe->objectCalls == 2);
    [first removeObserver:probe];
    post(second, probe, otherName, a, nil);
    check("broad-removal-is-center-local", probe->objectCalls == 3);
    [second removeObserver:probe];
    post(second, probe, primaryName, a, nil);
    post(second, probe, otherName, a, nil);
    check("broad-removal-clears-both-selectors", probe->pointerCalls == 4 && probe->objectCalls == 3);
    add(first, probe, @selector(misdeclared:), nil, nil);
    post(first, probe, primaryName, a, nil);
    post(first, probe, otherName, b, @{ @"wildcard": @YES });
    check("nil-name-and-sender-registration", probe->pointerCalls == 6);
    [first removeObserver:probe];
    checkPayloads(probe);
    [probe release]; [a release]; [b release]; [first release]; [second release];
}

static void selfRemovalAndRepeatedRegistration(void) {
    NSNotificationCenter *center = [NSNotificationCenter new];
    LC32NotificationSelectorFixture *probe = [LC32NotificationSelectorFixture new];
    probe->selfRemovalCenter = center;
    add(center, probe, @selector(misdeclared:), primaryName, nil);
    post(center, probe, primaryName, nil, nil);
    post(center, probe, primaryName, nil, nil);
    check("self-removal-during-callback", probe->pointerCalls == 1);
    probe->selfRemovalCenter = nil;
    BOOL repeated = YES;
    for(unsigned i = 0; i < 16; ++i) {
        add(center, probe, @selector(misdeclared:), primaryName, nil);
        post(center, probe, primaryName, nil, nil);
        repeated &= probe->pointerCalls == i + 2;
        if(i % 2) [center removeObserver:probe];
        else [center removeObserver:probe name:primaryName object:nil];
        post(center, probe, primaryName, nil, nil);
        repeated &= probe->pointerCalls == i + 2;
    }
    check("repeated-add-post-remove-post", repeated);
    checkPayloads(probe);
    [probe release]; [center release];
}

static void observerLifetime(void) {
    NSNotificationCenter *center = [NSNotificationCenter new];
    // A failure may leave the observer alive beyond this function; keep the
    // diagnostic flag valid even in that case, rather than storing stack data.
    static BOOL deallocated;
    deallocated = NO;
    @autoreleasepool {
        LC32NotificationSelectorFixture *probe = [LC32NotificationSelectorFixture new];
        probe->deallocated = &deallocated;
        add(center, probe, @selector(misdeclared:), primaryName, nil);
        add(center, probe, @selector(normal:), primaryName, nil);
        [probe release];
    }
    check("selector-registration-does-not-retain-observer", deallocated);
    // Modern Foundation's weak observer registration must also remain safe
    // after the guest object's dealloc, without calling remove on a stale id.
    [center postNotificationName:primaryName object:nil];
    [center release];
}

#ifndef LC32_NOTIFICATION_NATIVE_CHECK
static void workerCallback(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    LC32NotificationSelectorFixture *probe = [LC32NotificationSelectorFixture new];
    NSString *name = @"LC32GuestSelectorWorkerNotification";
    expect(probe, name, nil, nil);
    const pthread_t postingThread = pthread_self();
    add(center, probe, @selector(misdeclared:), name, nil);
    add(center, probe, @selector(normal:), name, nil);
    const uint64_t helper = LC32Dlsym("LC32TestPostNotificationOnWorker", YES);
    BOOL finished = helper && LC32InvokeHostCRet32(helper, 0, 0, 0);
    check("foreign-worker-pointer-and-object-callbacks", finished &&
        probe->pointerCalls == 1 && probe->objectCalls == 1 &&
        !pthread_equal(probe->callbackThread, postingThread));
    [center removeObserver:probe name:name object:nil];
    finished = helper && LC32InvokeHostCRet32(helper, 0, 0, 0);
    check("foreign-worker-filtered-removal", finished &&
        probe->pointerCalls == 1 && probe->objectCalls == 1);
    add(center, probe, @selector(misdeclared:), name, nil);
    finished = helper && LC32InvokeHostCRet32(helper, 0, 0, 0);
    [center removeObserver:probe];
    finished &= helper && LC32InvokeHostCRet32(helper, 0, 0, 0);
    check("foreign-worker-reregister-and-broad-removal", finished &&
        probe->pointerCalls == 2 && probe->objectCalls == 1);
    checkPayloads(probe);
    [probe release];
}
#endif

int main(void) {
    @autoreleasepool {
        Class type = [LC32NotificationSelectorFixture class];
        Method pointerMethod = class_getInstanceMethod(type, @selector(misdeclared:));
        Method objectMethod = class_getInstanceMethod(type, @selector(normal:));
        IMP pointerIMP = method_getImplementation(pointerMethod), objectIMP = method_getImplementation(objectMethod);
        char *before = method_copyArgumentType(pointerMethod, 2);
        check("fixture-argument-is-int-pointer", before && !strcmp(before, "^i"));
        free(before);
        basicAndDuplicateRegistration();
        filtersAndIndependentCenters();
        selfRemovalAndRepeatedRegistration();
        observerLifetime();
#ifndef LC32_NOTIFICATION_NATIVE_CHECK
        workerCallback();
#endif
        char *afterPointer = method_copyArgumentType(pointerMethod, 2);
        char *afterObject = method_copyArgumentType(objectMethod, 2);
        check("original-methods-and-encodings-unchanged", afterPointer && afterObject &&
            !strcmp(afterPointer, "^i") && !strcmp(afterObject, "@") &&
            method_getImplementation(pointerMethod) == pointerIMP &&
            method_getImplementation(objectMethod) == objectIMP);
        free(afterPointer); free(afterObject);
    }
    printf("notification selector summary: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
