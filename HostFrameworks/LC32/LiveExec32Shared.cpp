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
#include <mach/arm/thread_status.h>
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

namespace {

constexpr uint32_t LC32MaximumFatSlices = 32;
constexpr uint32_t LC32MaximumLoadCommands = 65536;

struct LC32MappedMachO {
    uintptr_t address = 0;
    size_t size = 0;
};

uint32_t LC32ConvertUInt32(uint32_t value, bool swap) {
    return swap ? OSSwapInt32(value) : value;
}

uint64_t LC32ConvertUInt64(uint64_t value, bool swap) {
    return swap ? OSSwapInt64(value) : value;
}

uint32_t LC32BaseCPUSubtype(cpu_subtype_t subtype) {
    return static_cast<uint32_t>(subtype) &
        ~static_cast<uint32_t>(CPU_SUBTYPE_MASK);
}

bool LC32RangeFits(uint64_t offset, uint64_t size, uint64_t containerSize) {
    return offset <= containerSize && size <= containerSize - offset;
}

bool LC32RoundUpGuestPage(uint32_t size, uint32_t *roundedSize) {
    if(roundedSize == nullptr) return false;
    const uint64_t rounded =
        (static_cast<uint64_t>(size) + DYN_PAGE_MASK) &
        ~static_cast<uint64_t>(DYN_PAGE_MASK);
    if(rounded > UINT32_MAX) return false;
    *roundedSize = static_cast<uint32_t>(rounded);
    return true;
}

bool LC32ReadSegmentCommand(
        const uint8_t *commandBytes, uint32_t commandSize,
        size_t imageSize, segment_command *result,
        uint32_t *roundedFileSize) {
    if(commandBytes == nullptr ||
            commandSize < sizeof(segment_command)) {
        return false;
    }

    segment_command segment = {};
    memcpy(&segment, commandBytes, sizeof(segment));
    const uint64_t sectionBytes =
        static_cast<uint64_t>(segment.nsects) *
        sizeof(struct section);
    if(!LC32RangeFits(sizeof(segment_command),
            sectionBytes, commandSize) ||
            !LC32RangeFits(segment.fileoff,
                segment.filesize, imageSize) ||
            (segment.vmaddr & DYN_PAGE_MASK) != 0 ||
            (segment.vmsize & DYN_PAGE_MASK) != 0 ||
            !LC32RangeFits(segment.vmaddr, segment.vmsize,
                UINT64_C(1) << 32)) {
        return false;
    }

    uint32_t rounded = 0;
    if(segment.filesize > segment.vmsize ||
            !LC32RoundUpGuestPage(segment.filesize, &rounded) ||
            rounded > segment.vmsize) {
        return false;
    }
    if(result != nullptr) *result = segment;
    if(roundedFileSize != nullptr) *roundedFileSize = rounded;
    return true;
}

bool LC32ReadARMThreadState(
        const uint8_t *commandBytes, uint32_t commandSize,
        arm_thread_state_t *result) {
    if(commandBytes == nullptr ||
            commandSize < sizeof(thread_command)) {
        return false;
    }

    uint64_t payloadOffset = sizeof(thread_command);
    bool foundState = false;
    arm_thread_state_t state = {};
    while(payloadOffset < commandSize) {
        if(!LC32RangeFits(payloadOffset,
                sizeof(uint32_t) * 2, commandSize)) {
            return false;
        }

        uint32_t flavor = 0;
        uint32_t count = 0;
        memcpy(&flavor, commandBytes + payloadOffset,
            sizeof(flavor));
        memcpy(&count,
            commandBytes + payloadOffset + sizeof(flavor),
            sizeof(count));
        payloadOffset += sizeof(uint32_t) * 2;

        const uint64_t stateSize =
            static_cast<uint64_t>(count) * sizeof(uint32_t);
        if(!LC32RangeFits(payloadOffset,
                stateSize, commandSize)) {
            return false;
        }

        if(flavor == ARM_THREAD_STATE ||
                flavor == ARM_THREAD_STATE32) {
            if(foundState ||
                    count != ARM_THREAD_STATE_COUNT ||
                    stateSize != sizeof(state)) {
                return false;
            }
            memcpy(&state, commandBytes + payloadOffset,
                sizeof(state));
            foundState = true;
        }
        payloadOffset += stateSize;
    }

    if(!foundState || payloadOffset != commandSize) return false;
    if(result != nullptr) *result = state;
    return true;
}

bool LC32ValidateARMImage(
        const uint8_t *fileBytes, size_t fileSize,
        uint64_t offset, uint64_t size,
        cpu_subtype_t descriptorSubtype) {
    if(!LC32RangeFits(offset, size, fileSize) ||
            size < sizeof(mach_header)) {
        return false;
    }

    mach_header header = {};
    memcpy(&header, fileBytes + offset, sizeof(header));
    if(header.magic != MH_MAGIC || header.cputype != CPU_TYPE_ARM ||
            LC32BaseCPUSubtype(header.cpusubtype) !=
                LC32BaseCPUSubtype(descriptorSubtype) ||
            header.ncmds > LC32MaximumLoadCommands ||
            header.ncmds > header.sizeofcmds / sizeof(load_command) ||
            header.sizeofcmds > size - sizeof(header)) {
        return false;
    }

    uint64_t commandOffset = sizeof(header);
    const uint64_t commandsEnd = commandOffset + header.sizeofcmds;
    for(uint32_t index = 0; index < header.ncmds; index++) {
        if(!LC32RangeFits(
                commandOffset, sizeof(load_command), commandsEnd)) {
            return false;
        }
        load_command command = {};
        memcpy(&command, fileBytes + offset + commandOffset,
            sizeof(command));
        if(command.cmdsize < sizeof(command) ||
                (command.cmdsize % sizeof(uint32_t)) != 0 ||
                !LC32RangeFits(
                    commandOffset, command.cmdsize, commandsEnd)) {
            return false;
        }
        const uint8_t *commandBytes =
            fileBytes + offset + commandOffset;
        if(command.cmd == LC_SEGMENT) {
            if(!LC32ReadSegmentCommand(commandBytes,
                    command.cmdsize, size, nullptr, nullptr)) {
                return false;
            }
        } else if(command.cmd == LC_UNIXTHREAD) {
            if(!LC32ReadARMThreadState(commandBytes,
                    command.cmdsize, nullptr)) {
                return false;
            }
        } else if(command.cmd == LC_ENCRYPTION_INFO ||
                command.cmd == LC_ENCRYPTION_INFO_64) {
            const size_t encryptionCommandSize =
                command.cmd == LC_ENCRYPTION_INFO_64 ?
                    sizeof(encryption_info_command_64) :
                    sizeof(encryption_info_command);
            if(command.cmdsize < encryptionCommandSize) return false;
            encryption_info_command encryption = {};
            memcpy(&encryption,
                fileBytes + offset + commandOffset,
                sizeof(encryption));
            if(encryption.cryptid != 0) return false;
        }
        commandOffset += command.cmdsize;
    }
    return commandOffset == commandsEnd;
}

int LC32ARMSubtypePriority(cpu_subtype_t subtype) {
    switch(LC32BaseCPUSubtype(subtype)) {
        case CPU_SUBTYPE_ARM_V7S:
            return 5;
        case CPU_SUBTYPE_ARM_V7:
            return 4;
        case CPU_SUBTYPE_ARM_V6:
            return 3;
        case CPU_SUBTYPE_ARM_ALL:
            return 2;
        default:
            return 1;
    }
}

bool LC32SelectARMImage(
        const uint8_t *fileBytes, size_t fileSize,
        LC32MappedMachO *selection) {
    if(fileSize < sizeof(uint32_t) || selection == nullptr) return false;

    uint32_t magic = 0;
    memcpy(&magic, fileBytes, sizeof(magic));
    if(magic == MH_MAGIC) {
        mach_header header = {};
        if(fileSize < sizeof(header)) return false;
        memcpy(&header, fileBytes, sizeof(header));
        if(!LC32ValidateARMImage(
                fileBytes, fileSize, 0, fileSize, header.cpusubtype)) {
            return false;
        }
        selection->address = reinterpret_cast<uintptr_t>(fileBytes);
        selection->size = fileSize;
        return true;
    }

    const bool fat64 = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
    const bool fat32 = magic == FAT_MAGIC || magic == FAT_CIGAM;
    if(!fat32 && !fat64) return false;
    const bool swap = magic == FAT_CIGAM || magic == FAT_CIGAM_64;
    if(fileSize < sizeof(fat_header)) return false;

    fat_header header = {};
    memcpy(&header, fileBytes, sizeof(header));
    const uint32_t count = LC32ConvertUInt32(header.nfat_arch, swap);
    const size_t entrySize = fat64 ?
        sizeof(fat_arch_64) : sizeof(fat_arch);
    const uint64_t tableSize = sizeof(header) +
        static_cast<uint64_t>(count) * entrySize;
    if(count == 0 || count > LC32MaximumFatSlices ||
            tableSize > fileSize) {
        return false;
    }

    int selectedPriority = 0;
    for(uint32_t index = 0; index < count; index++) {
        const uint64_t entryOffset = sizeof(header) +
            static_cast<uint64_t>(index) * entrySize;
        cpu_type_t cpuType = 0;
        cpu_subtype_t cpuSubtype = 0;
        uint64_t sliceOffset = 0;
        uint64_t sliceSize = 0;
        if(fat64) {
            fat_arch_64 architecture = {};
            memcpy(&architecture, fileBytes + entryOffset,
                sizeof(architecture));
            cpuType = static_cast<cpu_type_t>(LC32ConvertUInt32(
                static_cast<uint32_t>(architecture.cputype), swap));
            cpuSubtype = static_cast<cpu_subtype_t>(LC32ConvertUInt32(
                static_cast<uint32_t>(architecture.cpusubtype), swap));
            sliceOffset = LC32ConvertUInt64(architecture.offset, swap);
            sliceSize = LC32ConvertUInt64(architecture.size, swap);
        } else {
            fat_arch architecture = {};
            memcpy(&architecture, fileBytes + entryOffset,
                sizeof(architecture));
            cpuType = static_cast<cpu_type_t>(LC32ConvertUInt32(
                static_cast<uint32_t>(architecture.cputype), swap));
            cpuSubtype = static_cast<cpu_subtype_t>(LC32ConvertUInt32(
                static_cast<uint32_t>(architecture.cpusubtype), swap));
            sliceOffset = LC32ConvertUInt32(architecture.offset, swap);
            sliceSize = LC32ConvertUInt32(architecture.size, swap);
        }

        if(!LC32RangeFits(sliceOffset, sliceSize, fileSize)) return false;
        if(cpuType != CPU_TYPE_ARM) continue;
        if(!LC32ValidateARMImage(fileBytes, fileSize,
                sliceOffset, sliceSize, cpuSubtype)) {
            return false;
        }

        const int priority = LC32ARMSubtypePriority(cpuSubtype);
        if(priority > selectedPriority) {
            selection->address = reinterpret_cast<uintptr_t>(
                fileBytes + sliceOffset);
            selection->size = static_cast<size_t>(sliceSize);
            selectedPriority = priority;
        }
    }
    return selection->address != 0;
}

[[noreturn]] void LC32MapFileFailure(
        const char *path, const char *message) {
    fprintf(stderr, "LC32: could not map %s: %s\n",
        path ? path : "(null)", message);
    exit(1);
}

} // anonymous namespace

