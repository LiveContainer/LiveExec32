#import <Foundation/Foundation.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SystemConfiguration.h>

#include <stdlib.h>
#include <string.h>

static const SCNetworkReachabilityFlags LC32ReachableFlags =
    kSCNetworkReachabilityFlagsReachable;

const CFStringRef kCNNetworkInfoKeyBSSID = CFSTR("BSSID");
const CFStringRef kCNNetworkInfoKeySSID = CFSTR("SSID");
const CFStringRef kCNNetworkInfoKeySSIDData = CFSTR("SSIDDATA");
const CFStringRef kCFErrorDomainSystemConfiguration =
    CFSTR("com.apple.SystemConfiguration");

CFErrorRef SCCopyLastError(void) {
    return CFErrorCreate(kCFAllocatorDefault,
        kCFErrorDomainSystemConfiguration, SCError(), NULL);
}

int SCError(void) {
    return kSCStatusOK;
}

const char *SCErrorString(int status) {
    switch(status) {
        case kSCStatusOK: return "Success";
        case kSCStatusFailed: return "Non-specific failure";
        case kSCStatusInvalidArgument: return "Invalid argument";
        case kSCStatusAccessError: return "Permission denied";
        case kSCStatusNoKey: return "No such key";
        case kSCStatusKeyExists: return "Key already exists";
        case kSCStatusLocked: return "Lock already held";
        case kSCStatusNeedLock: return "Lock required";
        case kSCStatusNoStoreSession:
            return "Configuration daemon session not active";
        case kSCStatusNoStoreServer:
            return "Configuration daemon not available";
        case kSCStatusNotifierActive: return "Notifier is active";
        case kSCStatusNoPrefsSession: return "Preferences session not active";
        case kSCStatusPrefsBusy: return "Preferences update in progress";
        case kSCStatusNoConfigFile: return "Configuration file not found";
        case kSCStatusNoLink: return "No such link";
        case kSCStatusStale: return "Stale configuration";
        case kSCStatusMaxLink: return "Maximum link count exceeded";
        case kSCStatusReachabilityUnknown: return "Reachability unknown";
        case kSCStatusConnectionNoService:
            return "Network service not available";
        case kSCStatusConnectionIgnore:
            return "Network connection information not available";
        default: return "Unknown SystemConfiguration status";
    }
}

Boolean CNSetSupportedSSIDs(CFArrayRef ssidArray) {
    (void)ssidArray;
    return false;
}

Boolean CNMarkPortalOnline(CFStringRef interfaceName) {
    (void)interfaceName;
    return false;
}

Boolean CNMarkPortalOffline(CFStringRef interfaceName) {
    (void)interfaceName;
    return false;
}

CFArrayRef CNCopySupportedInterfaces(void) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0,
                         &kCFTypeArrayCallBacks);
}

CFDictionaryRef CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    (void)interfaceName;
    return NULL;
}

typedef struct LC32SCNetworkReachabilityRegistration {
    CFRunLoopRef runLoop;
    CFRunLoopMode mode;
    struct LC32SCNetworkReachabilityRegistration *next;
} LC32SCNetworkReachabilityRegistration;

@interface LC32SCNetworkReachability : NSObject {
@public
    SCNetworkReachabilityCallBack _callback;
    SCNetworkReachabilityContext _context;
    CFRunLoopSourceRef _source;
    LC32SCNetworkReachabilityRegistration *_registrations;
    BOOL _scheduled;
    BOOL _initialCallbackPending;
}
- (void)lc32_deliverInitialReachability;
@end

@implementation LC32SCNetworkReachability

