#import <Foundation/Foundation+LC32.h>

#import <objc/message.h>
#import <objc/runtime.h>

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <time.h>

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t ready;
    pthread_t pthread;
    uint64_t hostThread;
    id target;
    id object;
    id block;
    id name;
    id threadDictionary;
    SEL selector;
    NSUInteger stackSize;
    double priority;
    NSQualityOfService qualityOfService;
    BOOL ownsTarget;
    BOOL selectorTakesObject;
    BOOL started;
    BOOL executing;
    BOOL finished;
    BOOL cancelled;
} LC32NSThreadState;

static pthread_once_t LC32NSThreadKeyOnce = PTHREAD_ONCE_INIT;
static pthread_key_t LC32NSThreadKey;
static pthread_t LC32NSThreadMainPthread;
static uint32_t LC32NSThreadHasCreatedWorker;
static pthread_mutex_t LC32NSThreadGlobalLock = PTHREAD_MUTEX_INITIALIZER;
static NSThread *LC32NSThreadMainObject;

static void LC32NSThreadKeyDestructor(void *opaque) {
    NSThread *thread = (NSThread *)opaque;
    if(!thread) return;
    pthread_mutex_lock(&LC32NSThreadGlobalLock);
    const BOOL isMainObject = thread == LC32NSThreadMainObject;
    pthread_mutex_unlock(&LC32NSThreadGlobalLock);
    if(!isMainObject) [thread release];
}

static void LC32NSThreadCreateKey(void) {
    pthread_key_create(&LC32NSThreadKey, LC32NSThreadKeyDestructor);
}

static LC32NSThreadState *LC32NSThreadCreateState(void) {
    LC32NSThreadState *state = calloc(1, sizeof(*state));
    if(!state) return NULL;
    pthread_mutex_init(&state->lock, NULL);
    pthread_cond_init(&state->ready, NULL);
    state->priority = 0.5;
    state->qualityOfService = NSQualityOfServiceDefault;
    return state;
}

static void LC32NSThreadDestroyState(LC32NSThreadState *state) {
    if(!state) return;
    const uint64_t hostThread = state->hostThread;
    if(state->ownsTarget) [state->target release];
    [state->object release];
    [state->block release];
    [state->name release];
    [state->threadDictionary release];
    if(hostThread) {
        static uint64_t releaseSelector __attribute__((aligned(8)));
        LC32InvokeHostSelector(hostThread,
            LC32CachedHostSelector(&releaseSelector,
                @selector(release), NO), (uint64_t)0);
    }
    pthread_cond_destroy(&state->ready);
    pthread_mutex_destroy(&state->lock);
    free(state);
}

static uint64_t LC32HostNSThread(SEL selector) {
    static uint64_t currentThreadSelector __attribute__((aligned(8)));
    static uint64_t mainThreadSelector __attribute__((aligned(8)));
    uint64_t *selectorCache = selector == @selector(mainThread)
        ? &mainThreadSelector : &currentThreadSelector;
    const uint64_t hostClass = [(id)objc_getClass("NSThread") host_self];
    const uint64_t hostThread = LC32InvokeHostSelector(
        hostClass, LC32CachedHostSelector(selectorCache, selector, NO),
        (uint64_t)0);
    if(hostThread) {
        static uint64_t retainSelector __attribute__((aligned(8)));
        LC32InvokeHostSelector(hostThread,
            LC32CachedHostSelector(&retainSelector,
                @selector(retain), NO), (uint64_t)0);
    }
    return hostThread;
}

static void LC32NSThreadPublishHostThread(
        LC32NSThreadState *state, uint64_t hostThread) {
    if(!state || !hostThread) return;
    pthread_mutex_lock(&state->lock);
    if(!state->hostThread) {
        state->hostThread = hostThread;
        hostThread = 0;
    }
    pthread_cond_broadcast(&state->ready);
    pthread_mutex_unlock(&state->lock);
    if(hostThread) {
        static uint64_t releaseSelector __attribute__((aligned(8)));
        LC32InvokeHostSelector(hostThread,
            LC32CachedHostSelector(&releaseSelector,
                @selector(release), NO), (uint64_t)0);
    }
}

static void LC32NSThreadSetFlag(LC32NSThreadState *state,
                                BOOL *flag,
                                BOOL value) {
    pthread_mutex_lock(&state->lock);
    *flag = value;
    pthread_mutex_unlock(&state->lock);
}

