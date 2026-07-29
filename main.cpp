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
#include <algorithm>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include "dynarmic.h"
#include "arm_dynarmic_cp15.h"

#define SEG_DATA_CONST  "__DATA_CONST"

static std::string guestOSVersion;
static std::string guestOSBuild;
static std::string debuggerSymbolsRoot;
static std::string debuggerImageCacheRoot;
static std::vector<std::string> debuggerImageCacheFiles;
static std::vector<std::string> debuggerImageCacheDirectories;
static std::unordered_map<std::string, std::string> debuggerImagePathCache;
static std::unordered_map<u32, u32> debuggerInferiorAllocations;

static bool DebuggerWasRequested() {
    const char *listenAddress = getenv("GDB_LISTEN_ADDRESS");
    return listenAddress != NULL && listenAddress[0] != '\0';
}

static bool RangeIsInside(size_t containerSize,
                          size_t offset,
                          size_t size) {
    return offset <= containerSize && size <= containerSize - offset;
}

static bool ReadULEB128(const uint8_t *data,
                        size_t size,
                        size_t *offset,
                        uint64_t *value) {
    if (data == NULL || offset == NULL || value == NULL) {
        return false;
    }

    uint64_t result = 0;
    unsigned shift = 0;
    for (;;) {
        if (*offset >= size || shift >= 64) {
            return false;
        }
        const uint8_t byte = data[(*offset)++];
        const uint64_t payload = byte & 0x7f;
        if (payload > (UINT64_MAX >> shift)) {
            return false;
        }
        result |= payload << shift;
        if ((byte & 0x80) == 0) {
            *value = result;
            return true;
        }
        shift += 7;
    }
}

static void AppendULEB128(std::vector<uint8_t> *output, uint64_t value) {
    do {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        if (value != 0) {
            byte |= 0x80;
        }
        output->push_back(byte);
    } while (value != 0);
}

/*
 * Apple ld64's ARM LC_FUNCTION_STARTS stream accumulates deltas between
 * addresses whose low bit records Thumb state.  LLDB clears that bit from
 * the running accumulator, so every ARM/Thumb transition shifts all later
 * synthetic function boundaries.  The resulting boundaries can land in the
 * middle of an instruction and make assembly-based unwinding miss a prologue.
 *
 * Rewrite debugger-only copies to preserve the initial ARM run and then keep
 * the encoded state Thumb after the first Thumb function.  Every later delta
 * is therefore between addresses with the same low bit, so the affected LLDB
 * cannot shift a boundary.  Any later ARM function must have an nlist symbol
 * that supplies its real instruction-set state; otherwise the debugger copy
 * disables LC_FUNCTION_STARTS rather than risk decoding ARM as Thumb.  The
 * guest image and extracted symbol file are never modified.
 */
