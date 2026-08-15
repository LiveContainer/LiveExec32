#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int failures;
static CFReadStreamRef expectedStream;
static CFStreamClientContext *contextBeingRetained;
static int unexpectedReleases;

typedef struct {
    int retains;
    int releases;
    int callbacks;
    CFStreamEventType events;
    Boolean sawExpectedStream;
} ClientInfo;

static void unexpectedReleaseClientInfo(void *rawInfo) {
    (void)rawInfo;
    unexpectedReleases++;
}

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void *retainClientInfo(void *rawInfo) {
    ClientInfo *info = (ClientInfo *)rawInfo;
    info->retains++;
    if(contextBeingRetained) {
        /* CFReadStreamSetClient must have copied the context before invoking
         * retain. Mutating the caller's storage here must not alter the
         * release callback installed with the stream. */
        contextBeingRetained->release = unexpectedReleaseClientInfo;
        contextBeingRetained->copyDescription = NULL;
        contextBeingRetained = NULL;
    }
    return rawInfo;
}

static void releaseClientInfo(void *rawInfo) {
    ClientInfo *info = (ClientInfo *)rawInfo;
    info->releases++;
}

static CFStringRef copyClientInfoDescription(void *rawInfo) {
    (void)rawInfo;
    return CFStringCreateCopy(kCFAllocatorDefault,
                              CFSTR("read-stream-test-context"));
}

static void streamClient(CFReadStreamRef stream,
                         CFStreamEventType eventType, void *rawInfo) {
    ClientInfo *info = (ClientInfo *)rawInfo;
    info->callbacks++;
    info->events |= eventType;
    info->sawExpectedStream |= stream == expectedStream;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSData *data = [@"read-stream-data" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *input = [NSInputStream inputStreamWithData:data];
    CFReadStreamRef stream = (CFReadStreamRef)input;
    expectedStream = stream;

    check("initial-status",
        CFReadStreamGetStatus(stream) == kCFStreamStatusNotOpen);
    check("negative-read-rejected",
        CFReadStreamRead(stream, NULL, -1) == -1);

    ClientInfo info = {};
    CFStreamClientContext context = {
        0,
        &info,
        retainClientInfo,
        releaseClientInfo,
        copyClientInfoDescription,
    };
    contextBeingRetained = &context;
    const CFOptionFlags events =
        kCFStreamEventOpenCompleted |
        kCFStreamEventHasBytesAvailable |
        kCFStreamEventEndEncountered |
        kCFStreamEventErrorOccurred;
    check("set-client",
        CFReadStreamSetClient(stream, events, streamClient, &context));
    check("context-retained", info.retains == 1 && info.releases == 0);

    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFReadStreamScheduleWithRunLoop(
        stream, runLoop, kCFRunLoopDefaultMode);
    check("open", CFReadStreamOpen(stream));
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    UInt8 bytes[64] = {};
    const CFIndex count = CFReadStreamRead(stream, bytes, sizeof(bytes));
    check("read-count", count == (CFIndex)data.length);
    check("read-bytes", count == (CFIndex)data.length &&
        memcmp(bytes, data.bytes, data.length) == 0);
    check("end-of-stream", CFReadStreamRead(stream, bytes, sizeof(bytes)) == 0);
    check("status-query", CFReadStreamGetStatus(stream) != kCFStreamStatusError);

    CFStreamError legacyError = CFReadStreamGetError(stream);
    check("legacy-error", legacyError.domain == 0 && legacyError.error == 0);
    CFErrorRef error = CFReadStreamCopyError(stream);
    check("copy-error", error == NULL);
    if(error) CFRelease(error);

    CFStreamPropertyKey unknownProperty =
        CFSTR("LC32ReadStreamUnknownProperty");
    CFTypeRef property = CFReadStreamCopyProperty(stream, unknownProperty);
    check("copy-property", property == NULL);
    if(property) CFRelease(property);
    check("set-property",
        !CFReadStreamSetProperty(stream, unknownProperty, kCFBooleanTrue));

    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check("client-callback", info.callbacks > 0 && info.sawExpectedStream);

    CFReadStreamUnscheduleFromRunLoop(
        stream, runLoop, kCFRunLoopDefaultMode);
    check("remove-client-null-context",
        CFReadStreamSetClient(stream, events, streamClient, NULL));
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check("context-snapshot-release",
        info.releases == 1 && unexpectedReleases == 0);
    CFReadStreamClose(stream);

    expectedStream = NULL;
    [pool drain];
    return failures != 0;
}