static BOOL LC32NSThreadGetFlag(LC32NSThreadState *state,
                                BOOL *flag) {
    if(!state) return NO;
    pthread_mutex_lock(&state->lock);
    const BOOL value = *flag;
    pthread_mutex_unlock(&state->lock);
    return value;
}

@interface NSThread () {
@public
    LC32NSThreadState *_lc32State;
}
@end

static NSThread *LC32NSThreadGetMainObject(void) {
    pthread_once(&LC32NSThreadKeyOnce, LC32NSThreadCreateKey);
    pthread_mutex_lock(&LC32NSThreadGlobalLock);
    if(!LC32NSThreadMainObject) {
        NSThread *thread = [[NSThread alloc] init];
        LC32NSThreadState *state = thread->_lc32State;
        pthread_mutex_lock(&state->lock);
        state->pthread = LC32NSThreadMainPthread;
        state->started = YES;
        state->executing = YES;
        pthread_mutex_unlock(&state->lock);
        LC32NSThreadPublishHostThread(
            state, LC32HostNSThread(@selector(mainThread)));
        LC32NSThreadMainObject = thread;
    }
    NSThread *thread = LC32NSThreadMainObject;
    pthread_mutex_unlock(&LC32NSThreadGlobalLock);
    if(pthread_equal(pthread_self(), LC32NSThreadMainPthread) &&
       !pthread_getspecific(LC32NSThreadKey)) {
        pthread_setspecific(LC32NSThreadKey, thread);
    }
    return thread;
}

static void LC32NSThreadFinish(void *opaque) {
    NSThread *thread = (NSThread *)opaque;
    LC32NSThreadState *state = thread->_lc32State;
    if(!state) return;
    pthread_mutex_lock(&state->lock);
    state->executing = NO;
    state->finished = YES;
    pthread_cond_broadcast(&state->ready);
    pthread_mutex_unlock(&state->lock);
    pthread_setspecific(LC32NSThreadKey, NULL);
    [thread release];
}

static void *LC32NSThreadEntry(void *opaque) {
    NSThread *thread = (NSThread *)opaque;
    LC32NSThreadState *state = thread->_lc32State;
    pthread_once(&LC32NSThreadKeyOnce, LC32NSThreadCreateKey);
    pthread_setspecific(LC32NSThreadKey, thread);
    LC32NSThreadPublishHostThread(
        state, LC32HostNSThread(@selector(currentThread)));
    LC32NSThreadSetFlag(state, &state->executing, YES);

    pthread_cleanup_push(LC32NSThreadFinish, thread);
    @autoreleasepool {
        if(state->block) {
            ((void (^)(void))state->block)();
        } else if(state->target && state->selector) {
            if(state->selectorTakesObject) {
                ((void (*)(id, SEL, id))objc_msgSend)(
                    state->target, state->selector, state->object);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(
                    state->target, state->selector);
            }
        }
    }
    pthread_cleanup_pop(1);
    return NULL;
}

static int LC32NSThreadStart(NSThread *thread,
                             LC32NSThreadState *state) {
    if(!thread || !state) return EINVAL;
    pthread_mutex_lock(&state->lock);
    if(state->started) {
        pthread_mutex_unlock(&state->lock);
        return EALREADY;
    }
    state->started = YES;
    const NSUInteger stackSize = state->stackSize;
    pthread_mutex_unlock(&state->lock);

    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    if(stackSize) {
        (void)pthread_attr_setstacksize(&attributes, stackSize);
    }
    [thread retain];
    const int result = pthread_create(
        &state->pthread, &attributes, LC32NSThreadEntry, thread);
    pthread_attr_destroy(&attributes);
    if(result != 0) {
        [thread release];
        pthread_mutex_lock(&state->lock);
        state->started = NO;
        pthread_cond_broadcast(&state->ready);
        pthread_mutex_unlock(&state->lock);
        return result;
    }
    __atomic_store_n(&LC32NSThreadHasCreatedWorker, 1, __ATOMIC_RELEASE);
    return 0;
}

static void LC32NSThreadInstallLocalReferenceCounting(void) {
    Class threadClass = objc_getClass("NSThread");
    Class objectClass = objc_getClass("NSObject");
    const SEL publicSelectors[] = {
        @selector(autorelease), @selector(release), @selector(retain),
        @selector(retainCount),
    };
    const SEL originalSelectors[] = {
        @selector(LC32_autorelease), @selector(LC32_release),
        @selector(LC32_retain), @selector(LC32_retainCount),
    };
    for(size_t index = 0;
            index < sizeof(publicSelectors) / sizeof(publicSelectors[0]);
            ++index) {
        Method method = class_getInstanceMethod(
            objectClass, originalSelectors[index]);
        if(method) {
            class_addMethod(threadClass, publicSelectors[index],
                method_getImplementation(method), method_getTypeEncoding(method));
        }
    }
}

