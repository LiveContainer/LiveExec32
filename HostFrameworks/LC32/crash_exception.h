#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __OBJC__
@class NSException;
#endif

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((cold, noreturn, visibility("hidden")))
void LC32ThrowGuestCrashException(
    const char *report, size_t reportLength,
    uint32_t fallbackNamespace, uint64_t fallbackCode,
    const char *fallbackReason);

#ifdef __OBJC__
__attribute__((visibility("hidden")))
int LC32IsGuestCrashException(NSException *exception);
#endif

#ifdef __cplusplus
}
#endif
