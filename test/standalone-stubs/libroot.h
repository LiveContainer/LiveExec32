#pragma once
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define JBROOT_PATH_CSTRING(path) getenv("LC32_TEST_INSTALLED_FRAMEWORKS")
static inline const char *libroot_dyn_jbrootpath(const char *path, char *output) {
    (void)path;
    const char *installed = getenv("LC32_TEST_INSTALLED_LAUNCHER");
    if(!installed || strlen(installed) >= PATH_MAX) return NULL;
    strcpy(output, installed);
    return output;
}
