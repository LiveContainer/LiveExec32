#ifndef LC32_FAT_MACH_O_H
#define LC32_FAT_MACH_O_H

#include <stddef.h>

typedef enum {
    LC32MachOInjectionFailed = -1,
    LC32MachOInjectionNotApplicable = 0,
    LC32MachOInjectionSucceeded = 1,
} LC32MachOInjectionResult;

/*
 * Atomically adds the arm64 executable slice from shimPath to an ARM32-only
 * target, signing it for bundleIdentifier. The target is left untouched on
 * every failure before rename(2).
 */
LC32MachOInjectionResult LC32InjectArm64ExecutableSlice(
    const char *targetPath,
    const char *shimPath,
    const char *bundleIdentifier,
    char *errorBuffer,
    size_t errorBufferCapacity);

#endif
