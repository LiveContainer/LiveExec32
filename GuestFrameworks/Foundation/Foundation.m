#import <Foundation/Foundation+LC32.h>

#include <pthread.h>

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
NSString * const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
NSString * const NSUserDefaultsDidChangeNotification =
    @"NSUserDefaultsDidChangeNotification";

@implementation NSPlaceholderString : NSString
@end

@implementation NSTaggedPointerString : NSString
@end

void NSLog(NSString *format, ...) {
    printf("FIXME: NSLog called but unimplemented!\n");
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

NSString *NSTemporaryDirectory() {
    pthread_once(&LC32FoundationFunctionsOnce,
        LC32FoundationResolveFunctions);
    if(!LC32FoundationNSTemporaryDirectory) return nil;
    return (NSString *)LC32InvokeHostCRet32(
        LC32FoundationNSTemporaryDirectory);
}
