#import <Foundation/Foundation.h>

#include <stdio.h>
#include <math.h>

#if __has_feature(objc_arc)
#error This lifetime regression requires explicit MRC ownership transitions.
#endif

@interface NSObject (LC32PointerTest)
- (uint64_t)host_self;
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object,
                                       uint64_t selector, ...);

@interface LC32ClassSuperNullProbe : NSNull
+ (BOOL)superSupportsSecureCoding;
@end

@implementation LC32ClassSuperNullProbe
+ (BOOL)superSupportsSecureCoding {
    return [super supportsSecureCoding];
}
@end

@interface LC32RealSetterProbe : NSObject {
    id window;
    BOOL setterCalled;
}
- (void)setWindow:(id)value;
- (BOOL)setterCalled;
@end

@implementation LC32RealSetterProbe
- (void)setWindow:(id)value {
    window = value;
    setterCalled = YES;
}
- (BOOL)setterCalled {
    return setterCalled && window != nil;
}
@end

@interface LC32LeadingUnderscoreIvarProbe : NSObject {
    id _btnGameMode;
}
- (BOOL)receivedGameMode:(id)value;
@end

@implementation LC32LeadingUnderscoreIvarProbe
- (BOOL)receivedGameMode:(id)value {
    return [_btnGameMode isEqual:value];
}
@end

// NSMutableString's host implementation of appendString: calls this primitive
// method on its receiver.  Because the receiver is a guest subclass, that call
// crosses back from the ARM64 host with an NSRange by value before the trailing
// NSString argument.
@interface LC32RangeCallbackString : NSMutableString {
    BOOL rangeCallbackCalled;
    NSRange callbackRange;
    NSString *callbackString;
}
- (BOOL)receivedRange:(NSRange)range string:(NSString *)string;
@end

@implementation LC32RangeCallbackString
- (NSUInteger)length {
    return 4;
}

- (unichar)characterAtIndex:(NSUInteger)index {
    return [@"seed" characterAtIndex:index];
}

- (void)replaceCharactersInRange:(NSRange)range
                      withString:(NSString *)string {
    rangeCallbackCalled = YES;
    callbackRange = range;
    callbackString = [string copy];
}

- (BOOL)receivedRange:(NSRange)range string:(NSString *)string {
    return rangeCallbackCalled && NSEqualRanges(callbackRange, range) &&
        [callbackString isEqualToString:string];
}
@end

static unsigned int LC32HostRetainedProbeDeallocCount;

@interface LC32HostRetainedProbe : NSObject {
    unsigned int sentinel;
    unsigned int callbackCount;
}
- (instancetype)initWithSentinel:(unsigned int)value;
- (void)lc32HostVisit;
- (BOOL)hasSentinel:(unsigned int)expectedSentinel
      callbackCount:(unsigned int)expectedCallbackCount;
@end

@implementation LC32HostRetainedProbe
- (instancetype)initWithSentinel:(unsigned int)value {
    self = [super init];
    if(self) sentinel = value;
    return self;
}

- (void)lc32HostVisit {
    callbackCount++;
}

- (BOOL)hasSentinel:(unsigned int)expectedSentinel
      callbackCount:(unsigned int)expectedCallbackCount {
    return sentinel == expectedSentinel &&
        callbackCount == expectedCallbackCount;
}

- (void)dealloc {
    LC32HostRetainedProbeDeallocCount++;
    [super dealloc];
}
@end

@interface LC32MixedArgumentTimerProbe : NSObject
- (void)lc32TimerDidFire:(NSTimer *)timer;
@end

@implementation LC32MixedArgumentTimerProbe
- (void)lc32TimerDidFire:(NSTimer *)timer {
    (void)timer;
}
@end

