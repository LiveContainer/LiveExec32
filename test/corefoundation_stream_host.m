#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
        CFSTR("127.0.0.1"), 1, &readStream, &writeStream);
    check("socket-host-read-created", readStream != NULL);
    check("socket-host-write-created", writeStream != NULL);
    if(readStream) CFRelease(readStream);
    if(writeStream) CFRelease(writeStream);

    readStream = NULL;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
        CFSTR("localhost"), 1, &readStream, NULL);
    check("socket-host-read-only-created", readStream != NULL);
    if(readStream) CFRelease(readStream);

    writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
        CFSTR("localhost"), 1, NULL, &writeStream);
    check("socket-host-write-only-created", writeStream != NULL);
    if(writeStream) CFRelease(writeStream);

    readStream = (CFReadStreamRef)(uintptr_t)1;
    writeStream = (CFWriteStreamRef)(uintptr_t)1;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
        NULL, 1, &readStream, &writeStream);
    check("socket-host-null-host-clears-read", readStream == NULL);
    check("socket-host-null-host-clears-write", writeStream == NULL);

    CFStreamCreatePairWithSocketToHost(
        kCFAllocatorDefault, CFSTR("localhost"), 1, NULL, NULL);
    check("socket-host-null-outputs", YES);

    [pool drain];
    return failures ? 1 : 0;
}
