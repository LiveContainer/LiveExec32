/* Exercise the production helpers without loading device libraries or redirecting
 * the test process's stdout/stderr. Compile as manual-reference-counted ObjC. */
@import Darwin;
@import Foundation;
#include <asl.h>
#include <stdarg.h>
#include <sys/utsname.h>

enum AnswerKind {
    AnswerNull,
    AnswerString,
    AnswerEmptyString,
};

static int failures;
static unsigned checks;
static enum AnswerKind answerKind;
static BOOL unameFails;
static const char *simulatorModel;
static unsigned answerCalls, unameCalls;
static unsigned answerCreates, answerReleases, parentQueries;
static NSMutableArray *capturedLogs;

static void check(const char *label, BOOL condition) {
    ++checks;
    if(!condition) {
        ++failures;
        fprintf(stderr, "FAIL: %s\n", label);
    }
}

#if LC32_TEST_MG_PRESENT
/* Real NSString primitives with observable lifetime for the owned Copy answer. */
@interface LC32TestMarketingName : NSString {
    NSString *_value;
}
- (instancetype)initWithString:(NSString *)value;
@end

@implementation LC32TestMarketingName
- (instancetype)initWithString:(NSString *)value {
    if((self = [super init])) _value = [value copy];
    return self;
}
- (NSUInteger)length { return _value.length; }
- (unichar)characterAtIndex:(NSUInteger)index { return [_value characterAtIndex:index]; }
- (void)dealloc {
    ++answerReleases;
    [_value release];
    [super dealloc];
}
@end
#endif

static int TestUname(struct utsname *info) {
    ++unameCalls;
    if(unameFails) return -1;
    memset(info, 0, sizeof(*info));
    snprintf(info->machine, sizeof(info->machine), "TestMachine42");
    return 0;
}

static char *TestGetenv(const char *name) {
    if(strcmp(name, "SIMULATOR_MODEL_IDENTIFIER") == 0) return (char *)simulatorModel;
    check("constructor must not query logging environment", NO);
    return NULL;
}

static pid_t TestGetppid(void) {
    ++parentQueries;
    return 42;
}

static int TestPrintf(const char *format, ...) __attribute__((format(printf, 1, 2)));
static int TestPrintf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *buffer = NULL;
    int length = vasprintf(&buffer, format, args);
    va_end(args);
    check("printf capture formatting succeeded", length >= 0 && buffer != NULL);
    if(length < 0 || !buffer) return -1;
    NSString *line = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length
        encoding:NSUTF8StringEncoding];
    free(buffer);
    check("printf capture contains valid UTF-8", line != nil);
    check("logging capture is initialized", capturedLogs != nil);
    if(line) [capturedLogs addObject:line];
    [line release];
    return length;
}

