#import <Foundation/Foundation.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSPort *ports[] = {[NSPort port], [NSMachPort port],
            [[[NSPort alloc] init] autorelease], [[[NSMachPort alloc] init] autorelease]};
        int failures = 0;
        for(unsigned i = 0; i < 4; ++i) {
            NSPort *port = ports[i];
            BOOL valid = port && port.valid;
            printf("foundation-port-create-%u: %s\n", i, valid ? "PASS" : "FAIL");
            failures += !valid;
            if(valid) {
                NSRunLoop *loop = [NSRunLoop currentRunLoop];
                [loop addPort:port forMode:NSDefaultRunLoopMode];
                [loop removePort:port forMode:NSDefaultRunLoopMode];
                [port invalidate];
                printf("foundation-port-invalidate-%u: %s\n", i, !port.valid ? "PASS" : "FAIL");
                failures += port.valid;
            }
        }
        return failures ? 1 : 0;
    }
}
