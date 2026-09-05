#import <Foundation/Foundation.h>
#import <Block.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <pthread.h>

#include <stdio.h>

extern uint64_t LC32Dlsym(const char *name, BOOL isFunction);
extern uint32_t LC32InvokeHostCRet32(uint64_t hostPointer, ...);

static NSUInteger operationProxyDeallocCount;
static char operationProxyProbeKey;

/*
 * LLVM GCC 4.2 notification callbacks can advertise the 2010 block ABI while
 * leaving the descriptor's signature slot null.  Preserve that exact
 * 24-byte stack-block shape instead of clearing the signature flag on a
 * modern compiler-generated descriptor.
 */
struct LC32LegacyNotificationBlockDescriptor {
    uintptr_t reserved;
    uintptr_t size;
    const char *signature;
    const char *layout;
};

struct LC32LegacyNotificationProbe {
    BOOL invoked;
    NSString *expectedName;
};

struct LC32LegacyNotificationBlockLiteral {
    void *isa;
    uint32_t flags;
    uint32_t reserved;
    void (*invoke)(struct LC32LegacyNotificationBlockLiteral *,
                   NSNotification *);
    struct LC32LegacyNotificationBlockDescriptor *descriptor;
    struct LC32LegacyNotificationProbe *probe;
};

_Static_assert(sizeof(struct LC32LegacyNotificationBlockDescriptor) == 16,
               "legacy ARM32 block descriptor layout changed");
_Static_assert(sizeof(struct LC32LegacyNotificationBlockLiteral) == 24,
               "legacy ARM32 stack block layout changed");

static void LC32InvokeLegacyNotificationBlock(
        struct LC32LegacyNotificationBlockLiteral *block,
        NSNotification *notification) {
    block->probe->invoked =
        [notification.name isEqualToString:block->probe->expectedName];
}

static void LC32IgnoreLegacyNotificationBlock(
        struct LC32LegacyNotificationBlockLiteral *block,
        NSNotification *notification) {
    (void)block;
    (void)notification;
}

static struct LC32LegacyNotificationBlockDescriptor
    LC32LegacyNotificationDescriptor = {
        0,
        sizeof(struct LC32LegacyNotificationBlockLiteral),
        NULL,
        NULL,
    };

__attribute__((noinline))
static id LC32AddLegacyNotificationObserver(
        NSNotificationCenter *center, NSString *name,
        struct LC32LegacyNotificationProbe *probe) {
    struct LC32LegacyNotificationBlockLiteral literal = {
        .isa = _NSConcreteStackBlock,
        .flags = 1U << 30,
        .reserved = 0,
        .invoke = LC32InvokeLegacyNotificationBlock,
        .descriptor = &LC32LegacyNotificationDescriptor,
        .probe = probe,
    };
    void (^block)(NSNotification *) =
        (void (^)(NSNotification *))&literal;
    id observer = [center addObserverForName:name
                                      object:nil
                                       queue:nil
                                  usingBlock:block];
    /* A retained wrapper must own its heap copy before registration returns. */
    ((volatile struct LC32LegacyNotificationBlockLiteral *)&literal)->invoke =
        LC32IgnoreLegacyNotificationBlock;
    return observer;
}

static BOOL LC32RunTypedWorkerBlockProbe(id block, uint32_t kind) {
    static uint64_t probe;
    if(!probe) {
        probe = LC32Dlsym(
            "LC32TestInvokeTypedGuestBlockOnWorker", YES);
    }
    return probe && LC32InvokeHostCRet32(
        probe, (uint32_t)(uintptr_t)block, kind, 0) != 0;
}

/*
 * YTBaseService coalesces identical requests by copying each completion into
 * a native NSMutableArray, then enumerating that array after the request
 * finishes.  Keep this helper out of line so consecutive calls reuse the same
 * guest stack address for two block literals with different captures.  A
 * mirror cache keyed only by the guest block address would then alias the
 * second callback to the first one.
 */
__attribute__((noinline))
static uintptr_t LC32AppendCoalescedCallback(
        NSMutableArray *callbacks, NSMutableArray *results,
        NSUInteger marker) {
    void (^callback)(void) = ^{
        [results addObject:@(marker)];
    };
    const uintptr_t stackAddress = (uintptr_t)callback;
    [callbacks addObject:callback];
    return stackAddress;
}

/*
 * YouTube's request coalescing has one more ownership layer than the simple
 * case above: the object stored in the pending-request array is an outer
 * completion block which captures the caller's response block.  Both block
 * literals are deliberately created in this out-of-line helper so separate
 * requests can reuse their stack slots.  The bridged NSMutableArray must keep
 * independent heap copies, including each completion's captured response,
 * after this helper's autorelease pool has gone away.
 */
__attribute__((noinline))
static uintptr_t LC32AppendNestedCoalescedCallback(
        NSMutableArray *callbacks, NSMutableArray *results,
        NSUInteger marker, uintptr_t *innerStackAddress) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    void (^response)(void) = ^{
        [results addObject:[NSNumber numberWithUnsignedInteger:marker]];
    };
    void (^completion)(void) = ^{
        response();
    };
    *innerStackAddress = (uintptr_t)response;
    const uintptr_t outerStackAddress = (uintptr_t)completion;
    [callbacks addObject:completion];
    [pool drain];
    return outerStackAddress;
}

