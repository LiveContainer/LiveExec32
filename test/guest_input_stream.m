#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

@interface NSObject (LC32GuestInputStreamTest)
- (uint64_t)host_self;
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t receiver,
    uint64_t selector, ...);
extern id LC32HostToGuestObject(uint64_t object);

static unsigned failures;
static const uint8_t payload[] = {0x00, 0xff, 0x41, 0x00, 0x80, 0x42};

static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

typedef enum {
    ReadPayload,
    ReadEOF,
    ReadError,
    ReadOversizedResult,
    ReadInvalidNegative,
    ReadZeroLength,
} ReadMode;

typedef struct {
    ReadMode mode;
    NSUInteger calls;
    NSUInteger capacity;
    BOOL sawBuffer;
} ReadState;

@protocol LC32InputStreamFixture <NSObject>
- (ReadState *)readState;
@end

@interface LC32GuestInputStream : NSInputStream <LC32InputStreamFixture> {
@public
    ReadState state;
}
@end

static NSInteger readBytes(ReadState *stream,
                          uint8_t *buffer, NSUInteger length) {
    stream->calls++;
    stream->capacity = length;
    stream->sawBuffer = buffer != NULL;
    switch(stream->mode) {
        case ReadEOF:
            if(length) buffer[0] = 0x33;
            return 0;
        case ReadError:
            if(length) buffer[0] = 0x33;
            return -1;
        case ReadOversizedResult:
            return (NSInteger)length + 1;
        case ReadInvalidNegative:
            return -2;
        case ReadZeroLength:
            return length ? -1 : 0;
        case ReadPayload: {
            const NSUInteger count = MIN(length, sizeof(payload));
            memcpy(buffer, payload, count);
            return (NSInteger)count;
        }
    }
    return -1;
}

@implementation LC32GuestInputStream
- (ReadState *)readState { return &state; }
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)length {
    return readBytes(&state, buffer, length);
}
@end

// LLVM GCC-era subclasses used char * (encoded '*') for the same primitive.
// Its embedded NULs must not trigger the ordinary C-string bridge.
@interface LC32GuestCharInputStream : LC32GuestInputStream
@end

@implementation LC32GuestCharInputStream
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"
- (NSInteger)read:(char *)buffer maxLength:(NSUInteger)length {
    return readBytes(&state, (uint8_t *)buffer, length);
}
#pragma clang diagnostic pop
@end

// No NSInputStream superclass or protocol declaration supplies the native
// read signature. Keep separate ivars, and pass their address explicitly to
// the common test helper rather than casting this object to another layout.
@interface LC32GuestDuckInputStream : NSObject <LC32InputStreamFixture> {
    ReadState state;
}
- (NSInteger)read:(char *)buffer maxLength:(NSUInteger)length;
@end

@implementation LC32GuestDuckInputStream
- (ReadState *)readState { return &state; }
- (NSInteger)read:(char *)buffer maxLength:(NSUInteger)length {
    return readBytes(&state, (uint8_t *)buffer, length);
}
@end

static uint64_t nativeBytes(NSData *data, BOOL writable) {
    return LC32InvokeHostSelector([data host_self],
        LC32GetHostSelector(writable ? @selector(mutableBytes) :
            @selector(bytes)), (uint64_t)0);
}

static void setNativeArgument(NSInvocation *invocation,
                              const void *bytes, NSUInteger length,
                              NSUInteger index) {
    NSData *storage = [NSData dataWithBytes:bytes length:length];
    // NSInvocation copies the already-native argument representation here.
    // A regular guest setArgument: would intentionally translate its pointee
    // using ARM32 sizes; this test needs a real 64-bit caller-owned pointer.
    LC32InvokeHostSelector([invocation host_self],
        LC32GetHostSelector(@selector(setArgument:atIndex:)),
        nativeBytes(storage, NO), (uint64_t)index, (uint64_t)0);
}

static NSInvocation *readInvocation(id stream) {
    const uint64_t signature = LC32InvokeHostSelector([stream host_self],
        LC32GetHostSelector(@selector(methodSignatureForSelector:)),
        LC32GetHostSelector(@selector(read:maxLength:)), (uint64_t)0);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
        LC32HostToGuestObject(signature)];
    [invocation setTarget:stream];
    [invocation setSelector:@selector(read:maxLength:)];
    return invocation;
}