static bool NormalizeARMFunctionStartsInSlice(uint8_t *fileData,
                                               size_t fileSize,
                                               size_t sliceOffset,
                                               size_t sliceSize,
                                               bool *changed) {
    if (!RangeIsInside(fileSize, sliceOffset, sliceSize) ||
        sliceSize < sizeof(mach_header)) {
        return false;
    }

    mach_header header;
    memcpy(&header, fileData + sliceOffset, sizeof(header));
    if (header.magic != MH_MAGIC) {
        return false;
    }
    if (header.cputype != CPU_TYPE_ARM) {
        return true;
    }
    if (!RangeIsInside(sliceSize, sizeof(header), header.sizeofcmds)) {
        return false;
    }

    uint32_t textVMAddress = 0;
    uint32_t textVMSize = 0;
    bool foundText = false;
    uint32_t linkeditFileOffset = 0;
    uint32_t linkeditFileSize = 0;
    bool foundLinkedit = false;
    size_t functionStartsCommandOffset = 0;
    linkedit_data_command functionStarts = {};
    symtab_command symbolTable = {};
    bool foundSymbolTable = false;
    std::vector<bool> instructionSections(1, false);

    size_t commandOffset = sliceOffset + sizeof(header);
    const size_t commandsEnd = commandOffset + header.sizeofcmds;
    for (uint32_t i = 0; i < header.ncmds; ++i) {
        if (!RangeIsInside(commandsEnd, commandOffset,
                           sizeof(load_command))) {
            return false;
        }
        load_command command;
        memcpy(&command, fileData + commandOffset, sizeof(command));
        if (command.cmdsize < sizeof(command) ||
            !RangeIsInside(commandsEnd, commandOffset, command.cmdsize)) {
            return false;
        }

        if (command.cmd == LC_SEGMENT &&
            command.cmdsize >= sizeof(segment_command)) {
            segment_command segment;
            memcpy(&segment, fileData + commandOffset, sizeof(segment));
            if (segment.nsects >
                (command.cmdsize - sizeof(segment)) / sizeof(section)) {
                return false;
            }
            if (strncmp(segment.segname, SEG_TEXT,
                        sizeof(segment.segname)) == 0) {
                textVMAddress = segment.vmaddr;
                textVMSize = segment.vmsize;
                foundText = true;
            } else if (strncmp(segment.segname, SEG_LINKEDIT,
                               sizeof(segment.segname)) == 0) {
                linkeditFileOffset = segment.fileoff;
                linkeditFileSize = segment.filesize;
                foundLinkedit = true;
            }

            const uint8_t *sectionData =
                fileData + commandOffset + sizeof(segment);
            for (uint32_t sectionIndex = 0;
                 sectionIndex < segment.nsects; ++sectionIndex) {
                section currentSection;
                memcpy(&currentSection,
                       sectionData + sectionIndex * sizeof(currentSection),
                       sizeof(currentSection));
                instructionSections.push_back(
                    (currentSection.flags &
                     (S_ATTR_PURE_INSTRUCTIONS |
                      S_ATTR_SOME_INSTRUCTIONS)) != 0);
            }
        } else if (command.cmd == LC_FUNCTION_STARTS &&
                   command.cmdsize >= sizeof(linkedit_data_command)) {
            memcpy(&functionStarts, fileData + commandOffset,
                   sizeof(functionStarts));
            functionStartsCommandOffset = commandOffset;
        } else if (command.cmd == LC_SYMTAB &&
                   command.cmdsize >= sizeof(symtab_command)) {
            memcpy(&symbolTable, fileData + commandOffset,
                   sizeof(symbolTable));
            foundSymbolTable = true;
        }
        commandOffset += command.cmdsize;
    }

    if (!foundText || textVMSize == 0 ||
        textVMSize > UINT32_MAX - textVMAddress ||
        !foundLinkedit || functionStartsCommandOffset == 0 ||
        functionStarts.datasize == 0) {
        return true;
    }
    if (!RangeIsInside(sliceSize, functionStarts.dataoff,
                       functionStarts.datasize) ||
        functionStarts.dataoff < linkeditFileOffset ||
        !RangeIsInside(linkeditFileSize,
                       functionStarts.dataoff - linkeditFileOffset,
                       functionStarts.datasize)) {
        return false;
    }

    uint8_t *functionData =
        fileData + sliceOffset + functionStarts.dataoff;
    std::unordered_set<uint32_t> namedARMFunctions;
    if (foundSymbolTable) {
        if (symbolTable.nsyms > sliceSize / sizeof(struct nlist) ||
            !RangeIsInside(sliceSize, symbolTable.symoff,
                           symbolTable.nsyms * sizeof(struct nlist)) ||
            !RangeIsInside(sliceSize, symbolTable.stroff,
                           symbolTable.strsize)) {
            return false;
        }

        const uint8_t *symbolData =
            fileData + sliceOffset + symbolTable.symoff;
        const char *stringData = reinterpret_cast<const char *>(
            fileData + sliceOffset + symbolTable.stroff);
        for (uint32_t i = 0; i < symbolTable.nsyms; ++i) {
            struct nlist symbol;
            memcpy(&symbol, symbolData + i * sizeof(symbol),
                   sizeof(symbol));
            const uint32_t stringOffset = symbol.n_un.n_strx;
            if ((symbol.n_type & N_STAB) != 0 ||
                (symbol.n_type & N_TYPE) != N_SECT ||
                symbol.n_sect == 0 ||
                symbol.n_sect >= instructionSections.size() ||
                !instructionSections[symbol.n_sect] ||
                (symbol.n_desc & N_ARM_THUMB_DEF) != 0 ||
                stringOffset == 0 ||
                stringOffset >= symbolTable.strsize) {
                continue;
            }
            const char *name = stringData + stringOffset;
            const size_t maximumNameSize =
                symbolTable.strsize - stringOffset;
            if (name[0] == '\0' ||
                memchr(name, '\0', maximumNameSize) == NULL) {
                continue;
            }
            namedARMFunctions.insert(symbol.n_value);
        }
    }

    size_t inputOffset = 0;
    uint64_t taggedAddress = textVMAddress;
    uint64_t previousNormalizedAddress = textVMAddress;
    bool emittedThumbState = false;
    bool unsafeARMFunction = false;
    bool first = true;
    bool foundTerminator = false;
    std::vector<uint8_t> normalized;
    normalized.reserve(functionStarts.datasize);

    while (inputOffset < functionStarts.datasize) {
        uint64_t delta = 0;
        if (!ReadULEB128(functionData, functionStarts.datasize,
                         &inputOffset, &delta)) {
            return false;
        }
        if (delta == 0) {
            foundTerminator = true;
            break;
        }
        if (delta > UINT32_MAX - taggedAddress) {
            return false;
        }
        taggedAddress += delta;
        const uint64_t codeAddress = taggedAddress & ~UINT64_C(1);
        if (codeAddress < textVMAddress ||
            codeAddress >=
                static_cast<uint64_t>(textVMAddress) + textVMSize ||
            codeAddress <=
            (previousNormalizedAddress & ~UINT64_C(1))) {
            return false;
        }

        const bool isThumb = (taggedAddress & 1) != 0;
        if (isThumb) {
            emittedThumbState = true;
        } else if (emittedThumbState &&
                   namedARMFunctions.count(
                       static_cast<uint32_t>(codeAddress)) == 0) {
            unsafeARMFunction = true;
        }
        const uint64_t normalizedAddress =
            codeAddress + (emittedThumbState ? 1 : 0);
        const uint64_t normalizedDelta =
            normalizedAddress - previousNormalizedAddress;
        AppendULEB128(&normalized, normalizedDelta);
        previousNormalizedAddress = normalizedAddress;
        first = false;
    }
    if (!foundTerminator || first) {
        return false;
    }
    normalized.push_back(0);

    if (unsafeARMFunction ||
        normalized.size() > functionStarts.datasize) {
        /*
         * A poisoned function-start table is worse than no table.  This
         * fallback keeps nlist symbols and frame-pointer unwinding usable.
         */
        const uint32_t noFunctionStarts = 0;
        memcpy(fileData + functionStartsCommandOffset +
                   offsetof(linkedit_data_command, datasize),
               &noFunctionStarts, sizeof(noFunctionStarts));
        *changed = true;
        return true;
    }

    if (normalized.size() != functionStarts.datasize ||
        memcmp(functionData, normalized.data(), normalized.size()) != 0) {
        memset(functionData, 0, functionStarts.datasize);
        memcpy(functionData, normalized.data(), normalized.size());
        *changed = true;
    }
    return true;
}

static bool NormalizeDebuggerMachO(const char *path, bool *changed) {
    *changed = false;
    int fd = open(path, O_RDWR);
    if (fd < 0) {
        return false;
    }

    struct stat info;
    if (fstat(fd, &info) != 0 ||
        info.st_size < static_cast<off_t>(sizeof(uint32_t))) {
        close(fd);
        return false;
    }
    const size_t fileSize = static_cast<size_t>(info.st_size);
    void *mapping =
        mmap(NULL, fileSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) {
        close(fd);
        return false;
    }

    uint8_t *fileData = static_cast<uint8_t *>(mapping);
    uint32_t magic;
    memcpy(&magic, fileData, sizeof(magic));
    bool valid = true;
    if (magic == MH_MAGIC) {
        valid = NormalizeARMFunctionStartsInSlice(
            fileData, fileSize, 0, fileSize, changed);
    } else if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        fat_header fatHeader;
        if (!RangeIsInside(fileSize, 0, sizeof(fatHeader))) {
            valid = false;
        } else {
            memcpy(&fatHeader, fileData, sizeof(fatHeader));
            const bool swap = magic == FAT_CIGAM;
            const uint32_t architectureCount =
                swap ? OSSwapInt32(fatHeader.nfat_arch)
                     : fatHeader.nfat_arch;
            if (architectureCount > 64 ||
                !RangeIsInside(fileSize, sizeof(fatHeader),
                               architectureCount * sizeof(fat_arch))) {
                valid = false;
            }
            for (uint32_t i = 0; valid && i < architectureCount; ++i) {
                fat_arch architecture;
                memcpy(&architecture,
                       fileData + sizeof(fatHeader) +
                           i * sizeof(architecture),
                       sizeof(architecture));
                const uint32_t sliceOffset =
                    swap ? OSSwapInt32(architecture.offset)
                         : architecture.offset;
                const uint32_t sliceSize =
                    swap ? OSSwapInt32(architecture.size)
                         : architecture.size;
                const cpu_type_t cpuType =
                    swap ? OSSwapInt32(architecture.cputype)
                         : architecture.cputype;
                if (cpuType != CPU_TYPE_ARM) {
                    continue;
                }
                valid = NormalizeARMFunctionStartsInSlice(
                    fileData, fileSize, sliceOffset, sliceSize, changed);
            }
        }
    }

    if (*changed) {
        (void)msync(mapping, fileSize, MS_SYNC);
    }
    munmap(mapping, fileSize);
    close(fd);
    return valid;
}

