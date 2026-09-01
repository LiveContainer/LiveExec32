#include "MachOImage.h"

#include <errno.h>
#include <libkern/OSByteOrder.h>
#include <limits.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define LC32_MACH_O_MAX_LOAD_COMMANDS 1000u
#define LC32_MACH_O_MAX_LOAD_COMMAND_BYTES (8u * 1024u * 1024u)
#define LC32_MACH_O_MAX_LOAD_COMMAND_SIZE (64u * 1024u)
#define LC32_THIN_MACH_O_ALIGN_EXPONENT 14u

typedef struct {
    uint32_t offset;
    uint32_t size;
} LC32LinkeditDataRange;

typedef struct {
    uint32_t linkeditCount;
    uint32_t encryptionCount;
    uint32_t codeSignatureCount;
    uint32_t buildVersionCount;
    uint32_t versionMinIPhoneOSCount;
    uint32_t linkeditDataRangeCount;
    LC32LinkeditDataRange
        linkeditDataRanges[LC32_MACH_O_MAX_LOAD_COMMANDS];
} LC32LoadCommandState;

static void LC32MachOSetError(
        char *buffer, size_t capacity, const char *format, ...) {
    if(buffer == NULL || capacity == 0) return;

    va_list arguments;
    va_start(arguments, format);
    (void)vsnprintf(buffer, capacity, format, arguments);
    va_end(arguments);
}

static bool LC32MachORangeFits(
        uint64_t offset, uint64_t size, uint64_t containerSize) {
    return offset <= containerSize && size <= containerSize - offset;
}

static bool LC32MachORangeContains(
        uint64_t outerOffset, uint64_t outerSize,
        uint64_t innerOffset, uint64_t innerSize) {
    return innerOffset >= outerOffset &&
        LC32MachORangeFits(
            innerOffset - outerOffset, innerSize, outerSize);
}

static bool LC32MachORangesOverlap(
        uint64_t firstOffset, uint64_t firstSize,
        uint64_t secondOffset, uint64_t secondSize) {
    return firstSize != 0 && secondSize != 0 &&
        firstOffset < secondOffset + secondSize &&
        secondOffset < firstOffset + firstSize;
}

static bool LC32MachOReadAt(
        int fd, void *buffer, size_t size, uint64_t offset) {
    if((buffer == NULL && size != 0) || offset > (uint64_t)INT64_MAX ||
            (uint64_t)size > (uint64_t)INT64_MAX - offset) {
        errno = EOVERFLOW;
        return false;
    }

    size_t completed = 0;
    while(completed < size) {
        const ssize_t amount = pread(fd,
            (uint8_t *)buffer + completed, size - completed,
            (off_t)(offset + completed));
        if(amount < 0) {
            if(errno == EINTR) continue;
            return false;
        }
        if(amount == 0) {
            errno = EIO;
            return false;
        }
        completed += (size_t)amount;
    }
    return true;
}

static uint32_t LC32MachOConvertUInt32(uint32_t value, bool swap) {
    return swap ? OSSwapInt32(value) : value;
}

static uint64_t LC32MachOConvertUInt64(uint64_t value, bool swap) {
    return swap ? OSSwapInt64(value) : value;
}

static uint32_t LC32MachOBaseCPUSubtype(cpu_subtype_t subtype) {
    return (uint32_t)subtype & ~(uint32_t)CPU_SUBTYPE_MASK;
}

static bool LC32MachOCPUTypeUses64BitHeader(cpu_type_t cpuType) {
    uint32_t abiMask = CPU_ARCH_ABI64;
#ifdef CPU_ARCH_ABI64_32
    abiMask |= CPU_ARCH_ABI64_32;
#endif
    return ((uint32_t)cpuType & abiMask) != 0;
}

static bool LC32MachOCommandHasString(
        const uint8_t *command, uint32_t commandSize,
        uint32_t stringOffset, uint32_t minimumOffset) {
    if(stringOffset < minimumOffset || stringOffset >= commandSize) {
        return false;
    }
    return memchr(command + stringOffset, '\0',
        commandSize - stringOffset) != NULL;
}

