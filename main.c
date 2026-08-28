#include <dlfcn.h>
#include <libroot.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static bool FormatFrameworkPath(
        char *path, size_t capacity,
        const char *base, const char *name) {
    const int length = snprintf(
        path, capacity, "%s/%s.framework/%s",
        base, name, name);
    return length >= 0 && (size_t)length < capacity;
}

static void *LoadEmbeddedFramework(const char *name, int flags) {
    char rpathFrameworkPath[PATH_MAX];
    if(!FormatFrameworkPath(
            rpathFrameworkPath, sizeof(rpathFrameworkPath),
            "@rpath", name)) {
        fprintf(stderr, "LC32: embedded framework path is too long: %s\n",
            name);
        return NULL;
    }

    void *framework = dlopen(rpathFrameworkPath, flags);
    if(framework != NULL) return framework;

    const char *rpathError = dlerror();
    char rpathErrorCopy[PATH_MAX];
    snprintf(rpathErrorCopy, sizeof(rpathErrorCopy), "%s",
        rpathError ? rpathError : "unknown error");

    const char *installedFrameworksPath =
        JBROOT_PATH_CSTRING("/Applications/LiveExec32.app/Frameworks");
    char installedFrameworkPath[PATH_MAX];
    if(installedFrameworksPath == NULL ||
            !FormatFrameworkPath(
                installedFrameworkPath, sizeof(installedFrameworkPath),
                installedFrameworksPath, name)) {
        fprintf(stderr,
            "LC32: could not load %s: %s; installed path is unavailable\n",
            rpathFrameworkPath, rpathErrorCopy);
        return NULL;
    }

    framework = dlopen(installedFrameworkPath, flags);
    if(framework == NULL) {
        fprintf(stderr,
            "LC32: could not load %s: %s; fallback %s: %s\n",
            rpathFrameworkPath, rpathErrorCopy,
            installedFrameworkPath, dlerror());
    }
    return framework;
}

static void *LoadEntryPoint(void *framework, const char *name) {
    dlerror();
    void *symbol = dlsym(framework, name);
    const char *error = dlerror();
    if(error != NULL) {
        fprintf(stderr, "LC32: could not resolve %s: %s\n", name, error);
        return NULL;
    }
    return symbol;
}

int main(int argc, char *argv[], char *envp[]) {
    if(argc == 1) {
        printf("Usage: %s <path> argv...\n", argv[0]);

        /*
         * SpringBoard launches an application directly from launchd. The
         * Simulator's app parent is not guaranteed to be pid 1, so use the
         * common CoreSimulator launch variables there instead of a compile-
         * time TARGET_OS_SIMULATOR check.
         */
        const bool simulatorLaunch =
            getenv("SIMULATOR_UDID") != NULL ||
            getenv("SIMULATOR_DEVICE_NAME") != NULL;
        if(simulatorLaunch || getppid() == 1) {
            void *framework = LoadEmbeddedFramework(
                "LC32HelpUI", RTLD_NOW | RTLD_LOCAL);
            if(framework == NULL) return 1;

            typedef int (*RunHelpUI)(int, char *[]);
            RunHelpUI runHelpUI = (RunHelpUI)
                LoadEntryPoint(framework, "LC32RunHelpUI");
            if(runHelpUI == NULL) return 1;

            // UIApplicationMain is process-owning; this image must stay loaded.
            return runHelpUI(argc, argv);
        }
        return 1;
    }

    void *framework = LoadEmbeddedFramework(
        "LiveExec32Shared", RTLD_NOW | RTLD_GLOBAL);
    if(framework == NULL) return 1;

    typedef int (*RunGuest)(int, char *[], char *[]);
    RunGuest runGuest = (RunGuest)
        LoadEntryPoint(framework, "LC32RunGuest");
    if(runGuest == NULL) return 1;

    /*
     * LiveExec32Shared owns process-wide hooks and worker state. It is loaded
     * globally for the guest shims' RTLD_DEFAULT symbol lookups and is never
     * unloaded during the process lifetime.
     */
    return runGuest(argc, argv, envp);
}
