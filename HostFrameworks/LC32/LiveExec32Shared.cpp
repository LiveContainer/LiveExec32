#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <assert.h>
#include <signal.h>
#include <libgen.h>

#include <copyfile.h>
#include <dlfcn.h>
#include <dirent.h>
#include <sys/mman.h>
#include <sys/clonefile.h>
#include <mach-o/fat.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>

#include <string.h>
#include <ctype.h>
#include <string>
#include <utility>
#include <vector>
#include "LiveExec32Shared.h"
#include "dynarmic.h"
#include "arm_dynarmic_cp15.h"
#include "debugger_server.h"
#include "guest_bootstrap.h"

extern "C" void LC32ConfigureLegacyAppTransportSecurity(
    uint32_t guestSDKVersion);

static uint32_t guestExecutableSDKVersion;

static void InstallGuestTracepointsFromEnvironment() {
    const char *value = getenv("LC32_GUEST_TRACEPOINTS");
    if (value == nullptr || value[0] == '\0') {
        return;
    }

    char *list = strdup(value);
    if (list == nullptr) {
        fprintf(stderr,
            "LC32: could not allocate guest tracepoint list\n");
        return;
    }
    char *state = nullptr;
    for (char *token = strtok_r(list, ", \t\r\n", &state);
         token != nullptr;
         token = strtok_r(nullptr, ", \t\r\n", &state)) {
        errno = 0;
        char *end = nullptr;
        const unsigned long long parsed =
            strtoull(token, &end, 0);
        if (errno != 0 || end == token || *end != '\0' ||
                parsed > UINT32_MAX ||
                !Dynarmic_guest_tracepoint_set(parsed)) {
            fprintf(stderr,
                "LC32: failed to install guest tracepoint '%s'\n",
                token);
            continue;
        }
        fprintf(stderr,
            "LC32: installed one-shot guest tracepoint at 0x%08x\n",
            static_cast<uint32_t>(parsed) & ~1u);
    }
    free(list);
}