static bool LC32MachOValidateStringCommand(
        const uint8_t *commandBytes, uint32_t commandSize, bool swap,
        uint32_t minimumSize, size_t stringOffsetField) {
    if(commandSize < minimumSize ||
            stringOffsetField > minimumSize - sizeof(uint32_t)) {
        return false;
    }

    uint32_t rawStringOffset = 0;
    memcpy(&rawStringOffset, commandBytes + stringOffsetField,
        sizeof(rawStringOffset));
    const uint32_t stringOffset =
        LC32MachOConvertUInt32(rawStringOffset, swap);
    return LC32MachOCommandHasString(commandBytes, commandSize,
        stringOffset, minimumSize);
}

static bool LC32MachORecordLinkeditDataRange(
        uint32_t offset, uint32_t size,
        uint64_t sliceSize, uint64_t commandsEnd,
        LC32LoadCommandState *state) {
    /* Empty optional tables conventionally use 0/0.  Accept an in-file
     * offset too, because older linkers did not always canonicalize it. */
    if(size == 0) return offset == 0 || offset <= sliceSize;
    if(offset < commandsEnd ||
            !LC32MachORangeFits(offset, size, sliceSize) ||
            state->linkeditDataRangeCount >=
                LC32_MACH_O_MAX_LOAD_COMMANDS) {
        return false;
    }

    LC32LinkeditDataRange *range =
        &state->linkeditDataRanges[state->linkeditDataRangeCount++];
    range->offset = offset;
    range->size = size;
    return true;
}

static bool LC32MachOValidateLinkeditDataCommand(
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint64_t commandsEnd,
        LC32LoadCommandState *state) {
    if(commandSize < sizeof(struct linkedit_data_command)) return false;

    struct linkedit_data_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    return LC32MachORecordLinkeditDataRange(
        LC32MachOConvertUInt32(command.dataoff, swap),
        LC32MachOConvertUInt32(command.datasize, swap),
        sliceSize, commandsEnd, state);
}

static bool LC32MachOValidateBuildVersion(
        const uint8_t *commandBytes, uint32_t commandSize, bool swap,
        uint32_t commandOffset, LC32MachOSlice *slice,
        LC32LoadCommandState *state) {
    if(commandSize < sizeof(struct build_version_command) ||
            ++state->buildVersionCount > 1) {
        return false;
    }

    struct build_version_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t toolCount =
        LC32MachOConvertUInt32(command.ntools, swap);
    if(toolCount >
            (commandSize - sizeof(command)) /
                sizeof(struct build_tool_version)) {
        return false;
    }

    slice->hasBuildVersion = true;
    slice->buildVersionCommandOffset = commandOffset;
    slice->buildVersionPlatform =
        LC32MachOConvertUInt32(command.platform, swap);
    slice->buildVersionMinOS =
        LC32MachOConvertUInt32(command.minos, swap);
    slice->buildVersionSDK =
        LC32MachOConvertUInt32(command.sdk, swap);
    return true;
}

static bool LC32MachOValidateVersionMin(
        uint32_t commandType,
        const uint8_t *commandBytes, uint32_t commandSize, bool swap,
        LC32MachOSlice *slice, LC32LoadCommandState *state) {
    if(commandSize < sizeof(struct version_min_command)) return false;
    if(commandType != LC_VERSION_MIN_IPHONEOS) return true;
    if(++state->versionMinIPhoneOSCount > 1) return false;

    struct version_min_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    slice->hasVersionMinIPhoneOS = true;
    slice->versionMinIPhoneOSSDK =
        LC32MachOConvertUInt32(command.sdk, swap);
    return true;
}

static bool LC32MachOValidateLinkerOptions(
        const uint8_t *commandBytes, uint32_t commandSize, bool swap) {
    if(commandSize < sizeof(struct linker_option_command)) return false;

    struct linker_option_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t optionCount =
        LC32MachOConvertUInt32(command.count, swap);
    uint32_t offset = sizeof(command);
    for(uint32_t index = 0; index < optionCount; index++) {
        if(offset >= commandSize) return false;
        const uint8_t *terminator = memchr(
            commandBytes + offset, '\0', commandSize - offset);
        if(terminator == NULL) return false;
        offset = (uint32_t)(terminator - commandBytes) + 1;
    }
    return true;
}

