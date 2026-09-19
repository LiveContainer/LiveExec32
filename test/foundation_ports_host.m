#import <Foundation/Foundation.h>
#import "../HostFrameworks/Foundation/MachPort.h"

extern id objc_initWeakOrNil(id *, id);
extern id objc_loadWeakRetained(id *);
extern void objc_destroyWeak(id *);

static unsigned failures;
static void check(const char *name, BOOL ok) {
    printf("port-peer-%s: %s\n", name, ok ? "PASS" : "FAIL");
    failures += !ok;
}

int main(void) {
    @autoreleasepool {
        NSPort *port = [LC32AllocateMachPortPeer() init];
        check("create", port && port.valid);
        check("guest-class", port.class == NSMachPort.class);
        id slot = nil;
        check("weak-compatible", objc_initWeakOrNil(&slot, port) == port);
        id lease = objc_loadWeakRetained(&slot);
        check("weak-promotion", lease == port);
        [lease release];
        [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
        check("run-loop", [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode beforeDate:[NSDate date]]);
        [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
        NSPort *copy = [port copy];
        check("copy-identity", copy == port);
        [copy release];
        __block unsigned invalidations = 0;
        id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSPortDidBecomeInvalidNotification object:port queue:nil
            usingBlock:^(NSNotification *note) { ++invalidations; }];
        [port invalidate];
        [port invalidate];
        check("invalidate", !port.valid && invalidations == 1);
        [[NSNotificationCenter defaultCenter] removeObserver:token];
        [port release];
        lease = objc_loadWeakRetained(&slot);
        check("deallocation", !lease);
        [lease release];
        objc_destroyWeak(&slot);
    }
    return failures ? 1 : 0;
}
