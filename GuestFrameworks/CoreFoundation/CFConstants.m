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
const CFStringRef kCFBundleIdentifierKey = CFSTR("CFBundleIdentifier");
const CFStringRef kCFBundleNameKey = CFSTR("CFBundleName");

const CFRunLoopMode kCFRunLoopDefaultMode =
    CFSTR("kCFRunLoopDefaultMode");

/* These CFStream constants are exported by CoreFoundation on iOS 10. */
const CFStringRef kCFStreamPropertyShouldCloseNativeSocket =
    CFSTR("kCFStreamPropertyShouldCloseNativeSocket");
const CFStringRef kCFStreamSocketSecurityLevelNegotiatedSSL =
    CFSTR("kCFStreamSocketSecurityLevelNegotiatedSSL");
const CFStringRef kCFStreamSocketSecurityLevelSSLv3 =
    CFSTR("kCFStreamSocketSecurityLevelSSLv3");
const CFStringRef kCFStreamSocketSecurityLevelTLSv1 =
    CFSTR("kCFStreamSocketSecurityLevelTLSv1");
const CFStreamPropertyKey kCFStreamPropertyDataWritten =
    CFSTR("kCFStreamPropertyDataWritten");

const CFErrorDomain kCFErrorDomainMach = CFSTR("NSMachErrorDomain");
const CFErrorDomain kCFErrorDomainOSStatus = CFSTR("NSOSStatusErrorDomain");
const CFErrorDomain kCFErrorDomainPOSIX = CFSTR("NSPOSIXErrorDomain");
const CFStringRef kCFErrorDescriptionKey = CFSTR("NSDescription");
const CFStringRef kCFErrorLocalizedDescriptionKey =
    CFSTR("NSLocalizedDescription");
const CFStringRef kCFErrorUnderlyingErrorKey = CFSTR("NSUnderlyingError");

const CFCalendarIdentifier kCFGregorianCalendar = CFSTR("gregorian");
const CFLocaleKey kCFLocaleCountryCode = CFSTR("kCFLocaleCountryCodeKey");

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
NSString * const NSRangeException = @"NSRangeException";
NSString * const NSLocaleCountryCode = @"kCFLocaleCountryCodeKey";
NSString * const NSLocaleIdentifier = @"kCFLocaleIdentifierKey";
NSString * const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";
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

const CFSetCallBacks kCFTypeSetCallBacks = {
    0,
    __CFTypeCollectionRetain,
    __CFTypeCollectionRelease,
    (CFSetCopyDescriptionCallBack)CFCopyDescription,
    (CFSetEqualCallBack)CFEqual,
    LC32CFObjectHash,
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
        LC32CreateCoreFoundationConstantProxy("NSNumber", "kCFBooleanTrue");
    LC32CFBooleanFalse = (CFBooleanRef)
        LC32CreateCoreFoundationConstantProxy("NSNumber", "kCFBooleanFalse");
    LC32CFNull = (CFNullRef)
        LC32CreateCoreFoundationConstantProxy("NSNull", "kCFNull");
    LC32CFNumberNaN = (CFNumberRef)
        LC32CreateCoreFoundationConstantProxy("NSNumber", "kCFNumberNaN");
}