static bool LC32MachOValidateSegment32(
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint32_t commandOffset,
        LC32MachOSlice *slice, LC32LoadCommandState *state) {
    if(!slice->is32Bit || commandSize < sizeof(struct segment_command)) {
        return false;
    }

    struct segment_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t sectionCount =
        LC32MachOConvertUInt32(command.nsects, swap);
    if(sectionCount >
            (UINT32_MAX - sizeof(command)) / sizeof(struct section) ||
            sizeof(command) +
                (uint64_t)sectionCount * sizeof(struct section) !=
                    commandSize) {
        return false;
    }

    const uint64_t vmAddress =
        LC32MachOConvertUInt32(command.vmaddr, swap);
    const uint64_t vmSize =
        LC32MachOConvertUInt32(command.vmsize, swap);
    const uint64_t fileOffset =
        LC32MachOConvertUInt32(command.fileoff, swap);
    const uint64_t fileSize =
        LC32MachOConvertUInt32(command.filesize, swap);
    if(!LC32MachORangeFits(fileOffset, fileSize, sliceSize) ||
            vmAddress > UINT64_MAX - vmSize) {
        return false;
    }

    if(strncmp(command.segname, SEG_LINKEDIT,
            sizeof(command.segname)) == 0) {
        if(++state->linkeditCount > 1 || fileSize > vmSize) return false;
        slice->hasLinkedit = true;
        slice->linkeditCommandOffset = commandOffset;
        slice->linkeditVMAddress = vmAddress;
        slice->linkeditVMSize = vmSize;
        slice->linkeditFileOffset = fileOffset;
        slice->linkeditFileSize = fileSize;
    }
    return true;
}

static bool LC32MachOValidateSegment64(
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint32_t commandOffset,
        LC32MachOSlice *slice, LC32LoadCommandState *state) {
    if(slice->is32Bit || commandSize < sizeof(struct segment_command_64)) {
        return false;
    }

    struct segment_command_64 command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t sectionCount =
        LC32MachOConvertUInt32(command.nsects, swap);
    if(sectionCount >
            (UINT32_MAX - sizeof(command)) / sizeof(struct section_64) ||
            sizeof(command) +
                (uint64_t)sectionCount * sizeof(struct section_64) !=
                    commandSize) {
        return false;
    }

    const uint64_t vmAddress =
        LC32MachOConvertUInt64(command.vmaddr, swap);
    const uint64_t vmSize =
        LC32MachOConvertUInt64(command.vmsize, swap);
    const uint64_t fileOffset =
        LC32MachOConvertUInt64(command.fileoff, swap);
    const uint64_t fileSize =
        LC32MachOConvertUInt64(command.filesize, swap);
    if(!LC32MachORangeFits(fileOffset, fileSize, sliceSize) ||
            vmAddress > UINT64_MAX - vmSize) {
        return false;
    }

    if(strncmp(command.segname, SEG_LINKEDIT,
            sizeof(command.segname)) == 0) {
        if(++state->linkeditCount > 1 || fileSize > vmSize) return false;
        slice->hasLinkedit = true;
        slice->linkeditCommandOffset = commandOffset;
        slice->linkeditVMAddress = vmAddress;
        slice->linkeditVMSize = vmSize;
        slice->linkeditFileOffset = fileOffset;
        slice->linkeditFileSize = fileSize;
    }
    return true;
}

static bool LC32MachOValidateEncryption(
        uint32_t commandType,
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint64_t commandsEnd,
        LC32MachOSlice *slice, LC32LoadCommandState *state) {
    const bool commandIs64Bit = commandType == LC_ENCRYPTION_INFO_64;
    const size_t minimumSize = commandIs64Bit ?
        sizeof(struct encryption_info_command_64) :
        sizeof(struct encryption_info_command);
    if(commandIs64Bit == slice->is32Bit || commandSize < minimumSize ||
            ++state->encryptionCount > 1) {
        return false;
    }

    struct encryption_info_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t cryptOffset =
        LC32MachOConvertUInt32(command.cryptoff, swap);
    const uint32_t cryptSize =
        LC32MachOConvertUInt32(command.cryptsize, swap);
    const uint32_t cryptIdentifier =
        LC32MachOConvertUInt32(command.cryptid, swap);
    if(cryptSize != 0 && (cryptOffset < commandsEnd ||
            !LC32MachORangeFits(cryptOffset, cryptSize, sliceSize))) {
        return false;
    }
    slice->encryptionOffset = cryptOffset;
    slice->encryptionSize = cryptSize;
    slice->encryptionIdentifier = cryptIdentifier;
    slice->encrypted = cryptIdentifier != 0;
    return true;
}

