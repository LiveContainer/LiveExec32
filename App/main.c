#include <dlfcn.h>
#include <crt_externs.h>
#include <errno.h>
#include <libroot.h>
#include <limits.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef LC32_JAILBREAK_PACKAGE
extern uint32_t dyld_get_active_platform(void);
#endif

/* Lets future injector versions distinguish and migrate copied launchers. */
__attribute__((used, section("__TEXT,__lc32shim")))
static const char LC32InjectedShimMarker[] =
    "LiveExec32InjectedShim:1";

static bool FormatFrameworkPath(
        char *path, size_t capacity,
        const char *base, const char *name) {
    const int length = snprintf(
        path, capacity, "%s/%s.framework/%s",
        base, name, name);
    return length >= 0 && (size_t)length < capacity;
}

static bool ResolveInstalledFrameworkPath(
        char *path, size_t capacity, const char *name) {
    const char *installedFrameworksPath =
        JBROOT_PATH_CSTRING("/Applications/LiveExec32.app/Frameworks");
    return installedFrameworksPath != NULL &&
        FormatFrameworkPath(path, capacity, installedFrameworksPath, name);
}

static void *LoadInstalledFramework(const char *name, int flags) {
    char installedFrameworkPath[PATH_MAX];
    if(!ResolveInstalledFrameworkPath(
            installedFrameworkPath, sizeof(installedFrameworkPath), name)) {
        return NULL;
    }

    return dlopen(installedFrameworkPath, flags);
}

static void *LoadFrameworkFromSearchPaths(const char *name, int flags) {
    char rpathFrameworkPath[PATH_MAX];
    if(!FormatFrameworkPath(
            rpathFrameworkPath, sizeof(rpathFrameworkPath),
            "@rpath", name)) {
        return NULL;
    }

    return dlopen(rpathFrameworkPath, flags);
}

static void *LoadFramework(const char *name, int flags) {
    dlerror();
    void *framework = LoadFrameworkFromSearchPaths(name, flags);
    if(framework != NULL) return framework;

    const char *searchPathsError = dlerror();
    char searchPathsErrorCopy[PATH_MAX];
    snprintf(searchPathsErrorCopy, sizeof(searchPathsErrorCopy), "%s",
        searchPathsError ? searchPathsError :
        "framework search path is unavailable");

    dlerror();
    framework = LoadInstalledFramework(name, flags);
    if(framework == NULL) {
        const char *installedError = dlerror();
        fprintf(stderr,
            "LC32: could not load %s from framework search paths: %s; "
            "installed fallback: %s\n",
            name, searchPathsErrorCopy,
            installedError ? installedError :
            "installed framework path is unavailable");
    }
    return framework;
}

static void ConfigureDynarmicCodeMemoryMode(void) {
#ifdef LC32_JAILBREAK_PACKAGE
    /*
     * Configure this before loading LiveExec32Shared: Dynarmic also owns a
     * small code block constructed while the framework is initialized.
     *
     * A single-mapped iOS JIT cache changes the protection of the entire
     * cache before and after every newly translated block.  Separate RW and
     * RX aliases avoid those costly mprotect transitions on older devices.
     * Preserve Dynarmic's normal mapping policy for Catalyst and Simulator,
     * and respect an inherited explicit setting while debugging.
     */
    if(dyld_get_active_platform() == PLATFORM_IOS &&
            getenv("DYNARMIC_DUAL_MAPPED") == NULL &&
            setenv("DYNARMIC_DUAL_MAPPED", "1", 0) != 0) {
        fprintf(stderr,
            "LC32: could not enable dual-mapped JIT code memory: %s\n",
            strerror(errno));
    }
#endif
}