static void CleanupDebuggerImageCache() {
    for (const std::string &path : debuggerImageCacheFiles) {
        unlink(path.c_str());
    }
    for (auto i = debuggerImageCacheDirectories.rbegin();
         i != debuggerImageCacheDirectories.rend(); ++i) {
        rmdir(i->c_str());
    }
    if (!debuggerImageCacheRoot.empty()) {
        rmdir(debuggerImageCacheRoot.c_str());
    }
}

static bool EnsureDebuggerImageCache() {
    if (!debuggerImageCacheRoot.empty()) {
        return true;
    }
    const char *temporaryRoot = getenv("TMPDIR");
    if (temporaryRoot == NULL || temporaryRoot[0] == '\0') {
        temporaryRoot = "/tmp";
    }

    char path[PATH_MAX];
    const int length = snprintf(path, sizeof(path),
                                "%s%sLiveExec32-lldb.XXXXXX",
                                temporaryRoot,
                                temporaryRoot[strlen(temporaryRoot) - 1] == '/'
                                    ? "" : "/");
    if (length <= 0 || length >= sizeof(path) || mkdtemp(path) == NULL) {
        return false;
    }
    debuggerImageCacheRoot = path;
    atexit(CleanupDebuggerImageCache);
    return true;
}

static bool PrepareDebuggerImagePath(const char *sourcePath,
                                     char outputPath[PATH_MAX]) {
    if (sourcePath == NULL || outputPath == NULL) {
        return false;
    }
    const auto cached = debuggerImagePathCache.find(sourcePath);
    if (cached != debuggerImagePathCache.end()) {
        if (cached->second.size() >= PATH_MAX) {
            return false;
        }
        memcpy(outputPath, cached->second.c_str(),
               cached->second.size() + 1);
        return true;
    }

    std::string selectedPath = sourcePath;
    const char *disabled = getenv("GDB_DISABLE_ARM_FUNCTION_STARTS_FIX");
    if ((disabled == NULL || strcmp(disabled, "1") != 0) &&
        EnsureDebuggerImageCache()) {
        char directory[PATH_MAX];
        const int directoryLength = snprintf(
            directory, sizeof(directory), "%s/image.XXXXXX",
            debuggerImageCacheRoot.c_str());
        const char *basename = strrchr(sourcePath, '/');
        basename = basename != NULL ? basename + 1 : sourcePath;
        if (directoryLength > 0 && directoryLength < sizeof(directory) &&
            basename[0] != '\0' && mkdtemp(directory) != NULL) {
            debuggerImageCacheDirectories.emplace_back(directory);
            char shadowPath[PATH_MAX];
            const int shadowLength =
                snprintf(shadowPath, sizeof(shadowPath), "%s/%s",
                         directory, basename);
            if (shadowLength > 0 && shadowLength < sizeof(shadowPath)) {
                bool copied = clonefile(sourcePath, shadowPath, 0) == 0;
                if (!copied) {
                    unlink(shadowPath);
                    copied = copyfile(sourcePath, shadowPath, NULL,
                                      COPYFILE_DATA) == 0;
                }
                if (copied) {
                    bool changed = false;
                    if (NormalizeDebuggerMachO(shadowPath, &changed) &&
                        changed) {
                        selectedPath = shadowPath;
                        debuggerImageCacheFiles.emplace_back(shadowPath);
                    } else {
                        unlink(shadowPath);
                    }
                } else {
                    unlink(shadowPath);
                }
            }
        }
    }

    debuggerImagePathCache.emplace(sourcePath, selectedPath);
    if (selectedPath.size() >= PATH_MAX) {
        return false;
    }
    memcpy(outputPath, selectedPath.c_str(), selectedPath.size() + 1);
    return true;
}

bool ResolveDebuggerImagePath(const char *guestPath, char *hostPath) {
    if (guestPath == NULL || hostPath == NULL || guestPath[0] != '/') {
        return false;
    }
    char resolvedPath[PATH_MAX];
    if (sharedHandle.fs->pathGuestToHost(guestPath, resolvedPath) &&
        access(resolvedPath, R_OK) == 0) {
        if (DebuggerWasRequested()) {
            return PrepareDebuggerImagePath(resolvedPath, hostPath);
        }
        return strlcpy(hostPath, resolvedPath, PATH_MAX) < PATH_MAX;
    }
    if (debuggerSymbolsRoot.empty()) {
        return false;
    }

    const int length = snprintf(resolvedPath, PATH_MAX, "%s%s",
                                debuggerSymbolsRoot.c_str(), guestPath);
    if (length <= 0 || length >= PATH_MAX ||
        access(resolvedPath, R_OK) != 0) {
        return false;
    }
    if (DebuggerWasRequested()) {
        return PrepareDebuggerImagePath(resolvedPath, hostPath);
    }
    return strlcpy(hostPath, resolvedPath, PATH_MAX) < PATH_MAX;
}

enum {
    GDB_ARM_REG_COUNT = 17,
    GDB_ARM_CPSR_REGNO = 16,
};