u32 Dynarmic_map_file(bool isDyld, u32 target, const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("Dynarmic_map_file %s failed: %s\n", path, strerror(errno));
        exit(1);
    }
    
    struct stat file_info;
    fstat(fd, &file_info);
    size_t len = ALIGN_SIZE(file_info.st_size);
    uintptr_t map = (uintptr_t)mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    close(fd);
    
    // Map mach_header first
    //u32 addr = Dynarmic_direct_mmap(target, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, map, 0);
    
    // qXfer:libraries:read needs the complete host path so LLDB can load the
    // matching Mach-O and apply its symbols at the reported guest base.
    guestMappings[guestMappingLen].name = strdup(path);
    guestMappings[guestMappingLen].debuggerPathResolved = true;
    
    // FIXME: may leak other unused slices
    if(*(uint32_t *)map == FAT_CIGAM) {
        struct fat_header *fatheader = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)&fatheader[1];
        map = 0;
        for(int i = 0; i < OSSwapInt32(fatheader->nfat_arch); i++) {
            int subtype = OSSwapInt32(arch->cpusubtype);
            int offset = OSSwapInt32(arch->offset);
            if(subtype == CPU_SUBTYPE_ARM_V7S) {
                map = (uintptr_t)fatheader + offset;
                // preferred subtype
                break;
            } else if(subtype == CPU_SUBTYPE_ARM_V7) {
                map = (uintptr_t)fatheader + offset;
                // look for armv7s
            } else if(subtype == CPU_SUBTYPE_ARM_V6 && !map) {
                map = (uintptr_t)fatheader + offset;
                // look for armv7s or armv7
            }
            arch = &arch[1];
        }
    }
    guestMappings[guestMappingLen].hostAddr = map;
    struct mach_header *header = (struct mach_header *)map;
    assert(header->magic == MH_MAGIC && header->cputype == CPU_TYPE_ARM);

    /*
     * A non-PIE executable is linked for its preferred VM addresses and may
     * contain absolute pointers with no rebase records.  Sliding such an
     * image leaves (among other things) Objective-C class-list entries
     * pointing at the unmapped original addresses.  Let dyld load fixed
     * executables where they were linked; PIE executables still use the
     * caller-provided ASLR base.
     */
    if(header->filetype == MH_EXECUTE && !(header->flags & MH_PIE)) {
        target = 0;
        printf("LC32: mapping non-PIE executable at preferred addresses\n");
    }
    
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header);
    load_command *lc;
    int firstIndex = 0;
    u32 firstSegmentVMAddr = 0;
    for (uint i = 0; i < header->ncmds; i++, cur += lc->cmdsize) {
        lc = (load_command *)cur;
        if(!isDyld && lc->cmd == LC_VERSION_MIN_IPHONEOS &&
                lc->cmdsize >= sizeof(version_min_command)) {
            guestExecutableSDKVersion =
                ((version_min_command *)lc)->sdk;
        } else if(!isDyld && lc->cmd == LC_BUILD_VERSION &&
                  lc->cmdsize >= sizeof(build_version_command)) {
            build_version_command *build =
                (build_version_command *)lc;
            if(build->platform == PLATFORM_IOS) {
                guestExecutableSDKVersion = build->sdk;
            }
        }
        if (lc->cmd == LC_SEGMENT) {
            segment_command *seg = (segment_command *)lc;
            if(!strncmp(seg->segname, "__PAGEZERO", 10)) {
                firstIndex = 1;
                continue;
            }
            u32 filesize = ALIGN_DYN_SIZE(seg->filesize);
            if(seg->vmsize > seg->filesize) {
                // round up the page
                printf("vmsize 0x%x != filesize 0x%x\n", seg->vmsize, filesize);
                //abort();
            }
            if (i == firstIndex && seg->vmaddr >= 0x10000000) {
                target = 0;
            }
            printf("Mapping 0x%lx-0x%lx to 0x%x\n", map + seg->fileoff, map + seg->fileoff + seg->vmsize, target + seg->vmaddr);
            /*
             * dyld rebases and patches these direct file mappings in place,
             * and the debugger also needs to plant software breakpoints.
             * Preserve the loader's historically writable view while adding
             * execute permission only to Mach-O segments that requested it;
             * data-only segments must remain non-executable now that
             * instruction fetches enforce guest execute permission.
             */
            const int segmentProtection =
                PROT_READ | PROT_WRITE |
                (seg->initprot & PROT_EXEC);
            u32 mappedAddr = 0;
            if(filesize > 0) {
                mappedAddr = Dynarmic_direct_mmap(target + seg->vmaddr, filesize, segmentProtection, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, (void *)(map + seg->fileoff), 0);
                assert(mappedAddr != -1);
            }
            
            u32 vmMappedAddr = Dynarmic_mmap(target + seg->vmaddr + filesize, seg->vmsize - filesize, segmentProtection, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if(filesize == 0) {
                mappedAddr = vmMappedAddr;
            }
            
            if (i == firstIndex) {
                guestMappings[guestMappingLen].start = mappedAddr;
                guestMappings[guestMappingLen].end = mappedAddr + seg->vmsize;
                firstSegmentVMAddr = seg->vmaddr;
            }
        } else if (lc->cmd == LC_UNIXTHREAD) {
            thread_command *tc = (thread_command *)lc;
            arm_thread_state_t *state = (arm_thread_state_t *)((uint64_t)tc + sizeof(uint32_t)*4);
            for (int i = 0; i < 13; i++) {
                threadHandle.jit->Regs()[i] = state->__r[i];
            }
            threadHandle.jit->Regs()[Reg::SP] = state->__sp;
            threadHandle.jit->Regs()[Reg::LR] = state->__lr;
            /*
             * The mapped header is also the header dyld consumes.  Sliding
             * the LC_UNIXTHREAD command in place makes dyld apply the slide a
             * second time and reject legacy executables as having no valid
             * entry point.  Only slide the emulator's initial register.
             */
            threadHandle.jit->Regs()[Reg::PC] = state->__pc + target;
            threadHandle.jit->SetCpsr(state->__cpsr);
        }
    }
    
    if(isDyld) {
        const struct section *dyldInfoSection =
            getsectbynamefromheader(header, SEG_DATA, "__all_image_info");
        assert(dyldInfoSection != NULL);
        sharedHandle.dyld_info_section =
            (dyld_all_image_infos_32 *)(map + dyldInfoSection->offset);
        const u32 imageSlide =
            guestMappings[guestMappingLen].start - firstSegmentVMAddr;
        sharedHandle.dyld_info_guest_address =
            imageSlide + dyldInfoSection->addr;
        sharedHandle.dyld_load_address =
            guestMappings[guestMappingLen].start;
        // register a fake Mach port which is used to notify us about loading/unloading Mach-O libraries
        sharedHandle.dyld_info_section->notifyMachPorts[0] = -1;
    }
    
    u32 addr = guestMappings[guestMappingLen].start;
    guestMappingLen++;
    ++guestMappingGeneration;
    return addr;
}