__attribute__((constructor)) static void LC32NSThreadInitialize(void) {
    LC32NSThreadMainPthread = pthread_self();
    pthread_once(&LC32NSThreadKeyOnce, LC32NSThreadCreateKey);
    LC32NSThreadInstallLocalReferenceCounting();
}

@implementation NSThread

+ (void)detachNewThreadSelector:(SEL)selector
                       toTarget:(id)target
                     withObject:(id)object {
    if(!selector || !target) return;
    NSThread *thread = [[self alloc]
        initWithTarget:target selector:selector object:object];
    [thread start];
    [thread release];
}

+ (void)detachNewThreadWithBlock:(void (^)(void))block {
    if(!block) return;
    NSThread *thread = [[self alloc] initWithBlock:block];
    [thread start];
    [thread release];
}

+ (NSThread *)currentThread {
    pthread_once(&LC32NSThreadKeyOnce, LC32NSThreadCreateKey);
    if(pthread_equal(pthread_self(), LC32NSThreadMainPthread))
        return LC32NSThreadGetMainObject();
    NSThread *thread = pthread_getspecific(LC32NSThreadKey);
    if(thread) return thread;
    thread = [[self alloc] init];
    LC32NSThreadState *state = thread->_lc32State;
    pthread_mutex_lock(&state->lock);
    state->pthread = pthread_self();
    state->started = YES;
    state->executing = YES;
    pthread_mutex_unlock(&state->lock);
    LC32NSThreadPublishHostThread(
        state, LC32HostNSThread(@selector(currentThread)));
    pthread_setspecific(LC32NSThreadKey, thread);
    return thread;
}

+ (NSThread *)mainThread {
    return LC32NSThreadGetMainObject();
}

+ (BOOL)isMainThread {
    return pthread_equal(pthread_self(), LC32NSThreadMainPthread) != 0;
}

+ (BOOL)isMultiThreaded {
    return __atomic_load_n(
        &LC32NSThreadHasCreatedWorker, __ATOMIC_ACQUIRE) != 0;
}

+ (void)sleepUntilDate:(NSDate *)date {
    if(!date) return;
    [self sleepForTimeInterval:[date timeIntervalSinceNow]];
}

+ (void)sleepForTimeInterval:(NSTimeInterval)interval {
    if(interval <= 0) return;
    struct timespec requested = {
        .tv_sec = (time_t)interval,
        .tv_nsec = (long)((interval - (time_t)interval) * 1000000000.0),
    };
    while(nanosleep(&requested, &requested) != 0 && errno == EINTR) {}
}

+ (void)exit {
    pthread_exit(NULL);
}

+ (double)threadPriority {
    return [[self currentThread] threadPriority];
}

+ (BOOL)setThreadPriority:(double)priority {
    [[self currentThread] setThreadPriority:priority];
    return YES;
}

+ (NSArray<NSNumber *> *)callStackReturnAddresses {
    return nil;
}

+ (NSArray<NSString *> *)callStackSymbols {
    return nil;
}

- (instancetype)init {
    _lc32State = LC32NSThreadCreateState();
    if(!_lc32State) {
        [self release];
        return nil;
    }
    _lc32State->target = self;
    _lc32State->selector = @selector(main);
    _lc32State->selectorTakesObject = NO;
    return self;
}

- (instancetype)initWithTarget:(id)target
                       selector:(SEL)selector
                         object:(id)object {
    _lc32State = LC32NSThreadCreateState();
    if(!_lc32State || !target || !selector) {
        LC32NSThreadDestroyState(_lc32State);
        _lc32State = NULL;
        [self release];
        return nil;
    }
    _lc32State->target = [target retain];
    _lc32State->ownsTarget = YES;
    _lc32State->object = [object retain];
    _lc32State->selector = selector;
    _lc32State->selectorTakesObject = YES;
    return self;
}

- (instancetype)initWithBlock:(void (^)(void))block {
    _lc32State = LC32NSThreadCreateState();
    if(!_lc32State || !block) {
        LC32NSThreadDestroyState(_lc32State);
        _lc32State = NULL;
        [self release];
        return nil;
    }
    _lc32State->block = [block copy];
    return self;
}

- (void)start {
    (void)LC32NSThreadStart(self, _lc32State);
}

