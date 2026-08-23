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

CFStringRef CFBundleGetIdentifier(CFBundleRef bundle) {
    return bundle ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetIdentifier,
        LC32_CF_HOST(bundle)) : NULL;
}

CFURLRef CFBundleCopyBundleURL(CFBundleRef bundle) {
    return bundle ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyBundleURL,
        LC32_CF_HOST(bundle)) : NULL;
}

UInt32 CFBundleGetVersionNumber(CFBundleRef bundle) {
    return bundle ? LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetVersionNumber,
        LC32_CF_HOST(bundle)) : 0;
}

CFStringRef CFBundleCopyLocalizedString(
        CFBundleRef bundle, CFStringRef key, CFStringRef value,
        CFStringRef tableName) {
    if(!bundle || !key) return value ? (CFStringRef)CFRetain(value) : NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyLocalizedString,
        LC32_CF_HOST(bundle), LC32_CF_HOST(key), LC32_CF_HOST(value),
        LC32_CF_HOST(tableName));
}

CFURLRef CFBundleCopyResourceURL(
        CFBundleRef bundle, CFStringRef resourceName,
        CFStringRef resourceType, CFStringRef subDirName) {
    if(!bundle || !resourceName) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyResourceURL,
        LC32_CF_HOST(bundle), LC32_CF_HOST(resourceName),
        LC32_CF_HOST(resourceType), LC32_CF_HOST(subDirName));
}

CFBundleRef CFBundleCreate(CFAllocatorRef allocator, CFURLRef bundleURL) {
    (void)allocator;
    return bundleURL ? (CFBundleRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCreate,
        LC32_CF_HOST(bundleURL)) : NULL;
}

CFBundleRef CFBundleGetBundleWithIdentifier(CFStringRef bundleID) {
    return bundleID ? (CFBundleRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetBundleWithIdentifier,
        LC32_CF_HOST(bundleID)) : NULL;
}

void *CFBundleGetFunctionPointerForName(
        CFBundleRef bundle, CFStringRef functionName) {
    if(!bundle || !functionName) return NULL;
    return (void *)(uintptr_t)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetFunctionPointerForName,
        LC32_CF_HOST(bundle), LC32_CF_HOST(functionName));
}

CFRunLoopRef CFRunLoopGetMain(void) {
    return (CFRunLoopRef)LC32_CF_CALL0(
        LC32CoreFoundationOpRunLoopGetMain);
}

CFRunLoopRef CFRunLoopGetCurrent(void) {
    return (CFRunLoopRef)LC32_CF_CALL0(
        LC32CoreFoundationOpRunLoopGetCurrent);
}

CFUUIDRef CFUUIDCreate(CFAllocatorRef allocator) {
    (void)allocator;
    return (CFUUIDRef)[[NSUUID alloc] init];
}

CFUUIDRef CFUUIDCreateFromUUIDBytes(CFAllocatorRef allocator,
                                    CFUUIDBytes bytes) {
    static const char digits[] = "0123456789ABCDEF";
    const UInt8 rawBytes[16] = {
        bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
        bytes.byte4, bytes.byte5, bytes.byte6, bytes.byte7,
        bytes.byte8, bytes.byte9, bytes.byte10, bytes.byte11,
        bytes.byte12, bytes.byte13, bytes.byte14, bytes.byte15,
    };
    char text[37];
    size_t output = 0;
    for(size_t index = 0; index < sizeof(rawBytes); ++index) {
        if(index == 4 || index == 6 || index == 8 || index == 10) {
            text[output++] = '-';
        }
        text[output++] = digits[rawBytes[index] >> 4];
        text[output++] = digits[rawBytes[index] & 0x0f];
    }
    text[output] = '\0';

    CFStringRef string = CFStringCreateWithBytes(
        allocator, (const UInt8 *)text, (CFIndex)output,
        kCFStringEncodingASCII, false);
    if(!string) return NULL;
    CFUUIDRef uuid = (CFUUIDRef)[[NSUUID alloc]
        initWithUUIDString:(NSString *)string];
    CFRelease(string);
    return uuid;
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

CFStringRef CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveEscaped,
        CFStringEncoding encoding) {
    (void)allocator;
    if(!originalString) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateStringByReplacingPercentEscapes,
        LC32_CF_HOST(originalString),
        LC32_CF_HOST(charactersToLeaveEscaped), LC32_CF_U32(encoding));
}

CFStringRef CFURLCreateStringByReplacingPercentEscapes(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveEscaped) {
    return CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
        allocator, originalString, charactersToLeaveEscaped,
        kCFStringEncodingUTF8);
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
