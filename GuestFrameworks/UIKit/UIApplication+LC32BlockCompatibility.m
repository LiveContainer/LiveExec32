#import <LC32/LC32.h>
#import <UIKit/UIKit.h>

#include <pthread.h>

static pthread_mutex_t LC32BackgroundTaskMutex = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet *LC32BackgroundTasks;

static UIBackgroundTaskIdentifier LC32BeginBackgroundTask(
        UIApplication *application, NSString *name, void (^handler)(void)) {
    __block UIBackgroundTaskIdentifier identifier = UIBackgroundTaskInvalid;
    void (^typedHandler)(void) = ^{
        if(handler) handler();
        /* Some old analytics clients only log expiration. Release their
         * expired assertion so modern iOS can suspend, not kill, the guest.
         * endBackgroundTask: consumes the registration, making this a no-op
         * when the client's handler already ended the task itself. */
        [application endBackgroundTask:identifier];
    };

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(&hostCommand,
        @selector(beginBackgroundTaskWithName:expirationHandler:), NO);
    identifier = (UIBackgroundTaskIdentifier)(uint32_t)LC32InvokeHostSelector(
        application.host_self, command, [name host_self],
        [typedHandler host_self], (uint64_t)0);
    if(identifier != UIBackgroundTaskInvalid) {
        pthread_mutex_lock(&LC32BackgroundTaskMutex);
        if(!LC32BackgroundTasks) LC32BackgroundTasks = [NSMutableSet new];
        [LC32BackgroundTasks addObject:@(identifier)];
        pthread_mutex_unlock(&LC32BackgroundTaskMutex);
    }
    return identifier;
}

/*
 * Some legacy Apple LLVM compilers set BLOCK_HAS_SIGNATURE while leaving the
 * descriptor's signature pointer null.  The generic bridge cannot infer an
 * arbitrary callback ABI from that block, but UIApplication defines this one
 * as void(void).  Capture the legacy callback in a compiler-generated wrapper
 * so the bridge sees a complete signature while the guest invokes the original
 * block directly.
 */
@implementation UIApplication (LC32BlockCompatibility)

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
        (void (^)(void))handler {
    return LC32BeginBackgroundTask(self, nil, handler);
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name
        expirationHandler:(void (^)(void))handler {
    return LC32BeginBackgroundTask(self, name, handler);
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)identifier {
    pthread_mutex_lock(&LC32BackgroundTaskMutex);
    const BOOL active = [LC32BackgroundTasks containsObject:@(identifier)];
    [LC32BackgroundTasks removeObject:@(identifier)];
    pthread_mutex_unlock(&LC32BackgroundTaskMutex);
    if(!active) return;

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, command,
        (uint64_t)identifier, (uint64_t)0);
}

@end
