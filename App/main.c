#include <dlfcn.h>
#include <crt_externs.h>
#include <errno.h>
#include <fcntl.h>
#include <libkern/OSByteOrder.h>
#include <libroot.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Lets future injector versions distinguish and migrate copied launchers. */
__attribute__((used, section("__TEXT,__lc32shim")))
static const char LC32InjectedShimMarker[] =
    "LiveExec32InjectedShim:1";

typedef enum {
    LC32ExecutableInspectionFailed = -1,
    LC32ExecutableIsStandalone = 0,
    LC32ExecutableIsInjected = 1,
} LC32ExecutableInspectionResult;

static bool ReadExactlyAt(
        int fd, void *buffer, size_t size, off_t offset) {
    size_t completed = 0;
    while(completed < size) {
        const ssize_t amount = pread(fd,
            (uint8_t *)buffer + completed, size - completed,
            offset + (off_t)completed);
        if(amount < 0 && errno == EINTR) continue;
        if(amount <= 0) return false;
        completed += (size_t)amount;
    }
    return true;
}

static uint32_t ConvertUInt32(uint32_t value, bool swap) {
    return swap ? OSSwapInt32(value) : value;
}

static LC32ExecutableInspectionResult InspectExecutable(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if(fd < 0) return LC32ExecutableInspectionFailed;

    struct stat status = {0};
    uint32_t magic = 0;
    LC32ExecutableInspectionResult result =
        LC32ExecutableInspectionFailed;
    if(fstat(fd, &status) != 0 || !S_ISREG(status.st_mode) ||
            status.st_size < (off_t)sizeof(magic) ||
            !ReadExactlyAt(fd, &magic, sizeof(magic), 0)) {
        close(fd);
        return LC32ExecutableInspectionFailed;
    }

    if(magic == MH_MAGIC || magic == MH_CIGAM ||
            magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        const bool swap = magic == MH_CIGAM || magic == MH_CIGAM_64;
        const bool is64Bit = magic == MH_MAGIC_64 || magic == MH_CIGAM_64;
        const size_t headerSize = is64Bit ?
            sizeof(struct mach_header_64) : sizeof(struct mach_header);
        struct mach_header_64 header = {0};
        if(status.st_size >= (off_t)headerSize &&
                ReadExactlyAt(fd, &header, headerSize, 0) &&
                ConvertUInt32(header.filetype, swap) == MH_EXECUTE &&
                is64Bit &&
                ((uint32_t)ConvertUInt32(
                    (uint32_t)header.cputype, swap) &
                        CPU_ARCH_ABI64) != 0) {
            result = LC32ExecutableIsStandalone;
        }
    } else if(magic == FAT_MAGIC || magic == FAT_CIGAM) {
        struct fat_header header = {0};
        const bool swap = magic == FAT_CIGAM;
        if(status.st_size >= (off_t)sizeof(header) &&
                ReadExactlyAt(fd, &header, sizeof(header), 0)) {
            const uint32_t count = ConvertUInt32(header.nfat_arch, swap);
            const uint64_t tableSize = sizeof(header) +
                (uint64_t)count * sizeof(struct fat_arch);
            if(count > 0 && count <= 32 &&
                    tableSize <= (uint64_t)status.st_size) {
                result = LC32ExecutableIsStandalone;
                bool containsARM32 = false;
                for(uint32_t index = 0; index < count; index++) {
                    struct fat_arch architecture = {0};
                    const off_t offset = sizeof(header) +
                        (off_t)index * sizeof(architecture);
                    if(!ReadExactlyAt(fd, &architecture,
                            sizeof(architecture), offset)) {
                        result = LC32ExecutableInspectionFailed;
                        break;
                    }

                    const cpu_type_t cpuType =
                        (cpu_type_t)ConvertUInt32(
                            (uint32_t)architecture.cputype, swap);
                    const cpu_subtype_t cpuSubtype =
                        (cpu_subtype_t)ConvertUInt32(
                            (uint32_t)architecture.cpusubtype, swap);
                    const uint64_t sliceOffset = ConvertUInt32(
                        architecture.offset, swap);
                    const uint64_t sliceSize = ConvertUInt32(
                        architecture.size, swap);
                    if(sliceSize == 0 || sliceOffset < tableSize ||
                            sliceOffset > (uint64_t)status.st_size ||
                            sliceSize >
                                (uint64_t)status.st_size - sliceOffset) {
                        result = LC32ExecutableInspectionFailed;
                        break;
                    }
                    if(cpuType == CPU_TYPE_ARM) {
                        struct mach_header sliceHeader = {0};
                        if(sliceSize < sizeof(sliceHeader) ||
                                !ReadExactlyAt(fd, &sliceHeader,
                                    sizeof(sliceHeader),
                                    (off_t)sliceOffset) ||
                                (sliceHeader.magic != MH_MAGIC &&
                                    sliceHeader.magic != MH_CIGAM)) {
                            result = LC32ExecutableInspectionFailed;
                            break;
                        }
                        const bool sliceSwap =
                            sliceHeader.magic == MH_CIGAM;
                        if((cpu_type_t)ConvertUInt32(
                                (uint32_t)sliceHeader.cputype,
                                sliceSwap) != CPU_TYPE_ARM ||
                                ConvertUInt32(sliceHeader.filetype,
                                    sliceSwap) != MH_EXECUTE ||
                                ((uint32_t)ConvertUInt32(
                                    (uint32_t)sliceHeader.cpusubtype,
                                    sliceSwap) &
                                        ~(uint32_t)CPU_SUBTYPE_MASK) !=
                                    ((uint32_t)cpuSubtype &
                                        ~(uint32_t)CPU_SUBTYPE_MASK)) {
                            result = LC32ExecutableInspectionFailed;
                            break;
                        }
                        containsARM32 = true;
                    }
                }
                if(result != LC32ExecutableInspectionFailed &&
                        containsARM32) {
                    result = LC32ExecutableIsInjected;
                }
            }
        }
    }

    close(fd);
    return result;
}

