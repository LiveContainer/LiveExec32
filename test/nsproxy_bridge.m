#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#ifndef LC32_NSPROXY_NATIVE_CHECK
@interface NSObject (LC32ProxyBridgeTest)
- (uint64_t)host_self;
@end
extern id LC32HostToGuestObject(uint64_t object);
#endif

static unsigned checks, failures, deallocations;
static BOOL classCallback;
#ifndef LC32_NSPROXY_NATIVE_CHECK
static BOOL lateClassCallback;
#endif
static id valueCallback, echoCallback;
static int scalarCallback;
static unsigned forwardedCalls;
static unsigned directTargetDeallocations, fastFallbackCalls, fastDeallocations;
static int recordedValue;
static BOOL synthesizedArgumentsIntact = YES, synthesizedSelectorsIntact = YES;

static void check(const char *name, BOOL passed) {
    printf("nsproxy-bridge-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

@interface LC32ProxyBridgeFixture : NSProxy {
    id _value;
}
+ (NSString *)classMarker;
- (instancetype)initWithValue:(id)value;
- (id)echo:(id)value;
- (id)value;
- (int)addOne:(int)value;
@end

@implementation LC32ProxyBridgeFixture
+ (NSString *)classMarker { classCallback = YES; return @"proxy class callback"; }
- (instancetype)initWithValue:(id)value {
    _value = [value retain];
    return self;
}
- (id)echo:(id)value { echoCallback = value; return value; }
- (id)value { valueCallback = _value; return _value; }
- (int)addOne:(int)value { scalarCallback = value; return value + 1; }
- (void)dealloc {
    ++deallocations;
    [_value release];
    [super dealloc];
}
@end

@interface LC32ForwardingProxyBridgeFixture : LC32ProxyBridgeFixture
@end
@implementation LC32ForwardingProxyBridgeFixture
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_value methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    ++forwardedCalls;
    [invocation invokeWithTarget:_value];
}
@end

#ifndef LC32_NSPROXY_NATIVE_CHECK
static id lateClassMarker(id receiver, SEL selector) {
    lateClassCallback = receiver == (id)[LC32ProxyBridgeFixture class] &&
        selector == sel_registerName("lateClassMarker");
    return @"late proxy class callback";
}

static id invokeObject(uint64_t receiver, SEL selector, uint64_t argument) {
    const BOOL hasArgument = selector == @selector(echo:);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
        [NSMethodSignature signatureWithObjCTypes:hasArgument ? "@@:@" : "@@:"]];
    invocation.target = LC32HostToGuestObject(receiver);
    invocation.selector = selector;
    if(hasArgument) {
        id value = LC32HostToGuestObject(argument);
        [invocation setArgument:&value atIndex:2];
    }
    // NSInvocation invokes the native mirror as a real native caller. A direct
    // LC32InvokeHostSelector on a guest mirror intentionally calls its native
    // superclass instead, since that path implements guest framework shims.
    [invocation invoke];
    struct { uint32_t before; id value; uint32_t after; } result = {0x12345678, nil, 0x87654321};
    [invocation getReturnValue:&result.value];
    check("invocation-object-return-canaries", result.before == 0x12345678 && result.after == 0x87654321);
    return result.value;
}
#endif