static size_t emu_get_reg_bytes(int regno) {
    return regno >= 0 && regno < GDB_ARM_REG_COUNT ? sizeof(uint32_t) : 0;
}
static int emu_read_reg(void *args __attribute__((unused)), int index, void *value) {
    if (index < 0 || index >= GDB_ARM_REG_COUNT || value == NULL) {
        return EINVAL;
    }

    const uint32_t reg = index == GDB_ARM_CPSR_REGNO
                             ? static_cast<uint32_t>(Dynarmic_reg_1read_1cpsr())
                             : Dynarmic_reg_1read(index);
    memcpy(value, &reg, sizeof(reg));
    return 0;
}
static int emu_write_reg(void *args __attribute__((unused)), int index, void *value) {
    if (index < 0 || index >= GDB_ARM_REG_COUNT || value == NULL) {
        return EINVAL;
    }

    uint32_t reg;
    memcpy(&reg, value, sizeof(reg));
    return index == GDB_ARM_CPSR_REGNO ? Dynarmic_reg_1write_1cpsr(reg)
                                        : Dynarmic_reg_1write(index, reg);
}
static int emu_read_mem(void *args __attribute__((unused)), size_t addr, size_t len, void *val) {
    if (addr > UINT32_MAX || len > UINT32_MAX - addr || (len != 0 && val == NULL)) {
        return EFAULT;
    }
    return Dynarmic_debugger_mem_read(
               addr, len, static_cast<char *>(val))
               ? EFAULT
               : 0;
}
static int emu_write_mem(void *args __attribute__((unused)), size_t addr, size_t len, void *val) {
    if (addr > UINT32_MAX || len > UINT32_MAX - addr || (len != 0 && val == NULL)) {
        return EFAULT;
    }
    return Dynarmic_debugger_mem_write(
               addr, len, static_cast<char *>(val))
               ? EFAULT
               : 0;
}
static size_t emu_alloc_mem(
        void *args __attribute__((unused)),
        size_t len,
        target_memory_protection_t protection) {
    if (len == 0 || len > UINT32_MAX - DYN_PAGE_MASK) {
        return 0;
    }

    const u32 alignedLength = static_cast<u32>(
        (len + DYN_PAGE_MASK) & ~DYN_PAGE_MASK);
    int nativeProtection = 0;
    if ((protection & TARGET_MEMORY_READ) != 0) {
        nativeProtection |= PROT_READ;
    }
    if ((protection & TARGET_MEMORY_WRITE) != 0) {
        nativeProtection |= PROT_WRITE;
    }
    if ((protection & TARGET_MEMORY_EXECUTE) != 0) {
        /*
         * Dynarmic fetches instructions through the host page-table pointer,
         * while Dynarmic_mmap deliberately strips host PROT_EXEC.  Keep every
         * executable debugger scratch page host-readable even if LLDB asks
         * for execute-only memory.
         */
        nativeProtection |= PROT_READ | PROT_EXEC;
    }

    const u32 address = Dynarmic_mmap(
        0, alignedLength, nativeProtection,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (address == UINT32_MAX) {
        return 0;
    }
    debuggerInferiorAllocations[address] = alignedLength;
    return address;
}
static int emu_free_mem(void *args __attribute__((unused)), size_t addr) {
    if (addr > UINT32_MAX) {
        return EINVAL;
    }
    const auto allocation =
        debuggerInferiorAllocations.find(static_cast<u32>(addr));
    if (allocation == debuggerInferiorAllocations.end()) {
        return EINVAL;
    }

    if (threadHandle.jit != nullptr) {
        threadHandle.jit->InvalidateCacheRange(
            allocation->first, allocation->second);
    }
    if (Dynarmic_munmap(allocation->first, allocation->second) != 0) {
        return errno != 0 ? errno : EFAULT;
    }
    debuggerInferiorAllocations.erase(allocation);
    return 0;
}
static bool emu_set_bp(void *args __attribute__((unused)),
                       size_t addr,
                       size_t kind,
                       bp_type_t type) {
    return type == BP_SOFTWARE &&
           Dynarmic_debugger_set_breakpoint(addr, kind);
}
static bool emu_del_bp(void *args __attribute__((unused)),
                       size_t addr,
                       size_t kind,
                       bp_type_t type) {
    return type == BP_SOFTWARE &&
           Dynarmic_debugger_delete_breakpoint(addr, kind);
}
static gdb_action_t emu_action_for_halt(Dynarmic::HaltReason reason) {
    return Dynarmic::Has(reason, LC32HaltReasonExit) ? ACT_SHUTDOWN : ACT_RESUME;
}
static gdb_action_t emu_cont(void *args __attribute__((unused))) {
    return emu_action_for_halt(Dynarmic_emu_1resume());
}
static gdb_action_t emu_stepi(void *args __attribute__((unused))) {
    return emu_action_for_halt(Dynarmic_emu_1step());
}
static void emu_on_interrupt(void *args __attribute__((unused))) {
    Dynarmic_emu_1stop();
}
static int emu_get_stop_signal(void *args __attribute__((unused))) {
    return Dynarmic_emu_1get_1stop_1signal();
}
static void emu_set_resume_signal(void *args __attribute__((unused)),
                                  int signal) {
    // There is no host signal to inject into Dynarmic.  Fatal guest signals
    // are kept pending so LLDB's C/S actions re-report the unresolved stop;
    // lowercase c/s clears the pending signal by passing zero here.
    Dynarmic_emu_1set_1resume_1signal(signal);
}
static bool GetMainBinaryMetadata(u32 *slide, const uuid_command **uuid) {
    if (guestMappingLen == 0 || guestMappings[0].start == 0) {
        return false;
    }

    const mach_header *header =
        reinterpret_cast<const mach_header *>(guestMappings[0].hostAddr);
    if (header == NULL || header->magic != MH_MAGIC) {
        return false;
    }

    uintptr_t cursor = reinterpret_cast<uintptr_t>(header) + sizeof(*header);
    const uintptr_t commandsEnd = cursor + header->sizeofcmds;
    if (commandsEnd < cursor) {
        return false;
    }

    bool foundSlide = false;
    const uuid_command *foundUUID = NULL;
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (cursor > commandsEnd ||
            commandsEnd - cursor < sizeof(load_command)) {
            return false;
        }
        const load_command *command = reinterpret_cast<const load_command *>(cursor);
        if (command->cmdsize < sizeof(*command) ||
            command->cmdsize > commandsEnd - cursor) {
            return false;
        }
        if (command->cmd == LC_SEGMENT) {
            const segment_command *segment = reinterpret_cast<const segment_command *>(command);
            if (!foundSlide &&
                strncmp(segment->segname, "__PAGEZERO",
                        sizeof(segment->segname)) != 0) {
                *slide = guestMappings[0].start - segment->vmaddr;
                foundSlide = true;
            }
        } else if (command->cmd == LC_UUID &&
                   command->cmdsize >= sizeof(uuid_command)) {
            foundUUID = reinterpret_cast<const uuid_command *>(command);
        }
        cursor += command->cmdsize;
    }

    if (uuid != NULL) {
        *uuid = foundUUID;
    }
    return foundSlide;
}
static const char *emu_get_offsets(void *args __attribute__((unused))) {
    static char offsets[64];
    u32 slide;
    if (!GetMainBinaryMetadata(&slide, NULL)) {
        return NULL;
    }

    // qOffsets takes the load slide, not the mapped __TEXT address: LLDB adds
    // this value to file addresses.
    snprintf(offsets, sizeof(offsets), "Text=%x;Data=%x;Bss=%x", slide,
             slide, slide);
    return offsets;
}
static const char *emu_get_libraries_xml(void *args __attribute__((unused))) {
    static std::string libraryList;
    static size_t snapshotGeneration = static_cast<size_t>(-1);
    if (snapshotGeneration == guestMappingGeneration) {
        return libraryList.c_str();
    }

    libraryList.clear();
    libraryList.reserve(static_cast<size_t>(guestMappingLen) * 128);
    libraryList = "<?xml version=\"1.0\"?><library-list version=\"1.0\">";

    for (int i = 0; i < guestMappingLen; ++i) {
        const guest_file_mapping &mapping = guestMappings[i];
        if (mapping.name == NULL || mapping.start == 0 ||
            (mapping.debuggerPathResolved &&
             access(mapping.name, R_OK) != 0)) {
            continue;
        }

        // dyld can notify us about the executable and dyld again.  Reporting
        // the same load address twice only creates duplicate modules in LLDB.
        bool duplicate = false;
        for (int previous = 0; previous < i; ++previous) {
            if (guestMappings[previous].start == mapping.start &&
                guestMappings[previous].name != NULL &&
                (!guestMappings[previous].debuggerPathResolved ||
                 access(guestMappings[previous].name, R_OK) == 0)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            continue;
        }

        std::string entry = "<library name=\"";
        for (const char *p = mapping.name; *p != '\0'; ++p) {
            switch (*p) {
            case '&': entry += "&amp;"; break;
            case '\"': entry += "&quot;"; break;
            case '\'': entry += "&apos;"; break;
            case '<': entry += "&lt;"; break;
            case '>': entry += "&gt;"; break;
            default: entry += *p; break;
            }
        }

        // LLDB's qXfer:libraries parser takes the first <section> address as
        // the absolute module base.
        char suffix[80];
        snprintf(suffix, sizeof(suffix),
                 "\"><section address=\"0x%x\"/></library>", mapping.start);
        entry += suffix;
        libraryList += entry;
    }
    libraryList += "</library-list>";
    snapshotGeneration = guestMappingGeneration;
    return libraryList.c_str();
}
static size_t emu_get_libraries_generation(void *args __attribute__((unused))) {
    return guestMappingGeneration;
}
static const char *emu_get_os_version(void *args __attribute__((unused))) {
    return guestOSVersion.empty() ? NULL : guestOSVersion.c_str();
}
static const char *emu_get_os_build(void *args __attribute__((unused))) {
    return guestOSBuild.empty() ? NULL : guestOSBuild.c_str();
}
static size_t emu_get_shlib_info_addr(void *args __attribute__((unused))) {
    return sharedHandle.dyld_info_guest_address;
}
struct DebuggerMachOImage {
    mach_header header;
    uint8_t uuid[16];
    bool hasUUID;
    std::vector<segment_command> segments;
};

static bool ReadDebuggerMachOImage(u32 loadAddress,
                                   DebuggerMachOImage *image) {
    if (image == NULL ||
        loadAddress > UINT32_MAX - sizeof(mach_header) ||
        Dynarmic_mem_1read(loadAddress, sizeof(image->header),
                           reinterpret_cast<char *>(&image->header)) != 0 ||
        image->header.magic != MH_MAGIC ||
        image->header.sizeofcmds > 1024 * 1024 ||
        loadAddress > UINT32_MAX - sizeof(mach_header) -
                          image->header.sizeofcmds) {
        return false;
    }

    image->hasUUID = false;
    image->segments.clear();
    std::vector<uint8_t> commands(image->header.sizeofcmds);
    if (!commands.empty() &&
        Dynarmic_mem_1read(loadAddress + sizeof(mach_header),
                           commands.size(),
                           reinterpret_cast<char *>(commands.data())) != 0) {
        return false;
    }

    size_t cursor = 0;
    for (uint32_t i = 0; i < image->header.ncmds; ++i) {
        if (cursor > commands.size() ||
            commands.size() - cursor < sizeof(load_command)) {
            return false;
        }

        load_command command;
        memcpy(&command, commands.data() + cursor, sizeof(command));
        if (command.cmdsize < sizeof(command) ||
            command.cmdsize > commands.size() - cursor) {
            return false;
        }

        if (command.cmd == LC_SEGMENT &&
            command.cmdsize >= sizeof(segment_command)) {
            segment_command segment;
            memcpy(&segment, commands.data() + cursor, sizeof(segment));
            image->segments.push_back(segment);
        } else if (command.cmd == LC_UUID &&
                   command.cmdsize >= sizeof(uuid_command)) {
            uuid_command uuid;
            memcpy(&uuid, commands.data() + cursor, sizeof(uuid));
            memcpy(image->uuid, uuid.uuid, sizeof(image->uuid));
            image->hasUUID = true;
        }
        cursor += command.cmdsize;
    }
    return !image->segments.empty();
}

struct DebuggerDyldImageInfo32 {
    u32 imageLoadAddress;
    u32 imageFilePath;
    u32 imageFileModDate;
};

static bool ReadDebuggerCString(u32 address, std::string *value) {
    if (address == 0 || value == NULL) {
        return false;
    }
    value->clear();
    while (value->size() < PATH_MAX - 1) {
        const char *chunk =
            static_cast<const char *>(get_memory(address));
        if (chunk == NULL) {
            return false;
        }
        const size_t pageRemaining =
            DYN_PAGE_SIZE - (address & DYN_PAGE_MASK);
        const size_t available =
            std::min(pageRemaining, PATH_MAX - 1 - value->size());
        const char *terminator =
            static_cast<const char *>(memchr(chunk, '\0', available));
        const size_t length =
            terminator != NULL ? static_cast<size_t>(terminator - chunk)
                               : available;
        value->append(chunk, length);
        if (terminator != NULL) {
            return true;
        }
        if (address > UINT32_MAX - available) {
            return false;
        }
        address += static_cast<u32>(available);
    }
    return false;
}

/*
 * dyld calls its debugger notifier before it sends this process's synthetic
 * Mach-port image notification.  LLDB immediately asks for full information
 * about the addresses passed to that notifier, so seed the debugger mappings
 * directly from the stopped notifier's r1/r2 arguments.
 */
static void RegisterDebuggerImagesFromDyldNotification() {
    const u32 mode = Dynarmic_reg_1read(0);
    const u32 count = Dynarmic_reg_1read(1);
    const u32 infosAddress = Dynarmic_reg_1read(2);
    if (mode != 0 || count == 0 || count > 4096 || infosAddress == 0 ||
        count > (UINT32_MAX - infosAddress) /
                    sizeof(DebuggerDyldImageInfo32)) {
        return;
    }

    std::vector<DebuggerDyldImageInfo32> infos(count);
    if (Dynarmic_mem_1read(
            infosAddress, infos.size() * sizeof(infos[0]),
            reinterpret_cast<char *>(infos.data())) != 0) {
        return;
    }

    for (const DebuggerDyldImageInfo32 &info : infos) {
        if (info.imageLoadAddress == 0 || info.imageFilePath == 0) {
            continue;
        }

        std::string guestPath;
        if (!ReadDebuggerCString(info.imageFilePath, &guestPath) ||
            guestPath.empty() || guestPath[0] != '/') {
            continue;
        }

        char hostPath[PATH_MAX];
        const bool pathResolved =
            ResolveDebuggerImagePath(guestPath.c_str(), hostPath);
        const char *mappingName =
            pathResolved ? hostPath : guestPath.c_str();

        DebuggerMachOImage image;
        if (!ReadDebuggerMachOImage(info.imageLoadAddress, &image)) {
            continue;
        }
        u32 textSize = 0;
        for (const segment_command &segment : image.segments) {
            if (strncmp(segment.segname, SEG_TEXT,
                        sizeof(segment.segname)) == 0) {
                textSize = segment.vmsize;
                break;
            }
        }
        if (textSize == 0 ||
            info.imageLoadAddress > UINT32_MAX - textSize) {
            continue;
        }

        int mappingIndex = -1;
        for (int i = 0; i < guestMappingLen; ++i) {
            if (guestMappings[i].start == info.imageLoadAddress) {
                mappingIndex = i;
                break;
            }
        }
        if (mappingIndex >= 0) {
            if (guestMappings[mappingIndex].debuggerPathResolved ||
                !pathResolved) {
                continue;
            }
        } else {
            if (guestMappingLen >= 1000) {
                break;
            }
            mappingIndex = guestMappingLen++;
        }

        char *newName = strdup(mappingName);
        if (newName == NULL) {
            if (mappingIndex == guestMappingLen - 1 &&
                guestMappings[mappingIndex].name == NULL) {
                --guestMappingLen;
            }
            continue;
        }
        free(const_cast<char *>(guestMappings[mappingIndex].name));
        guestMappings[mappingIndex].name = newName;
        guestMappings[mappingIndex].debuggerPathResolved = pathResolved;
        guestMappings[mappingIndex].start = info.imageLoadAddress;
        guestMappings[mappingIndex].end = info.imageLoadAddress + textSize;
        guestMappings[mappingIndex].hostAddr =
            reinterpret_cast<uintptr_t>(get_memory(info.imageLoadAddress));
        ++guestMappingGeneration;
    }
}

static void FormatDebuggerUUID(const uint8_t uuid[16], char output[37]) {
    snprintf(
        output, 37,
        "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-"
        "%02X%02X%02X%02X%02X%02X",
        uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6],
        uuid[7], uuid[8], uuid[9], uuid[10], uuid[11], uuid[12],
        uuid[13], uuid[14], uuid[15]);
}

