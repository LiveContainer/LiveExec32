#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int failures;
static CFWriteStreamRef expectedStream;
static CFStreamClientContext *contextBeingRetained;
static int unexpectedReleases;

typedef struct {
    int retains;
    int releases;
    int callbacks;
    CFStreamEventType events;
    Boolean sawExpectedStream;
} ClientInfo;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void unexpectedReleaseClientInfo(void *rawInfo) {
    (void)rawInfo;
    unexpectedReleases++;
}

static void *retainClientInfo(void *rawInfo) {
    ClientInfo *info = (ClientInfo *)rawInfo;
    info->retains++;
    if(contextBeingRetained) {
        /* The wrapper must snapshot the version-0 context before retain can
         * mutate caller-owned storage. */
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
                              CFSTR("write-stream-test-context"));
}

static void streamClient(CFWriteStreamRef stream,
                         CFStreamEventType eventType, void *rawInfo) {
    ClientInfo *info = (ClientInfo *)rawInfo;
    info->callbacks++;
    info->events |= eventType;
    info->sawExpectedStream |= stream == expectedStream;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSOutputStream *output = [NSOutputStream outputStreamToMemory];
    CFWriteStreamRef stream = (CFWriteStreamRef)output;
    expectedStream = stream;

    check("initial-status",
        CFWriteStreamGetStatus(stream) == kCFStreamStatusNotOpen);
    check("negative-write-rejected",
        CFWriteStreamWrite(stream, NULL, -1) == -1);
    check("null-buffer-rejected",
        CFWriteStreamWrite(stream, NULL, 1) == -1);
    check("oversized-write-rejected",
        CFWriteStreamWrite(stream, (const UInt8 *)"x",
                           64 * 1024 * 1024 + 1) == -1);

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
        kCFStreamEventCanAcceptBytes |
        kCFStreamEventEndEncountered |
        kCFStreamEventErrorOccurred;
    check("set-client",
        CFWriteStreamSetClient(stream, events, streamClient, &context));
    check("context-retained", info.retains == 1 && info.releases == 0);

    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFWriteStreamScheduleWithRunLoop(
        stream, runLoop, kCFRunLoopDefaultMode);
    check("open", CFWriteStreamOpen(stream));
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    static const UInt8 payload[] = "write-stream-data";
    check("can-accept", CFWriteStreamCanAcceptBytes(stream));
    const CFIndex count = CFWriteStreamWrite(
        stream, payload, sizeof(payload) - 1);
    check("write-count", count == (CFIndex)sizeof(payload) - 1);

    CFDataRef data = (CFDataRef)CFWriteStreamCopyProperty(
        stream, kCFStreamPropertyDataWritten);
    const CFIndex dataLength = data ? CFDataGetLength(data) : 0;
    const UInt8 *dataBytes = data ? CFDataGetBytePtr(data) : NULL;
    check("copy-property-bytes",
        dataLength == (CFIndex)sizeof(payload) - 1 && dataBytes &&
        memcmp(dataBytes, payload, sizeof(payload) - 1) == 0);
    if(data) CFRelease(data);

    CFStreamError legacyError = CFWriteStreamGetError(stream);
    check("legacy-error", legacyError.domain == 0 && legacyError.error == 0);
    CFErrorRef error = CFWriteStreamCopyError(stream);
    check("copy-error", error == NULL);
    if(error) CFRelease(error);

    CFStreamPropertyKey unknownProperty =
        CFSTR("LC32WriteStreamUnknownProperty");
    check("set-property",
        !CFWriteStreamSetProperty(stream, unknownProperty, kCFBooleanTrue));

    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check("client-callback", info.callbacks > 0 && info.sawExpectedStream);

    CFWriteStreamUnscheduleFromRunLoop(
        stream, runLoop, kCFRunLoopDefaultMode);
    check("remove-client-null-context",
        CFWriteStreamSetClient(stream, events, streamClient, NULL));
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check("context-snapshot-release",
        info.releases == 1 && unexpectedReleases == 0);
    CFWriteStreamClose(stream);

    const int socketDescriptor = socket(AF_INET, SOCK_STREAM, 0);
    check("socket-create", socketDescriptor >= 0);
    if(socketDescriptor >= 0) {
        CFReadStreamRef pairedRead = NULL;
        CFWriteStreamRef pairedWrite = NULL;
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketDescriptor,
                                     &pairedRead, &pairedWrite);
        check("socket-pair-created", pairedRead != NULL && pairedWrite != NULL);
        if(pairedRead) {
            check("socket-read-status",
                CFReadStreamGetStatus(pairedRead) == kCFStreamStatusNotOpen);
            CFRelease(pairedRead);
        }
        if(pairedWrite) {
            check("socket-write-status",
                CFWriteStreamGetStatus(pairedWrite) == kCFStreamStatusNotOpen);
            CFRelease(pairedWrite);
        }
        close(socketDescriptor);
    }

    expectedStream = NULL;
    [pool drain];
    return failures != 0;
}
