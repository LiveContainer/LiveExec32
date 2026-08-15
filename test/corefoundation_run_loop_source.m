#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdio.h>

static int failures;
static int unexpectedReleases;
static int unexpectedPerforms;
static CFRunLoopSourceContext *contextBeingRetained;

typedef struct {
    int retains;
    int releases;
    int performs;
    Boolean sawRetainedInfo;
} SourceInfo;

static SourceInfo originalInfo;
static SourceInfo retainedInfo;

static void check(const char *name, Boolean condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void unexpectedRelease(const void *rawInfo) {
    (void)rawInfo;
    unexpectedReleases++;
}

static void unexpectedPerform(void *rawInfo) {
    (void)rawInfo;
    unexpectedPerforms++;
}

static const void *retainSourceInfo(const void *rawInfo) {
    SourceInfo *info = (SourceInfo *)rawInfo;
    info->retains++;
    if(contextBeingRetained) {
        /* Creation must snapshot the whole context before retain runs. */
        contextBeingRetained->release = unexpectedRelease;
        contextBeingRetained->copyDescription = NULL;
        contextBeingRetained->perform = unexpectedPerform;
        contextBeingRetained = NULL;
    }
    return &retainedInfo;
}

static void releaseSourceInfo(const void *rawInfo) {
    if(rawInfo == &retainedInfo) {
        retainedInfo.releases++;
    } else {
        unexpectedReleases++;
    }
}

static CFStringRef copySourceInfoDescription(const void *rawInfo) {
    (void)rawInfo;
    return CFStringCreateCopy(kCFAllocatorDefault,
                              CFSTR("run-loop-source-context"));
}

static void performSourceInfo(void *rawInfo) {
    retainedInfo.performs++;
    retainedInfo.sawRetainedInfo |= rawInfo == &retainedInfo;
}

typedef struct {
    int retains;
} RejectedInfo;

static const void *retainRejectedInfo(const void *rawInfo) {
    ((RejectedInfo *)rawInfo)->retains++;
    return rawInfo;
}

static Boolean unsupportedEqual(const void *left, const void *right) {
    return left == right;
}

static CFHashCode unsupportedHash(const void *rawInfo) {
    return (CFHashCode)(uintptr_t)rawInfo;
}

static void unsupportedSchedule(void *rawInfo, CFRunLoopRef runLoop,
                                CFRunLoopMode mode) {
    (void)rawInfo;
    (void)runLoop;
    (void)mode;
}

static void unsupportedCancel(void *rawInfo, CFRunLoopRef runLoop,
                              CFRunLoopMode mode) {
    (void)rawInfo;
    (void)runLoop;
    (void)mode;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFRunLoopSourceContext zeroContext = {};
    CFRunLoopSourceRef zeroSource = CFRunLoopSourceCreate(
        kCFAllocatorDefault, INT32_MIN, &zeroContext);
    check("all-zero-context", zeroSource != NULL);
    if(zeroSource) {
        CFRunLoopSourceInvalidate(zeroSource);
        CFRelease(zeroSource);
    }

    CFRunLoopSourceContext context = {
        0,
        &originalInfo,
        retainSourceInfo,
        releaseSourceInfo,
        copySourceInfoDescription,
        NULL,
        NULL,
        NULL,
        NULL,
        performSourceInfo,
    };
    contextBeingRetained = &context;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(
        kCFAllocatorDefault, -7654321, &context);
    check("perform-source-create", source != NULL);
    check("context-retained-once",
        originalInfo.retains == 1 && retainedInfo.releases == 0);
    check("context-snapshotted-before-retain",
        contextBeingRetained == NULL &&
        context.release == unexpectedRelease &&
        context.perform == unexpectedPerform);

    if(source) {
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);
        CFRunLoopSourceSignal(source);
        const CFRunLoopRunResult result = CFRunLoopRunInMode(
            kCFRunLoopDefaultMode, 1.0, true);
        check("guest-perform-callback",
            result == kCFRunLoopRunHandledSource &&
            retainedInfo.performs == 1 &&
            retainedInfo.sawRetainedInfo &&
            unexpectedPerforms == 0);
        CFRunLoopRemoveSource(runLoop, source, kCFRunLoopDefaultMode);
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
    }
    check("context-released-once",
        retainedInfo.releases == 1 && unexpectedReleases == 0);

    RejectedInfo rejectedInfo = {};
    CFRunLoopSourceContext rejected = {};
    rejected.info = &rejectedInfo;
    rejected.retain = retainRejectedInfo;
    rejected.perform = performSourceInfo;

    rejected.version = 1;
    check("reject-context-version",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &rejected) == NULL &&
        rejectedInfo.retains == 0);
    rejected.version = 0;

    rejected.equal = unsupportedEqual;
    check("reject-equal",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &rejected) == NULL &&
        rejectedInfo.retains == 0);
    rejected.equal = NULL;
    rejected.hash = unsupportedHash;
    check("reject-hash",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &rejected) == NULL &&
        rejectedInfo.retains == 0);
    rejected.hash = NULL;
    rejected.schedule = unsupportedSchedule;
    check("reject-schedule",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &rejected) == NULL &&
        rejectedInfo.retains == 0);
    rejected.schedule = NULL;
    rejected.cancel = unsupportedCancel;
    check("reject-cancel",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &rejected) == NULL &&
        rejectedInfo.retains == 0);
    check("reject-null-context",
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, NULL) == NULL);

    [pool drain];
    return failures != 0;
}