static bool GetExecutablePath(char *path, size_t capacity) {
    if(capacity > UINT32_MAX) return false;
    uint32_t size = (uint32_t)capacity;
    if(_NSGetExecutablePath(path, &size) != 0) return false;

    char resolvedPath[PATH_MAX];
    if(realpath(path, resolvedPath) != NULL) {
        const int length = snprintf(path, capacity, "%s", resolvedPath);
        if(length < 0 || (size_t)length >= capacity) return false;
    }
    return true;
}

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
    char executablePath[PATH_MAX] = {0};
    if(!GetExecutablePath(executablePath, sizeof(executablePath))) {
        fprintf(stderr, "LC32: could not resolve the executable path\n");
        return 1;
    }
    const LC32ExecutableInspectionResult inspectionResult =
        InspectExecutable(executablePath);
    if(inspectionResult == LC32ExecutableInspectionFailed) {
        fprintf(stderr, "LC32: could not inspect executable %s\n",
            executablePath);
        return 1;
    }
    const bool injectedLauncher =
        inspectionResult == LC32ExecutableIsInjected;

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
    if(argc < 1 || argv == NULL || argc == INT_MAX) {
        fprintf(stderr, "LC32: invalid injected application arguments\n");
        return 1;
    }

    const size_t guestArgumentCount = (size_t)argc + 1;
    char **guestArguments = calloc(
        guestArgumentCount + 1, sizeof(*guestArguments));
    if(guestArguments == NULL) {
        fprintf(stderr,
            "LC32: could not allocate injected application arguments\n");
        return 1;
    }
    guestArguments[0] = installedLauncherPath;
    guestArguments[1] = executablePath;
    for(int index = 1; index < argc; index++) {
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