- (void)lc32_deliverInitialReachability {
    _initialCallbackPending = NO;
    if(!_scheduled || !_callback) return;

    /*
     * The callback may unschedule the last run-loop source or replace its
     * context. Keep both the reachability object and a retained context
     * snapshot alive until that callback returns.
     */
    [self retain];
    SCNetworkReachabilityCallBack callback = _callback;
    const void *info = _context.info;
    CFAllocatorRetainCallBack retainInfo = _context.retain;
    CFAllocatorReleaseCallBack releaseInfo = _context.release;
    if(retainInfo && info) info = retainInfo(info);
    callback((SCNetworkReachabilityRef)self, LC32ReachableFlags,
             (void *)info);
    if(releaseInfo && info) releaseInfo(info);
    [self release];
}

- (void)dealloc {
    CFRunLoopSourceRef source = _source;
    _source = NULL;
    while(_registrations) {
        LC32SCNetworkReachabilityRegistration *registration =
            _registrations;
        _registrations = registration->next;
        if(source) {
            CFRunLoopRemoveSource(registration->runLoop, source,
                                  registration->mode);
        }
        CFRelease(registration->runLoop);
        CFRelease(registration->mode);
        free(registration);
    }
    if(source) {
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
    }
    if(_context.release && _context.info)
        _context.release(_context.info);
    [super dealloc];
}

@end

static void LC32SCNetworkReachabilitySourcePerform(void *info) {
    [(LC32SCNetworkReachability *)info lc32_deliverInitialReachability];
}

static LC32SCNetworkReachabilityRegistration *
LC32SCNetworkReachabilityFindRegistration(
        LC32SCNetworkReachability *reachability,
        CFRunLoopRef runLoop, CFRunLoopMode mode) {
    for(LC32SCNetworkReachabilityRegistration *registration =
            reachability->_registrations; registration;
            registration = registration->next) {
        if(registration->runLoop == runLoop &&
           (registration->mode == mode ||
            CFEqual(registration->mode, mode))) {
            return registration;
        }
    }
    return NULL;
}