#define CONFIG_SHARED_FRAMEWORK_BUNDLE_ID "org.liveexec32.test.missing-framework-bundle"
#define CONFIG_VERSION "9.8.7-test"
#define CONFIG_COMMIT "0123abc"
#define CONFIG_BRANCH "test/logging"
#define MGCopyAnswer LC32TestMGCopyAnswer
#define uname TestUname
#define getenv TestGetenv
#define getppid TestGetppid
#define printf TestPrintf
#pragma clang diagnostic push
/* The unexecuted file-logging path still uses the existing legacy ASL API. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "../HostFrameworks/LC32/log.m"
#pragma clang diagnostic pop
#undef printf
#undef getppid
#undef getenv
#undef uname
#undef MGCopyAnswer

#if LC32_TEST_MG_PRESENT
CFTypeRef LC32TestMGCopyAnswer(CFStringRef question, CFDictionaryRef options) {
    ++answerCalls;
    check("MobileGestalt key and options", CFEqual(question, CFSTR("marketing-name")) && !options);
    if(answerKind == AnswerNull) return NULL;
    NSString *value = answerKind == AnswerString ? @"Test Phone Pro" : @"";
    LC32TestMarketingName *answer = [[LC32TestMarketingName alloc] initWithString:value];
    check("Copy answer allocation", answer != nil);
    ++answerCreates;
    return (CFTypeRef)answer;
}
#endif

static void resetCase(void) {
    check("all prior Copy answers released", answerCreates == answerReleases);
    answerKind = AnswerNull;
    unameFails = NO;
    simulatorModel = NULL;
    answerCalls = unameCalls = 0;
    answerCreates = answerReleases = 0;
    [capturedLogs removeAllObjects];
}

int main(void) {
    @autoreleasepool {
        capturedLogs = [NSMutableArray new];
        check("automatic constructor stopped at CLI guard", parentQueries == 1 && answerCalls == 0);
        unsigned initialParentQueries = parentQueries;
        logToFileIfNeeded();
        check("explicit CLI guard leaves logging inactive", parentQueries == initialParentQueries + 1 &&
            answerCalls == 0 && capturedLogs.count == 0);

#if LC32_TEST_MG_PRESENT
        resetCase();
        check("null answer uses machine", [LC32DeviceModel() isEqualToString:@"TestMachine42"]);
        check("null answer has no release", answerCalls == 1 && answerCreates == 0 && answerReleases == 0 && unameCalls == 1);

        resetCase();
        answerKind = AnswerEmptyString;
        @autoreleasepool {
            check("empty string uses machine", [LC32DeviceModel() isEqualToString:@"TestMachine42"]);
            check("empty Copy answer lives until pool drains", answerCreates == 1 && answerReleases == 0);
        }
        check("empty Copy answer released once", answerReleases == 1);

        resetCase();
        answerKind = AnswerString;
        NSString *name;
        @autoreleasepool {
            name = [LC32DeviceModel() retain];
            check("valid Copy answer lives until pool drains", answerCreates == 1 && answerReleases == 0);
        }
        check("retained model survives inner pool", [name isEqualToString:@"Test Phone Pro"] && answerReleases == 0);
        check("valid marketing name avoids uname", answerCalls == 1 && unameCalls == 0);
        [name release];
        check("Copy answer ownership balances after caller release", answerReleases == 1);

#else
        resetCase();
        check("missing weak symbol resolves to null", LC32TestMGCopyAnswer == NULL);
        check("missing MobileGestalt uses machine", [LC32DeviceModel() isEqualToString:@"TestMachine42"]);
        check("missing symbol does not call", answerCalls == 0 && unameCalls == 1);
#endif

        resetCase();
        simulatorModel = "iPhone99,1";
        check("simulator identifier takes precedence", [LC32DeviceModel() isEqualToString:@"Simulator (iPhone99,1)"]);
        check("simulator avoids MobileGestalt and uname", answerCalls == 0 && unameCalls == 0);

        resetCase();
        simulatorModel = "";
        check("empty simulator identifier falls back", [LC32DeviceModel() isEqualToString:@"TestMachine42"]);

        resetCase();
        unameFails = YES;
        check("missing machine has unknown label", [LC32DeviceModel() isEqualToString:@"unknown"]);

        resetCase();
        simulatorModel = "iPad99,2";
        LC32LogBuildAndDeviceInfo();
        check("metadata emits exactly two lines", capturedLogs.count == 2);
        if(capturedLogs.count == 2) {
            check("build metadata and missing-bundle version fallback", [capturedLogs[0]
                isEqualToString:@"LiveExec32 version: 9.8.7-test commit 0123abc (test/logging)\n"]);
            NSString *expectedDevice = [NSString stringWithFormat:@"Device: Simulator (iPad99,2), %@\n",
                NSProcessInfo.processInfo.operatingSystemVersionString];
            check("device metadata includes model and OS", [capturedLogs[1] isEqualToString:expectedDevice]);
        }
        resetCase();
        [capturedLogs release];
        capturedLogs = nil;
        printf("%s: build info logging, MobileGestalt %s (%u checks)\n",
            failures ? "FAIL" : "PASS", LC32_TEST_MG_PRESENT ? "present" : "missing", checks);
    }
    return failures ? 1 : 0;
}
