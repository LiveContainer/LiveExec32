#import <Foundation/Foundation.h>

#include "crash_exception.h"

extern "C" __attribute__((cold, noreturn))
void abort_with_reason(
    uint32_t reasonNamespace, uint64_t reasonCode,
    const char *reasonString, uint64_t reasonFlags);

static constexpr size_t LC32GuestCrashExceptionReportPrefixMax = 64 * 1024;
static NSString *const LC32GuestCrashExceptionName =
    @"LC32GuestCrashException";
static NSString *const LC32GuestCrashExceptionTruncatedMarker =
    @"\n[remaining guest crash report omitted]";

extern "C" __attribute__((visibility("hidden")))
int LC32IsGuestCrashException(NSException *exception) {
    return [exception.name isEqualToString:LC32GuestCrashExceptionName];
}

extern "C" __attribute__((cold, noreturn, visibility("hidden")))
void LC32ThrowGuestCrashException(
        const char *report, size_t reportLength,
        uint32_t fallbackNamespace, uint64_t fallbackCode,
        const char *fallbackReason) {
    NSException *exception = nil;
    @autoreleasepool {
        @try {
            NSString *reason = nil;
            const size_t reasonLength =
                reportLength < LC32GuestCrashExceptionReportPrefixMax
                    ? reportLength
                    : LC32GuestCrashExceptionReportPrefixMax;
            if (report != nullptr && reasonLength != 0) {
                reason = [[NSString alloc]
                    initWithBytes:report
                           length:reasonLength
                         encoding:NSUTF8StringEncoding];
                if (reason == nil) {
                    /* Guest paths and assertion text are byte strings and
                     * need not be valid UTF-8. Preserve every byte in the
                     * fatal diagnostic instead of losing the exception. */
                    reason = [[NSString alloc]
                        initWithBytes:report
                               length:reasonLength
                             encoding:NSISOLatin1StringEncoding];
                }
            }
            if (reason == nil) {
                reason = @"LiveExec32 guest process crashed";
            }
            if (reportLength > reasonLength) {
                reason = [reason stringByAppendingString:
                    LC32GuestCrashExceptionTruncatedMarker];
            }

            exception = [NSException
                exceptionWithName:LC32GuestCrashExceptionName
                             reason:reason
                           userInfo:nil];
        } @catch (__unused NSException *constructionException) {
            exception = nil;
        }

        /* Keep the fatal throw outside the construction @try so its own
         * NSException is not mistaken for an allocation/conversion error. */
        if (exception != nil) {
            @throw exception;
        }
    }

    /* Allocation failure should not turn a fatal guest crash into a return
     * through the JIT. Preserve the previous kernel termination fallback. */
    abort_with_reason(
        fallbackNamespace, fallbackCode,
        fallbackReason != nullptr ? fallbackReason :
            "LiveExec32 guest process crashed",
        0);
}
