#import <CoreFoundation/CoreFoundation+LC32.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

/*
 * NULL means "use the current/default allocator" in CoreFoundation APIs,
 * while these four exported allocators are real, distinguishable values.
 * Keep lightweight guest-side identities for now: the manual CF entry points
 * either ignore the allocator or can recognize these addresses without ever
 * passing a host pointer into ARM code.
 */
typedef struct {
    uint32_t kind;
} LC32CFAllocatorIdentity;

static const LC32CFAllocatorIdentity LC32SystemAllocator = { 1 };
static const LC32CFAllocatorIdentity LC32MallocAllocator = { 2 };
static const LC32CFAllocatorIdentity LC32MallocZoneAllocator = { 3 };
static const LC32CFAllocatorIdentity LC32NullAllocator = { 4 };

const CFAllocatorRef kCFAllocatorSystemDefault =
    (CFAllocatorRef)&LC32SystemAllocator;
const CFAllocatorRef kCFAllocatorMalloc =
    (CFAllocatorRef)&LC32MallocAllocator;
const CFAllocatorRef kCFAllocatorMallocZone =
    (CFAllocatorRef)&LC32MallocZoneAllocator;
const CFAllocatorRef kCFAllocatorNull =
    (CFAllocatorRef)&LC32NullAllocator;

const CFTimeInterval kCFAbsoluteTimeIntervalSince1970 = 978307200.0;

const CFStringRef kCFBundleExecutableKey = CFSTR("CFBundleExecutable");
const CFStringRef kCFBundleInfoDictionaryVersionKey =
    CFSTR("CFBundleInfoDictionaryVersion");
const CFStringRef kCFBundleIdentifierKey = CFSTR("CFBundleIdentifier");
const CFStringRef kCFBundleVersionKey = CFSTR("CFBundleVersion");
const CFStringRef kCFBundleDevelopmentRegionKey =
    CFSTR("CFBundleDevelopmentRegion");
const CFStringRef kCFBundleNameKey = CFSTR("CFBundleName");
const CFStringRef kCFBundleLocalizationsKey = CFSTR("CFBundleLocalizations");

const CFRunLoopMode kCFRunLoopDefaultMode =
    CFSTR("kCFRunLoopDefaultMode");

/* These CFStream constants are exported by CoreFoundation on iOS 10. */
const CFStringRef kCFStreamPropertyShouldCloseNativeSocket =
    CFSTR("kCFStreamPropertyShouldCloseNativeSocket");
const CFStreamPropertyKey kCFStreamPropertySocketNativeHandle =
    CFSTR("kCFStreamPropertySocketNativeHandle");
const CFStringRef kCFStreamPropertySOCKSPassword =
    CFSTR("kCFStreamPropertySOCKSPassword");
const CFStringRef kCFStreamPropertySOCKSProxy =
    CFSTR("kCFStreamPropertySOCKSProxy");
const CFStringRef kCFStreamPropertySOCKSProxyHost = CFSTR("SOCKSProxy");
const CFStringRef kCFStreamPropertySOCKSProxyPort = CFSTR("SOCKSPort");
const CFStringRef kCFStreamPropertySOCKSUser =
    CFSTR("kCFStreamPropertySOCKSUser");
const CFStringRef kCFStreamPropertySOCKSVersion =
    CFSTR("kCFStreamPropertySOCKSVersion");
const CFStringRef kCFStreamPropertySocketSecurityLevel =
    CFSTR("kCFStreamPropertySocketSecurityLevel");
const CFStringRef kCFStreamSocketSOCKSVersion4 =
    CFSTR("kCFStreamSocketSOCKSVersion4");
const CFStringRef kCFStreamSocketSOCKSVersion5 =
    CFSTR("kCFStreamSocketSOCKSVersion5");
const CFStringRef kCFStreamSocketSecurityLevelNegotiatedSSL =
    CFSTR("kCFStreamSocketSecurityLevelNegotiatedSSL");
const CFStringRef kCFStreamSocketSecurityLevelNone =
    CFSTR("kCFStreamSocketSecurityLevelNone");
const CFStringRef kCFStreamSocketSecurityLevelSSLv2 =
    CFSTR("kCFStreamSocketSecurityLevelSSLv2");
const CFStringRef kCFStreamSocketSecurityLevelSSLv3 =
    CFSTR("kCFStreamSocketSecurityLevelSSLv3");
const CFStringRef kCFStreamSocketSecurityLevelTLSv1 =
    CFSTR("kCFStreamSocketSecurityLevelTLSv1");
const CFStreamPropertyKey kCFStreamPropertyDataWritten =
    CFSTR("kCFStreamPropertyDataWritten");

