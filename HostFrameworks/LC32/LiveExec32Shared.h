#ifndef LIVEEXEC32_SHARED_H
#define LIVEEXEC32_SHARED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Runs one 32-bit guest process. This entry point owns the process runtime. */
__attribute__((visibility("default")))
int LC32RunGuest(int argc, char *argv[], char *envp[]);

/** Returns the SDK encoded in the guest executable's Mach-O load command. */
__attribute__((visibility("default")))
uint32_t LC32GetGuestExecutableSDKVersion(void);

#ifdef __cplusplus
}
#endif

#endif