static void AppendDebuggerJSONString(std::string &output,
                                     const char *value,
                                     size_t length) {
    output.push_back('"');
    for (size_t i = 0; i < length; ++i) {
        const unsigned char byte = static_cast<unsigned char>(value[i]);
        switch (byte) {
        case '"': output += "\\\""; break;
        case '\\': output += "\\\\"; break;
        case '\b': output += "\\b"; break;
        case '\f': output += "\\f"; break;
        case '\n': output += "\\n"; break;
        case '\r': output += "\\r"; break;
        case '\t': output += "\\t"; break;
        default:
            if (byte < 0x20) {
                char escape[7];
                snprintf(escape, sizeof(escape), "\\u%04x", byte);
                output += escape;
            } else {
                output.push_back(static_cast<char>(byte));
            }
            break;
        }
    }
    output.push_back('"');
}

static bool IsDebuggerMappingUsable(int index) {
    if (index < 0 || index >= guestMappingLen) {
        return false;
    }
    const guest_file_mapping &mapping = guestMappings[index];
    if (mapping.name == NULL || mapping.start == 0 ||
        (mapping.debuggerPathResolved && access(mapping.name, R_OK) != 0)) {
        return false;
    }
    for (int previous = 0; previous < index; ++previous) {
        const guest_file_mapping &candidate = guestMappings[previous];
        if (candidate.start == mapping.start && candidate.name != NULL &&
            (!candidate.debuggerPathResolved ||
             access(candidate.name, R_OK) == 0)) {
            return false;
        }
    }
    return true;
}