@protocol LC32DirectForwardMessages
- (BOOL)isCurRootViewControllerOfClass:(Class)type;
- (id)forwardedObject:(id)value;
- (Class)forwardedClass:(Class)type;
- (SEL)forwardedSelector:(SEL)selector;
- (int8_t)forwardedSigned8:(int8_t)value;
- (int16_t)forwardedSigned16:(int16_t)value;
- (uint8_t)forwardedUnsigned8:(uint8_t)value;
- (uint16_t)forwardedUnsigned16:(uint16_t)value;
- (int32_t)forwardedSigned32:(int32_t)value;
- (uint32_t)forwardedUnsigned32:(uint32_t)value;
- (int64_t)forwardedSigned64:(int64_t)value bias:(int32_t)bias;
- (uint64_t)forwardedUnsigned64:(uint64_t)value;
- (float)forwardedFloat:(float)value;
- (double)forwardedDouble:(double)value;
- (_Bool)forwardedBoolFromDouble:(double)value;
- (double)forwardedMixed:(int32_t)prefix wide:(int64_t)wide ratio:(double)ratio tail:(float)tail;
- (int32_t)forwardedStack:(int32_t)a b:(int32_t)b c:(int32_t)c d:(int32_t)d e:(int32_t)e f:(int32_t)f;
- (void)forwardedRecord:(int32_t)value;
@end

@interface LC32DirectForwardTarget : NSObject <LC32DirectForwardMessages>
@end
@implementation LC32DirectForwardTarget
- (BOOL)isCurRootViewControllerOfClass:(Class)type { return type == [NSObject class]; }
- (id)forwardedObject:(id)value { return value; }
- (Class)forwardedClass:(Class)type { return type; }
- (SEL)forwardedSelector:(SEL)selector { return selector; }
- (int8_t)forwardedSigned8:(int8_t)value { return value + 1; }
- (int16_t)forwardedSigned16:(int16_t)value { return value + 1; }
- (uint8_t)forwardedUnsigned8:(uint8_t)value { return value + 13; }
- (uint16_t)forwardedUnsigned16:(uint16_t)value { return value - 7; }
- (int32_t)forwardedSigned32:(int32_t)value { return value - 13; }
- (uint32_t)forwardedUnsigned32:(uint32_t)value { return value ^ UINT32_C(0xa5a5a5a5); }
- (int64_t)forwardedSigned64:(int64_t)value bias:(int32_t)bias { return value + bias; }
- (uint64_t)forwardedUnsigned64:(uint64_t)value { return value ^ UINT64_C(0xfedcba9876543210); }
- (float)forwardedFloat:(float)value { return value * 1.5f; }
- (double)forwardedDouble:(double)value { return value * -2.5; }
- (_Bool)forwardedBoolFromDouble:(double)value { return value > 0; }
- (double)forwardedMixed:(int32_t)prefix wide:(int64_t)wide ratio:(double)ratio tail:(float)tail {
    return (double)wide + prefix + ratio + tail;
}
- (int32_t)forwardedStack:(int32_t)a b:(int32_t)b c:(int32_t)c d:(int32_t)d e:(int32_t)e f:(int32_t)f {
    return a + 10*b + 100*c + 1000*d + 10000*e + 100000*f;
}
- (void)forwardedRecord:(int32_t)value { recordedValue = value; }
- (void)dealloc { ++directTargetDeallocations; [super dealloc]; }
@end

@interface LC32FastForwardBridgeFixture : NSObject {
    id _target;
}
- (instancetype)initWithTarget:(id)target;
@end
@implementation LC32FastForwardBridgeFixture
- (instancetype)initWithTarget:(id)target {
    if((self = [super init])) _target = [target retain];
    return self;
}
- (id)forwardingTargetForSelector:(SEL)selector {
    (void)selector;
    return _target;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_target methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    ++fastFallbackCalls;
    [invocation invokeWithTarget:_target];
}
- (void)dealloc { ++fastDeallocations; [_target release]; [super dealloc]; }
@end