const CFErrorDomain kCFErrorDomainMach = CFSTR("NSMachErrorDomain");
const CFErrorDomain kCFErrorDomainOSStatus = CFSTR("NSOSStatusErrorDomain");
const CFErrorDomain kCFErrorDomainPOSIX = CFSTR("NSPOSIXErrorDomain");
const CFErrorDomain kCFErrorDomainCocoa = CFSTR("NSCocoaErrorDomain");
const CFStringRef kCFErrorDescriptionKey = CFSTR("NSDescription");
const CFStringRef kCFErrorLocalizedDescriptionKey =
    CFSTR("NSLocalizedDescription");
const CFStringRef kCFErrorLocalizedFailureReasonKey =
    CFSTR("NSLocalizedFailureReason");
const CFStringRef kCFErrorLocalizedRecoverySuggestionKey =
    CFSTR("NSLocalizedRecoverySuggestion");
const CFStringRef kCFErrorUnderlyingErrorKey = CFSTR("NSUnderlyingError");
const CFStringRef kCFErrorURLKey = CFSTR("NSURL");
const CFStringRef kCFErrorFilePathKey = CFSTR("NSFilePath");

const CFCalendarIdentifier kCFGregorianCalendar = CFSTR("gregorian");
const CFLocaleKey kCFLocaleCountryCode = CFSTR("kCFLocaleCountryCodeKey");

/* Match the legacy CoreFoundation constants' actual NSString payloads. */
const CFStringRef kCFStringTransformStripCombiningMarks =
    CFSTR(")kCFStringTransformStripCombiningMarks");
const CFStringRef kCFStringTransformToLatin =
    CFSTR(")kCFStringTransformToLatin");

const CFStringRef kCFPreferencesAnyApplication =
    CFSTR("kCFPreferencesAnyApplication");
const CFStringRef kCFPreferencesCurrentApplication =
    CFSTR("kCFPreferencesCurrentApplication");
const CFStringRef kCFPreferencesAnyHost = CFSTR("kCFPreferencesAnyHost");
const CFStringRef kCFPreferencesCurrentHost =
    CFSTR("kCFPreferencesCurrentHost");
const CFStringRef kCFPreferencesAnyUser = CFSTR("kCFPreferencesAnyUser");
const CFStringRef kCFPreferencesCurrentUser =
    CFSTR("kCFPreferencesCurrentUser");

const CFStringRef kCFURLIsExcludedFromBackupKey =
    CFSTR("NSURLIsExcludedFromBackupKey");
const CFStringRef kCFURLFileDirectoryContents =
    CFSTR("kCFURLFileDirectoryContents");
const CFStringRef kCFURLFileExists = CFSTR("kCFURLFileExists");

/* Private keys consumed by the iOS 10 Security/IOKit dependency closure. */
const CFStringRef _kCFBundlePackageTypeKey = CFSTR("CFBundlePackageType");
const CFStringRef _kCFSystemVersionBuildVersionKey =
    CFSTR("ProductBuildVersion");
const CFStringRef _kCFSystemVersionProductNameKey = CFSTR("ProductName");
const CFStringRef _kCFSystemVersionProductVersionKey =
    CFSTR("ProductVersion");

/* Foundation spellings which are two-level bound to CoreFoundation here. */
NSString * const NSGenericException = @"NSGenericException";
NSString * const NSInternalInconsistencyException =
    @"NSInternalInconsistencyException";
NSString * const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString * const NSMallocException = @"NSMallocException";
NSString * const NSRangeException = @"NSRangeException";
NSString * const NSLocaleCountryCode = @"kCFLocaleCountryCodeKey";
NSString * const NSLocaleCurrencyCode = @"currency";
const NSLocaleKey NSLocaleCurrencySymbol = @"kCFLocaleCurrencySymbolKey";
NSString * const NSLocaleIdentifier = @"kCFLocaleIdentifierKey";
NSString * const NSLocaleLanguageCode = @"kCFLocaleLanguageCodeKey";
NSNotificationName const NSCurrentLocaleDidChangeNotification =
    @"kCFLocaleCurrentLocaleDidChangeNotification";
NSString * const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";
const NSStreamPropertyKey NSStreamDataWrittenToMemoryStreamKey =
    @"kCFStreamPropertyDataWritten";
const NSStreamPropertyKey NSStreamFileCurrentOffsetKey =
    @"kCFStreamPropertyFileCurrentOffset";
NSString * const NSURLIsExcludedFromBackupKey =
    @"NSURLIsExcludedFromBackupKey";

extern const void *__CFTypeCollectionRetain(CFAllocatorRef allocator,
                                             const void *value);
extern void __CFTypeCollectionRelease(CFAllocatorRef allocator,
                                      const void *value);

static CFHashCode LC32CFObjectHash(const void *value) {
    return [(id)value hash];
}

static const void *LC32CFCopyString(CFAllocatorRef allocator,
                                    const void *value) {
    return CFStringCreateCopy(allocator, (CFStringRef)value);
}