static int64_t invokeRead(NSInvocation *invocation, NSMutableData *output,
                         uint64_t maxLength, BOOL nullBuffer) {
    const uint64_t pointer = nullBuffer ? 0 : nativeBytes(output, YES);
    setNativeArgument(invocation, &pointer, sizeof(pointer), 2);
    setNativeArgument(invocation, &maxLength, sizeof(maxLength), 3);
    [invocation invoke];

    // The native stream signature uses q, so the typed invocation bridge
    // copies its full 64-bit result directly into this guest buffer.
    int64_t result = 0;
    [invocation getReturnValue:&result];
    return result;
}

static NSMutableData *sentinelOutput(void) {
    uint8_t bytes[32];
    memset(bytes, 0xa5, sizeof(bytes));
    return [NSMutableData dataWithBytes:bytes length:sizeof(bytes)];
}

static BOOL hasSentinelTail(NSData *data, NSUInteger start) {
    const uint8_t *bytes = [data bytes];
    for(NSUInteger index = start; index < [data length]; index++) {
        if(bytes[index] != 0xa5) return NO;
    }
    return YES;
}

static void testStream(Class cls) {
    id<LC32InputStreamFixture> stream = [[cls alloc] init];
    ReadState *state = [stream readState];
    NSInvocation *invocation = [readInvocation(stream) retain];
    NSMutableData *output = sentinelOutput();
    state->mode = ReadPayload;
    int64_t result = invokeRead(invocation, output, 16, NO);
    check("native-read-binary-payload", result == sizeof(payload) &&
        memcmp([output bytes], payload, sizeof(payload)) == 0 &&
        state->capacity == 16 && state->sawBuffer);
    check("native-read-short-result-preserves-tail",
        hasSentinelTail(output, sizeof(payload)));

    output = sentinelOutput();
    result = invokeRead(invocation, output, 3, NO);
    check("native-read-bounded-small-buffer", result == 3 &&
        memcmp([output bytes], payload, 3) == 0 &&
        hasSentinelTail(output, 3));

    for(ReadMode mode = ReadEOF; mode <= ReadInvalidNegative; mode++) {
        output = sentinelOutput();
        state->mode = mode;
        result = invokeRead(invocation, output, 16, NO);
        check(mode == ReadEOF ? "native-read-eof" :
            mode == ReadError ? "native-read-error-sign-extension" :
            mode == ReadOversizedResult ? "native-read-invalid-count" :
            "native-read-invalid-negative-count",
            result == (mode == ReadEOF ? 0 : -1) &&
            hasSentinelTail(output, 0));
    }

    state->mode = ReadZeroLength;
    output = sentinelOutput();
    result = invokeRead(invocation, output, 0, NO);
    check("native-read-zero-length-preserves-pointer", result == 0 &&
        state->capacity == 0 && state->sawBuffer &&
        hasSentinelTail(output, 0));
    result = invokeRead(invocation, output, 0, YES);
    check("native-read-zero-length-null", result == 0 &&
        state->capacity == 0 && !state->sawBuffer);

    const NSUInteger previousCalls = state->calls;
    result = invokeRead(invocation, output, 1, YES);
    check("native-read-null-output-rejected", result == -1 &&
        state->calls == previousCalls);
    result = invokeRead(invocation, output, UINT64_C(0x100000000), NO);
    check("native-read-wide-length-not-truncated", result == -1 &&
        state->calls == previousCalls && hasSentinelTail(output, 0));
    result = invokeRead(invocation, output, 64u * 1024u * 1024u + 1u, NO);
    check("native-read-allocation-limit", result == -1 &&
        state->calls == previousCalls && hasSentinelTail(output, 0));

    [invocation release];
    [stream release];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    printf("Testing uint8_t * stream override\n");
    testStream([LC32GuestInputStream class]);
    printf("Testing legacy char * stream override\n");
    testStream([LC32GuestCharInputStream class]);
    printf("Testing NSObject duck-typed stream adapter\n");
    testStream([LC32GuestDuckInputStream class]);
    [pool drain];
    return failures ? 1 : 0;
}