static bool ConfigureInjectedEnvironment(
        char installedLauncherPath[PATH_MAX]) {
    char guestHome[PATH_MAX];
    const char *currentHome = getenv("HOME");
    if(currentHome == NULL || currentHome[0] != '/' ||
            snprintf(guestHome, sizeof(guestHome), "%s", currentHome) < 0 ||
            strlen(guestHome) != strlen(currentHome)) {
        snprintf(guestHome, sizeof(guestHome), "%s", "/var/mobile");
    }

    const char *resolvedLauncherPath = libroot_dyn_jbrootpath(
        "/Applications/LiveExec32.app/LiveExec32",
        installedLauncherPath);
    if(resolvedLauncherPath == NULL || resolvedLauncherPath[0] == '\0') {
        fprintf(stderr,
            "LC32: could not resolve the installed launcher path\n");
        return false;
    }

    const char *lastSlash = strrchr(installedLauncherPath, '/');
    if(lastSlash == NULL || lastSlash == installedLauncherPath) {
        fprintf(stderr, "LC32: installed launcher path is invalid\n");
        return false;
    }
    char rootPath[PATH_MAX];
    const int rootPathLength = snprintf(
        rootPath, sizeof(rootPath), "%.*s/RootFS",
        (int)(lastSlash - installedLauncherPath), installedLauncherPath);
    if(rootPathLength < 0 || (size_t)rootPathLength >= sizeof(rootPath)) {
        fprintf(stderr, "LC32: installed RootFS path is too long\n");
        return false;
    }

    if(setenv("ROOT_PATH", rootPath, 1) != 0 ||
            setenv("LC32_GUEST_HOME", guestHome, 1) != 0 ||
            unsetenv("DYLD_PATH") != 0 ||
            unsetenv("NATIVE_GUEST_THREADS") != 0) {
        fprintf(stderr,
            "LC32: could not configure the injected launch environment: %s\n",
            strerror(errno));
        return false;
    }
    return true;
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
    if(argc < 1 || argv == NULL || argv[0] == NULL || argc == INT_MAX) {
        fprintf(stderr, "LC32: invalid application arguments\n");
        return 1;
    }

    ConfigureDynarmicCodeMemoryMode();

    const char *executableName = strrchr(argv[0], '/');
    executableName = executableName == NULL ?
        argv[0] : executableName + 1;
    const bool injectedLauncher =
        strncmp(executableName, "LiveExec32", 10) != 0;

    char installedLauncherPath[PATH_MAX] = {0};
    if(injectedLauncher &&
            !ConfigureInjectedEnvironment(installedLauncherPath)) {
        return 1;
    }

    if(!injectedLauncher && argc == 1) {
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
            void *framework = LoadFramework(
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

    void *framework = LoadFramework(
        "LiveExec32Shared", RTLD_NOW | RTLD_GLOBAL);
    if(framework == NULL) return 1;

    typedef int (*RunGuest)(int, char *[], char *[]);
    RunGuest runGuest = (RunGuest)
        LoadEntryPoint(framework, "LC32RunGuest");
    if(runGuest == NULL) return 1;

    char **currentEnvironment = *_NSGetEnviron();
    if(currentEnvironment == NULL) currentEnvironment = envp;

    if(!injectedLauncher) {
        return runGuest(argc, argv, currentEnvironment);
    }

    /*
     * The injected arm64 slice is byte-for-byte LiveExec32's launcher, but
     * argv[0] names the installed 32-bit application's executable. Supply
     * the installed launcher as argv[0] so LiveExec32Shared finds its RootFS,
     * and the current universal executable as argv[1] so its ARM32 slice is
     * the guest program. Preserve arguments passed to the application.
     */
    const size_t guestArgumentCount = (size_t)argc + 1;
    char **guestArguments = calloc(
        guestArgumentCount + 1, sizeof(*guestArguments));
    if(guestArguments == NULL) {
        fprintf(stderr,
            "LC32: could not allocate injected application arguments\n");
        return 1;
    }
    guestArguments[0] = installedLauncherPath;
    for(int index = 0; index < argc; index++) {
        guestArguments[index + 1] = argv[index];
    }

    /*
     * LiveExec32Shared owns process-wide hooks and worker state. It is loaded
     * globally for the guest shims' RTLD_DEFAULT symbol lookups and is never
     * unloaded during the process lifetime.
     */
    const int result = runGuest(
        (int)guestArgumentCount, guestArguments, currentEnvironment);
    free(guestArguments);
    return result;
}