static const guest_file_mapping *FindDebuggerMapping(u32 loadAddress) {
    for (int i = 0; i < guestMappingLen; ++i) {
        if (IsDebuggerMappingUsable(i) &&
            guestMappings[i].start == loadAddress) {
            return &guestMappings[i];
        }
    }
    return NULL;
}

static bool AppendDebuggerImageJSON(
    std::string &output, const guest_file_mapping &mapping) {
    DebuggerMachOImage image;
    if (!ReadDebuggerMachOImage(mapping.start, &image)) {
        return false;
    }

    char uuid[37] = {};
    if (image.hasUUID) {
        FormatDebuggerUUID(image.uuid, uuid);
    }

    output += "{\"load_address\":";
    output += std::to_string(mapping.start);
    output += ",\"pathname\":";
    AppendDebuggerJSONString(output, mapping.name, strlen(mapping.name));
    output += ",\"uuid\":";
    AppendDebuggerJSONString(output, uuid, strlen(uuid));
    output += ",\"mach_header\":{\"magic\":";
    output += std::to_string(static_cast<uint32_t>(image.header.magic));
    output += ",\"cputype\":";
    output += std::to_string(static_cast<uint32_t>(image.header.cputype));
    output += ",\"cpusubtype\":";
    output += std::to_string(static_cast<uint32_t>(image.header.cpusubtype));
    output += ",\"filetype\":";
    output += std::to_string(static_cast<uint32_t>(image.header.filetype));
    output += "},\"segments\":[";

    for (size_t i = 0; i < image.segments.size(); ++i) {
        const segment_command &segment = image.segments[i];
        if (i != 0) {
            output.push_back(',');
        }
        output += "{\"name\":";
        AppendDebuggerJSONString(
            output, segment.segname,
            strnlen(segment.segname, sizeof(segment.segname)));
        output += ",\"vmaddr\":";
        output += std::to_string(segment.vmaddr);
        output += ",\"vmsize\":";
        output += std::to_string(segment.vmsize);
        output += ",\"fileoff\":";
        output += std::to_string(segment.fileoff);
        output += ",\"filesize\":";
        output += std::to_string(segment.filesize);
        output += ",\"maxprot\":";
        output += std::to_string(segment.maxprot);
        output.push_back('}');
    }
    output += "]}";
    return true;
}