static void LC32SCNetworkReachabilitySignalInitial(
        LC32SCNetworkReachability *reachability) {
    if(!reachability->_callback || !reachability->_source ||
       !reachability->_registrations ||
       reachability->_initialCallbackPending) {
        return;
    }
    reachability->_initialCallbackPending = YES;
    CFRunLoopSourceSignal(reachability->_source);
    for(LC32SCNetworkReachabilityRegistration *registration =
            reachability->_registrations; registration;
            registration = registration->next) {
        CFRunLoopWakeUp(registration->runLoop);
    }
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(
        CFAllocatorRef allocator, const struct sockaddr *address) {
    (void)allocator;
    if(!address) return NULL;
    return (SCNetworkReachabilityRef)
        [[LC32SCNetworkReachability alloc] init];
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddressPair(
        CFAllocatorRef allocator, const struct sockaddr *localAddress,
        const struct sockaddr *remoteAddress) {
    (void)allocator;
    if(!localAddress && !remoteAddress) return NULL;
    return (SCNetworkReachabilityRef)
        [[LC32SCNetworkReachability alloc] init];
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(
        CFAllocatorRef allocator, const char *nodeName) {
    (void)allocator;
    if(!nodeName) return NULL;
    return (SCNetworkReachabilityRef)
        [[LC32SCNetworkReachability alloc] init];
}

CFTypeID SCNetworkReachabilityGetTypeID(void) {
    // CFTypeID is opaque; callers only require a stable, nonzero identity for
    // the process-local compatibility object.
    return (CFTypeID)UINT32_C(0x4c433252);
}

Boolean SCNetworkReachabilityGetFlags(
        SCNetworkReachabilityRef target,
        SCNetworkReachabilityFlags *flags) {
    if(!target || !flags) return false;
    *flags = LC32ReachableFlags;
    return true;
}

Boolean SCNetworkReachabilitySetCallback(
        SCNetworkReachabilityRef target,
        SCNetworkReachabilityCallBack callback,
        SCNetworkReachabilityContext *context) {
    if(!target) return false;
    LC32SCNetworkReachability *reachability =
        (LC32SCNetworkReachability *)target;

    SCNetworkReachabilityContext newContext = {};
    if(callback && context) {
        if(context->version != 0) {
            return false;
        }
        newContext = *context;
        if(context->retain && context->info) {
            newContext.info = (void *)context->retain(context->info);
        }
    }

    /* Retain the replacement before releasing the installed context. The
     * caller is allowed to re-register the exact same info pointer after
     * relinquishing its own reference. */
    const SCNetworkReachabilityContext oldContext = reachability->_context;
    reachability->_callback = callback;
    reachability->_context = newContext;
    if(oldContext.release && oldContext.info)
        oldContext.release(oldContext.info);

    if(callback) LC32SCNetworkReachabilitySignalInitial(reachability);
    return true;
}

Boolean SCNetworkReachabilityScheduleWithRunLoop(
        SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
        CFStringRef runLoopMode) {
    if(!target || !runLoop || !runLoopMode) return false;
    LC32SCNetworkReachability *reachability =
        (LC32SCNetworkReachability *)target;
    if(LC32SCNetworkReachabilityFindRegistration(
            reachability, runLoop, runLoopMode)) {
        return true;
    }

    LC32SCNetworkReachabilityRegistration *registration =
        calloc(1, sizeof(*registration));
    if(!registration) return false;
    registration->runLoop = (CFRunLoopRef)CFRetain(runLoop);
    registration->mode = CFRetain(runLoopMode);

    if(!reachability->_source) {
        CFRunLoopSourceContext sourceContext = {
            .version = 0,
            .info = reachability,
            .retain = CFRetain,
            .release = CFRelease,
            .perform = LC32SCNetworkReachabilitySourcePerform,
        };
        reachability->_source = CFRunLoopSourceCreate(
            kCFAllocatorDefault, 0, &sourceContext);
        if(!reachability->_source) {
            CFRelease(registration->runLoop);
            CFRelease(registration->mode);
            free(registration);
            return false;
        }
    }

    registration->next = reachability->_registrations;
    reachability->_registrations = registration;
    reachability->_scheduled = YES;
    CFRunLoopAddSource(runLoop, reachability->_source, runLoopMode);

    /*
     * Native SystemConfiguration delivers reachability changes from the
     * scheduled run loop; it never re-enters the caller before this function
     * returns. Legacy clients may record their registration only after this
     * call, so an inline callback can recursively schedule the same target.
     * Signal a source installed in the caller's exact run-loop mode instead.
     */
    LC32SCNetworkReachabilitySignalInitial(reachability);
    return true;
}

Boolean SCNetworkReachabilityUnscheduleFromRunLoop(
        SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
        CFStringRef runLoopMode) {
    if(!target || !runLoop || !runLoopMode) return false;
    LC32SCNetworkReachability *reachability =
        (LC32SCNetworkReachability *)target;
    LC32SCNetworkReachabilityRegistration **link =
        &reachability->_registrations;
    while(*link) {
        LC32SCNetworkReachabilityRegistration *registration = *link;
        if(registration->runLoop != runLoop ||
           (registration->mode != runLoopMode &&
            !CFEqual(registration->mode, runLoopMode))) {
            link = &registration->next;
            continue;
        }
        CFRunLoopRemoveSource(runLoop, reachability->_source, runLoopMode);
        *link = registration->next;
        CFRelease(registration->runLoop);
        CFRelease(registration->mode);
        free(registration);
        break;
    }

    reachability->_scheduled = reachability->_registrations != NULL;
    if(!reachability->_scheduled && reachability->_source) {
        /* Breaking the source-context retain can release target, so keep the
         * receiver alive until this API call has completely unwound. */
        [reachability retain];
        CFRunLoopSourceRef source = reachability->_source;
        reachability->_source = NULL;
        reachability->_initialCallbackPending = NO;
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
        [reachability release];
    }
    return true;
}