static bool LC32MachOValidateCodeSignature(
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint64_t commandsEnd,
        uint32_t commandOffset, LC32MachOSlice *slice,
        LC32LoadCommandState *state) {
    /* XNU's load_code_signature() requires this command to be exactly the
     * published structure size. */
    if(commandSize != sizeof(struct linkedit_data_command) ||
            ++state->codeSignatureCount > 1) {
        return false;
    }

    struct linkedit_data_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint32_t signatureOffset =
        LC32MachOConvertUInt32(command.dataoff, swap);
    const uint32_t signatureSize =
        LC32MachOConvertUInt32(command.datasize, swap);
    if(signatureSize == 0 || signatureOffset < commandsEnd ||
            !LC32MachORangeFits(
                signatureOffset, signatureSize, sliceSize)) {
        return false;
    }

    slice->hasCodeSignature = true;
    slice->codeSignatureOffset = signatureOffset;
    slice->codeSignatureSize = signatureSize;
    slice->codeSignatureCommandOffset = commandOffset;
    return true;
}

static bool LC32MachOValidateDylibCommand(
        const uint8_t *commandBytes, uint32_t commandSize, bool swap) {
    return LC32MachOValidateStringCommand(commandBytes, commandSize, swap,
        sizeof(struct dylib_command),
        offsetof(struct dylib_command, dylib.name.offset));
}

static bool LC32MachOValidateRPathCommand(
        const uint8_t *commandBytes, uint32_t commandSize, bool swap) {
    return LC32MachOValidateStringCommand(commandBytes, commandSize, swap,
        sizeof(struct rpath_command),
        offsetof(struct rpath_command, path.offset));
}

#ifdef LC_FILESET_ENTRY
static bool LC32MachOValidateFilesetEntry(
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint64_t commandsEnd) {
    if(commandSize < sizeof(struct fileset_entry_command)) return false;
    struct fileset_entry_command command = {0};
    memcpy(&command, commandBytes, sizeof(command));
    const uint64_t fileOffset =
        LC32MachOConvertUInt64(command.fileoff, swap);
    const uint32_t identifierOffset =
        LC32MachOConvertUInt32(command.entry_id.offset, swap);
    return fileOffset >= commandsEnd && fileOffset < sliceSize &&
        LC32MachOCommandHasString(
            commandBytes, commandSize, identifierOffset, sizeof(command));
}
#endif

static bool LC32MachOValidateLoadCommand(
        uint32_t commandType,
        const uint8_t *commandBytes, uint32_t commandSize,
        bool swap, uint64_t sliceSize, uint64_t commandsEnd,
        uint32_t commandOffset, LC32MachOSlice *slice,
        LC32LoadCommandState *state) {
    switch(commandType) {
        case LC_SEGMENT:
            return LC32MachOValidateSegment32(commandBytes, commandSize,
                swap, sliceSize, commandOffset, slice, state);
        case LC_SEGMENT_64:
            return LC32MachOValidateSegment64(commandBytes, commandSize,
                swap, sliceSize, commandOffset, slice, state);
        case LC_ENCRYPTION_INFO:
        case LC_ENCRYPTION_INFO_64:
            return LC32MachOValidateEncryption(commandType,
                commandBytes, commandSize, swap, sliceSize, commandsEnd,
                slice, state);
        case LC_CODE_SIGNATURE:
            return LC32MachOValidateCodeSignature(commandBytes, commandSize,
                swap, sliceSize, commandsEnd, commandOffset, slice, state);
        case LC_LOAD_DYLIB:
        case LC_ID_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB:
        case LC_LAZY_LOAD_DYLIB:
        case LC_LOAD_UPWARD_DYLIB:
            return LC32MachOValidateDylibCommand(
                commandBytes, commandSize, swap);
        case LC_RPATH:
            return LC32MachOValidateRPathCommand(
                commandBytes, commandSize, swap);
        case LC_LOAD_DYLINKER:
        case LC_ID_DYLINKER:
        case LC_DYLD_ENVIRONMENT:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct dylinker_command),
                offsetof(struct dylinker_command, name.offset));
        case LC_SUB_FRAMEWORK:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct sub_framework_command),
                offsetof(struct sub_framework_command, umbrella.offset));
        case LC_SUB_UMBRELLA:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct sub_umbrella_command),
                offsetof(struct sub_umbrella_command,
                    sub_umbrella.offset));
        case LC_SUB_CLIENT:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct sub_client_command),
                offsetof(struct sub_client_command, client.offset));
        case LC_SUB_LIBRARY:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct sub_library_command),
                offsetof(struct sub_library_command, sub_library.offset));
