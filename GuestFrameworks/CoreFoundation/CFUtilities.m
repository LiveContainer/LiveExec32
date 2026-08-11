#import <CoreFoundation/CoreFoundation+LC32.h>

const CFStringRef kCFBundleVersionKey = CFSTR("CFBundleVersion");
const CFRunLoopMode kCFRunLoopCommonModes = CFSTR("kCFRunLoopCommonModes");

/* Foundation's iOS 6 import is two-level bound to CoreFoundation. */
NSString * const NSGregorianCalendar = @"gregorian";

CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

CFBundleRef CFBundleGetMainBundle(void) {
    return (CFBundleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpBundleGetMainBundle);
}

CFDictionaryRef CFBundleGetInfoDictionary(CFBundleRef bundle) {
    return bundle
        ? (CFDictionaryRef)[(NSBundle *)bundle infoDictionary]
        : NULL;
}

CFRunLoopRef CFRunLoopGetMain(void) {
    return (CFRunLoopRef)LC32_CF_CALL0(
        LC32CoreFoundationOpRunLoopGetMain);
}

CFUUIDRef CFUUIDCreate(CFAllocatorRef allocator) {
    (void)allocator;
    return (CFUUIDRef)[[NSUUID alloc] init];
}

CFStringRef CFUUIDCreateString(CFAllocatorRef allocator, CFUUIDRef uuid) {
    (void)allocator;
    return uuid ? (CFStringRef)[[(NSUUID *)uuid UUIDString] copy] : NULL;
}

CFStringRef CFURLCreateStringByAddingPercentEscapes(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveUnescaped,
        CFStringRef legalURLCharactersToBeEscaped,
        CFStringEncoding encoding) {
    (void)allocator;
    if(!originalString) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateStringByAddingPercentEscapes,
        LC32_CF_HOST(originalString),
        LC32_CF_HOST(charactersToLeaveUnescaped),
        LC32_CF_HOST(legalURLCharactersToBeEscaped),
        LC32_CF_U32(encoding));
}

Boolean CFNumberGetValue(CFNumberRef number, CFNumberType type,
                         void *valuePointer) {
    if(!number || !valuePointer) return false;
    return LC32_CF_CALL(LC32CoreFoundationOpNumberGetValue,
        LC32_CF_HOST(number), LC32_CF_U32(type),
        LC32_CF_U32((uintptr_t)valuePointer)) != 0;
}

@interface LC32CFLocalNotificationObserver : NSObject {
    CFNotificationCenterRef _center;
    const void *_observer;
    CFNotificationCallback _callback;
}
- (instancetype)initWithCenter:(CFNotificationCenterRef)center
                       observer:(const void *)observer
                       callback:(CFNotificationCallback)callback;
- (void)lc32_handleNotification:(NSNotification *)notification;
@end

@implementation LC32CFLocalNotificationObserver

- (instancetype)initWithCenter:(CFNotificationCenterRef)center
                       observer:(const void *)observer
                       callback:(CFNotificationCallback)callback {
    self = [super init];
    if(self) {
        _center = center;
        _observer = observer;
        _callback = callback;
    }
    return self;
}

- (void)lc32_handleNotification:(NSNotification *)notification {
    if(!_callback) return;
    _callback(_center, (void *)_observer,
        (CFNotificationName)notification.name,
        (const void *)notification.object,
        (CFDictionaryRef)notification.userInfo);
}

@end

CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void) {
    return (CFNotificationCenterRef)[NSNotificationCenter defaultCenter];
}

void CFNotificationCenterAddObserver(
        CFNotificationCenterRef center, const void *observer,
        CFNotificationCallback callback, CFStringRef name,
        const void *object,
        CFNotificationSuspensionBehavior suspensionBehavior) {
    (void)suspensionBehavior;
    if(!callback) return;
    if(!center) center = CFNotificationCenterGetLocalCenter();

    LC32CFLocalNotificationObserver *trampoline =
        [[LC32CFLocalNotificationObserver alloc]
            initWithCenter:center observer:observer callback:callback];
    [(NSNotificationCenter *)center
        addObserver:trampoline
           selector:@selector(lc32_handleNotification:)
               name:(NSString *)name
             object:(id)object];

    /*
     * CF's selector-style registration remains active until explicitly
     * removed. Flappy does not import the removal API, so retain the small
     * trampoline for the same lifetime instead of relying on the host's
     * modern weak-observer implementation.
     */
    (void)trampoline;
}
