#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdio.h>

static unsigned failures;
static void check(const char *name, BOOL passed) {
    printf("invocation-block-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

__attribute__((noinline))
static NSInvocation *retainedInvocation(NSMutableArray *results, int marker) {
    NSInvocation *call = nil;
    @autoreleasepool {
        SEL selector = @selector(blockOperationWithBlock:);
        call = [[NSInvocation invocationWithMethodSignature:
            [NSBlockOperation methodSignatureForSelector:selector]] retain];
        call.target = [NSBlockOperation class];
        call.selector = selector;
        void (^block)(void) = ^{ [results addObject:@(marker)]; };
        [call setArgument:&block atIndex:2];
        [call retainArguments];
    }
    return call;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSMutableArray *results = [NSMutableArray new];
        NSInvocation *first = retainedInvocation(results, 11);
        NSInvocation *second = retainedInvocation(results, 22);
        // Both native invocations must keep independent copies after the
        // conversion pool and original guest stack frame have gone away.
        [first invoke];
        [second invoke];
        NSBlockOperation *operation = nil;
        [first getReturnValue:&operation];
        [operation start];
        [second getReturnValue:&operation];
        [operation start];
        check("retained-captures", [results isEqual:@[@11, @22]]);

        struct {
            uint32_t before;
            void (^block)(void);
            uint32_t after;
        } output = {0x12345678, nil, 0x87654321};
        [first getArgument:&output.block atIndex:2];
        if(output.block) output.block();
        check("argument-roundtrip", [results isEqual:@[@11, @22, @11]]);
        check("argument-32bit-canaries",
            output.before == 0x12345678 && output.after == 0x87654321);

        NSInvocation *returnOnly = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:"@?8@0:4"]];
        void (^block)(void) = ^{ [results addObject:@33]; };
        [returnOnly setReturnValue:&block];
        output.block = nil;
        [returnOnly getReturnValue:&output.block];
        if(output.block) output.block();
        check("return-roundtrip", [results isEqual:@[@11, @22, @11, @33]]);
        check("return-32bit-canaries",
            output.before == 0x12345678 && output.after == 0x87654321);

        block = nil;
        [first setArgument:&block atIndex:2];
        [first getArgument:&output.block atIndex:2];
        check("nil-argument", output.block == nil);
        [returnOnly setReturnValue:&block];
        [returnOnly getReturnValue:&output.block];
        check("nil-return", output.block == nil);
        [first release];
        [second release];
        [results release];
    }
    printf("invocation-block regression: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