#ifdef LC_TARGET_TRIPLE
        case LC_TARGET_TRIPLE:
            return LC32MachOValidateStringCommand(
                commandBytes, commandSize, swap,
                sizeof(struct target_triple_command),
                offsetof(struct target_triple_command, triple.offset));
#endif
        case LC_SYMTAB:
            return commandSize >= sizeof(struct symtab_command);
        case LC_SYMSEG:
            return commandSize >= sizeof(struct symseg_command);
        case LC_DYSYMTAB:
            return commandSize >= sizeof(struct dysymtab_command);
        case LC_ROUTINES:
            return commandSize >= sizeof(struct routines_command);
        case LC_ROUTINES_64:
            return commandSize >= sizeof(struct routines_command_64);
        case LC_TWOLEVEL_HINTS:
            return commandSize >= sizeof(struct twolevel_hints_command);
        case LC_PREBIND_CKSUM:
            return commandSize >= sizeof(struct prebind_cksum_command);
        case LC_UUID:
            return commandSize >= sizeof(struct uuid_command);
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY:
            return commandSize >= sizeof(struct dyld_info_command);
        case LC_VERSION_MIN_MACOSX:
        case LC_VERSION_MIN_IPHONEOS:
        case LC_VERSION_MIN_TVOS:
        case LC_VERSION_MIN_WATCHOS:
            return LC32MachOValidateVersionMin(commandType,
                commandBytes, commandSize, swap, slice, state);
        case LC_MAIN:
            return commandSize >= sizeof(struct entry_point_command);
        case LC_SOURCE_VERSION:
            return commandSize >= sizeof(struct source_version_command);
        case LC_NOTE:
            return commandSize >= sizeof(struct note_command);
        case LC_BUILD_VERSION:
            return LC32MachOValidateBuildVersion(
                commandBytes, commandSize, swap,
                commandOffset, slice, state);
        case LC_LINKER_OPTION:
            return LC32MachOValidateLinkerOptions(
                commandBytes, commandSize, swap);
        case LC_THREAD:
        case LC_UNIXTHREAD:
            return commandSize >= sizeof(struct thread_command);
        case LC_SEGMENT_SPLIT_INFO:
        case LC_FUNCTION_STARTS:
        case LC_DATA_IN_CODE:
        case LC_DYLIB_CODE_SIGN_DRS:
        case LC_LINKER_OPTIMIZATION_HINT:
#ifdef LC_DYLD_EXPORTS_TRIE
        case LC_DYLD_EXPORTS_TRIE:
#endif
#ifdef LC_DYLD_CHAINED_FIXUPS
        case LC_DYLD_CHAINED_FIXUPS:
#endif
#ifdef LC_ATOM_INFO
        case LC_ATOM_INFO:
#endif
#ifdef LC_FUNCTION_VARIANTS
        case LC_FUNCTION_VARIANTS:
#endif
#ifdef LC_FUNCTION_VARIANT_FIXUPS
        case LC_FUNCTION_VARIANT_FIXUPS:
#endif
            return LC32MachOValidateLinkeditDataCommand(
                commandBytes, commandSize, swap,
                sliceSize, commandsEnd, state);
#ifdef LC_FILESET_ENTRY
        case LC_FILESET_ENTRY:
            return LC32MachOValidateFilesetEntry(commandBytes, commandSize,
                swap, sliceSize, commandsEnd);
#endif
        default:
            /* Preserve forward compatibility with commands understood by a
             * newer target dyld but not by this build's SDK. */
            return true;
    }
}