u32 Dynarmic_map_file(bool isDyld, u32 target, const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        LC32MapFileFailure(path, strerror(errno));
    }

    struct stat fileInfo = {};
    if(fstat(fd, &fileInfo) != 0) {
        const int savedError = errno;
        close(fd);
        LC32MapFileFailure(path, strerror(savedError));
    }
    if(!S_ISREG(fileInfo.st_mode) || fileInfo.st_size <= 0 ||
            static_cast<uint64_t>(fileInfo.st_size) >
                SIZE_MAX - PAGE_SIZE) {
        close(fd);
        LC32MapFileFailure(path, "invalid file size");
    }
    const size_t fileSize = static_cast<size_t>(fileInfo.st_size);
    const size_t mappingSize = ALIGN_SIZE(fileSize);
    void *fileMapping = mmap(NULL, mappingSize,
        PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    const int mappingError = errno;
    close(fd);
    if(fileMapping == MAP_FAILED) {
        LC32MapFileFailure(path, strerror(mappingError));
    }

    LC32MappedMachO selectedImage;
    if(!LC32SelectARMImage(
            static_cast<const uint8_t *>(fileMapping),
            fileSize, &selectedImage)) {
        munmap(fileMapping, mappingSize);
        LC32MapFileFailure(path,
            "no valid, decrypted ARM32 Mach-O slice");
    }
    uintptr_t map = selectedImage.address;
    
    // Map mach_header first
    //u32 addr = Dynarmic_direct_mmap(target, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, map, 0);
    
    // qXfer:libraries:read needs the complete host path so LLDB can load the
    // matching Mach-O and apply its symbols at the reported guest base.
    if(guestMappingLen >= 1000) {
        munmap(fileMapping, mappingSize);
        LC32MapFileFailure(path, "guest image table is full");
    }
    guestMappings[guestMappingLen].name = strdup(path);
    if(guestMappings[guestMappingLen].name == nullptr) {
        munmap(fileMapping, mappingSize);
        LC32MapFileFailure(path, "could not allocate the image path");
    }
    guestMappings[guestMappingLen].debuggerPathResolved = true;
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
            segment_command segment = {};
            u32 fileMappingSize = 0;
            if(!LC32ReadSegmentCommand(
                    reinterpret_cast<const uint8_t *>(lc),
                    lc->cmdsize, selectedImage.size,
                    &segment, &fileMappingSize)) {
                LC32MapFileFailure(path,
                    "invalid LC_SEGMENT command");
            }
            if(!strncmp(segment.segname, "__PAGEZERO", 10)) {
                firstIndex = 1;
                continue;
            }
            if(segment.vmsize > segment.filesize) {
                // round up the page
                printf("vmsize 0x%x != filesize 0x%x\n",
                    segment.vmsize, fileMappingSize);
                //abort();
            }
            if (i == firstIndex && segment.vmaddr >= 0x10000000) {
                target = 0;
            }
            const uint64_t guestSegmentAddress64 =
                static_cast<uint64_t>(target) + segment.vmaddr;
            const uint64_t guestSegmentEnd =
                guestSegmentAddress64 + segment.vmsize;
            if(guestSegmentAddress64 > UINT32_MAX ||
                    guestSegmentEnd > UINT32_MAX ||
                    (guestSegmentAddress64 & DYN_PAGE_MASK) != 0) {
                LC32MapFileFailure(path,
                    "LC_SEGMENT guest address is out of range");
            }
            const u32 guestSegmentAddress =
                static_cast<u32>(guestSegmentAddress64);
            printf("Mapping 0x%lx-0x%lx to 0x%x\n",
                map + segment.fileoff,
                map + segment.fileoff + segment.filesize,
                guestSegmentAddress);
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
                (segment.initprot & PROT_EXEC);
            u32 mappedAddr = 0;
            if(fileMappingSize > 0) {
                mappedAddr = Dynarmic_direct_mmap(
                    guestSegmentAddress, fileMappingSize,
                    segmentProtection,
                    MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS,
                    reinterpret_cast<void *>(
                        map + segment.fileoff), 0);
                if(mappedAddr == UINT32_MAX) {
                    LC32MapFileFailure(path,
                        "could not map LC_SEGMENT file data");
                }
            }

            const u32 zeroFillSize =
                segment.vmsize - fileMappingSize;
            if(zeroFillSize > 0) {
                const u32 vmMappedAddr = Dynarmic_mmap(
                    guestSegmentAddress + fileMappingSize,
                    zeroFillSize, segmentProtection,
                    MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS,
                    -1, 0);
                if(vmMappedAddr == UINT32_MAX) {
                    LC32MapFileFailure(path,
                        "could not map LC_SEGMENT zero-fill data");
                }
                if(fileMappingSize == 0) {
                    mappedAddr = vmMappedAddr;
                }
            }

            if (i == firstIndex) {
                guestMappings[guestMappingLen].start = mappedAddr;
                guestMappings[guestMappingLen].end =
                    static_cast<u32>(guestSegmentEnd);
                firstSegmentVMAddr = segment.vmaddr;
            }
        } else if (lc->cmd == LC_UNIXTHREAD) {
            arm_thread_state_t state = {};
            if(!LC32ReadARMThreadState(
                    reinterpret_cast<const uint8_t *>(lc),
                    lc->cmdsize, &state)) {
                LC32MapFileFailure(path,
                    "invalid LC_UNIXTHREAD command");
            }
            for (int i = 0; i < 13; i++) {
                threadHandle.jit->Regs()[i] = state.__r[i];
            }
            threadHandle.jit->Regs()[Reg::SP] = state.__sp;
            threadHandle.jit->Regs()[Reg::LR] = state.__lr;
            /*
             * The mapped header is also the header dyld consumes.  Sliding
             * the LC_UNIXTHREAD command in place makes dyld apply the slide a
             * second time and reject legacy executables as having no valid
             * entry point.  Only slide the emulator's initial register.
             */
            const uint64_t guestProgramCounter =
                static_cast<uint64_t>(state.__pc) + target;
            if(guestProgramCounter > UINT32_MAX) {
                LC32MapFileFailure(path,
                    "LC_UNIXTHREAD program counter is out of range");
            }
            threadHandle.jit->Regs()[Reg::PC] =
                static_cast<u32>(guestProgramCounter);
            threadHandle.jit->SetCpsr(state.__cpsr);
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

    const char *configuredGuestHomeValue = getenv("LC32_GUEST_HOME");
    const std::string configuredGuestHome =
        configuredGuestHomeValue != nullptr &&
            configuredGuestHomeValue[0] == '/' ?
                configuredGuestHomeValue : "";

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
    std::string guestHome = configuredGuestHome.empty() ?
        "/var/mobile" : configuredGuestHome;
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
        if (configuredGuestHome.empty() &&
                applicationsOffset != std::string::npos &&
                applicationsOffset != 0) {
            guestHome = executablePath.substr(0, applicationsOffset);
            if (getuid() != 0) {
                sharedHandle.fs->addMountpoint(guestHome, guestHome);
            }
        }
    }
    if(!configuredGuestHome.empty() && getuid() != 0) {
        sharedHandle.fs->addMountpoint(guestHome, guestHome);
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