static std::string DefaultGuestRootPath(const char *argv0) {
    char resolvedExecutablePath[PATH_MAX];
    const char *executable = argv0 ? argv0 : "";
    if(argv0 != nullptr &&
            realpath(argv0, resolvedExecutablePath) != nullptr) {
        executable = resolvedExecutablePath;
    }

    std::string executablePath = executable;
    const size_t lastSlash = executablePath.rfind('/');
    if(lastSlash == std::string::npos) return "RootFS";
    return executablePath.substr(0, lastSlash + 1) + "RootFS";
}

static const char *ConfigureGuestThreadMode(const char *argv0) {
    const char *rootPath = getenv("ROOT_PATH");
    static std::string defaultRootPath;
    if(!rootPath || !rootPath[0]) {
        defaultRootPath = DefaultGuestRootPath(argv0);
        rootPath = defaultRootPath.c_str();
    }

    /*
     * The generated Objective-C frameworks use native NSThread objects for
     * cross-thread selector delivery.  That is only valid when each guest
     * pthread owns a host pthread/JIT.  Detect this bridge configuration by
     * its private LC32 framework, before Dynarmic caches the thread mode.
     * Full-system roots do not contain that framework, so their cooperative
     * scheduler remains the default.  An explicit environment setting always
     * wins, including NATIVE_GUEST_THREADS=0 for debugging either mode.
     */
    if(getenv("NATIVE_GUEST_THREADS") == NULL) {
        const std::string marker = std::string(rootPath) +
            "/System/Library/Frameworks/LC32.framework/LC32";
        if(access(marker.c_str(), F_OK) == 0) {
            setenv("NATIVE_GUEST_THREADS", "1", 0);
            fprintf(stderr,
                "LC32: enabling native guest threads for shim frameworks\n");
        }
    }
    return rootPath;
}

void setupPathEnvs(char* argv0) {
    char path[PATH_MAX];
    
    // resolve default rootfs path to /path/to/LiveExec32.app/RootFS
    const std::string defaultRootPath = DefaultGuestRootPath(argv0);
    snprintf(path, sizeof(path), "%s", defaultRootPath.c_str());
    setenv("ROOT_PATH", path, 0);
    const char *rootPath = getenv("ROOT_PATH");

    DebuggerConfigureForGuestRoot(rootPath);

    if (getuid() == 0) {
        chroot(rootPath);
        chdir("/");
    } else {
        chdir(rootPath);
        //sharedHandle.fs->addMountpoint("/rootfs", "/");
        sharedHandle.fs->addMountpoint("/", rootPath);
        sharedHandle.fs->addMountpoint("/dev", "/dev");
        // redirecting symlink doesn't work currently, so we add both
        sharedHandle.fs->addMountpoint("/private/var", "/private/var");
        sharedHandle.fs->addMountpoint("/var", "/var");
    }
    
    // resolve default dyld path to ${ROOT_PATH}/usr/lib/dyld
    const char *guestDyldPath = "/usr/lib/dyld";
    sharedHandle.fs->pathGuestToHost(guestDyldPath, path);
    setenv("DYLD_PATH", path, 0);
}