static bool LC32MachOParseSlice(
        int fd, uint64_t sliceOffset, uint64_t sliceSize,
        LC32MachOSlice *slice,
        char *errorBuffer, size_t errorBufferCapacity) {
    uint32_t magic = 0;
    if(sliceSize < sizeof(magic) ||
            !LC32MachOReadAt(fd, &magic, sizeof(magic), sliceOffset)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O slice is too short for a header");
        return false;
    }

    bool swap = false;
    bool is32Bit = false;
    uint32_t headerSize = 0;
    switch(magic) {
        case MH_MAGIC:
            is32Bit = true;
            headerSize = sizeof(struct mach_header);
            break;
        case MH_CIGAM:
            is32Bit = true;
            swap = true;
            headerSize = sizeof(struct mach_header);
            break;
        case MH_MAGIC_64:
            headerSize = sizeof(struct mach_header_64);
            break;
        case MH_CIGAM_64:
            swap = true;
            headerSize = sizeof(struct mach_header_64);
            break;
        default:
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "unsupported Mach-O slice magic 0x%08x", magic);
            return false;
    }

    if(sliceSize < headerSize) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O slice header is truncated");
        return false;
    }

    struct mach_header_64 header = {0};
    if(!LC32MachOReadAt(fd, &header, headerSize, sliceOffset)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "could not read Mach-O slice header: %s", strerror(errno));
        return false;
    }

    slice->cpuType = (cpu_type_t)LC32MachOConvertUInt32(
        (uint32_t)header.cputype, swap);
    slice->cpuSubtype = (cpu_subtype_t)LC32MachOConvertUInt32(
        (uint32_t)header.cpusubtype, swap);
    slice->fileType = LC32MachOConvertUInt32(header.filetype, swap);
    slice->is32Bit = is32Bit;
    slice->isByteSwapped = swap;
    slice->headerSize = headerSize;

    if(LC32MachOCPUTypeUses64BitHeader(slice->cpuType) == is32Bit) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O CPU type does not match its header width");
        return false;
    }

    const uint32_t commandCount =
        LC32MachOConvertUInt32(header.ncmds, swap);
    const uint32_t commandBytes =
        LC32MachOConvertUInt32(header.sizeofcmds, swap);
    const uint32_t commandAlignment = is32Bit ? 4u : 8u;
    if(commandCount == 0 ||
            commandCount > LC32_MACH_O_MAX_LOAD_COMMANDS ||
            commandBytes > LC32_MACH_O_MAX_LOAD_COMMAND_BYTES ||
            commandCount > commandBytes / sizeof(struct load_command) ||
            (commandBytes & (commandAlignment - 1)) != 0 ||
            !LC32MachORangeFits(headerSize, commandBytes, sliceSize)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O has an invalid load-command table");
        return false;
    }
    slice->loadCommandCount = commandCount;
    slice->loadCommandBytes = commandBytes;

    uint8_t *commands = malloc(commandBytes);
    const bool allocationFailed = commands == NULL;
    if(commands == NULL || !LC32MachOReadAt(fd, commands, commandBytes,
            sliceOffset + headerSize)) {
        const int readError = errno;
        free(commands);
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "could not read Mach-O load commands: %s",
            allocationFailed ? "out of memory" : strerror(readError));
        return false;
    }

    const uint64_t commandsEnd = (uint64_t)headerSize + commandBytes;
    uint32_t relativeOffset = 0;
    LC32LoadCommandState state = {0};
    for(uint32_t index = 0; index < commandCount; index++) {
        if(!LC32MachORangeFits(relativeOffset,
                sizeof(struct load_command), commandBytes)) {
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "Mach-O load-command header is truncated");
            free(commands);
            return false;
        }

        struct load_command command = {0};
        memcpy(&command, commands + relativeOffset, sizeof(command));
        const uint32_t commandType =
            LC32MachOConvertUInt32(command.cmd, swap);
        const uint32_t commandSize =
            LC32MachOConvertUInt32(command.cmdsize, swap);
        if(commandSize < sizeof(struct load_command) ||
                commandSize > LC32_MACH_O_MAX_LOAD_COMMAND_SIZE ||
                (commandSize & (commandAlignment - 1)) != 0 ||
                !LC32MachORangeFits(
                    relativeOffset, commandSize, commandBytes) ||
                !LC32MachOValidateLoadCommand(commandType,
                    commands + relativeOffset, commandSize,
                    swap, sliceSize, commandsEnd,
                    headerSize + relativeOffset, slice, &state)) {
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "Mach-O load command %u is malformed", index);
            free(commands);
            return false;
        }
        relativeOffset += commandSize;
    }
    free(commands);

    if(relativeOffset != commandBytes) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O load-command sizes do not match sizeofcmds");
        return false;
    }
    if(slice->hasLinkedit) {
        for(uint32_t index = 0;
                index < state.linkeditDataRangeCount; index++) {
            const LC32LinkeditDataRange *range =
                &state.linkeditDataRanges[index];
            if(!LC32MachORangeContains(
                    slice->linkeditFileOffset, slice->linkeditFileSize,
                    range->offset, range->size)) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "Mach-O linkedit data is outside its unique "
                    "__LINKEDIT segment");
                return false;
            }
        }
    }
    if(slice->hasCodeSignature && (!slice->hasLinkedit ||
            !LC32MachORangeContains(
                slice->linkeditFileOffset, slice->linkeditFileSize,
                slice->codeSignatureOffset, slice->codeSignatureSize))) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O code signature is outside its unique __LINKEDIT segment");
        return false;
    }
    if(slice->encrypted && slice->hasCodeSignature &&
            LC32MachORangesOverlap(
                slice->encryptionOffset, slice->encryptionSize,
                slice->codeSignatureOffset, slice->codeSignatureSize)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O encrypted and code-signature ranges overlap");
        return false;
    }
    return true;
}

