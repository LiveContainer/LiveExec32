#import <Foundation/Foundation+LC32.h>

#import <objc/message.h>

extern BOOL LC32NSThreadNativeModeEnabled(void);
extern BOOL LC32NSThreadIsCurrentThread(NSThread *thread);
extern uint64_t LC32NSThreadHostThread(NSThread *thread);

static NSArray *LC32CommonRunLoopModes(void) {
    return [NSArray arrayWithObject:NSRunLoopCommonModes];
}

@implementation NSObject (LC32ThreadPerforming)

- (void)performSelector:(SEL)selector
               onThread:(NSThread *)thread
             withObject:(id)object
          waitUntilDone:(BOOL)wait
                  modes:(NSArray<NSString *> *)modes {
    if(!selector || !thread) return;

    /*
     * Keep same-thread delivery tied to a guest request.  Forwarding this
     * case through native -performSelector:onThread: installs a host run-loop
     * source whose target is only a mirror of the guest object.  The delayed
     * performing shim instead uses a host-backed timer which explicitly
     * re-enters the guest to invoke the original selector.  In particular,
     * YTApiaryDeviceAuthenticator queues work back to its current thread with
     * waitUntilDone:NO; the native NSThread source never re-entered the guest,
     * so performQueuedRequest: was never run.
     */
    if(LC32NSThreadIsCurrentThread(thread)) {
        if(wait) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                self, selector, object);
        } else {
            [self performSelector:selector withObject:object afterDelay:0
                          inModes:modes];
        }
        return;
    }

    if(!LC32NSThreadNativeModeEnabled()) {
        CRSetCrashLogMessage(
            "cross-thread performSelector requires native guest threads");
        return;
    }

    const uint64_t hostThread = LC32NSThreadHostThread(thread);
    if(!hostThread) {
        CRSetCrashLogMessage(
            "performSelector target NSThread has no native thread");
        return;
    }

    static uint64_t hostSelector __attribute__((aligned(8)));
    LC32InvokeHostSelector(
        self.host_self,
        LC32CachedHostSelector(&hostSelector, _cmd, NO),
        LC32GetHostSelector(selector), hostThread, [object host_self],
        (uint64_t)wait, [modes host_self], (uint64_t)0);
}

- (void)performSelector:(SEL)selector
               onThread:(NSThread *)thread
             withObject:(id)object
          waitUntilDone:(BOOL)wait {
    [self performSelector:selector onThread:thread withObject:object
            waitUntilDone:wait modes:LC32CommonRunLoopModes()];
}

- (void)performSelectorOnMainThread:(SEL)selector
                         withObject:(id)object
                      waitUntilDone:(BOOL)wait
                              modes:(NSArray<NSString *> *)modes {
    [self performSelector:selector onThread:[NSThread mainThread]
               withObject:object waitUntilDone:wait modes:modes];
}

- (void)performSelectorOnMainThread:(SEL)selector
                         withObject:(id)object
                      waitUntilDone:(BOOL)wait {
    [self performSelector:selector onThread:[NSThread mainThread]
               withObject:object waitUntilDone:wait
                    modes:LC32CommonRunLoopModes()];
}

- (void)performSelectorInBackground:(SEL)selector withObject:(id)object {
    [NSThread detachNewThreadSelector:selector toTarget:self withObject:object];
}

@end