int LC32RunGuest(int argc, char* argv[], char* envp[]) {
    if(argc < 2 || argv == nullptr || argv[0] == nullptr ||
            argv[1] == nullptr) {
        printf("Usage: %s <path> argv...\n",
            argv != nullptr && argv[0] != nullptr ?
                argv[0] : "LiveExec32");
        return 1;
    }

    /*
     * Snapshot explicit guest variables before any setenv call can replace
     * the process environment array.  The extra ENV component keeps this
     * operator-facing namespace separate from LC32_GUEST_HOME,
     * LC32_GUEST_EXECUTABLE, and other launcher/build controls.
     */
    auto guestEnvironmentSelection =
        LC32GuestBootstrap::CollectEnvironment(envp);
    for(const std::string &name :
            guestEnvironmentSelection.rejectedSourceNames) {
        fprintf(stderr,
            "LC32: ignoring malformed guest environment variable %s\n",
            name.c_str());
    }
    
    // NativeGuestThreadsRequested() caches this setting during initialization.
    ConfigureGuestThreadMode(argv[0]);

    // initialize page table, callback, Jit objects, paths
    if (!Dynarmic_nativeInitialize()) {
        fprintf(stderr, "Failed to initialize Dynarmic.\n");
        return 1;
    }
    struct DynarmicRuntimeCleanup {
        ~DynarmicRuntimeCleanup() {
            Dynarmic_nativeDestroy();
        }
    } dynarmicRuntimeCleanup;
    setupPathEnvs(argv[0]);
    
    // Make the executable and its adjacent bundle resources visible at the
    // path dyld publishes through _NSGetExecutablePath.  Without this mount,
    // guest file syscalls prepend ROOT_PATH to an absolute host-side argv[1],
    // causing CFBundleGetMainBundle() to return NULL.
    char resolvedExecPath[PATH_MAX];
    const char *execPath = argv[1];
    std::string guestHome = "/var/mobile";
    if (realpath(execPath, resolvedExecPath) != NULL) {
        execPath = resolvedExecPath;
        const char *lastSlash = strrchr(execPath, '/');
        if (lastSlash != NULL && lastSlash != execPath) {
            const std::string execDirectory(
                execPath, static_cast<size_t>(lastSlash - execPath));
            sharedHandle.fs->addMountpoint(execDirectory, execDirectory);
        }

        const std::string executablePath(execPath);
        const std::string documentsApplications = "/Documents/Applications/";
        const size_t applicationsOffset =
            executablePath.find(documentsApplications);
        if (applicationsOffset != std::string::npos && applicationsOffset != 0) {
            guestHome = executablePath.substr(0, applicationsOffset);
            if (getuid() != 0) {
                sharedHandle.fs->addMountpoint(guestHome, guestHome);
            }
        }
    }
    setenv("LC32_GUEST_HOME", guestHome.c_str(), 1);
    setenv("LC32_GUEST_EXECUTABLE", execPath, 1);

    // map the main executable first
    u32 execAddr = Dynarmic_map_file(false, 0x11000000, execPath);
    LC32ConfigureLegacyAppTransportSecurity(
        guestExecutableSDKVersion);
    
    // map dyld
    const char *dyldPath = getenv("DYLD_PATH");
    printf("Loading dyld at DYLD_PATH %s\n", dyldPath);
    Dynarmic_map_file(true, 0x10000000, dyldPath);
    InstallGuestTracepointsFromEnvironment();
    printf("entry point: 0x%x\n", threadHandle.jit->Regs()[15]);
    
    // commpage 0xffff4000+0x1000
    u32 commpage = Dynarmic_mmap(0xffff4000, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    sharedHandle.ucb->MemoryWrite16(commpage + 0x1E, 3); // version
    sharedHandle.ucb->MemoryWrite32(commpage + 0x20, 0x9000);
    sharedHandle.ucb->MemoryWrite8(commpage + 0x22, 1); // number of CPUs
    sharedHandle.ucb->MemoryWrite8(commpage + 0x24, DYN_PAGE_BITS); // 32-bit page shift
    sharedHandle.ucb->MemoryWrite16(commpage + 0x26, 128); // cache line size, 32? 64?
    //sharedHandle.ucb->MemoryWrite32(commpage + 0x28, 128); // sched count
    sharedHandle.ucb->MemoryWrite8(commpage + 0x34, 1); // active CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x35, 1); // physical CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x36, 1); // logical CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x37, DYN_PAGE_BITS); // kernel page shift
    sharedHandle.ucb->MemoryWrite32(commpage + 0x38, 0x40000000u); // max memory size, 1GB
    // TODO: mach time stuff
    //sharedHandle.ucb->MemoryWrite64(commpage + 0x40, 0x4141414141414141); // FIXME
    //sharedHandle.ucb->MemoryWrite64(commpage + 0x80, 0x41414141); // FIXME
    sharedHandle.ucb->MemoryWrite64(commpage + 0x84, 1); // dev firmware
    
    // allocate stack guards and stack buffer for dyld
    constexpr u32 InvalidGuestMapping = static_cast<u32>(-1);
    constexpr u32 DyldStackSize = 0xff000;
    constexpr u32 DyldStackGuardSize = 0x1000;
    constexpr u32 DyldStackMappingSize =
        DyldStackGuardSize + DyldStackSize + DyldStackGuardSize;
    const u32 dyldStackGuardStart = Dynarmic_mmap(
        0x80000000, DyldStackMappingSize, PROT_NONE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if(dyldStackGuardStart == InvalidGuestMapping) {
        fprintf(stderr, "LC32: could not allocate the guest initial stack\n");
        return 1;
    }
    const u32 dyldStack = dyldStackGuardStart + DyldStackGuardSize;
    if(Dynarmic_mprotect(
            dyldStack, DyldStackSize, PROT_READ | PROT_WRITE) != 0) {
        fprintf(stderr, "LC32: could not protect the guest initial stack\n");
        return 1;
    }

    std::vector<std::string> guestArguments;
    guestArguments.reserve(static_cast<size_t>(argc - 1));
    for(int index = 1; index < argc; index++) {
        guestArguments.emplace_back(argv[index] ? argv[index] : "");
    }

    std::vector<std::string> overriddenGuestEnvironmentNames;
    std::vector<std::string> guestEnvironment =
        LC32GuestBootstrap::FinalizeEnvironment(
            std::move(guestEnvironmentSelection), guestHome,
            getenv("LC32_OBJC_TRACE") ?: "0",
            getenv("NATIVE_GUEST_THREADS") ?: "0",
            &overriddenGuestEnvironmentNames);
    for(const std::string &name : overriddenGuestEnvironmentNames) {
        fprintf(stderr,
            "LC32: launcher value overrides forwarded guest variable %s\n",
            name.c_str());
    }

    char mainStackApple[128];
    const int mainStackLength = snprintf(
        mainStackApple, sizeof(mainStackApple),
        "main_stack=0x%x,0xff000,0x%x,0x100000",
        dyldStackGuardStart + 0x100000, dyldStackGuardStart);
    if(mainStackLength < 0 ||
            static_cast<size_t>(mainStackLength) >=
                sizeof(mainStackApple)) {
        fprintf(stderr, "LC32: could not format the guest stack metadata\n");
        return 1;
    }
    const std::vector<std::string> guestApple = {
        execPath,
        mainStackApple,
        "pfz=0xffffffff",
        "stack_guard=0xff39f7772c708a80",
        // Comment out the entropy entries to let dyld choose ASLR values.
        "malloc_entropy=0xf0ef08e3de46c995,0xd5adb183cbc1fed0",
    };

    LC32GuestBootstrap::InitialStackImage initialStack;
    std::string initialStackError;
    if(!LC32GuestBootstrap::BuildInitialStackImage(
            dyldStack, DyldStackSize, execAddr,
            guestArguments, guestEnvironment, guestApple,
            &initialStack, &initialStackError)) {
        fprintf(stderr, "LC32: could not build the guest initial stack: %s\n",
            initialStackError.c_str());
        return 1;
    }
    for(LC32GuestBootstrap::InitialStackString &string :
            initialStack.strings) {
        if(Dynarmic_mem_1write(
                string.address, string.value.size() + 1,
                string.value.data()) != 0) {
            fprintf(stderr,
                "LC32: could not write a guest launch string at 0x%x\n",
                string.address);
            return 1;
        }
    }
    if(Dynarmic_mem_1write(
            initialStack.stackPointer,
            initialStack.words.size() * sizeof(u32),
            reinterpret_cast<char *>(initialStack.words.data())) != 0) {
        fprintf(stderr, "LC32: could not write the guest initial stack table\n");
        return 1;
    }
    const u32 dyldStackPtr = initialStack.stackPointer;
    
    printf("LC32: stack ptr now 0x%x\n", dyldStackPtr);
    
    // Go!
    Dynarmic_reg_1write(13, dyldStackPtr);

    const char *gdbListenAddress = getenv("GDB_LISTEN_ADDRESS");
    if (gdbListenAddress != NULL && gdbListenAddress[0] != '\0') {
        if (setupGDBStub(gdbListenAddress) != 0) {
            return -1;
        }

        Dynarmic_emu_1set_1debugger_1enabled(true);
        const bool gdbstubRan =
            gdbstub_run(&sharedHandle.gdbstub, (void *)&sharedHandle);
        const gdbstub_run_reason_t gdbstubReason =
            gdbstub_get_run_reason(&sharedHandle.gdbstub);

        /*
         * D and transport loss leave the inferior stopped but alive.  Remove
         * physical BKPT patches before releasing debugger all-stop; if even
         * one mapped site cannot be restored, do not risk executing it as an
         * application breakpoint.  A target which already exited needs no
         * resume and keeps the existing clean-exit path.
         */
        const bool targetExited =
            gdbstubReason == GDBSTUB_RUN_REASON_TARGET_EXITED;
        const bool breakpointsRestored = targetExited ||
            Dynarmic_debugger_remove_all_breakpoints();
        if (!breakpointsRestored) {
            /* Keep debugger all-stop asserted through target teardown. */
            gdbstub_close(&sharedHandle.gdbstub);
            fprintf(stderr,
                "LC32: refusing to resume after debugger shutdown: "
                "one or more guest breakpoints could not be restored\n");
            return -1;
        }
        gdbstub_close(&sharedHandle.gdbstub);
        Dynarmic_emu_1set_1debugger_1enabled(false);

        if (targetExited) {
            return gdbstubRan ? 0 : -1;
        }
        if (!gdbstubRan) {
            fprintf(stderr,
                "LC32: debugger stopped with error; resuming guest "
                "without the debugger\n");
        } else {
            fprintf(stderr,
                "LC32: debugger detached (reason=%d); resuming guest\n",
                (int)gdbstubReason);
        }
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1resume();
        fprintf(stderr,
            "LC32: top-level guest execution stopped: reason=0x%08x "
            "pc=0x%08x lr=0x%08x sp=0x%08x cpsr=0x%08x\n",
            static_cast<unsigned>(reason),
            threadHandle.jit->Regs()[Reg::PC],
            threadHandle.jit->Regs()[Reg::LR],
            threadHandle.jit->Regs()[Reg::SP],
            threadHandle.jit->Cpsr());
        fflush(stderr);
    } else {
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1start(threadHandle.jit->Regs()[15]);
        fprintf(stderr,
            "LC32: top-level guest execution stopped: reason=0x%08x "
            "pc=0x%08x lr=0x%08x sp=0x%08x cpsr=0x%08x\n",
            static_cast<unsigned>(reason),
            threadHandle.jit->Regs()[Reg::PC],
            threadHandle.jit->Regs()[Reg::LR],
            threadHandle.jit->Regs()[Reg::SP],
            threadHandle.jit->Cpsr());
        fflush(stderr);
    }
    return 0;
}
