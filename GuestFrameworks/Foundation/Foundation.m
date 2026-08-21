#import <Foundation/Foundation+LC32.h>
#import <CoreFoundation/CoreFoundation.h>

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>

const NSErrorDomain NSCocoaErrorDomain = @"NSCocoaErrorDomain";
const NSErrorDomain NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
const NSErrorDomain NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
const NSErrorDomain NSMachErrorDomain = @"NSMachErrorDomain";
const NSErrorDomain NSUnderlyingErrorKey = @"NSUnderlyingError";
const NSErrorDomain NSLocalizedDescriptionKey = @"NSLocalizedDescription";
const NSErrorDomain NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
const NSErrorDomain NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
const NSErrorDomain NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
const NSErrorDomain NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
const NSErrorDomain NSHelpAnchorErrorKey = @"NSHelpAnchor";
const NSErrorDomain NSStringEncodingErrorKey = @"NSStringEncodingErrorKey";
const NSErrorDomain NSURLErrorKey = @"NSURL";
const NSErrorDomain NSFilePathErrorKey = @"NSFilePathErrorKey";
const NSErrorDomain NSURLErrorDomain = @"NSURLErrorDomain";
const NSFileAttributeKey NSFileType = @"NSFileType";
const NSFileAttributeKey NSFileSize = @"NSFileSize";
const NSFileAttributeKey NSFileModificationDate = @"NSFileModificationDate";
const NSFileAttributeKey NSFileReferenceCount = @"NSFileReferenceCount";
const NSFileAttributeKey NSFileDeviceIdentifier = @"NSFileDeviceIdentifier";
const NSFileAttributeKey NSFileOwnerAccountName = @"NSFileOwnerAccountName";
const NSFileAttributeKey NSFileGroupOwnerAccountName = @"NSFileGroupOwnerAccountName";
const NSFileAttributeKey NSFilePosixPermissions = @"NSFilePosixPermissions";
const NSFileAttributeKey NSFileSystemNumber = @"NSFileSystemNumber";
const NSFileAttributeKey NSFileSystemFileNumber = @"NSFileSystemFileNumber";
const NSFileAttributeKey NSFileExtensionHidden = @"NSFileExtensionHidden";
const NSFileAttributeKey NSFileHFSCreatorCode = @"NSFileHFSCreatorCode";
const NSFileAttributeKey NSFileHFSTypeCode = @"NSFileHFSTypeCode";
const NSFileAttributeKey NSFileImmutable = @"NSFileImmutable";
const NSFileAttributeKey NSFileAppendOnly = @"NSFileAppendOnly";
const NSFileAttributeKey NSFileCreationDate = @"NSFileCreationDate";
const NSFileAttributeKey NSFileOwnerAccountID = @"NSFileOwnerAccountID";
const NSFileAttributeKey NSFileGroupOwnerAccountID = @"NSFileGroupOwnerAccountID";
const NSFileAttributeKey NSFileBusy = @"NSFileBusy";
const NSFileAttributeKey NSFileProtectionKey = @"NSFileProtectionKey";
const NSFileAttributeKey NSFileSystemSize = @"NSFileSystemSize";
const NSFileAttributeKey NSFileSystemFreeSize = @"NSFileSystemFreeSize";
const NSFileAttributeKey NSFileSystemNodes = @"NSFileSystemNodes";
const NSFileAttributeKey NSFileSystemFreeNodes = @"NSFileSystemFreeNodes";
const NSFileAttributeType NSFileTypeDirectory = @"NSFileTypeDirectory";
const NSFileAttributeType NSFileTypeRegular = @"NSFileTypeRegular";
const NSFileAttributeType NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";
const NSFileAttributeType NSFileTypeSocket = @"NSFileTypeSocket";
const NSFileAttributeType NSFileTypeCharacterSpecial = @"NSFileTypeCharacterSpecial";
const NSFileAttributeType NSFileTypeBlockSpecial = @"NSFileTypeBlockSpecial";
const NSFileAttributeType NSFileTypeUnknown = @"NSFileTypeUnknown";
const NSFileProtectionType NSFileProtectionNone = @"NSFileProtectionNone";
const NSFileProtectionType NSFileProtectionComplete = @"NSFileProtectionComplete";
const NSFileProtectionType NSFileProtectionCompleteUnlessOpen = @"NSFileProtectionCompleteUnlessOpen";
const NSFileProtectionType NSFileProtectionCompleteUntilFirstUserAuthentication = @"NSFileProtectionCompleteUntilFirstUserAuthentication";
const NSHTTPCookiePropertyKey NSHTTPCookieName = @"NSHTTPCookieName";
const NSHTTPCookiePropertyKey NSHTTPCookieValue = @"NSHTTPCookieValue";
const NSHTTPCookiePropertyKey NSHTTPCookieDomain = @"NSHTTPCookieDomain";
const NSHTTPCookiePropertyKey NSHTTPCookiePath = @"NSHTTPCookiePath";
NSString * const NSProgressCategoryKey = @"NSProgressCategoryKey";
NSString * const NSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey";
NSString * const NSURLErrorFailingURLStringErrorKey =
    @"NSErrorFailingURLStringKey";
