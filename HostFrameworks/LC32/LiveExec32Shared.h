#ifndef LIVEEXEC32_SHARED_H
#define LIVEEXEC32_SHARED_H

#ifdef __cplusplus
extern "C" {
#endif

/** Runs one 32-bit guest process. This entry point owns the process runtime. */
__attribute__((visibility("default")))
int LC32RunGuest(int argc, char *argv[], char *envp[]);

#ifdef __cplusplus
}
#endif

#endif