const CFDictionaryKeyCallBacks kCFCopyStringDictionaryKeyCallBacks = {
    0,
    LC32CFCopyString,
    __CFTypeCollectionRelease,
    (CFDictionaryCopyDescriptionCallBack)CFCopyDescription,
    (CFDictionaryEqualCallBack)CFEqual,
    LC32CFObjectHash,
};

const CFBagCallBacks kCFTypeBagCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    (CFBagCopyDescriptionCallBack)CFCopyDescription,
    (CFBagEqualCallBack)CFEqual,
    LC32CFObjectHash,
};

const CFBagCallBacks kCFCopyStringBagCallBacks = {
    0,
    LC32CFCopyString,
    __CFTypeCollectionRelease,
    (CFBagCopyDescriptionCallBack)CFCopyDescription,
    (CFBagEqualCallBack)CFEqual,
    LC32CFObjectHash,
};

const CFSetCallBacks kCFTypeSetCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    (CFSetCopyDescriptionCallBack)CFCopyDescription,
    (CFSetEqualCallBack)CFEqual,
    LC32CFObjectHash,
};

const CFSetCallBacks kCFCopyStringSetCallBacks = {
    0,
    LC32CFCopyString,
    __CFTypeCollectionRelease,
    (CFSetCopyDescriptionCallBack)CFCopyDescription,
    (CFSetEqualCallBack)CFEqual,
    LC32CFObjectHash,
};

static CFComparisonResult LC32CFStringBinaryHeapCompare(
        const void *left, const void *right, void *context) {
    (void)context;
    return CFStringCompare((CFStringRef)left, (CFStringRef)right, 0);
}

const CFBinaryHeapCallBacks kCFStringBinaryHeapCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    CFCopyDescription,
    LC32CFStringBinaryHeapCompare,
};

/*
 * These globals must contain guest Objective-C objects, not native pointers.
 * Give the exported symbols writable backing under private C identifiers so
 * they can be populated after the Objective-C images have been registered.
 */
CFBooleanRef LC32CFBooleanTrue __asm__("_kCFBooleanTrue");
CFBooleanRef LC32CFBooleanFalse __asm__("_kCFBooleanFalse");
CFNullRef LC32CFNull __asm__("_kCFNull");
CFNumberRef LC32CFNumberNaN __asm__("_kCFNumberNaN");
CFNumberRef LC32CFNumberPositiveInfinity
    __asm__("_kCFNumberPositiveInfinity");
CFNumberRef LC32CFNumberNegativeInfinity
    __asm__("_kCFNumberNegativeInfinity");

/*
 * Real CF Boolean, null, NaN, and infinity objects are process-lifetime
 * singletons: retaining, releasing, or autoreleasing them cannot destroy
 * them.  Some clients rely on that contract and deliberately transfer these
 * constants into collections without first retaining them (JSONKit is one
 * example).  Ordinary LC32 host-object proxies do have guest retain counts,
 * so use dedicated subclasses which preserve the singleton ownership
 * semantics while inheriting the normal NSNumber/NSNull forwarding surface.
 */
@interface LC32CFImmortalNumber : NSNumber
@end

@implementation LC32CFImmortalNumber
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return (NSUInteger)-1; }
@end

@interface LC32CFImmortalNull : NSNull
@end

@implementation LC32CFImmortalNull
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return (NSUInteger)-1; }
@end

static id LC32CreateCoreFoundationConstantProxy(const char *className,
                                                 const char *symbolName) {
    Class cls = objc_getClass(className);
    id guestObject = cls ? class_createInstance(cls, 0) : nil;
    const uint64_t hostObject = LC32Dlsym(symbolName, NO);
    if(!guestObject || !hostObject) abort();

    /*
     * Calling +numberWithBool:/+numberWithDouble: here asks the native
     * singleton for its guest_self while dyld is still running framework
     * initializers.  That re-enters guest objc_msgSend before startup has a
     * resumable PC.  Instead, allocate the already-registered proxy class
     * locally and bind it directly to the native constant.  No host-to-guest
     * callback is needed, and subsequent conversions reuse this proxy.
     */
    [guestObject bindHostSelf:hostObject];
    return guestObject;
}

__attribute__((constructor))
static void LC32InitializeCoreFoundationObjectConstants(void) {
    LC32CFBooleanTrue = (CFBooleanRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNumber", "kCFBooleanTrue");
    LC32CFBooleanFalse = (CFBooleanRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNumber", "kCFBooleanFalse");
    LC32CFNull = (CFNullRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNull", "kCFNull");
    LC32CFNumberNaN = (CFNumberRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNumber", "kCFNumberNaN");
    LC32CFNumberPositiveInfinity = (CFNumberRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNumber", "kCFNumberPositiveInfinity");
    LC32CFNumberNegativeInfinity = (CFNumberRef)
        LC32CreateCoreFoundationConstantProxy(
            "LC32CFImmortalNumber", "kCFNumberNegativeInfinity");
}