NSString * const NSGregorianCalendar = @"gregorian";
const NSLocaleKey NSLocaleIdentifier = @"kCFLocaleIdentifierKey";
NSString * const NSURLAuthenticationMethodServerTrust =
    @"NSURLAuthenticationMethodServerTrust";
const NSKeyValueChangeKey NSKeyValueChangeKindKey = @"kind";
const NSKeyValueChangeKey NSKeyValueChangeNewKey = @"new";
const NSKeyValueChangeKey NSKeyValueChangeOldKey = @"old";
const NSKeyValueChangeKey NSKeyValueChangeIndexesKey = @"indexes";
const NSKeyValueChangeKey NSKeyValueChangeNotificationIsPriorKey =
    @"notificationIsPrior";
const NSExceptionName NSParseErrorException = @"NSParseErrorException";
NSString * const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
NSString * const NSUserDefaultsDidChangeNotification =
    @"NSUserDefaultsDidChangeNotification";
NSString * const NSUserActivityTypeBrowsingWeb = @"NSUserActivityTypeBrowsingWeb";
NSNotificationName const NSUbiquitousKeyValueStoreDidChangeExternallyNotification =
    @"NSUbiquitousKeyValueStoreDidChangeExternallyNotification";
NSString * const NSUbiquitousKeyValueStoreChangeReasonKey =
    @"NSUbiquitousKeyValueStoreChangeReasonKey";

/* Match Foundation shipped by iOS 10.3.3 rather than the host runtime. */
double NSFoundationVersionNumber = 1350.0;

NSRange NSIntersectionRange(NSRange range1, NSRange range2) {
    const NSUInteger start = MAX(range1.location, range2.location);
    const NSUInteger end = MIN(NSMaxRange(range1), NSMaxRange(range2));
    if(end < start) return NSMakeRange(0, 0);
    return NSMakeRange(start, end - start);
}

@implementation NSPlaceholderString : NSString
@end

@implementation NSTaggedPointerString : NSString
@end

@implementation NSBundle (LC32GuestMainBundle)

+ (NSBundle *)mainBundle {
    /*
     * The native process belongs to LiveContainer, while the guest's main
     * executable lives in the selected legacy application bundle.  Reuse
     * the CoreFoundation bridge, which constructs an NSBundle beside that
     * executable, rather than exposing the host process's main bundle.
     */
    return (NSBundle *)CFBundleGetMainBundle();
}

@end

void NSLogv(NSString *format, va_list arguments) {
    if(!format) return;

    va_list argumentsCopy;
    va_copy(argumentsCopy, arguments);
    NSString *message = [[NSString alloc]
        initWithFormat:format arguments:argumentsCopy];
    va_end(argumentsCopy);

    const char *utf8 = message.UTF8String;
    if(utf8) fprintf(stderr, "%s\n", utf8);
    [message release];
}

void NSLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSLogv(format, arguments);
    va_end(arguments);
}

/*
 * Keep the handler in the ARM32 process. Passing this function pointer to
 * native Foundation would make an arm64 exception path branch into guest
 * code directly. The legacy Foundation contract only requires process-wide
 * set/get storage; guest exception machinery can retrieve and invoke it.
 */