/*
 * Model YTBaseService's pending-request fanout more closely than the generic
 * nested probe above.  Each request contributes an outer completion to one
 * native NSMutableArray.  That completion captures a request-specific error
 * fallback, and both helpers deliberately reuse the same guest stack slots.
 * After the native array has retained the outer wrappers, the original guest
 * pool disappears; reverse mapping the two native wrappers must still yield
 * two independent guest copies whose fallback captures also remain distinct.
 */
__attribute__((noinline))
static uintptr_t LC32AppendRequestFallback(
        NSMutableArray *pendingCallbacks, NSMutableArray *fallbackResults,
        NSUInteger marker, uintptr_t *fallbackStackAddress) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    void (^fallback)(NSError *) = ^(NSError *error) {
        if(error) {
            [fallbackResults addObject:
                [NSNumber numberWithUnsignedInteger:marker]];
        }
    };
    void (^completion)(id, NSError *) = ^(id response, NSError *error) {
        if(!response && error) fallback(error);
    };
    *fallbackStackAddress = (uintptr_t)fallback;
    const uintptr_t completionStackAddress = (uintptr_t)completion;
    [pendingCallbacks addObject:completion];
    [pool drain];
    return completionStackAddress;
}

/*
 * This models the full generic shape used before YTBaseService reaches its
 * pending-request array.  A setup block first crosses the bridge through
 * +[NSBlockOperation blockOperationWithBlock:].  When that operation runs,
 * it creates and stores an outer pending completion which itself retains the
 * request-specific response block.  Calling this helper twice forces both
 * request trees to originate from the same guest stack slots.
 */
__attribute__((noinline))
static uintptr_t LC32AppendCoalescingOperation(
        NSMutableArray *operations, NSMutableArray *pendingCallbacks,
        NSMutableArray *results, NSMutableArray *pendingStackAddresses,
        NSMutableArray *mainThreadResults, NSUInteger marker,
        pthread_t expectedMainThread, uintptr_t *responseStackAddress) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    void (^response)(void) = ^{
        [results addObject:[NSNumber numberWithUnsignedInteger:marker]];
    };
    void (^setup)(void) = ^{
        void (^pendingCompletion)(void) = ^{
            response();
        };
        [pendingStackAddresses addObject:[NSNumber numberWithUnsignedLong:
            (unsigned long)(uintptr_t)pendingCompletion]];
        [mainThreadResults addObject:[NSNumber numberWithBool:
            pthread_equal(pthread_self(), expectedMainThread)]];
        [pendingCallbacks addObject:pendingCompletion];
    };
    *responseStackAddress = (uintptr_t)response;
    const uintptr_t setupStackAddress = (uintptr_t)setup;
    NSBlockOperation *operation =
        [NSBlockOperation blockOperationWithBlock:setup];
    [operations addObject:operation];
    [pool drain];
    return setupStackAddress;
}

@interface LC32OperationProxyLifetimeProbe : NSObject
@end

@implementation LC32OperationProxyLifetimeProbe
- (void)dealloc {
    operationProxyDeallocCount++;
    [super dealloc];
}
@end

@interface LC32BlockObjectArgumentReceiver : NSObject {
    NSMutableArray *_results;
    uintptr_t _receivedBlockAddress;
}

- (instancetype)initWithResults:(NSMutableArray *)results;
- (void)invokeBlockPassedAsObject:(id)blockObject;
- (uintptr_t)receivedBlockAddress;

@end

@implementation LC32BlockObjectArgumentReceiver

- (instancetype)initWithResults:(NSMutableArray *)results {
    self = [super init];
    if(self) _results = [results retain];
    return self;
}

- (void)invokeBlockPassedAsObject:(id)blockObject {
    _receivedBlockAddress = (uintptr_t)blockObject;
    ((void (^)(void))blockObject)();
}

- (uintptr_t)receivedBlockAddress {
    return _receivedBlockAddress;
}

- (void)dealloc {
    [_results release];
    [super dealloc];
}

@end

/*
 * YTBaseService stores completion arrays in a native NSMutableDictionary,
 * keyed by a guest PendingRequestKey.  Foundation consequently calls the
 * guest key's NSCopying/hash/equality methods through its host mirror.  Keep
 * this key intentionally immutable and use the same equality rule as the
 * application: equal request values plus identical authorizer objects.
 */
@interface LC32PendingRequestKeyProbe : NSObject <NSCopying> {
    NSString *_request;
    id _authorizer;
}

- (instancetype)initWithRequest:(NSString *)request authorizer:(id)authorizer;

@end

@implementation LC32PendingRequestKeyProbe

