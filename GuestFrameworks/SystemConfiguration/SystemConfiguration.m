#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

#include <string.h>

@interface LC32SCNetworkReachability : NSObject {
@public
    SCNetworkReachabilityCallBack _callback;
    SCNetworkReachabilityContext _context;
    BOOL _scheduled;
}
@end

@implementation LC32SCNetworkReachability

- (void)dealloc {
    if(_context.release && _context.info)
        _context.release(_context.info);
    [super dealloc];
}

@end

static const SCNetworkReachabilityFlags LC32ReachableFlags =
    kSCNetworkReachabilityFlagsReachable;

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(
        CFAllocatorRef allocator, const struct sockaddr *address) {
    (void)allocator;
    if(!address) return NULL;
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

    if(reachability->_context.release && reachability->_context.info)
        reachability->_context.release(reachability->_context.info);
    memset(&reachability->_context, 0, sizeof(reachability->_context));
    reachability->_callback = callback;

    if(callback && context) {
        if(context->version != 0) {
            reachability->_callback = NULL;
            return false;
        }
        reachability->_context = *context;
        if(context->retain && context->info) {
            reachability->_context.info =
                (void *)context->retain(context->info);
        }
    }
    return true;
}

Boolean SCNetworkReachabilityScheduleWithRunLoop(
        SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
        CFStringRef runLoopMode) {
    if(!target || !runLoop || !runLoopMode) return false;
    LC32SCNetworkReachability *reachability =
        (LC32SCNetworkReachability *)target;
    reachability->_scheduled = YES;

    /*
     * The compatibility target has a stable, immediately-known state.
     * Deliver the initial notification synchronously; Flappy's Reachability
     * helper only uses it to update its cached online/offline flag.
     */
    if(reachability->_callback) {
        [(id)target retain];
        reachability->_callback(target, LC32ReachableFlags,
                                reachability->_context.info);
        [(id)target release];
    }
    return true;
}

Boolean SCNetworkReachabilityUnscheduleFromRunLoop(
        SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
        CFStringRef runLoopMode) {
    if(!target || !runLoop || !runLoopMode) return false;
    ((LC32SCNetworkReachability *)target)->_scheduled = NO;
    return true;
}