@protocol LC32SynthesizedForwardMessages
- (int32_t)synthesizedTriple:(int32_t)value;
- (id)synthesizedEcho:(id)value;
@end
@interface LC32SynthesizedForwardProxy : NSProxy
@end
@implementation LC32SynthesizedForwardProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(selector == @selector(synthesizedTriple:))
        return [NSMethodSignature signatureWithObjCTypes:"i@:i"];
    if(selector == @selector(synthesizedEcho:))
        return [NSMethodSignature signatureWithObjCTypes:"@@:@"];
    return nil;
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL selector = invocation.selector;
    if(selector == @selector(synthesizedTriple:)) {
        struct { uint32_t before; int32_t value; uint32_t after; } argument = {0x12345678, 0, 0x87654321};
        [invocation getArgument:&argument.value atIndex:2];
        synthesizedArgumentsIntact &= argument.before == 0x12345678 && argument.after == 0x87654321;
        int32_t result = argument.value * 3;
        [invocation setReturnValue:&result];
    } else if(selector == @selector(synthesizedEcho:)) {
        struct { uint32_t before; id value; uint32_t after; } argument = {0x12345678, nil, 0x87654321};
        [invocation getArgument:&argument.value atIndex:2];
        synthesizedArgumentsIntact &= argument.before == 0x12345678 && argument.after == 0x87654321;
        [invocation setReturnValue:&argument.value];
    } else {
        synthesizedSelectorsIntact = NO;
    }
}
@end

static void invocationLongEncodings(void) {
    // Foundation treats legacy Objective-C l/L encodings as four bytes even
    // when native C long is eight. Exercise the encoding, not sizeof(long).
    const char *types[] = {"l@:l", "L@:L"};
    for(unsigned i = 0; i < 2; ++i) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:types[i]]];
        uint32_t value = i ? UINT32_C(0xfedc1234) : (uint32_t)-123456789;
        struct { uint32_t before, value, after; } argument = {0x12345678, 0, 0x87654321};
        [invocation setArgument:&value atIndex:2];
        [invocation getArgument:&argument.value atIndex:2];
        check(i ? "invocation-L-argument-canaries" : "invocation-l-argument-canaries",
            argument.before == 0x12345678 && argument.after == 0x87654321 && argument.value == value);
        struct { uint32_t before, value, after; } result = {0x12345678, 0, 0x87654321};
        [invocation setReturnValue:&value];
        [invocation getReturnValue:&result.value];
        check(i ? "invocation-L-return-canaries" : "invocation-l-return-canaries",
            result.before == 0x12345678 && result.after == 0x87654321 && result.value == value);
    }
}