static const char *emu_get_loaded_libraries_json(
    void *args __attribute__((unused)), const char *request) {
    static std::string response;
    if (strstr(request, "\"solib_addresses\"") != NULL) {
        RegisterDebuggerImagesFromDyldNotification();
    }
    response = "{\"images\":[";
    bool first = true;

    const char *addressList = strstr(request, "\"solib_addresses\"");
    if (addressList != NULL) {
        addressList = strchr(addressList, '[');
        const char *listEnd =
            addressList != NULL ? strchr(addressList, ']') : NULL;
        if (addressList != NULL && listEnd != NULL) {
            ++addressList;
            while (addressList < listEnd) {
                while (addressList < listEnd &&
                       (isspace(static_cast<unsigned char>(*addressList)) ||
                        *addressList == ',')) {
                    ++addressList;
                }
                if (addressList == listEnd) {
                    break;
                }

                char *numberEnd = NULL;
                errno = 0;
                const unsigned long long address =
                    strtoull(addressList, &numberEnd, 10);
                if (errno != 0 || numberEnd == addressList ||
                    numberEnd > listEnd || address > UINT32_MAX) {
                    break;
                }
                addressList = numberEnd;

                const guest_file_mapping *mapping =
                    FindDebuggerMapping(static_cast<u32>(address));
                if (mapping == NULL) {
                    continue;
                }
                const size_t oldSize = response.size();
                if (!first) {
                    response.push_back(',');
                }
                if (!AppendDebuggerImageJSON(response, *mapping)) {
                    response.resize(oldSize);
                    continue;
                }
                first = false;
            }
        }
    } else {
        const bool addressOnly =
            strstr(request, "\"address-only\"") != NULL ||
            strstr(request, "\"report_load_commands\":false") != NULL;
        for (int i = 0; i < guestMappingLen; ++i) {
            if (!IsDebuggerMappingUsable(i)) {
                continue;
            }

            // Validate now so every address advertised here can be returned
            // in LLDB's subsequent full-information request.
            DebuggerMachOImage image;
            if (!ReadDebuggerMachOImage(guestMappings[i].start, &image)) {
                continue;
            }
            if (addressOnly) {
                if (!first) {
                    response.push_back(',');
                }
                response += "{\"load_address\":";
                response += std::to_string(guestMappings[i].start);
                response.push_back('}');
            } else {
                const size_t oldSize = response.size();
                if (!first) {
                    response.push_back(',');
                }
                if (!AppendDebuggerImageJSON(response, guestMappings[i])) {
                    response.resize(oldSize);
                    continue;
                }
            }
            first = false;
        }
    }

    response += "]}";
    return response.c_str();
}
static void emu_set_cpu(void *args __attribute__((unused)), int cpuid) {
    // mini-gdbstub exposes its one CPU as remote thread ID 1.
    (void)cpuid;
}
static int emu_get_cpu(void *args __attribute__((unused))) {
    return 1;
}
struct target_ops emu_ops = {
    .get_reg_bytes = emu_get_reg_bytes,
    .read_reg = emu_read_reg,
    .write_reg = emu_write_reg,
    .read_mem = emu_read_mem,
    .write_mem = emu_write_mem,
    .alloc_mem = emu_alloc_mem,
    .free_mem = emu_free_mem,
    .cont = emu_cont,
    .stepi = emu_stepi,
    .set_bp = emu_set_bp,
    .del_bp = emu_del_bp,
    .on_interrupt = emu_on_interrupt,
    .get_libraries_xml = emu_get_libraries_xml,
    .get_offsets = emu_get_offsets,
    .set_cpu = emu_set_cpu,
    .get_cpu = emu_get_cpu,
    .get_stop_signal = emu_get_stop_signal,
    .set_resume_signal = emu_set_resume_signal,
    .get_libraries_generation = emu_get_libraries_generation,
    .get_os_version = emu_get_os_version,
    .get_os_build = emu_get_os_build,
    .get_shlib_info_addr = emu_get_shlib_info_addr,
    .get_loaded_libraries_json = emu_get_loaded_libraries_json,
};