int main(void) {
    NSScanner *integerScanner =
        [NSScanner scannerWithString:@"-123"];
    NSInteger integer = 0x55555555;
    BOOL integerPassed = [integerScanner scanInteger:&integer] &&
        integer == -123 && integerScanner.isAtEnd;
    printf("pointer-out-integer: %s\n",
        integerPassed ? "PASS" : "FAIL");

    NSScanner *nullIntegerScanner =
        [NSScanner scannerWithString:@"456"];
    BOOL nullIntegerPassed =
        [nullIntegerScanner scanInteger:NULL] &&
        nullIntegerScanner.isAtEnd;
    printf("pointer-out-null-integer: %s\n",
        nullIntegerPassed ? "PASS" : "FAIL");

    NSScanner *objectScanner =
        [NSScanner scannerWithString:@"token"];
    NSString *matched = nil;
    BOOL objectPassed =
        [objectScanner scanString:@"token" intoString:&matched] &&
        [matched isEqualToString:@"token"] && objectScanner.isAtEnd;
    printf("pointer-out-object: %s\n",
        objectPassed ? "PASS" : "FAIL");

    NSScanner *nullObjectScanner =
        [NSScanner scannerWithString:@"token"];
    BOOL nullObjectPassed =
        [nullObjectScanner scanString:@"token" intoString:NULL] &&
        nullObjectScanner.isAtEnd;
    printf("pointer-out-null-object: %s\n",
        nullObjectPassed ? "PASS" : "FAIL");

    BOOL classSuperPassed =
        [LC32ClassSuperNullProbe superSupportsSecureCoding] ==
        [NSNull supportsSecureCoding];
    printf("class-method-super: %s\n",
        classSuperPassed ? "PASS" : "FAIL");

    const float floatValue = [@"1.25" floatValue];
    const double doubleValue = [@"-2.5" doubleValue];
    const BOOL floatingReturnPassed =
        fabsf(floatValue - 1.25f) < 0.0001f &&
        fabs(doubleValue + 2.5) < 0.0001;
    printf("floating-returns: %s\n",
        floatingReturnPassed ? "PASS" : "FAIL");

    /*
     * ARM64 assigns the leading double to d0 while target, selector,
     * userInfo, and repeats begin at x2. This used to duplicate the double's
     * bits into x2 and make NSTimer retain 0x3ff... as an Objective-C object.
     */
    LC32MixedArgumentTimerProbe *timerProbe =
        [LC32MixedArgumentTimerProbe new];
    NSString *timerUserInfo = @"mixed-argument-sentinel";
    NSTimer *mixedArgumentTimer =
        [NSTimer scheduledTimerWithTimeInterval:3600.25
            target:timerProbe
            selector:@selector(lc32TimerDidFire:)
            userInfo:timerUserInfo
            repeats:YES];
    const BOOL mixedArgumentTimerPassed =
        mixedArgumentTimer != nil &&
        fabs(mixedArgumentTimer.timeInterval - 3600.25) < 0.0001 &&
        [mixedArgumentTimer.userInfo isEqual:timerUserInfo];
    [mixedArgumentTimer invalidate];
    [timerProbe release];
    printf("host-mixed-fp-object-arguments: %s\n",
        mixedArgumentTimerPassed ? "PASS" : "FAIL");

    LC32RealSetterProbe *setterProbe = [LC32RealSetterProbe new];
    NSString *setterValue = @"window";
    NSString *setterKey = @"window";
    LC32InvokeHostSelector(
        setterProbe.host_self,
        LC32GetHostSelector(@selector(setValue:forKey:)),
        setterValue.host_self, setterKey.host_self, (uint64_t)0);
    const BOOL realSetterPassed = setterProbe.setterCalled;
    printf("host-kvc-real-setter: %s\n",
        realSetterPassed ? "PASS" : "FAIL");

    LC32LeadingUnderscoreIvarProbe *underscoreProbe =
        [LC32LeadingUnderscoreIvarProbe new];
    NSString *underscoreValue = @"creative";
    NSString *underscoreKey = @"_btnGameMode";
    LC32InvokeHostSelector(
        underscoreProbe.host_self,
        LC32GetHostSelector(@selector(setValue:forKey:)),
        underscoreValue.host_self, underscoreKey.host_self, (uint64_t)0);
    const BOOL literalIvarKeyPassed =
        [underscoreProbe receivedGameMode:underscoreValue];
    printf("host-kvc-leading-underscore-ivar: %s\n",
        literalIvarKeyPassed ? "PASS" : "FAIL");

    NSMutableArray *plainArray = [[NSMutableArray alloc] init];
    [plainArray addObject:@"plain"];
    NSMutableArray *newArray = [NSMutableArray new];
    [newArray addObject:@"new"];
    NSMutableArray *capacityArray =
        [[NSMutableArray alloc] initWithCapacity:2];
    [capacityArray addObject:@"capacity"];
    const uint64_t reverseMappedGuest = LC32InvokeHostSelector(
        plainArray.host_self,
        LC32GetHostSelector(@selector(guest_self)), (uint64_t)0);
    const uint64_t reverseMappedNewGuest = LC32InvokeHostSelector(
        newArray.host_self,
        LC32GetHostSelector(@selector(guest_self)), (uint64_t)0);
    const uint64_t reverseMappedCapacityGuest = LC32InvokeHostSelector(
        capacityArray.host_self,
        LC32GetHostSelector(@selector(guest_self)), (uint64_t)0);
    const BOOL classClusterInitPassed =
        plainArray.count == 1 && newArray.count == 1 &&
        capacityArray.count == 1 &&
        (uint32_t)reverseMappedGuest == (uint32_t)(uintptr_t)plainArray &&
        (uint32_t)reverseMappedNewGuest == (uint32_t)(uintptr_t)newArray &&
        (uint32_t)reverseMappedCapacityGuest ==
            (uint32_t)(uintptr_t)capacityArray;
    printf("class-cluster-init-and-identity: %s\n",
        classClusterInitPassed ? "PASS" : "FAIL");

    LC32RangeCallbackString *rangeProbe =
        [LC32RangeCallbackString new];
    [rangeProbe appendString:@"!"];
    const BOOL rangeArgumentPassed =
        [rangeProbe receivedRange:NSMakeRange(4, 0) string:@"!"];
    printf("host-to-guest-nsrange: %s\n",
        rangeArgumentPassed ? "PASS" : "FAIL");

    const unsigned int deallocsBeforeLifetimeProbe =
        LC32HostRetainedProbeDeallocCount;
    NSMutableArray *lifetimeArray = [[NSMutableArray alloc] init];
    LC32HostRetainedProbe *lifetimeProbe =
        [[LC32HostRetainedProbe alloc]
            initWithSentinel:0x51a7e123];
    const uintptr_t originalLifetimeProbe = (uintptr_t)lifetimeProbe;
    [lifetimeArray addObject:lifetimeProbe];

    // Drop the guest's local +1. The host array must now keep the original
    // guest proxy alive along with its host peer.
    [lifetimeProbe release];
    lifetimeProbe = nil;
    const BOOL survivedLocalRelease =
        LC32HostRetainedProbeDeallocCount == deallocsBeforeLifetimeProbe;

    // This selector is sent by the host NSArray implementation. It verifies
    // that callbacks still target the original guest object before a normal
    // host-to-guest object conversion retrieves it below.
    [lifetimeArray makeObjectsPerformSelector:@selector(lc32HostVisit)];
    LC32HostRetainedProbe *retrievedLifetimeProbe =
        [lifetimeArray objectAtIndex:0];
    const BOOL hostRetainedLifetimePassed =
        survivedLocalRelease &&
        LC32HostRetainedProbeDeallocCount == deallocsBeforeLifetimeProbe &&
        (uintptr_t)retrievedLifetimeProbe == originalLifetimeProbe &&
        [retrievedLifetimeProbe hasSentinel:0x51a7e123
                              callbackCount:1];

    // objectAtIndex: returned a +0 object; do not release it. Removing the
    // host collection's final ownership should destroy the guest proxy once.
    [lifetimeArray removeAllObjects];
    const BOOL hostRetainedLifetimeCleanupPassed =
        LC32HostRetainedProbeDeallocCount ==
            deallocsBeforeLifetimeProbe + 1;
    printf("host-retained-guest-lifetime: %s\n",
        hostRetainedLifetimePassed && hostRetainedLifetimeCleanupPassed
            ? "PASS" : "FAIL");

    /*
     * Framework-native proxies need the same lifetime guarantee as dynamic
     * guest subclasses. NSMutableString also exercises an initializer which
     * may replace its allocation placeholder with a class-cluster instance.
     */
    NSMutableString *nativeLifetimeProbe =
        [[NSMutableString alloc] initWithString:@"native-pin"];
    const uintptr_t originalNativeLifetimeProbe =
        (uintptr_t)nativeLifetimeProbe;
    [lifetimeArray addObject:nativeLifetimeProbe];
    [nativeLifetimeProbe release];
    nativeLifetimeProbe = nil;
    NSMutableString *retrievedNativeLifetimeProbe =
        [lifetimeArray objectAtIndex:0];
    const BOOL hostRetainedNativeLifetimePassed =
        (uintptr_t)retrievedNativeLifetimeProbe ==
            originalNativeLifetimeProbe &&
        [retrievedNativeLifetimeProbe isEqualToString:@"native-pin"];
    [lifetimeArray removeAllObjects];
    printf("host-retained-native-lifetime: %s\n",
        hostRetainedNativeLifetimePassed ? "PASS" : "FAIL");

    const UInt8 fileSystemPath[] = {
        '/', 'p', 'r', 'i', 'v', 'a', 't', 'e', '/', 't', 'm', 'p', '/',
        'l', 'c', '3', '2', '-', 'u', 'r', 'l', '.', 'b', 'i', 'n'
    };
    CFURLRef fileSystemURL = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, fileSystemPath, sizeof(fileSystemPath), false);
    const BOOL fileSystemURLPassed = fileSystemURL &&
        [(NSURL *)fileSystemURL isFileURL] &&
        [[(NSURL *)fileSystemURL path]
            hasSuffix:@"/private/tmp/lc32-url.bin"];
    if(fileSystemURL) CFRelease(fileSystemURL);
    printf("cfurl-file-system-representation: %s\n",
        fileSystemURLPassed ? "PASS" : "FAIL");

    [lifetimeArray release];

    return !(integerPassed && nullIntegerPassed &&
             objectPassed && nullObjectPassed && classSuperPassed &&
             floatingReturnPassed && mixedArgumentTimerPassed &&
             realSetterPassed &&
             literalIvarKeyPassed && classClusterInitPassed &&
             rangeArgumentPassed && hostRetainedLifetimePassed &&
             hostRetainedLifetimeCleanupPassed &&
             hostRetainedNativeLifetimePassed && fileSystemURLPassed);
}