static NSUncaughtExceptionHandler *LC32UncaughtExceptionHandler;

NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void) {
    return __atomic_load_n(
        &LC32UncaughtExceptionHandler, __ATOMIC_ACQUIRE);
}

void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler) {
    __atomic_store_n(
        &LC32UncaughtExceptionHandler, handler, __ATOMIC_RELEASE);
}

static pthread_once_t LC32FoundationFunctionsOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32FoundationNSClassFromString;
static uint64_t LC32FoundationNSSelectorFromString;
static uint64_t LC32FoundationNSSearchPath;
static uint64_t LC32FoundationNSTemporaryDirectory;

static void LC32FoundationResolveFunctions(void) {
    LC32FoundationNSClassFromString =
        LC32Dlsym("LC32_Foundation_NSClassFromString", YES);
    LC32FoundationNSSelectorFromString =
        LC32Dlsym("LC32_Foundation_NSSelectorFromString", YES);
    LC32FoundationNSSearchPath = LC32Dlsym(
        "LC32_Foundation_NSSearchPathForDirectoriesInDomains", YES);
    LC32FoundationNSTemporaryDirectory =
        LC32Dlsym("LC32_Foundation_NSTemporaryDirectory", YES);
}

Class NSClassFromString(NSString *aClassName) {
    if(!aClassName) return Nil;
    pthread_once(&LC32FoundationFunctionsOnce,
        LC32FoundationResolveFunctions);
    if(!LC32FoundationNSClassFromString) return Nil;
    return (Class)LC32InvokeHostCRet32(
        LC32FoundationNSClassFromString, aClassName.host_self);
}

SEL NSSelectorFromString(NSString *aSelectorName) {
    if(!aSelectorName) return NULL;
    pthread_once(&LC32FoundationFunctionsOnce,
        LC32FoundationResolveFunctions);
    if(!LC32FoundationNSSelectorFromString) return NULL;
    return (SEL)LC32InvokeHostCRet32(
        LC32FoundationNSSelectorFromString, aSelectorName.host_self);
}

NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(
        NSSearchPathDirectory directory,
        NSSearchPathDomainMask domainMask,
        BOOL expandTilde) {
    pthread_once(&LC32FoundationFunctionsOnce,
        LC32FoundationResolveFunctions);
    if(!LC32FoundationNSSearchPath) return nil;
    return (NSArray<NSString *> *)LC32InvokeHostCRet32(
        LC32FoundationNSSearchPath, (uint32_t)directory,
        (uint32_t)domainMask, (uint32_t)expandTilde);
}

NSString *NSStringFromClass(Class aClass) {
    return @(class_getName(aClass));
}

NSString *NSStringFromSelector(SEL aSelector) {
    if(!aSelector) return nil;
    const char *name = sel_getName(aSelector);
    return name ? [NSString stringWithUTF8String:name] : nil;
}

NSString *NSStringFromProtocol(Protocol *protocol) {
    if(!protocol) return nil;
    const char *name = protocol_getName(protocol);
    return name ? [NSString stringWithUTF8String:name] : nil;
}

id NSAllocateObject(Class aClass, NSUInteger extraBytes, NSZone *zone) {
    (void)zone;
    return aClass ? class_createInstance(aClass, extraBytes) : nil;
}

static uintptr_t LC32DefaultMallocZoneStorage;

NSZone *NSDefaultMallocZone(void) {
    /* Preserve the legacy non-null identity; allocation itself ignores it. */
    return (NSZone *)&LC32DefaultMallocZoneStorage;
}

NSZone *NSZoneFromPointer(void *pointer) {
    (void)pointer;
    return NSDefaultMallocZone();
}

NSString *NSTemporaryDirectory() {
    pthread_once(&LC32FoundationFunctionsOnce,
        LC32FoundationResolveFunctions);
    if(!LC32FoundationNSTemporaryDirectory) return nil;
    return (NSString *)LC32InvokeHostCRet32(
        LC32FoundationNSTemporaryDirectory);
}