static void directForwarding(void) {
    unsigned before = forwardedCalls, previousDeallocations = deallocations;
    @autoreleasepool {
        LC32DirectForwardTarget *target = [LC32DirectForwardTarget new];
        id<LC32DirectForwardMessages> proxy = (id)[[LC32ForwardingProxyBridgeFixture alloc] initWithValue:target];
        id<LC32DirectForwardMessages> fast = (id)[[LC32FastForwardBridgeFixture alloc] initWithTarget:target];
        id value = [NSMutableString stringWithString:@"direct forwarding payload"];
        check("direct-selectors-are-not-concrete-proxy-methods",
            class_getInstanceMethod([LC32ForwardingProxyBridgeFixture class],
                @selector(isCurRootViewControllerOfClass:)) == NULL &&
            class_getInstanceMethod([LC32ForwardingProxyBridgeFixture class], @selector(forwardedMixed:wide:ratio:tail:)) == NULL);
        check("direct-game-bool-class-true", [proxy isCurRootViewControllerOfClass:[NSObject class]] == YES);
        check("direct-game-bool-class-false", [proxy isCurRootViewControllerOfClass:[NSArray class]] == NO);
        check("direct-object", [proxy forwardedObject:value] == value);
        check("direct-class", [proxy forwardedClass:[LC32DirectForwardTarget class]] == [LC32DirectForwardTarget class]);
        check("direct-selector", [proxy forwardedSelector:@selector(description)] == @selector(description));
        int signed8 = [proxy forwardedSigned8:-8];
        int signed16 = [proxy forwardedSigned16:-1235];
        unsigned unsigned8 = [proxy forwardedUnsigned8:0xe7];
        check("direct-signed8-sign-extended", signed8 == -7);
        check("direct-signed16-sign-extended", signed16 == -1234);
        check("direct-unsigned8-zero-extended", unsigned8 == 0xf4);
        check("direct-unsigned16", [proxy forwardedUnsigned16:0xf123] == 0xf11c);
        check("direct-signed32", [proxy forwardedSigned32:-123456789] == -123456802);
        check("direct-unsigned32", [proxy forwardedUnsigned32:UINT32_C(0x87654321)] == UINT32_C(0x22c0e684));
        check("direct-signed64", [proxy forwardedSigned64:-INT64_C(0x11223344556677) bias:-19] == -INT64_C(0x1122334455668a));
        check("direct-unsigned64", [proxy forwardedUnsigned64:UINT64_C(0x8123456789abcdef)] == UINT64_C(0x7fffffffffffffff));
        check("direct-float", [proxy forwardedFloat:-2.25f] == -3.375f);
        check("direct-double", [proxy forwardedDouble:3.125] == -7.8125);
        // _Bool encodes B, unlike the legacy BOOL/c. The native callback must
        // not treat stale r1 bits from the guest's scalar return as true.
        check("direct-bool-fp-true", [proxy forwardedBoolFromDouble:1.25]);
        check("direct-bool-fp-false", ![proxy forwardedBoolFromDouble:-1.25]);
        // On Apple ARMv7 the wide argument begins in r3 and continues on the
        // stack. Following double/float words must not acquire extra padding.
        const double mixed = (double)INT64_C(0x123456789) - 7 + 0.125 + 1.5;
        check("direct-mixed-r3-stack-split", [proxy forwardedMixed:-7 wide:INT64_C(0x123456789) ratio:0.125 tail:1.5f] == mixed);
        check("direct-stacked-integers", [proxy forwardedStack:1 b:2 c:3 d:4 e:5 f:6] == 654321);
        [proxy forwardedRecord:-9123];
        check("direct-void", recordedValue == -9123);
        check("direct-full-forwarding-count", forwardedCalls == before + 20);

        check("fast-game-bool-class", [fast isCurRootViewControllerOfClass:[NSObject class]] == YES);
        check("fast-object", [fast forwardedObject:value] == value);
        check("fast-mixed-r3-stack-split", [fast forwardedMixed:-7 wide:INT64_C(0x123456789) ratio:0.125 tail:1.5f] == mixed);
        check("fast-path-bypasses-full-forwarding", fastFallbackCalls == 0 && forwardedCalls == before + 20);

        char booleanSignature[16];
        snprintf(booleanSignature, sizeof(booleanSignature), "%s@:#", @encode(BOOL));
        NSInvocation *flag = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:booleanSignature]];
        flag.target = target;
        flag.selector = @selector(isCurRootViewControllerOfClass:);
        check("invocation-selector-roundtrip", flag.selector == @selector(isCurRootViewControllerOfClass:));
        Class type = [NSObject class];
        [flag setArgument:&type atIndex:2];
        [flag invoke];
        struct { uint8_t before; BOOL value; uint8_t after[8]; } result;
        memset(&result, 0xa5, sizeof(result));
        [flag getReturnValue:&result.value];
        BOOL canaries = result.before == 0xa5;
        for(unsigned i = 0; i < sizeof(result.after); ++i) canaries &= result.after[i] == 0xa5;
        check("invocation-bool-return-canaries", canaries && result.value == YES);

        id<LC32SynthesizedForwardMessages> synthetic = (id)[LC32SynthesizedForwardProxy alloc];
        check("direct-synthesized-scalar-return", [synthetic synthesizedTriple:-37] == -111);
        check("direct-synthesized-object-return", [synthetic synthesizedEcho:value] == value);
        check("invocation-get-argument-canaries", synthesizedArgumentsIntact);
        check("invocation-forwarded-selector-roundtrip", synthesizedSelectorsIntact);
        invocationLongEncodings();
        [(id)synthetic release];
        [(id)proxy release];
        [(id)fast release];
        [target release];
    }
    check("direct-forwarding-ownership-balanced", deallocations == previousDeallocations + 1 &&
        directTargetDeallocations == 1 && fastDeallocations == 1);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