static bool LC32MachOParseFat(
        int fd, uint64_t fileSize, uint32_t magic,
        LC32MachOImage *image,
        char *errorBuffer, size_t errorBufferCapacity) {
    if(fileSize < sizeof(struct fat_header)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "fat Mach-O header is truncated");
        return false;
    }

    struct fat_header header = {0};
    if(!LC32MachOReadAt(fd, &header, sizeof(header), 0)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "could not read fat Mach-O header: %s", strerror(errno));
        return false;
    }

    const bool isFat64 = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
    const bool swap = magic == FAT_CIGAM || magic == FAT_CIGAM_64;
    const uint32_t count =
        LC32MachOConvertUInt32(header.nfat_arch, swap);
    if(count == 0 || count > LC32_MAX_MACH_O_SLICES) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "fat Mach-O has an invalid slice count: %u", count);
        return false;
    }

    const size_t descriptorSize = isFat64 ?
        sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    if(fileSize < sizeof(header) ||
            count > (fileSize - sizeof(header)) / descriptorSize) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "fat Mach-O architecture table is truncated");
        return false;
    }
    const uint64_t tableSize =
        sizeof(header) + (uint64_t)count * descriptorSize;

    image->isFat = true;
    image->isFat64 = isFat64;
    image->isFatByteSwapped = swap;

    for(uint32_t index = 0; index < count; index++) {
        LC32MachOSlice descriptor = {0};
        const uint64_t descriptorOffset =
            sizeof(header) + (uint64_t)index * descriptorSize;
        if(isFat64) {
            struct fat_arch_64 architecture = {0};
            if(!LC32MachOReadAt(fd, &architecture,
                    sizeof(architecture), descriptorOffset)) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "could not read fat64 architecture: %s",
                    strerror(errno));
                return false;
            }
            descriptor.cpuType = (cpu_type_t)LC32MachOConvertUInt32(
                (uint32_t)architecture.cputype, swap);
            descriptor.cpuSubtype = (cpu_subtype_t)LC32MachOConvertUInt32(
                (uint32_t)architecture.cpusubtype, swap);
            descriptor.offset =
                LC32MachOConvertUInt64(architecture.offset, swap);
            descriptor.size =
                LC32MachOConvertUInt64(architecture.size, swap);
            descriptor.alignExponent =
                LC32MachOConvertUInt32(architecture.align, swap);
            if(LC32MachOConvertUInt32(architecture.reserved, swap) != 0) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "fat64 architecture %u has a nonzero reserved field",
                    index);
                return false;
            }
        } else {
            struct fat_arch architecture = {0};
            if(!LC32MachOReadAt(fd, &architecture,
                    sizeof(architecture), descriptorOffset)) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "could not read fat architecture: %s", strerror(errno));
                return false;
            }
            descriptor.cpuType = (cpu_type_t)LC32MachOConvertUInt32(
                (uint32_t)architecture.cputype, swap);
            descriptor.cpuSubtype = (cpu_subtype_t)LC32MachOConvertUInt32(
                (uint32_t)architecture.cpusubtype, swap);
            descriptor.offset =
                LC32MachOConvertUInt32(architecture.offset, swap);
            descriptor.size =
                LC32MachOConvertUInt32(architecture.size, swap);
            descriptor.alignExponent =
                LC32MachOConvertUInt32(architecture.align, swap);
        }

        if(descriptor.size == 0 || descriptor.alignExponent > 30 ||
                descriptor.offset < tableSize ||
                !LC32MachORangeFits(
                    descriptor.offset, descriptor.size, fileSize)) {
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "fat Mach-O slice %u has an invalid range", index);
            return false;
        }
        const uint64_t alignment =
            UINT64_C(1) << descriptor.alignExponent;
        if((descriptor.offset & (alignment - 1)) != 0) {
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "fat Mach-O slice %u has an invalid alignment", index);
            return false;
        }

        for(uint32_t previous = 0; previous < index; previous++) {
            const LC32MachOSlice *other = &image->slices[previous];
            if(descriptor.cpuType == other->cpuType &&
                    descriptor.cpuSubtype == other->cpuSubtype) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "fat Mach-O contains duplicate architecture entries");
                return false;
            }
            if(descriptor.offset < other->offset + other->size &&
                    other->offset < descriptor.offset + descriptor.size) {
                LC32MachOSetError(errorBuffer, errorBufferCapacity,
                    "fat Mach-O contains overlapping slices");
                return false;
            }
        }

        LC32MachOSlice parsed = descriptor;
        if(!LC32MachOParseSlice(fd, descriptor.offset, descriptor.size,
                &parsed, errorBuffer, errorBufferCapacity)) {
            return false;
        }
        if(parsed.cpuType != descriptor.cpuType ||
                parsed.cpuSubtype != descriptor.cpuSubtype) {
            LC32MachOSetError(errorBuffer, errorBufferCapacity,
                "fat Mach-O slice %u descriptor does not match its header",
                index);
            return false;
        }
        parsed.offset = descriptor.offset;
        parsed.size = descriptor.size;
        parsed.alignExponent = descriptor.alignExponent;
        image->slices[index] = parsed;
    }

    image->count = count;
    return true;
}