- (instancetype)initWithRequest:(NSString *)request authorizer:(id)authorizer {
    self = [super init];
    if(self) {
        _request = [request copy];
        _authorizer = [authorizer retain];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone __attribute__((unused)) {
    return [self retain];
}

- (NSUInteger)hash {
    return [_request hash] * 37u + (NSUInteger)(uintptr_t)_authorizer;
}

- (BOOL)isEqual:(id)object {
    if(self == object) return YES;
    if(![object isMemberOfClass:[LC32PendingRequestKeyProbe class]]) {
        return NO;
    }
    LC32PendingRequestKeyProbe *other = object;
    return [_request isEqual:other->_request] &&
        _authorizer == other->_authorizer;
}

- (void)dealloc {
    [_request release];
    [_authorizer release];
    [super dealloc];
}

@end

int main(void) {
    @autoreleasepool {
        pthread_t mainGuestThread = pthread_self();
        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];
        NSString *name = @"LC32GuestBlockBridgeTestNotification";
        __block BOOL invoked = NO;

        id observer = [center addObserverForName:name
                                          object:nil
                                           queue:nil
                                      usingBlock:^(NSNotification *note) {
            invoked = [note.name isEqualToString:name];
        }];
        [center postNotificationName:name object:nil];
        if(observer) [center removeObserver:observer];

        printf("guest-block-object-argument: %s\n",
               invoked ? "PASS" : "FAIL");

        struct LC32LegacyNotificationProbe legacyNotificationProbe = {
            .invoked = NO,
            .expectedName = name,
        };
        id legacyObserver = LC32AddLegacyNotificationObserver(
            center, name, &legacyNotificationProbe);
        [center postNotificationName:name object:nil];
        if(legacyObserver) [center removeObserver:legacyObserver];
        printf("guest-block-notification-null-signature: %s\n",
               legacyNotificationProbe.invoked ? "PASS" : "FAIL");

        NSOperationQueue *notificationQueue =
            [NSOperationQueue new];
        notificationQueue.maxConcurrentOperationCount = 1;
        __block BOOL queuedNotificationInvoked = NO;
        __block pthread_t notificationGuestThread = (pthread_t)0;
        id queuedObserver = [center addObserverForName:name
                                                object:nil
                                                 queue:notificationQueue
                                            usingBlock:^(NSNotification *note) {
            notificationGuestThread = pthread_self();
            queuedNotificationInvoked =
                [note.name isEqualToString:name];
        }];
        [center postNotificationName:name object:nil];
        [notificationQueue waitUntilAllOperationsAreFinished];
        if(queuedObserver) [center removeObserver:queuedObserver];
        const BOOL queuedNotificationPassed =
            queuedNotificationInvoked &&
            !pthread_equal(notificationGuestThread, mainGuestThread);
        printf("guest-block-queued-object-argument: %s\n",
               queuedNotificationPassed ? "PASS" : "FAIL");
        [notificationQueue release];

        NSMutableArray *coalescedCallbacks = [NSMutableArray array];
        NSMutableArray *coalescedResults = [NSMutableArray array];
        const uintptr_t firstStackAddress = LC32AppendCoalescedCallback(
            coalescedCallbacks, coalescedResults, 17);
        const uintptr_t secondStackAddress = LC32AppendCoalescedCallback(
            coalescedCallbacks, coalescedResults, 29);
        const BOOL coalescedStackReused =
            firstStackAddress == secondStackAddress;

        id firstCoalescedCallback = [coalescedCallbacks objectAtIndex:0];
        id secondCoalescedCallback = [coalescedCallbacks objectAtIndex:1];
        const BOOL coalescedCopiesDistinct =
            firstCoalescedCallback != secondCoalescedCallback;
        [coalescedCallbacks enumerateObjectsUsingBlock:
            ^(id callback, NSUInteger index __attribute__((unused)),
              BOOL *stop __attribute__((unused))) {
                ((void (^)(void))callback)();
            }];
        const BOOL coalescedFanoutPassed =
            [coalescedResults isEqual:@[@17, @29]];
        printf("guest-block-coalesced-array-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               coalescedStackReused ? "PASS" : "FAIL",
               (unsigned long)firstStackAddress,
               (unsigned long)secondStackAddress);
        printf("guest-block-coalesced-array-distinct-copies: %s\n",
               coalescedCopiesDistinct ? "PASS" : "FAIL");
        printf("guest-block-coalesced-array-fanout: %s\n",
               coalescedFanoutPassed ? "PASS" : "FAIL");

        NSMutableArray *nestedCallbacks =
            [[NSMutableArray alloc] init];
        NSMutableArray *nestedResults =
            [[NSMutableArray alloc] init];
        uintptr_t firstInnerStackAddress = 0;
        uintptr_t secondInnerStackAddress = 0;
        const uintptr_t firstOuterStackAddress =
            LC32AppendNestedCoalescedCallback(
                nestedCallbacks, nestedResults, 41,
                &firstInnerStackAddress);
        const uintptr_t secondOuterStackAddress =
            LC32AppendNestedCoalescedCallback(
                nestedCallbacks, nestedResults, 73,
                &secondInnerStackAddress);
        const BOOL nestedOuterStackReused =
            firstOuterStackAddress == secondOuterStackAddress;
        const BOOL nestedInnerStackReused =
            firstInnerStackAddress == secondInnerStackAddress;
        id firstNestedCallback = [nestedCallbacks objectAtIndex:0];
        id secondNestedCallback = [nestedCallbacks objectAtIndex:1];
        const BOOL nestedCopiesDistinct =
            firstNestedCallback != secondNestedCallback;

        /* Encourage reuse of objects released by the helper-local pools
         * before either retained completion is invoked. */
        for(NSUInteger iteration = 0; iteration < 32; iteration++) {
            NSAutoreleasePool *churnPool = [NSAutoreleasePool new];
            for(NSUInteger value = 0; value < 32; value++) {
                [NSString stringWithFormat:@"lc32-%lu-%lu",
                    (unsigned long)iteration, (unsigned long)value];
            }
            [churnPool drain];
        }

        [nestedCallbacks enumerateObjectsUsingBlock:
            ^(id completion, NSUInteger index __attribute__((unused)),
              BOOL *stop __attribute__((unused))) {
                ((void (^)(void))completion)();
            }];
        const BOOL nestedFanoutPassed =
            [nestedResults isEqual:@[@41, @73]];
        printf("guest-block-nested-coalesced-outer-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               nestedOuterStackReused ? "PASS" : "FAIL",
               (unsigned long)firstOuterStackAddress,
               (unsigned long)secondOuterStackAddress);
        printf("guest-block-nested-coalesced-inner-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               nestedInnerStackReused ? "PASS" : "FAIL",
               (unsigned long)firstInnerStackAddress,
               (unsigned long)secondInnerStackAddress);
        printf("guest-block-nested-coalesced-distinct-copies: %s\n",
               nestedCopiesDistinct ? "PASS" : "FAIL");
        printf("guest-block-nested-coalesced-fanout: %s\n",
               nestedFanoutPassed ? "PASS" : "FAIL");
        [nestedCallbacks release];
        [nestedResults release];

        NSMutableArray *requestFallbackCallbacks =
            [[NSMutableArray alloc] init];
        NSMutableArray *requestFallbackResults =
            [[NSMutableArray alloc] init];
        uintptr_t firstFallbackStackAddress = 0;
        uintptr_t secondFallbackStackAddress = 0;
        const uintptr_t firstRequestCompletionStackAddress =
            LC32AppendRequestFallback(
                requestFallbackCallbacks, requestFallbackResults, 401,
                &firstFallbackStackAddress);
        const uintptr_t secondRequestCompletionStackAddress =
            LC32AppendRequestFallback(
                requestFallbackCallbacks, requestFallbackResults, 509,
                &secondFallbackStackAddress);
        const BOOL requestCompletionStackReused =
            firstRequestCompletionStackAddress ==
                secondRequestCompletionStackAddress;
        const BOOL requestFallbackStackReused =
            firstFallbackStackAddress == secondFallbackStackAddress;

        id firstRequestCompletion =
            [requestFallbackCallbacks objectAtIndex:0];
        id secondRequestCompletion =
            [requestFallbackCallbacks objectAtIndex:1];
        const BOOL requestCompletionCopiesDistinct =
            firstRequestCompletion != secondRequestCompletion;
        const BOOL requestCompletionReverseMapsStable =
            firstRequestCompletion ==
                [requestFallbackCallbacks objectAtIndex:0] &&
            secondRequestCompletion ==
                [requestFallbackCallbacks objectAtIndex:1];

        NSAutoreleasePool *requestFallbackChurnPool =
            [NSAutoreleasePool new];
        for(NSUInteger value = 0; value < 256; value++) {
            [NSString stringWithFormat:@"lc32-request-fallback-%lu",
                (unsigned long)value];
        }
        [requestFallbackChurnPool drain];

        NSError *requestError = [NSError errorWithDomain:
            @"LC32RequestFallbackRegression" code:404 userInfo:nil];
        [requestFallbackCallbacks enumerateObjectsUsingBlock:
            ^(id completion, NSUInteger index __attribute__((unused)),
              BOOL *stop __attribute__((unused))) {
                ((void (^)(id, NSError *))completion)(nil, requestError);
            }];
        const BOOL requestFallbackFanoutPassed =
            [requestFallbackResults isEqual:@[@401, @509]];
        printf("guest-block-request-fallback-completion-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               requestCompletionStackReused ? "PASS" : "FAIL",
               (unsigned long)firstRequestCompletionStackAddress,
               (unsigned long)secondRequestCompletionStackAddress);
        printf("guest-block-request-fallback-leaf-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               requestFallbackStackReused ? "PASS" : "FAIL",
               (unsigned long)firstFallbackStackAddress,
               (unsigned long)secondFallbackStackAddress);
        printf("guest-block-request-fallback-distinct-reverse-maps: %s "
               "(0x%lx, 0x%lx)\n",
               requestCompletionCopiesDistinct ? "PASS" : "FAIL",
               (unsigned long)(uintptr_t)firstRequestCompletion,
               (unsigned long)(uintptr_t)secondRequestCompletion);
        printf("guest-block-request-fallback-stable-reverse-maps: %s\n",
               requestCompletionReverseMapsStable ? "PASS" : "FAIL");
        printf("guest-block-request-fallback-error-fanout: %s\n",
               requestFallbackFanoutPassed ? "PASS" : "FAIL");
        [requestFallbackCallbacks release];
        [requestFallbackResults release];

        NSObject *sharedAuthorizer = [NSObject new];
        NSObject *differentAuthorizer = [NSObject new];
        NSString *firstRequest = [[NSString alloc]
            initWithFormat:@"https://example.invalid/watch?v=%d", 17];
        NSString *equalRequest = [[NSString alloc]
            initWithFormat:@"https://example.invalid/watch?v=%d", 17];
        LC32PendingRequestKeyProbe *firstPendingKey =
            [[LC32PendingRequestKeyProbe alloc]
                initWithRequest:firstRequest authorizer:sharedAuthorizer];
        LC32PendingRequestKeyProbe *equalPendingKey =
            [[LC32PendingRequestKeyProbe alloc]
                initWithRequest:equalRequest authorizer:sharedAuthorizer];
        LC32PendingRequestKeyProbe *differentPendingKey =
            [[LC32PendingRequestKeyProbe alloc]
                initWithRequest:equalRequest authorizer:differentAuthorizer];
        NSMutableDictionary *pendingRequests =
            [[NSMutableDictionary alloc] init];
        NSMutableArray *pendingCompletions =
            [[NSMutableArray alloc] init];
        [pendingRequests setObject:pendingCompletions
                            forKey:firstPendingKey];

        /* The native dictionary owns its copied host mirror from here on. */
        [firstPendingKey release];
        firstPendingKey = nil;
        NSMutableArray *coalescedPendingCompletions =
            [pendingRequests objectForKey:equalPendingKey];
        NSMutableArray *wrongAuthorizerCompletions =
            [pendingRequests objectForKey:differentPendingKey];
        NSMutableArray *pendingKeyResults =
            [[NSMutableArray alloc] init];
        [coalescedPendingCompletions addObject:^{
            [pendingKeyResults addObject:@613];
        }];
        ((void (^)(void))[coalescedPendingCompletions
            objectAtIndex:0])();
        const BOOL pendingKeyCoalescingPassed =
            coalescedPendingCompletions == pendingCompletions &&
            wrongAuthorizerCompletions == nil &&
            [pendingKeyResults isEqual:@[@613]];
        printf("guest-pending-key-native-dictionary-coalescing: %s\n",
               pendingKeyCoalescingPassed ? "PASS" : "FAIL");

        [pendingKeyResults release];
        [pendingRequests release];
        [pendingCompletions release];
        [equalPendingKey release];
        [differentPendingKey release];
        [firstRequest release];
        [equalRequest release];
        [sharedAuthorizer release];
        [differentAuthorizer release];

        NSMutableArray *coalescingOperations =
            [[NSMutableArray alloc] init];
        NSMutableArray *operationPendingCallbacks =
            [[NSMutableArray alloc] init];
        NSMutableArray *operationResults =
            [[NSMutableArray alloc] init];
        NSMutableArray *operationPendingStackAddresses =
            [[NSMutableArray alloc] init];
        NSMutableArray *operationMainThreadResults =
            [[NSMutableArray alloc] init];
        uintptr_t firstOperationResponseAddress = 0;
        uintptr_t secondOperationResponseAddress = 0;
        const uintptr_t firstSetupStackAddress =
            LC32AppendCoalescingOperation(
                coalescingOperations, operationPendingCallbacks,
                operationResults, operationPendingStackAddresses,
                operationMainThreadResults, 101, mainGuestThread,
                &firstOperationResponseAddress);
        const uintptr_t secondSetupStackAddress =
            LC32AppendCoalescingOperation(
                coalescingOperations, operationPendingCallbacks,
                operationResults, operationPendingStackAddresses,
                operationMainThreadResults, 203, mainGuestThread,
                &secondOperationResponseAddress);
        const BOOL operationSetupStackReused =
            firstSetupStackAddress == secondSetupStackAddress;
        const BOOL operationResponseStackReused =
            firstOperationResponseAddress == secondOperationResponseAddress;

        /* -start invokes an NSBlockOperation synchronously on this main guest
         * thread.  Release the operations afterwards so the pending array,
         * not an operation's setup block, is the only owner of each response
         * by the time fanout occurs. */
        [(NSOperation *)[coalescingOperations objectAtIndex:0] start];
        [(NSOperation *)[coalescingOperations objectAtIndex:1] start];
        const BOOL operationCallbacksRanOnMainThread =
            [operationMainThreadResults isEqual:@[@YES, @YES]];
        const BOOL operationPendingStackReused =
            operationPendingStackAddresses.count == 2 &&
            [[operationPendingStackAddresses objectAtIndex:0]
                isEqual:[operationPendingStackAddresses objectAtIndex:1]];
        const BOOL operationPendingCopiesDistinct =
            operationPendingCallbacks.count == 2 &&
            [operationPendingCallbacks objectAtIndex:0] !=
                [operationPendingCallbacks objectAtIndex:1];
        [coalescingOperations release];

        NSAutoreleasePool *operationChurnPool = [NSAutoreleasePool new];
        for(NSUInteger value = 0; value < 256; value++) {
            [NSString stringWithFormat:@"lc32-operation-%lu",
                (unsigned long)value];
        }
        [operationChurnPool drain];

        [operationPendingCallbacks enumerateObjectsUsingBlock:
            ^(id completion, NSUInteger index __attribute__((unused)),
              BOOL *stop __attribute__((unused))) {
                ((void (^)(void))completion)();
            }];
        const BOOL operationCoalescedFanoutPassed =
            [operationResults isEqual:@[@101, @203]];
        printf("guest-block-operation-coalescing-setup-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               operationSetupStackReused ? "PASS" : "FAIL",
               (unsigned long)firstSetupStackAddress,
               (unsigned long)secondSetupStackAddress);
        printf("guest-block-operation-coalescing-response-stack-reuse: %s "
               "(0x%lx, 0x%lx)\n",
               operationResponseStackReused ? "PASS" : "FAIL",
               (unsigned long)firstOperationResponseAddress,
               (unsigned long)secondOperationResponseAddress);
        printf("guest-block-operation-coalescing-pending-stack-reuse: %s\n",
               operationPendingStackReused ? "PASS" : "FAIL");
        printf("guest-block-operation-coalescing-main-thread: %s\n",
               operationCallbacksRanOnMainThread ? "PASS" : "FAIL");
        printf("guest-block-operation-coalescing-distinct-copies: %s\n",
               operationPendingCopiesDistinct ? "PASS" : "FAIL");
        printf("guest-block-operation-coalescing-fanout: %s\n",
               operationCoalescedFanoutPassed ? "PASS" : "FAIL");
        [operationPendingCallbacks release];
        [operationResults release];
        [operationPendingStackAddresses release];
        [operationMainThreadResults release];

        /*
         * An old Objective-C helper may type a completion as plain id rather
         * than @?.  NSInvocation provides the exact ownership shape: convert
         * the guest stack block to a native object, retain that argument on
         * the host, drain the conversion pool, then pass it back through the
         * generic LC32HostToGuestArgument Objective-C method trampoline.
         */
        NSMutableArray *objectArgumentResults =
            [[NSMutableArray alloc] init];
        LC32BlockObjectArgumentReceiver *objectArgumentReceiver =
            [[LC32BlockObjectArgumentReceiver alloc]
                initWithResults:objectArgumentResults];
        SEL objectArgumentSelector =
            @selector(invokeBlockPassedAsObject:);
        NSMethodSignature *objectArgumentSignature =
            [objectArgumentReceiver
                methodSignatureForSelector:objectArgumentSelector];
        NSInvocation *objectArgumentInvocation =
            [[NSInvocation invocationWithMethodSignature:
                objectArgumentSignature] retain];
        objectArgumentInvocation.target = objectArgumentReceiver;
        objectArgumentInvocation.selector = objectArgumentSelector;

        NSAutoreleasePool *objectArgumentPool =
            [NSAutoreleasePool new];
        void (^objectArgumentBlock)(void) = ^{
            [objectArgumentResults addObject:@307];
        };
        const uintptr_t objectArgumentStackAddress =
            (uintptr_t)objectArgumentBlock;
        id objectArgument = objectArgumentBlock;
        [objectArgumentInvocation setArgument:&objectArgument atIndex:2];
        [objectArgumentInvocation retainArguments];
        [objectArgumentPool drain];

        NSAutoreleasePool *objectArgumentChurnPool =
            [NSAutoreleasePool new];
        for(NSUInteger value = 0; value < 128; value++) {
            [NSString stringWithFormat:@"lc32-block-object-%lu",
                (unsigned long)value];
        }
        [objectArgumentChurnPool drain];
        [objectArgumentInvocation invoke];
        const uintptr_t receivedObjectArgumentAddress =
            objectArgumentReceiver.receivedBlockAddress;
        const BOOL objectArgumentCopied =
            receivedObjectArgumentAddress != 0 &&
            receivedObjectArgumentAddress != objectArgumentStackAddress;
        const BOOL objectArgumentRoundTripPassed =
            [objectArgumentResults isEqual:@[@307]];
        printf("guest-block-id-parameter-host-retained-copy: %s "
               "(stack=0x%lx received=0x%lx)\n",
               objectArgumentCopied ? "PASS" : "FAIL",
               (unsigned long)objectArgumentStackAddress,
               (unsigned long)receivedObjectArgumentAddress);
        printf("guest-block-id-parameter-host-to-guest-roundtrip: %s\n",
               objectArgumentRoundTripPassed ? "PASS" : "FAIL");
        [objectArgumentInvocation release];
        [objectArgumentReceiver release];
        [objectArgumentResults release];

        /* Keep an ordinary +0 convenience result across the native pool
         * drain using an explicit guest retain.  The final release must also
         * destroy the guest proxy; otherwise its host pointer can outlive the
         * native object and become the zombie YouTube hit. */
        NSAutoreleasePool *returnPool = [NSAutoreleasePool new];
        __block BOOL operationInvoked = NO;
        __block BOOL completionInvoked = NO;
        __block pthread_t operationGuestThread = (pthread_t)0;
        __block pthread_t completionGuestThread = (pthread_t)0;
        NSBlockOperation *operation =
            [[NSBlockOperation blockOperationWithBlock:^{
                operationGuestThread = pthread_self();
                operationInvoked = YES;
            }] retain];
        LC32OperationProxyLifetimeProbe *probe =
            [LC32OperationProxyLifetimeProbe new];
        objc_setAssociatedObject(operation, &operationProxyProbeKey, probe,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [probe release];
        [returnPool drain];
        [operation setCompletionBlock:^{
            completionGuestThread = pthread_self();
            completionInvoked = YES;
        }];

        /* NSOperationQueue must invoke this native block on a host worker
         * which has no guest JIT TLS. The bridge serializes it through its
         * dedicated registered guest callback pthread while this main guest
         * thread waits, so dispatch_sync(main) would deadlock here. */
        __block pthread_t callbackGuestThread = (pthread_t)0;
        __block BOOL asyncOperationInvoked = NO;
        __block BOOL workerDispatchInvoked = NO;
        dispatch_semaphore_t workerDispatchSemaphore =
            dispatch_semaphore_create(0);
        NSBlockOperation *asyncOperation =
            [NSBlockOperation blockOperationWithBlock:^{
                callbackGuestThread = pthread_self();
                asyncOperationInvoked = YES;
                /*
                 * This callback runs on the registered native guest callback
                 * pthread while the main guest thread is still inside the
                 * deferred waitUntilAllOperationsAreFinished SVC. Queueing
                 * work here makes that worker request a cooperative libdispatch
                 * workqueue upcall and halt the main JIT. The deferred SVC
                 * consumes the transition first, so the next Run() must ignore
                 * the now-stale level-triggered Workqueue halt.
                 */
                dispatch_async(dispatch_get_global_queue(
                        DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    workerDispatchInvoked = YES;
                    dispatch_semaphore_signal(workerDispatchSemaphore);
                });
            }];
        NSOperationQueue *queue = [NSOperationQueue new];
        queue.maxConcurrentOperationCount = 2;
        [queue addOperation:operation];
        [queue addOperation:asyncOperation];
        [queue waitUntilAllOperationsAreFinished];
        BOOL operationReusePassed =
            operationInvoked && completionInvoked;
        printf("guest-block-operation-after-pool-drain: %s\n",
               operationReusePassed ? "PASS" : "FAIL");
        const BOOL asyncOperationPassed =
            asyncOperationInvoked &&
            !pthread_equal(callbackGuestThread, mainGuestThread) &&
            pthread_equal(callbackGuestThread, operationGuestThread) &&
            pthread_equal(callbackGuestThread, completionGuestThread);
        printf("guest-block-operation-queue-registered-worker: %s\n",
               asyncOperationPassed ? "PASS" : "FAIL");
        const long workerDispatchWait = dispatch_semaphore_wait(
            workerDispatchSemaphore,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        const BOOL workerDispatchPassed =
            workerDispatchWait == 0 && workerDispatchInvoked;
        printf("guest-block-worker-dispatch-async: %s\n",
               workerDispatchPassed ? "PASS" : "FAIL");
        if (workerDispatchWait == 0) {
            dispatch_release(workerDispatchSemaphore);
        }
        [queue release];
        [operation release];
        BOOL operationLifetimePassed = operationProxyDeallocCount == 1;
        printf("guest-block-operation-proxy-balanced: %s\n",
               operationLifetimePassed ? "PASS" : "FAIL");

        /* This is a guest Blocks-runtime ABI smoke test.  The two bridge
         * wrappers are exercised by application callbacks, not this direct
         * invocation. */
        __block BOOL twoObjectsInvoked = NO;
        void (^twoObjects)(id, id) = ^(id first, id second) {
            twoObjectsInvoked = [first isEqual:@"first"] &&
                [second isEqual:@"second"];
        };
        twoObjects(@"first", @"second");
        printf("guest-block-local-two-object-arguments: %s\n",
               twoObjectsInvoked ? "PASS" : "FAIL");

        /* These Foundation entry points invoke the guest block through the
         * native host. They cover scalar block results rather than merely
         * exercising the guest Blocks runtime locally. */
        NSArray *unorderedValues = @[@3, @1, @2];
        NSArray *orderedValues = [unorderedValues
            sortedArrayUsingComparator:^NSComparisonResult(
                    NSNumber *left, NSNumber *right) {
                return [left compare:right];
            }];
        const BOOL signedIntReturnPassed =
            [orderedValues isEqual:@[@1, @2, @3]];
        printf("guest-block-signed-int-return: %s\n",
               signedIntReturnPassed ? "PASS" : "FAIL");

        NSPredicate *predicate = [NSPredicate predicateWithBlock:
            ^BOOL(NSNumber *value,
                  NSDictionary *bindings __attribute__((unused))) {
                return value.integerValue == 42;
            }];
        const BOOL signedCharReturnPassed =
            [predicate evaluateWithObject:@42] &&
            ![predicate evaluateWithObject:@41];
        printf("guest-block-signed-char-return: %s\n",
               signedCharReturnPassed ? "PASS" : "FAIL");

        NSArray *searchValues = @[@10, @20, @30, @40];
        __block NSUInteger visitedCount = 0;
        const NSUInteger matchingIndex =
            [searchValues indexOfObjectPassingTest:
                ^BOOL(NSNumber *value, NSUInteger index, BOOL *stop) {
                    visitedCount++;
                    if(value.integerValue == 30) {
                        *stop = YES;
                        return YES;
                    }
                    return NO;
                }];
        const BOOL scalarPointerPassed =
            matchingIndex == 2 && visitedCount == 3;
        printf("guest-block-unsigned-and-char-pointer-arguments: %s\n",
               scalarPointerPassed ? "PASS" : "FAIL");

        NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:5];
        __block NSRange observedRange = NSMakeRange(NSNotFound, 0);
        [indexes enumerateRangesUsingBlock:
            ^(NSRange range, BOOL *stop) {
                observedRange = range;
                *stop = YES;
            }];
        const BOOL rangeArgumentPassed = NSEqualRanges(
            observedRange, NSMakeRange(5, 1));
        printf("guest-block-range-argument: %s\n",
               rangeArgumentPassed ? "PASS" : "FAIL");

        const BOOL workerScalarPassed = LC32RunTypedWorkerBlockProbe(
            ^int32_t(id value, uint64_t marker, BOOL *stop) {
                if([value isEqual:@"worker"] &&
                   marker == UINT64_C(0x1122334455667788)) {
                    *stop = YES;
                    return -37;
                }
                return 0;
            }, 1);
        printf("guest-block-worker-scalar-pointer-result: %s\n",
               workerScalarPassed ? "PASS" : "FAIL");

        const BOOL workerFiveArgumentPassed =
            LC32RunTypedWorkerBlockProbe(
                ^id(id first, id second, id third, id fourth,
                    int64_t marker) {
                    if([second isEqual:@"second"] &&
                       [third isEqual:@"third"] &&
                       [fourth isEqual:@"fourth"] &&
                       marker == -INT64_C(0x102030405060708)) {
                        return first;
                    }
                    printf("guest-block-worker-five-inputs: second=%d "
                           "third=%d fourth=%d marker=0x%llx\n",
                           [second isEqual:@"second"],
                           [third isEqual:@"third"],
                           [fourth isEqual:@"fourth"],
                           (unsigned long long)marker);
                    return nil;
                }, 2);
        printf("guest-block-worker-five-arguments-object-result: %s\n",
               workerFiveArgumentPassed ? "PASS" : "FAIL");

        const BOOL workerUnsigned64Passed =
            LC32RunTypedWorkerBlockProbe(
                ^uint64_t(int64_t signedValue, uint64_t unsignedValue) {
                    if(signedValue != -INT64_C(0x102030405060708)) return 1;
                    if(unsignedValue != UINT64_C(0xfedcba9876543210)) return 2;
                    return UINT64_C(0x8877665544332211);
                }, 3);
        printf("guest-block-worker-signed-unsigned-64: %s\n",
               workerUnsigned64Passed ? "PASS" : "FAIL");

        const BOOL workerSigned64ResultPassed =
            LC32RunTypedWorkerBlockProbe(^int64_t(int32_t value) {
                return value == -19
                    ? -INT64_C(0x11223344556677)
                    : 0;
            }, 4);
        printf("guest-block-worker-signed-64-result: %s\n",
               workerSigned64ResultPassed ? "PASS" : "FAIL");

        return invoked && legacyNotificationProbe.invoked &&
            queuedNotificationPassed && operationReusePassed &&
            coalescedStackReused && coalescedCopiesDistinct &&
            coalescedFanoutPassed &&
            nestedOuterStackReused && nestedInnerStackReused &&
            nestedCopiesDistinct && nestedFanoutPassed &&
            requestCompletionStackReused && requestFallbackStackReused &&
            requestCompletionCopiesDistinct &&
            requestCompletionReverseMapsStable &&
            requestFallbackFanoutPassed &&
            pendingKeyCoalescingPassed &&
            operationSetupStackReused && operationResponseStackReused &&
            operationPendingStackReused &&
            operationCallbacksRanOnMainThread &&
            operationPendingCopiesDistinct &&
            operationCoalescedFanoutPassed &&
            objectArgumentCopied && objectArgumentRoundTripPassed &&
            asyncOperationPassed && workerDispatchPassed &&
            operationLifetimePassed &&
            twoObjectsInvoked && signedIntReturnPassed &&
            signedCharReturnPassed && scalarPointerPassed &&
            rangeArgumentPassed && workerScalarPassed &&
            workerFiveArgumentPassed && workerUnsigned64Passed &&
            workerSigned64ResultPassed ? 0 : 1;
    }
}
