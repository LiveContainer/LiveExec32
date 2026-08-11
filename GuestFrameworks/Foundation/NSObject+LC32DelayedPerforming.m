#import <Foundation/Foundation+LC32.h>
#import "LC32FoundationBridge.h"

#import <objc/message.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

@interface LC32DelayedPerformRequest : NSObject {
@public
    id _target;
    id _object;
    SEL _selector;
    NSTimer *_timer;
    LC32DelayedPerformRequest *_nextPending;
}

- (instancetype)initWithTarget:(id)target
                       selector:(SEL)selector
                         object:(id)object;
- (void)lc32_fireDelayedPerform:(NSTimer *)timer;

@end

static pthread_mutex_t LC32DelayedPerformLock = PTHREAD_MUTEX_INITIALIZER;
static LC32DelayedPerformRequest *LC32PendingDelayedPerforms;
static pthread_once_t LC32DelayedTimerHostOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32DelayedTimerHostFunction;

static void LC32ResolveDelayedTimerHostFunction(void) {
    LC32DelayedTimerHostFunction = LC32Dlsym(
        "LC32_Foundation_CreateDelayedTimer", YES);
}

static void LC32RegisterDelayedPerform(
        LC32DelayedPerformRequest *request) {
    pthread_mutex_lock(&LC32DelayedPerformLock);
    request->_nextPending = LC32PendingDelayedPerforms;
    LC32PendingDelayedPerforms = request;
    pthread_mutex_unlock(&LC32DelayedPerformLock);
}

static BOOL LC32TakeDelayedPerform(LC32DelayedPerformRequest *request) {
    BOOL found = NO;
    pthread_mutex_lock(&LC32DelayedPerformLock);
    LC32DelayedPerformRequest **link = &LC32PendingDelayedPerforms;
    while(*link) {
        if(*link == request) {
            *link = request->_nextPending;
            request->_nextPending = nil;
            found = YES;
            break;
        }
        link = &(*link)->_nextPending;
    }
    pthread_mutex_unlock(&LC32DelayedPerformLock);
    return found;
}

static LC32DelayedPerformRequest *LC32TakeMatchingDelayedPerforms(
        id target, SEL selector, id object, BOOL matchSelectorAndObject) {
    LC32DelayedPerformRequest *matches = nil;
    pthread_mutex_lock(&LC32DelayedPerformLock);
    LC32DelayedPerformRequest **link = &LC32PendingDelayedPerforms;
    while(*link) {
        LC32DelayedPerformRequest *request = *link;
        const BOOL matchesTarget = request->_target == target;
        const BOOL matchesArguments = !matchSelectorAndObject ||
            (request->_selector == selector && request->_object == object);
        if(matchesTarget && matchesArguments) {
            *link = request->_nextPending;
            request->_nextPending = matches;
            matches = request;
        } else {
            link = &request->_nextPending;
        }
    }
    pthread_mutex_unlock(&LC32DelayedPerformLock);
    return matches;
}

static void LC32CancelDelayedPerforms(
        id target, SEL selector, id object, BOOL matchSelectorAndObject) {
    LC32DelayedPerformRequest *request = LC32TakeMatchingDelayedPerforms(
        target, selector, object, matchSelectorAndObject);
    while(request) {
        LC32DelayedPerformRequest *next = request->_nextPending;
        request->_nextPending = nil;
        [request->_timer invalidate];
        /* The pending list owns the request's original +1. */
        [request release];
        request = next;
    }
}

@implementation LC32DelayedPerformRequest

- (instancetype)initWithTarget:(id)target
                       selector:(SEL)selector
                         object:(id)object {
    self = [super init];
    if(self) {
        _target = [target retain];
        _selector = selector;
        _object = [object retain];
    }
    return self;
}

- (void)dealloc {
    [_timer release];
    [_object release];
    [_target release];
    [super dealloc];
}

- (void)lc32_fireDelayedPerform:(NSTimer *)timer {
    (void)timer;
    if(!LC32TakeDelayedPerform(self)) return;

    /*
     * Passing the optional object is ABI-safe for zero-argument selectors and
     * matches NSObject's delayed-performing contract for one-argument ones.
     * In particular, @selector(release) must execute in the guest instead of
     * accidentally releasing only the native mirror.
     */
    ((void (*)(id, SEL, id))objc_msgSend)(
        _target, _selector, _object);

    /* Drop the +1 transferred to the pending list at construction. */
    [self release];
}

@end

static NSTimer *LC32CreateDelayedPerformTimer(
        id target, SEL selector, id object, NSTimeInterval delay) {
    LC32DelayedPerformRequest *request =
        [[LC32DelayedPerformRequest alloc]
            initWithTarget:target selector:selector object:object];
    pthread_once(&LC32DelayedTimerHostOnce,
        LC32ResolveDelayedTimerHostFunction);
    if(!LC32DelayedTimerHostFunction) {
        [request release];
        return nil;
    }

    LC32FoundationDelayedTimerCall call = {
        .version = LC32FoundationDelayedTimerABIVersion,
        .slotCount = LC32FoundationDelayedTimerSlotCount,
    };
    call.slots[LC32FoundationDelayedTimerTargetSlot] = request.host_self;
    call.slots[LC32FoundationDelayedTimerSelectorSlot] =
        LC32GetHostSelector(@selector(lc32_fireDelayedPerform:));
    memcpy(&call.slots[LC32FoundationDelayedTimerIntervalSlot],
        &delay, sizeof(delay));
    NSTimer *timer = (NSTimer *)(uintptr_t)LC32InvokeHostCRet32(
        LC32DelayedTimerHostFunction, (uint32_t)(uintptr_t)&call);
    if(!timer) {
        [request release];
        return nil;
    }
    request->_timer = [timer retain];

    /* Transfer request's original +1 to the pending list before arming it. */
    LC32RegisterDelayedPerform(request);
    return timer;
}

@implementation NSObject (LC32DelayedPerforming)

- (void)performSelector:(SEL)selector
             withObject:(id)object
             afterDelay:(NSTimeInterval)delay {
    if(!selector) return;
    NSTimer *timer = LC32CreateDelayedPerformTimer(
        self, selector, object, delay);
    if(!timer) return;
    [[NSRunLoop currentRunLoop] addTimer:timer
                                forMode:NSDefaultRunLoopMode];
}

- (void)performSelector:(SEL)selector
             withObject:(id)object
             afterDelay:(NSTimeInterval)delay
                inModes:(NSArray<NSRunLoopMode> *)modes {
    if(!selector || modes.count == 0) return;

    NSTimer *timer = LC32CreateDelayedPerformTimer(
        self, selector, object, delay);
    if(!timer) return;
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    for(NSRunLoopMode mode in modes) {
        [runLoop addTimer:timer forMode:mode];
    }
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)target {
    LC32CancelDelayedPerforms(target, NULL, nil, NO);
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)target
                                       selector:(SEL)selector
                                         object:(id)object {
    LC32CancelDelayedPerforms(target, selector, object, YES);
}

@end