int setupGDBStub(const char *gdbListenAddress) {
    extern const char *TARGET_ARMV7;
    arch_info_t info = {
        .smp = 1,
        .reg_num = GDB_ARM_REG_COUNT,
        .target_desc = (char *)TARGET_ARMV7,
    };
    if (!gdbstub_init(&sharedHandle.gdbstub, &emu_ops, info,
                      const_cast<char *>(gdbListenAddress))) {
        fprintf(stderr, "Fail to create socket.\n");
        return -1;
    }
    return 0;
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
    
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header);
    load_command *lc;
    int firstIndex = 0;
    u32 firstSegmentVMAddr = 0;
    for (uint i = 0; i < header->ncmds; i++, cur += lc->cmdsize) {
        lc = (load_command *)cur;
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
            u32 mappedAddr = 0;
            if(filesize > 0) {
                mappedAddr = Dynarmic_direct_mmap(target + seg->vmaddr, filesize, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, (void *)(map + seg->fileoff), 0);
                assert(mappedAddr != -1);
            }
            
            u32 vmMappedAddr = Dynarmic_mmap(target + seg->vmaddr + filesize, seg->vmsize - filesize, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
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
            state->__pc += target;
            for (int i = 0; i < 13; i++) {
                threadHandle.jit->Regs()[i] = state->__r[i];
            }
            threadHandle.jit->Regs()[Reg::SP] = state->__sp;
            threadHandle.jit->Regs()[Reg::LR] = state->__lr;
            threadHandle.jit->Regs()[Reg::PC] = state->__pc;
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

u32 prependString(u32& address, const char* fmt, ...) {
    char buffer[1000];
    va_list args;
    va_start(args, fmt);
    u32 len = vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    address -= len + 1;
    Dynarmic_mem_1write(address, len, buffer);
    return address;
}

void setupPathEnvs(char* argv0) {
    char path[PATH_MAX];
    
    // resolve default rootfs path to /path/to/LiveExec32.app/RootFS
    snprintf(path, sizeof(path), "%s/RootFS", dirname(argv0));
    setenv("ROOT_PATH", path, 0);
    const char *rootPath = getenv("ROOT_PATH");

    // Tell LLDB which DeviceSupport SDK matches the emulated root.  In
    // qHostInfo, os_version is plain text and os_build is hex encoded by the
    // gdbstub.  PlatformRemoteiOS uses these fields to select the matching
    // Symbols tree.
    snprintf(path, sizeof(path),
             "%s/System/Library/CoreServices/SystemVersion.plist", rootPath);
    FILE *systemVersionFile = fopen(path, "r");
    if (systemVersionFile != NULL) {
        std::string contents;
        char chunk[1024];
        size_t bytesRead;
        while ((bytesRead = fread(chunk, 1, sizeof(chunk), systemVersionFile)) !=
               0) {
            contents.append(chunk, bytesRead);
        }
        fclose(systemVersionFile);

        const auto readPlistString = [&contents](const char *key) {
            const std::string keyTag = std::string("<key>") + key + "</key>";
            size_t valueStart = contents.find(keyTag);
            if (valueStart == std::string::npos) {
                return std::string();
            }
            valueStart = contents.find("<string>", valueStart + keyTag.size());
            if (valueStart == std::string::npos) {
                return std::string();
            }
            valueStart += strlen("<string>");
            const size_t valueEnd = contents.find("</string>", valueStart);
            return valueEnd == std::string::npos
                       ? std::string()
                       : contents.substr(valueStart, valueEnd - valueStart);
        };

        guestOSVersion = readPlistString("ProductVersion");
        guestOSBuild = readPlistString("ProductBuildVersion");
        if (!guestOSVersion.empty() || !guestOSBuild.empty()) {
            printf("LC32: guest OS %s (%s)\n", guestOSVersion.c_str(),
                   guestOSBuild.c_str());
        }
    }

    // Prefer exact extracted cache images when the debugger runs on this same
    // Mac.  LLDB_SYMBOL_ROOT may name either a DeviceSupport directory or its
    // Symbols subdirectory.  Otherwise discover Xcode's matching version/build
    // directory, including model-prefixed names such as
    // "iPhone5,1 10.3.3 (14G60)".
    const auto useSymbolsRoot = [](const std::string &candidate) {
        if (candidate.empty()) {
            return false;
        }
        const std::string nested = candidate + "/Symbols";
        if (access(nested.c_str(), R_OK | X_OK) == 0) {
            debuggerSymbolsRoot = nested;
            return true;
        }
        if (access(candidate.c_str(), R_OK | X_OK) == 0) {
            debuggerSymbolsRoot = candidate;
            return true;
        }
        return false;
    };

    const char *configuredSymbolsRoot = getenv("LLDB_SYMBOL_ROOT");
    if (configuredSymbolsRoot != NULL) {
        useSymbolsRoot(configuredSymbolsRoot);
    }
    if (debuggerSymbolsRoot.empty() && !guestOSVersion.empty() &&
        !guestOSBuild.empty()) {
        const char *home = getenv("HOME");
        if (home != NULL) {
            const std::string deviceSupport =
                std::string(home) +
                "/Library/Developer/Xcode/iOS DeviceSupport";
            DIR *directory = opendir(deviceSupport.c_str());
            if (directory != NULL) {
                const std::string suffix =
                    " " + guestOSVersion + " (" + guestOSBuild + ")";
                const std::string exact =
                    guestOSVersion + " (" + guestOSBuild + ")";
                while (dirent *entry = readdir(directory)) {
                    const std::string name = entry->d_name;
                    const bool matches =
                        name == exact ||
                        (name.size() >= suffix.size() &&
                         name.compare(name.size() - suffix.size(),
                                      suffix.size(), suffix) == 0);
                    if (matches &&
                        useSymbolsRoot(deviceSupport + "/" + name)) {
                        break;
                    }
                }
                closedir(directory);
            }
        }
    }
    if (!debuggerSymbolsRoot.empty()) {
        printf("LC32: debugger symbols root %s\n",
               debuggerSymbolsRoot.c_str());
    }

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

extern "C"
int main(int argc, char* argv[], char* envp[]) {
    if (argc == 1) {
        //printf("Usage: %s <path> argv...\n", argv[0]);
        // TODO: display help or setup wizard
        return 1;
    }
    
    // initialize page table, callback, Jit objects, paths
    Dynarmic_nativeInitialize();
    setupPathEnvs(argv[0]);
    
    // Make the executable and its adjacent bundle resources visible at the
    // path dyld publishes through _NSGetExecutablePath.  Without this mount,
    // guest file syscalls prepend ROOT_PATH to an absolute host-side argv[1],
    // causing CFBundleGetMainBundle() to return NULL.
    char resolvedExecPath[PATH_MAX];
    const char *execPath = argv[1];
    if (realpath(execPath, resolvedExecPath) != NULL) {
        execPath = resolvedExecPath;
        const char *lastSlash = strrchr(execPath, '/');
        if (lastSlash != NULL && lastSlash != execPath) {
            const std::string execDirectory(
                execPath, static_cast<size_t>(lastSlash - execPath));
            sharedHandle.fs->addMountpoint(execDirectory, execDirectory);
        }
    }

    // map the main executable first
    u32 execAddr = Dynarmic_map_file(false, 0x11000000, execPath);
    
    // map dyld
    const char *dyldPath = getenv("DYLD_PATH");
    printf("Loading dyld at DYLD_PATH %s\n", dyldPath);
    Dynarmic_map_file(true, 0x10000000, dyldPath);
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
    u32 dyldStackGuardStart = Dynarmic_mmap(0x80000000, 0x1000, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    u32 dyldStack = Dynarmic_mmap(0x80000000, 0xff000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Dynarmic_mmap(0x80000000, 0x1000, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    
    u32 dyldStackPtr = dyldStack - 0x1000 + 0x100000;
    
    // write strings to the stack
    u32 guest_apple[] = {
        0, // separator
        // apple
        // comment out these if you want ASLR
        prependString(dyldStackPtr, "malloc_entropy=0xf0ef08e3de46c995,0xd5adb183cbc1fed0"),
        prependString(dyldStackPtr, "stack_guard=0xff39f7772c708a80"),
        
        prependString(dyldStackPtr, "pfz=0xffffffff"),
        prependString(dyldStackPtr, "main_stack=0x%x,0xff000,0x%x,0x100000", dyldStackGuardStart + 0x100000, dyldStackGuardStart),
        prependString(dyldStackPtr, "%s", execPath),
    };
    u32 guest_envp[] = {
        0, // separator
        // envp
        //prependString(dyldStackPtr, "OBJC_PRINT_LOAD_METHODS=1"),
        //prependString(dyldStackPtr, "OBJC_PRINT_RESOLVED_METHODS=1"),
        //prependString(dyldStackPtr, "OBJC_PRINT_CLASS_SETUP=1"),
        prependString(dyldStackPtr, "DYLD_SHARED_REGION=private"),
        prependString(dyldStackPtr, "DYLD_PRINT_OPTS=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_ENV=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_SEGMENTS=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_INITIALIZERS=1"),
        //prependString(dyldStackPtr, "MallocTracing=YES"),
        //prependString(dyldStackPtr, "MallocStackLogging=YES"),
        //prependString(dyldStackPtr, "MallocScribble=YES"),
        //prependString(dyldStackPtr, "MallocLogFile=/tmp/a.malloc.log")
    };
    u32 guest_argv[1000] = {0};
    guest_argv[0] = argc - 1;
    // CAUTION: write backwards!!
    for (int i = argc-1; i >= 1; i--) {
        guest_argv[i] = prependString(dyldStackPtr, "%s", argv[i]);
    }
    
    // align
    dyldStackPtr &= ~(sizeof(u32)-1);
    dyldStackPtr -= 0x1000;
    
    // calculate for alignment...
    int toBeWritten = sizeof(guest_apple) + sizeof(guest_envp) + sizeof(guest_argv) + sizeof(u32) * 2;
    dyldStackPtr -= (dyldStackPtr - toBeWritten) & 0xF;
    
    // write apple
    for (int i = 0; i < sizeof(guest_apple)/sizeof(u32); i++) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_apple[i]);
    }
    
    // write envp
    for (int i = 0; i < sizeof(guest_envp)/sizeof(u32); i++) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_envp[i]);
    }
    
    // write argv and argc
    for (int i = argc; i >= 0; i--) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_argv[i]);
    }
    
    // write main executable base
    sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), execAddr);
    
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
        Dynarmic_emu_1set_1debugger_1enabled(false);
        gdbstub_close(&sharedHandle.gdbstub);
        if (!gdbstubRan) {
            fprintf(stderr, "Fail to run in debug mode.\n");
            return -1;
        }
    } else {
        Dynarmic_emu_1start(threadHandle.jit->Regs()[15]);
    }
}