- (void)main {
}

- (void)cancel {
    if(_lc32State)
        LC32NSThreadSetFlag(_lc32State, &_lc32State->cancelled, YES);
}

- (BOOL)isCancelled {
    return LC32NSThreadGetFlag(_lc32State, &_lc32State->cancelled);
}

- (BOOL)isExecuting {
    return LC32NSThreadGetFlag(_lc32State, &_lc32State->executing);
}

- (BOOL)isFinished {
    return LC32NSThreadGetFlag(_lc32State, &_lc32State->finished);
}

- (BOOL)isMainThread {
    if(!_lc32State) return NO;
    pthread_mutex_lock(&_lc32State->lock);
    const BOOL result = _lc32State->started && pthread_equal(
        _lc32State->pthread, LC32NSThreadMainPthread);
    pthread_mutex_unlock(&_lc32State->lock);
    return result;
}

- (NSMutableDictionary *)threadDictionary {
    if(!_lc32State) return nil;
    pthread_mutex_lock(&_lc32State->lock);
    if(!_lc32State->threadDictionary)
        _lc32State->threadDictionary = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dictionary = _lc32State->threadDictionary;
    pthread_mutex_unlock(&_lc32State->lock);
    return dictionary;
}

- (NSString *)name {
    if(!_lc32State) return nil;
    pthread_mutex_lock(&_lc32State->lock);
    NSString *name = _lc32State->name;
    pthread_mutex_unlock(&_lc32State->lock);
    return name;
}

- (void)setName:(NSString *)name {
    if(!_lc32State) return;
    pthread_mutex_lock(&_lc32State->lock);
    if(_lc32State->name != name) {
        [_lc32State->name release];
        _lc32State->name = [name copy];
    }
    pthread_mutex_unlock(&_lc32State->lock);
}

- (NSUInteger)stackSize {
    if(!_lc32State) return 0;
    pthread_mutex_lock(&_lc32State->lock);
    const NSUInteger stackSize = _lc32State->stackSize;
    pthread_mutex_unlock(&_lc32State->lock);
    return stackSize;
}

- (void)setStackSize:(NSUInteger)stackSize {
    if(!_lc32State) return;
    pthread_mutex_lock(&_lc32State->lock);
    if(!_lc32State->started) _lc32State->stackSize = stackSize;
    pthread_mutex_unlock(&_lc32State->lock);
}

- (double)threadPriority {
    if(!_lc32State) return 0.5;
    pthread_mutex_lock(&_lc32State->lock);
    const double priority = _lc32State->priority;
    pthread_mutex_unlock(&_lc32State->lock);
    return priority;
}

- (void)setThreadPriority:(double)priority {
    if(!_lc32State) return;
    if(priority < 0.0) priority = 0.0;
    if(priority > 1.0) priority = 1.0;
    pthread_mutex_lock(&_lc32State->lock);
    _lc32State->priority = priority;
    pthread_mutex_unlock(&_lc32State->lock);
}

- (NSQualityOfService)qualityOfService {
    if(!_lc32State) return NSQualityOfServiceDefault;
    pthread_mutex_lock(&_lc32State->lock);
    const NSQualityOfService quality = _lc32State->qualityOfService;
    pthread_mutex_unlock(&_lc32State->lock);
    return quality;
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService {
    if(!_lc32State) return;
    pthread_mutex_lock(&_lc32State->lock);
    if(!_lc32State->started)
        _lc32State->qualityOfService = qualityOfService;
    pthread_mutex_unlock(&_lc32State->lock);
}

- (void)dealloc {
    LC32NSThreadDestroyState(_lc32State);
    _lc32State = NULL;
    [super dealloc];
}

@end

BOOL LC32NSThreadNativeModeEnabled(void) {
    const char *value = getenv("NATIVE_GUEST_THREADS");
    return value && value[0] && strcmp(value, "0") != 0;
}

BOOL LC32NSThreadIsCurrentThread(NSThread *thread) {
    return thread && thread == [NSThread currentThread];
}

uint64_t LC32NSThreadHostThread(NSThread *thread) {
    if(!thread || !thread->_lc32State) return 0;
    LC32NSThreadState *state = thread->_lc32State;
    pthread_mutex_lock(&state->lock);
    while(state->started && !state->finished && !state->hostThread) {
        pthread_cond_wait(&state->ready, &state->lock);
    }
    const uint64_t hostThread = state->hostThread;
    pthread_mutex_unlock(&state->lock);
    return hostThread;
}