bool LC32MachOImageParseFD(
        int fd, LC32MachOImage *image,
        char *errorBuffer, size_t errorBufferCapacity) {
    if(errorBuffer != NULL && errorBufferCapacity != 0) {
        errorBuffer[0] = '\0';
    }
    if(image == NULL || fd < 0) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "invalid Mach-O parser arguments");
        return false;
    }
    memset(image, 0, sizeof(*image));

    struct stat status = {0};
    if(fstat(fd, &status) != 0) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "could not stat Mach-O: %s", strerror(errno));
        return false;
    }
    if(status.st_size <= 0) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "Mach-O file is empty");
        return false;
    }
    const uint64_t fileSize = (uint64_t)status.st_size;
    image->fileSize = fileSize;

    uint32_t magic = 0;
    if(!LC32MachOReadAt(fd, &magic, sizeof(magic), 0)) {
        LC32MachOSetError(errorBuffer, errorBufferCapacity,
            "could not read Mach-O magic: %s", strerror(errno));
        memset(image, 0, sizeof(*image));
        return false;
    }

    const bool isFat = magic == FAT_MAGIC || magic == FAT_CIGAM ||
        magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
    bool success = false;
    if(isFat) {
        success = LC32MachOParseFat(fd, fileSize, magic, image,
            errorBuffer, errorBufferCapacity);
    } else {
        LC32MachOSlice slice = {
            .offset = 0,
            .size = fileSize,
            .alignExponent = LC32_THIN_MACH_O_ALIGN_EXPONENT,
        };
        success = LC32MachOParseSlice(fd, 0, fileSize, &slice,
            errorBuffer, errorBufferCapacity);
        if(success) {
            image->slices[0] = slice;
            image->count = 1;
        }
    }

    if(!success) memset(image, 0, sizeof(*image));
    return success;
}

const LC32MachOSlice *LC32MachOImageFindSlice(
        const LC32MachOImage *image,
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype) {
    if(image == NULL) return NULL;

    const LC32MachOSlice *baseMatch = NULL;
    bool baseMatchIsAmbiguous = false;
    for(uint32_t index = 0; index < image->count; index++) {
        const LC32MachOSlice *slice = &image->slices[index];
        if(slice->cpuType != cpuType) continue;
        if(slice->cpuSubtype == cpuSubtype) return slice;
        if(LC32MachOBaseCPUSubtype(slice->cpuSubtype) ==
                LC32MachOBaseCPUSubtype(cpuSubtype)) {
            /* Capability-bearing variants may legally coexist in FAT.  A
             * loose lookup is only deterministic when exactly one exists. */
            if(baseMatch == NULL) {
                baseMatch = slice;
            } else {
                baseMatchIsAmbiguous = true;
            }
        }
    }
    return baseMatchIsAmbiguous ? NULL : baseMatch;
}

void LC32MachOImageFree(LC32MachOImage *image) {
    if(image != NULL) memset(image, 0, sizeof(*image));
}