#ifndef LC32_NSPROXY_NATIVE_CHECK
    @autoreleasepool {
        check("independent-root-class",
            class_getSuperclass([NSProxy class]) == Nil);
        const uint64_t hostClass = [(id)[LC32ProxyBridgeFixture class] host_self];
        check("class-mirror-created", hostClass != 0);
        check("class-reverse-map",
            LC32HostToGuestObject(hostClass) == (id)[LC32ProxyBridgeFixture class]);
        invokeObject(hostClass, @selector(classMarker), 0);
        check("class-selector-resolves-on-metaclass", classCallback);
        SEL lateSelector = sel_registerName("lateClassMarker");
        check("late-guest-class-method-added",
            class_addMethod(object_getClass([LC32ProxyBridgeFixture class]),
                lateSelector, (IMP)lateClassMarker, "@@:"));
        invokeObject(hostClass, lateSelector, 0);
        check("late-class-method-dynamically-resolves", lateClassCallback);

        id value = [NSMutableString stringWithString:@"proxy payload"];
        id proxy = [[LC32ProxyBridgeFixture alloc] initWithValue:value];
        const uint64_t hostProxy = [proxy host_self];
        check("instance-mirror-created", hostProxy != 0);
        check("instance-reverse-map", LC32HostToGuestObject(hostProxy) == proxy);
        invokeObject(hostProxy, @selector(value), 0);
        check("instance-object-callback", valueCallback == value);
        invokeObject(hostProxy, @selector(echo:), [value host_self]);
        check("instance-object-argument-roundtrip", echoCallback == value);
        NSInvocation *scalar = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:"i@:i"]];
        scalar.target = proxy;
        scalar.selector = @selector(addOne:);
        int argument = 41;
        [scalar setArgument:&argument atIndex:2];
        [scalar invoke];
        check("instance-scalar-callback", scalarCallback == 41);
        struct { uint32_t before; int32_t value; uint32_t after; } scalarResult = {0x12345678, 0, 0x87654321};
        [scalar getReturnValue:&scalarResult.value];
        check("invocation-scalar-return-canaries", scalarResult.value == 42 &&
            scalarResult.before == 0x12345678 && scalarResult.after == 0x87654321);
        [proxy release];

        // This modern UIKit query is absent from the captured ARM32 method
        // tables. A native NSProxy forwarding it still needs the native
        // delegate's real signature, not nil from the guest-only lookup.
        SEL nativeOnly = sel_registerName("__isKindOfUIResponder");
        id delegate = [[NSObject alloc] init];
        check("native-only-instance-signature",
            [delegate methodSignatureForSelector:nativeOnly] != nil);
        check("native-only-class-instance-signature",
            [NSObject instanceMethodSignatureForSelector:nativeOnly] != nil);
        check("class-signature-does-not-use-instance-methods",
            [NSArray methodSignatureForSelector:@selector(indexOfObject:)] == nil);
        check("unknown-selector-still-has-no-signature",
            [delegate methodSignatureForSelector:
                sel_registerName("lc32ThisSelectorDoesNotExist_91028")] == nil);
        id forwardingProxy = [[LC32ForwardingProxyBridgeFixture alloc] initWithValue:delegate];
        NSInvocation *forwarded = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:"B@:"]];
        forwarded.target = forwardingProxy;
        forwarded.selector = nativeOnly;
        [forwarded invoke];
        check("native-only-query-forwards-to-delegate", forwardedCalls == 1);
        [forwardingProxy release];
        [delegate release];
    }
    check("both-proxies-deallocated-once", deallocations == 2);
#endif
    directForwarding();
    printf("NSProxy bridge summary: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
