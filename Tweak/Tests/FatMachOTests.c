#include "../FatMachO.h"

#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>

#define LC32_TEST_SLICE_CAPACITY 4096u
#define LC32_TEST_TIMEOUT_SECONDS 60u
#define LC32_TEST_CODE_SIGNATURE_OFFSET 0x400u
#define LC32_TEST_LARGE_CODE_SIGNATURE_OFFSET \
    ((256u * 1024u) + LC32_TEST_CODE_SIGNATURE_OFFSET)
#define LC32_TEST_ADHOC_FLAG 0x2u
#define LC32_TEST_EMBEDDED_SIGNATURE_MAGIC 0xfade0cc0u
#define LC32_TEST_CODE_DIRECTORY_MAGIC 0xfade0c02u
#define LC32_TEST_REQUIREMENTS_MAGIC 0xfade0c01u
#define LC32_TEST_ENTITLEMENTS_MAGIC 0xfade7171u
#define LC32_TEST_DER_ENTITLEMENTS_MAGIC 0xfade7172u
#define LC32_TEST_BLOB_WRAPPER_MAGIC 0xfade0b01u
#define LC32_TEST_CODE_DIRECTORY_SLOT 0u
#define LC32_TEST_REQUIREMENTS_SLOT 2u
#define LC32_TEST_ENTITLEMENTS_SLOT 5u
#define LC32_TEST_DER_ENTITLEMENTS_SLOT 7u
#define LC32_TEST_CMS_SIGNATURE_SLOT 0x10000u
#define LC32_TEST_SHA256_TYPE 2u
#define LC32_TEST_EXECSEG_MAIN_BINARY UINT64_C(0x1)
#define LC32_TEST_IOS_8_VERSION (8u << 16)
#define LC32_TEST_IOS_10_3_VERSION ((10u << 16) | (3u << 8))
#define LC32_TEST_IOS_11_VERSION (11u << 16)
#define LC32_TEST_IOS_14_4_VERSION ((14u << 16) | (4u << 8))
#define LC32_TEST_SHIM_MINOS ((16u << 16) | (2u << 8))
#define LC32_TEST_SHIM_SDK ((17u << 16) | (4u << 8))
#define LC32_TEST_DEFAULT_TEAM_IDENTIFIER "T8ALTGMVXN"
#define LC32_TEST_DERIVED_TEAM_IDENTIFIER "UY94678XHZ"
#define LC32_TEST_EXPLICIT_TEAM_IDENTIFIER "EXPLICIT42"
#define LC32_TEST_BUNDLE_IDENTIFIER "com.example.LiveExec32Target"
#define LC32_TEST_APPLICATION_IDENTIFIER \
    LC32_TEST_DERIVED_TEAM_IDENTIFIER "." LC32_TEST_BUNDLE_IDENTIFIER
#define LC32_TEST_CODE_IDENTIFIER "legacy.target.signature.identifier"
#define LC32_TEST_FALLBACK_CODE_IDENTIFIER \
    LC32_TEST_DEFAULT_TEAM_IDENTIFIER "." LC32_TEST_BUNDLE_IDENTIFIER

typedef struct {
    uint32_t magic;
    uint32_t length;
    uint32_t version;
    uint32_t flags;
    uint32_t hashOffset;
    uint32_t identOffset;
    uint32_t nSpecialSlots;
    uint32_t nCodeSlots;
    uint32_t codeLimit;
    uint8_t hashSize;
    uint8_t hashType;
    uint8_t platform;
    uint8_t pageSize;
    uint32_t spare2;
    uint32_t scatterOffset;
    uint32_t teamOffset;
} LC32TestLegacyCodeDirectory;

typedef struct {
    uint32_t magic;
    uint32_t length;
    uint32_t version;
    uint32_t flags;
    uint32_t hashOffset;
    uint32_t identOffset;
    uint32_t nSpecialSlots;
    uint32_t nCodeSlots;
    uint32_t codeLimit;
    uint8_t hashSize;
    uint8_t hashType;
    uint8_t platform;
    uint8_t pageSize;
    uint32_t spare2;
    uint32_t scatterOffset;
    uint32_t teamOffset;
    uint32_t spare3;
    uint64_t codeLimit64;
    uint64_t execSegBase;
    uint64_t execSegLimit;
    uint64_t execSegFlags;
} LC32TestCodeDirectory;

typedef struct {
    const uint8_t *bytes;
    size_t size;
} LC32TestSliceView;

typedef struct {
    const uint8_t *bytes;
    size_t size;
    uint32_t type;
} LC32TestBlobView;

_Static_assert(sizeof(LC32TestLegacyCodeDirectory) == 52,
    "test CodeDirectory layout must match version 0x20200");
_Static_assert(sizeof(LC32TestCodeDirectory) == 88,
    "test CodeDirectory layout must match version 0x20400");

static const char LC32TestTargetEntitlements[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\"><dict>"
    "<key>com.example.target-only</key><string>target</string>"
    "<key>com.example.merge-conflict</key><string>target</string>"
    "</dict></plist>\n";

static const char LC32TestDerivedTeamEntitlements[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\"><dict>"
    "<key>application-identifier</key><string>"
        LC32_TEST_APPLICATION_IDENTIFIER "</string>"
    "<key>com.example.target-only</key><string>target</string>"
    "<key>com.example.merge-conflict</key><string>target</string>"
    "</dict></plist>\n";

static const char LC32TestExplicitTeamEntitlements[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\"><dict>"
    "<key>application-identifier</key><string>"
        LC32_TEST_APPLICATION_IDENTIFIER "</string>"
    "<key>com.apple.developer.team-identifier</key><string>"
        LC32_TEST_EXPLICIT_TEAM_IDENTIFIER "</string>"
    "<key>com.example.target-only</key><string>target</string>"
    "<key>com.example.merge-conflict</key><string>target</string>"
    "</dict></plist>\n";

static const char LC32TestShimEntitlements[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\"><dict>"
    "<key>com.example.shim-only</key><true/>"
    "<key>com.example.merge-conflict</key><string>shim</string>"
    "<key>com.apple.developer.team-identifier</key>"
        "<string>" LC32_TEST_DEFAULT_TEAM_IDENTIFIER "</string>"
    "<key>com.apple.private.amfi.can-execute-cdhash</key><true/>"
    "</dict></plist>\n";

static int Fail(const char *message) {
    fprintf(stderr, "FatMachOTests: %s\n", message);
    return 1;
}

static bool FormatTestPath(
        char *path, size_t capacity,
        const char *directory, const char *name) {
    const int length = snprintf(
        path, capacity, "%s/%s", directory, name);
    return length >= 0 && (size_t)length < capacity;
}

static bool WriteExactly(
        int fd, const void *bytes, size_t size, off_t offset) {
    size_t completed = 0;
    while(completed < size) {
        const ssize_t amount = pwrite(fd,
            (const uint8_t *)bytes + completed,
            size - completed, offset + (off_t)completed);
        if(amount <= 0) return false;
        completed += (size_t)amount;
    }
    return true;
}

static bool WriteFile(
        const char *path, const void *bytes, size_t size, mode_t mode) {
    const int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
    if(fd < 0) return false;
    const bool wroteFile = fchmod(fd, mode) == 0 &&
        WriteExactly(fd, bytes, size, 0);
    const int closeResult = close(fd);
    return wroteFile && closeResult == 0;
}

static size_t MakeThinExecutable(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY],
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype,
        uint8_t payloadByte) {
    memset(bytes, 0, LC32_TEST_SLICE_CAPACITY);
    size_t headerSize = 0;
    size_t commandSize = 0;
    if(cpuType == CPU_TYPE_ARM64) {
        const struct mach_header_64 header = {
            .magic = MH_MAGIC_64,
            .cputype = cpuType,
            .cpusubtype = cpuSubtype,
            .filetype = MH_EXECUTE,
            .ncmds = 1,
            .sizeofcmds = sizeof(struct segment_command_64),
        };
        const struct segment_command_64 segment = {
            .cmd = LC_SEGMENT_64,
            .cmdsize = sizeof(segment),
        };
        memcpy(bytes, &header, sizeof(header));
        headerSize = sizeof(header);
        memcpy(bytes + headerSize, &segment, sizeof(segment));
        commandSize = sizeof(segment);
    } else {
        const struct mach_header header = {
            .magic = MH_MAGIC,
            .cputype = cpuType,
            .cpusubtype = cpuSubtype,
            .filetype = MH_EXECUTE,
            .ncmds = 1,
            .sizeofcmds = sizeof(struct segment_command),
        };
        const struct segment_command segment = {
            .cmd = LC_SEGMENT,
            .cmdsize = sizeof(segment),
        };
        memcpy(bytes, &header, sizeof(header));
        headerSize = sizeof(header);
        memcpy(bytes + headerSize, &segment, sizeof(segment));
        commandSize = sizeof(segment);
    }
    memset(bytes + headerSize + commandSize, payloadByte, 16);
    return headerSize + commandSize + 16;
}

static size_t MakeSignedThinExecutableWithVersionMin(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY],
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype,
        uint8_t payloadByte, const char *identifier,
        const char *entitlementsXML,
        uint32_t versionMinVersion, uint32_t versionMinSDK) {
    const bool is64Bit = cpuType == CPU_TYPE_ARM64;
    const bool hasVersionMin = !is64Bit &&
        (versionMinVersion != 0 || versionMinSDK != 0);
    const size_t headerSize = is64Bit ?
        sizeof(struct mach_header_64) : sizeof(struct mach_header);
    const size_t segmentSize = is64Bit ?
        sizeof(struct segment_command_64) : sizeof(struct segment_command);
    const size_t versionCommandSize = is64Bit ?
        sizeof(struct build_version_command) :
        (hasVersionMin ? sizeof(struct version_min_command) : 0);
    const size_t commandBytes = 2 * segmentSize +
        sizeof(struct entry_point_command) +
        sizeof(struct linkedit_data_command) + versionCommandSize;
    const size_t payloadOffset = headerSize + commandBytes;
    const size_t identifierSize = strlen(identifier) + 1;
    const uint32_t specialSlotCount = LC32_TEST_ENTITLEMENTS_SLOT;
    const uint32_t codeSlotCount = 1;
    const size_t codeDirectoryHashOffset =
        sizeof(LC32TestLegacyCodeDirectory) + identifierSize +
        specialSlotCount * CC_SHA256_DIGEST_LENGTH;
    const size_t codeDirectorySize = codeDirectoryHashOffset +
        codeSlotCount * CC_SHA256_DIGEST_LENGTH;
    const size_t entitlementsPayloadSize = strlen(entitlementsXML);
    const size_t entitlementsBlobSize = 8 + entitlementsPayloadSize;
    const size_t superblobHeaderSize = 12 + 2 * 8;
    const size_t codeDirectoryOffset = superblobHeaderSize;
    const size_t entitlementsOffset =
        codeDirectoryOffset + codeDirectorySize;
    const size_t superblobSize = entitlementsOffset + entitlementsBlobSize;
    const size_t fileSize = LC32_TEST_CODE_SIGNATURE_OFFSET + superblobSize;
    if(identifierSize < 2 ||
            payloadOffset + 16 > LC32_TEST_CODE_SIGNATURE_OFFSET ||
            fileSize > LC32_TEST_SLICE_CAPACITY ||
            codeDirectorySize > UINT32_MAX || superblobSize > UINT32_MAX) {
        return 0;
    }

    memset(bytes, 0, LC32_TEST_SLICE_CAPACITY);
    if(is64Bit) {
        const struct mach_header_64 header = {
            .magic = MH_MAGIC_64,
            .cputype = cpuType,
            .cpusubtype = cpuSubtype,
            .filetype = MH_EXECUTE,
            .ncmds = 5,
            .sizeofcmds = (uint32_t)commandBytes,
        };
        struct segment_command_64 text = {
            .cmd = LC_SEGMENT_64,
            .cmdsize = sizeof(text),
            .vmaddr = 0x100000000,
            .vmsize = 0x1000,
            .fileoff = 0,
            .filesize = LC32_TEST_CODE_SIGNATURE_OFFSET,
            .maxprot = VM_PROT_READ | VM_PROT_EXECUTE,
            .initprot = VM_PROT_READ | VM_PROT_EXECUTE,
        };
        struct segment_command_64 linkedit = {
            .cmd = LC_SEGMENT_64,
            .cmdsize = sizeof(linkedit),
            .vmaddr = 0x100001000,
            .vmsize = 0x1000,
            .fileoff = LC32_TEST_CODE_SIGNATURE_OFFSET,
            .filesize = superblobSize,
            .maxprot = VM_PROT_READ,
            .initprot = VM_PROT_READ,
        };
        memcpy(text.segname, SEG_TEXT, sizeof(SEG_TEXT));
        memcpy(linkedit.segname, SEG_LINKEDIT, sizeof(SEG_LINKEDIT));
        memcpy(bytes, &header, sizeof(header));
        memcpy(bytes + headerSize, &text, sizeof(text));
        memcpy(bytes + headerSize + segmentSize,
            &linkedit, sizeof(linkedit));
    } else {
        const struct mach_header header = {
            .magic = MH_MAGIC,
            .cputype = cpuType,
            .cpusubtype = cpuSubtype,
            .filetype = MH_EXECUTE,
            .ncmds = hasVersionMin ? 5 : 4,
            .sizeofcmds = (uint32_t)commandBytes,
        };
        struct segment_command text = {
            .cmd = LC_SEGMENT,
            .cmdsize = sizeof(text),
            .vmaddr = 0x1000,
            .vmsize = 0x1000,
            .fileoff = 0,
            .filesize = LC32_TEST_CODE_SIGNATURE_OFFSET,
            .maxprot = VM_PROT_READ | VM_PROT_EXECUTE,
            .initprot = VM_PROT_READ | VM_PROT_EXECUTE,
        };
        struct segment_command linkedit = {
            .cmd = LC_SEGMENT,
            .cmdsize = sizeof(linkedit),
            .vmaddr = 0x2000,
            .vmsize = 0x1000,
            .fileoff = LC32_TEST_CODE_SIGNATURE_OFFSET,
            .filesize = (uint32_t)superblobSize,
            .maxprot = VM_PROT_READ,
            .initprot = VM_PROT_READ,
        };
        memcpy(text.segname, SEG_TEXT, sizeof(SEG_TEXT));
        memcpy(linkedit.segname, SEG_LINKEDIT, sizeof(SEG_LINKEDIT));
        memcpy(bytes, &header, sizeof(header));
        memcpy(bytes + headerSize, &text, sizeof(text));
        memcpy(bytes + headerSize + segmentSize,
            &linkedit, sizeof(linkedit));
    }

    const struct entry_point_command entryPointCommand = {
        .cmd = LC_MAIN,
        .cmdsize = sizeof(entryPointCommand),
        .entryoff = payloadOffset,
    };
    memcpy(bytes + headerSize + 2 * segmentSize,
        &entryPointCommand, sizeof(entryPointCommand));

    const struct linkedit_data_command signatureCommand = {
        .cmd = LC_CODE_SIGNATURE,
        .cmdsize = sizeof(signatureCommand),
        .dataoff = LC32_TEST_CODE_SIGNATURE_OFFSET,
        .datasize = (uint32_t)superblobSize,
    };
    memcpy(bytes + headerSize + 2 * segmentSize +
            sizeof(entryPointCommand),
        &signatureCommand, sizeof(signatureCommand));
    const size_t versionCommandOffset = headerSize + 2 * segmentSize +
        sizeof(entryPointCommand) + sizeof(signatureCommand);
    if(is64Bit) {
        const struct build_version_command buildVersion = {
            .cmd = LC_BUILD_VERSION,
            .cmdsize = sizeof(buildVersion),
            .platform = PLATFORM_IOS,
            .minos = LC32_TEST_SHIM_MINOS,
            .sdk = LC32_TEST_SHIM_SDK,
        };
        memcpy(bytes + versionCommandOffset,
            &buildVersion, sizeof(buildVersion));
    } else if(hasVersionMin) {
        const struct version_min_command versionMin = {
            .cmd = LC_VERSION_MIN_IPHONEOS,
            .cmdsize = sizeof(versionMin),
            .version = versionMinVersion,
            .sdk = versionMinSDK,
        };
        memcpy(bytes + versionCommandOffset,
            &versionMin, sizeof(versionMin));
    }
    memset(bytes + payloadOffset, payloadByte, 16);

    uint8_t *superblob = bytes + LC32_TEST_CODE_SIGNATURE_OFFSET;
    const uint32_t superblobMagic = OSSwapHostToBigInt32(
        LC32_TEST_EMBEDDED_SIGNATURE_MAGIC);
    const uint32_t encodedSuperblobSize = OSSwapHostToBigInt32(
        (uint32_t)superblobSize);
    const uint32_t encodedBlobCount = OSSwapHostToBigInt32(2);
    memcpy(superblob, &superblobMagic, sizeof(superblobMagic));
    memcpy(superblob + 4, &encodedSuperblobSize,
        sizeof(encodedSuperblobSize));
    memcpy(superblob + 8, &encodedBlobCount, sizeof(encodedBlobCount));

    const uint32_t codeDirectorySlot = OSSwapHostToBigInt32(
        LC32_TEST_CODE_DIRECTORY_SLOT);
    const uint32_t encodedCodeDirectoryOffset = OSSwapHostToBigInt32(
        (uint32_t)codeDirectoryOffset);
    const uint32_t entitlementsSlot = OSSwapHostToBigInt32(
        LC32_TEST_ENTITLEMENTS_SLOT);
    const uint32_t encodedEntitlementsOffset = OSSwapHostToBigInt32(
        (uint32_t)entitlementsOffset);
    memcpy(superblob + 12, &codeDirectorySlot, 4);
    memcpy(superblob + 16, &encodedCodeDirectoryOffset, 4);
    memcpy(superblob + 20, &entitlementsSlot, 4);
    memcpy(superblob + 24, &encodedEntitlementsOffset, 4);

    LC32TestLegacyCodeDirectory codeDirectory = {
        .magic = OSSwapHostToBigInt32(LC32_TEST_CODE_DIRECTORY_MAGIC),
        .length = OSSwapHostToBigInt32((uint32_t)codeDirectorySize),
        .version = OSSwapHostToBigInt32(0x20200),
        .flags = OSSwapHostToBigInt32(LC32_TEST_ADHOC_FLAG),
        .hashOffset = OSSwapHostToBigInt32(
            (uint32_t)codeDirectoryHashOffset),
        .identOffset = OSSwapHostToBigInt32(
            sizeof(LC32TestLegacyCodeDirectory)),
        .nSpecialSlots = OSSwapHostToBigInt32(specialSlotCount),
        .nCodeSlots = OSSwapHostToBigInt32(codeSlotCount),
        .codeLimit = OSSwapHostToBigInt32(
            LC32_TEST_CODE_SIGNATURE_OFFSET),
        .hashSize = CC_SHA256_DIGEST_LENGTH,
        .hashType = LC32_TEST_SHA256_TYPE,
        .pageSize = 12,
    };
    uint8_t *codeDirectoryBytes = superblob + codeDirectoryOffset;
    memcpy(codeDirectoryBytes, &codeDirectory, sizeof(codeDirectory));
    memcpy(codeDirectoryBytes + sizeof(codeDirectory),
        identifier, identifierSize);

    uint8_t *entitlementsBytes = superblob + entitlementsOffset;
    const uint32_t entitlementsMagic = OSSwapHostToBigInt32(
        LC32_TEST_ENTITLEMENTS_MAGIC);
    const uint32_t encodedEntitlementsSize = OSSwapHostToBigInt32(
        (uint32_t)entitlementsBlobSize);
    memcpy(entitlementsBytes, &entitlementsMagic, 4);
    memcpy(entitlementsBytes + 4, &encodedEntitlementsSize, 4);
    memcpy(entitlementsBytes + 8,
        entitlementsXML, entitlementsPayloadSize);

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(entitlementsBytes, (CC_LONG)entitlementsBlobSize, digest);
    memcpy(codeDirectoryBytes + codeDirectoryHashOffset -
            LC32_TEST_ENTITLEMENTS_SLOT * CC_SHA256_DIGEST_LENGTH,
        digest, sizeof(digest));
    CC_SHA256(bytes, LC32_TEST_CODE_SIGNATURE_OFFSET, digest);
    memcpy(codeDirectoryBytes + codeDirectoryHashOffset,
        digest, sizeof(digest));
    return fileSize;
}

static size_t MakeSignedThinExecutable(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY],
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype,
        uint8_t payloadByte, const char *identifier,
        const char *entitlementsXML) {
    return MakeSignedThinExecutableWithVersionMin(
        bytes, cpuType, cpuSubtype, payloadByte,
        identifier, entitlementsXML, 0, 0);
}

static size_t MakeEncryptedARMExecutable(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY],
        uint32_t codeDirectoryVersion) {
    const size_t originalSize = MakeSignedThinExecutableWithVersionMin(
        bytes, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0xe3,
        LC32_TEST_CODE_IDENTIFIER, LC32TestDerivedTeamEntitlements,
        LC32_TEST_IOS_8_VERSION, LC32_TEST_IOS_10_3_VERSION);
    if(originalSize == 0) return 0;

    struct mach_header *header = (struct mach_header *)bytes;
    const size_t oldCommandsEnd = sizeof(*header) + header->sizeofcmds;
    if(header->magic != MH_MAGIC || header->ncmds != 5 ||
            oldCommandsEnd + sizeof(struct encryption_info_command) + 16 >
                LC32_TEST_CODE_SIGNATURE_OFFSET) {
        return 0;
    }
    memmove(bytes + oldCommandsEnd + sizeof(struct encryption_info_command),
        bytes + oldCommandsEnd, 16);
    const struct encryption_info_command encryption = {
        .cmd = LC_ENCRYPTION_INFO,
        .cmdsize = sizeof(encryption),
        .cryptoff = (uint32_t)(oldCommandsEnd + sizeof(encryption)),
        .cryptsize = 16,
        .cryptid = 2,
    };
    memcpy(bytes + oldCommandsEnd, &encryption, sizeof(encryption));
    header->ncmds++;
    header->sizeofcmds += sizeof(encryption);

    const size_t entryPointOffset = sizeof(*header) +
        2 * sizeof(struct segment_command);
    struct entry_point_command *entryPoint =
        (struct entry_point_command *)(bytes + entryPointOffset);
    entryPoint->entryoff += sizeof(encryption);

    struct segment_command *linkedit = (struct segment_command *)(
        bytes + sizeof(*header) + sizeof(struct segment_command));
    struct linkedit_data_command *signature =
        (struct linkedit_data_command *)(bytes + entryPointOffset +
            sizeof(struct entry_point_command));
    const uint32_t signatureCapacity =
        LC32_TEST_SLICE_CAPACITY - LC32_TEST_CODE_SIGNATURE_OFFSET;
    if(strncmp(linkedit->segname, SEG_LINKEDIT,
            sizeof(linkedit->segname)) != 0 ||
            signature->cmd != LC_CODE_SIGNATURE) {
        return 0;
    }
    linkedit->filesize = signatureCapacity;
    signature->datasize = signatureCapacity;

    uint8_t *superblob = bytes + LC32_TEST_CODE_SIGNATURE_OFFSET;
    uint32_t encodedCodeDirectoryOffset = 0;
    memcpy(&encodedCodeDirectoryOffset, superblob + 16, 4);
    const uint32_t codeDirectoryOffset =
        OSSwapBigToHostInt32(encodedCodeDirectoryOffset);
    if(codeDirectoryOffset > signatureCapacity ||
            sizeof(LC32TestLegacyCodeDirectory) >
                signatureCapacity - codeDirectoryOffset) {
        return 0;
    }
    uint8_t *codeDirectory = superblob + codeDirectoryOffset;
    const uint32_t encodedVersion =
        OSSwapHostToBigInt32(codeDirectoryVersion);
    memcpy(codeDirectory + offsetof(
        LC32TestLegacyCodeDirectory, version), &encodedVersion, 4);

    uint32_t encodedHashOffset = 0;
    memcpy(&encodedHashOffset, codeDirectory + offsetof(
        LC32TestLegacyCodeDirectory, hashOffset), 4);
    const uint32_t hashOffset =
        OSSwapBigToHostInt32(encodedHashOffset);
    if(hashOffset > signatureCapacity - codeDirectoryOffset ||
            CC_SHA256_DIGEST_LENGTH >
                signatureCapacity - codeDirectoryOffset - hashOffset) {
        return 0;
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, LC32_TEST_CODE_SIGNATURE_OFFSET, digest);
    memcpy(codeDirectory + hashOffset, digest, sizeof(digest));
    return LC32_TEST_SLICE_CAPACITY;
}

static size_t MakeByteSwappedARMExecutable(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY]) {
    const uint32_t fileSize = sizeof(struct mach_header) +
        sizeof(struct segment_command) + 16;
    memset(bytes, 0, LC32_TEST_SLICE_CAPACITY);
    const struct mach_header header = {
        .magic = MH_CIGAM,
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM_V7),
        .filetype = OSSwapHostToBigInt32(MH_EXECUTE),
        .ncmds = OSSwapHostToBigInt32(1),
        .sizeofcmds = OSSwapHostToBigInt32(
            sizeof(struct segment_command)),
    };
    const struct segment_command segment = {
        .cmd = OSSwapHostToBigInt32(LC_SEGMENT),
        .cmdsize = OSSwapHostToBigInt32(
            sizeof(struct segment_command)),
        .vmaddr = OSSwapHostToBigInt32(0x1000),
        .vmsize = OSSwapHostToBigInt32(0x1000),
        .fileoff = 0,
        .filesize = OSSwapHostToBigInt32(fileSize),
        .maxprot = (vm_prot_t)OSSwapHostToBigInt32(
            VM_PROT_READ | VM_PROT_EXECUTE),
        .initprot = (vm_prot_t)OSSwapHostToBigInt32(
            VM_PROT_READ | VM_PROT_EXECUTE),
    };
    memcpy(bytes, &header, sizeof(header));
    memcpy(bytes + sizeof(header), &segment, sizeof(segment));
    memset(bytes + sizeof(header) + sizeof(segment), 0x5c, 16);
    return fileSize;
}

static uint8_t *MakeRepeatedLoadCommandsExecutable(
        uint32_t commandCount, uint32_t commandSize,
        size_t *sizeOut) {
    if(commandSize < sizeof(struct load_command) ||
            commandCount >
                (SIZE_MAX - sizeof(struct mach_header)) / commandSize) {
        return NULL;
    }
    const size_t commandBytes = (size_t)commandCount * commandSize;
    if(commandBytes > UINT32_MAX) return NULL;
    const size_t size = sizeof(struct mach_header) + commandBytes;
    uint8_t *bytes = calloc(1, size);
    if(bytes == NULL) return NULL;

    const struct mach_header header = {
        .magic = MH_MAGIC,
        .cputype = CPU_TYPE_ARM,
        .cpusubtype = CPU_SUBTYPE_ARM_V7,
        .filetype = MH_EXECUTE,
        .ncmds = commandCount,
        .sizeofcmds = (uint32_t)commandBytes,
    };
    memcpy(bytes, &header, sizeof(header));
    for(uint32_t index = 0; index < commandCount; index++) {
        const struct load_command command = {
            .cmd = 0x7fffffffu,
            .cmdsize = commandSize,
        };
        memcpy(bytes + sizeof(header) + (size_t)index * commandSize,
            &command, sizeof(command));
    }
    *sizeOut = size;
    return bytes;
}

static size_t MakeTruncatedLoadCommandExecutable(
        uint8_t bytes[sizeof(struct mach_header) +
            sizeof(struct load_command)],
        uint32_t commandCount, uint32_t declaredCommandBytes,
        uint32_t commandSize) {
    memset(bytes, 0,
        sizeof(struct mach_header) + sizeof(struct load_command));
    const struct mach_header header = {
        .magic = MH_MAGIC,
        .cputype = CPU_TYPE_ARM,
        .cpusubtype = CPU_SUBTYPE_ARM_V7,
        .filetype = MH_EXECUTE,
        .ncmds = commandCount,
        .sizeofcmds = declaredCommandBytes,
    };
    const struct load_command command = {
        .cmd = 0x7fffffffu,
        .cmdsize = commandSize,
    };
    memcpy(bytes, &header, sizeof(header));
    memcpy(bytes + sizeof(header), &command, sizeof(command));
    return sizeof(struct mach_header) + sizeof(struct load_command);
}

static uint8_t *MakeSingleSliceFatImage(
        const uint8_t *slice, size_t sliceSize, size_t *sizeOut) {
    const uint32_t sliceOffset = 0x1000;
    if(slice == NULL || sliceSize == 0 ||
            sliceSize > UINT32_MAX - sliceOffset) {
        return NULL;
    }
    const size_t fileSize = sliceOffset + sliceSize;
    uint8_t *bytes = calloc(1, fileSize);
    if(bytes == NULL) return NULL;

    struct fat_header *header = (struct fat_header *)bytes;
    header->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    header->nfat_arch = OSSwapHostToBigInt32(1);
    struct fat_arch *architecture =
        (struct fat_arch *)(bytes + sizeof(*header));
    *architecture = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM_V7),
        .offset = OSSwapHostToBigInt32(sliceOffset),
        .size = OSSwapHostToBigInt32((uint32_t)sliceSize),
        .align = OSSwapHostToBigInt32(12),
    };
    memcpy(bytes + sliceOffset, slice, sliceSize);
    *sizeOut = fileSize;
    return bytes;
}

static uint8_t *MakeRepeatedSliceFatImage(
        const uint8_t *slice, size_t sliceSize,
        uint32_t sliceCount, size_t *sizeOut) {
    const uint32_t firstSliceOffset = 0x1000;
    const uint32_t sliceStride = 0x1000;
    if(slice == NULL || sliceSize == 0 || sliceSize > sliceStride ||
            sliceCount == 0 ||
            sliceCount > (UINT32_MAX - firstSliceOffset) / sliceStride) {
        return NULL;
    }
    const size_t tableSize = sizeof(struct fat_header) +
        (size_t)sliceCount * sizeof(struct fat_arch);
    const size_t fileSize = firstSliceOffset +
        (size_t)(sliceCount - 1) * sliceStride + sliceSize;
    if(tableSize > firstSliceOffset) return NULL;

    uint8_t *bytes = calloc(1, fileSize);
    if(bytes == NULL) return NULL;
    struct fat_header *header = (struct fat_header *)bytes;
    header->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    header->nfat_arch = OSSwapHostToBigInt32(sliceCount);
    struct fat_arch *architectures =
        (struct fat_arch *)(bytes + sizeof(*header));
    for(uint32_t index = 0; index < sliceCount; index++) {
        const uint32_t offset = firstSliceOffset + index * sliceStride;
        architectures[index] = (struct fat_arch){
            .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
            .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
                CPU_SUBTYPE_ARM_V7),
            .offset = OSSwapHostToBigInt32(offset),
            .size = OSSwapHostToBigInt32((uint32_t)sliceSize),
            .align = OSSwapHostToBigInt32(12),
        };
        memcpy(bytes + offset, slice, sliceSize);
    }
    *sizeOut = fileSize;
    return bytes;
}

static uint8_t *MakeFiveSliceARMFatImage(
        const uint8_t *slice, size_t sliceSize, size_t *sizeOut) {
    static const cpu_subtype_t subtypes[] = {
        CPU_SUBTYPE_ARM_ALL,
        CPU_SUBTYPE_ARM_V6,
        CPU_SUBTYPE_ARM_V7,
        CPU_SUBTYPE_ARM_V7S,
        CPU_SUBTYPE_ARM_V7K,
    };
    uint8_t *bytes = MakeRepeatedSliceFatImage(
        slice, sliceSize,
        (uint32_t)(sizeof(subtypes) / sizeof(subtypes[0])), sizeOut);
    if(bytes == NULL) return NULL;

    struct fat_arch *architectures = (struct fat_arch *)(
        bytes + sizeof(struct fat_header));
    for(size_t index = 0;
            index < sizeof(subtypes) / sizeof(subtypes[0]); index++) {
        architectures[index].cpusubtype =
            (cpu_subtype_t)OSSwapHostToBigInt32(
                (uint32_t)subtypes[index]);
        const uint32_t sliceOffset = OSSwapBigToHostInt32(
            architectures[index].offset);
        struct mach_header *header =
            (struct mach_header *)(bytes + sliceOffset);
        header->cpusubtype = subtypes[index];
    }
    return bytes;
}

static uint32_t BigToHost32(uint32_t value) {
    return OSSwapBigToHostInt32(value);
}

static uint64_t BigToHost64(uint64_t value) {
    return OSSwapBigToHostInt64(value);
}

static bool FatListsShimFirstWithTrailingData(
        const uint8_t *fileBytes, size_t fileSize,
        uint32_t expectedCount) {
    if(fileBytes == NULL ||
            fileSize < sizeof(struct fat_header) || expectedCount < 2) {
        return false;
    }
    const struct fat_header *header =
        (const struct fat_header *)fileBytes;
    if(BigToHost32(header->magic) != FAT_MAGIC ||
            BigToHost32(header->nfat_arch) != expectedCount ||
            expectedCount > (fileSize - sizeof(*header)) /
                sizeof(struct fat_arch)) {
        return false;
    }

    const struct fat_arch *architectures =
        (const struct fat_arch *)(fileBytes + sizeof(*header));
    if((cpu_type_t)BigToHost32(
            (uint32_t)architectures[0].cputype) != CPU_TYPE_ARM64 ||
            (cpu_subtype_t)BigToHost32(
                (uint32_t)architectures[0].cpusubtype) !=
                    CPU_SUBTYPE_ARM64_ALL) {
        return false;
    }
    const uint32_t shimOffset = BigToHost32(architectures[0].offset);
    const uint32_t shimSize = BigToHost32(architectures[0].size);
    if(shimOffset > fileSize || shimSize > fileSize - shimOffset) {
        return false;
    }

    uint32_t previousTargetOffset = 0;
    for(uint32_t index = 1; index < expectedCount; index++) {
        const cpu_type_t cpuType = (cpu_type_t)BigToHost32(
            (uint32_t)architectures[index].cputype);
        const uint32_t offset = BigToHost32(architectures[index].offset);
        const uint32_t size = BigToHost32(architectures[index].size);
        if(cpuType != CPU_TYPE_ARM || offset >= shimOffset ||
                (index > 1 && offset <= previousTargetOffset) ||
                offset > fileSize || size > fileSize - offset) {
            return false;
        }
        previousTargetOffset = offset;
    }
    return true;
}

static bool FindFatSlice(
        const uint8_t *fileBytes, size_t fileSize,
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype,
        LC32TestSliceView *sliceOut) {
    if(fileBytes == NULL || sliceOut == NULL ||
            fileSize < sizeof(struct fat_header)) {
        return false;
    }
    const struct fat_header *header =
        (const struct fat_header *)fileBytes;
    if(BigToHost32(header->magic) != FAT_MAGIC) return false;

    const uint32_t count = BigToHost32(header->nfat_arch);
    if(count == 0 || count > 16 ||
            count > (fileSize - sizeof(*header)) /
                sizeof(struct fat_arch)) {
        return false;
    }
    const struct fat_arch *architectures =
        (const struct fat_arch *)(fileBytes + sizeof(*header));
    for(uint32_t index = 0; index < count; index++) {
        const cpu_type_t candidateType = (cpu_type_t)BigToHost32(
            (uint32_t)architectures[index].cputype);
        const cpu_subtype_t candidateSubtype = (cpu_subtype_t)BigToHost32(
            (uint32_t)architectures[index].cpusubtype);
        const uint32_t offset = BigToHost32(architectures[index].offset);
        const uint32_t size = BigToHost32(architectures[index].size);
        if(candidateType == cpuType && candidateSubtype == cpuSubtype) {
            if(offset > fileSize || size > fileSize - offset) return false;
            *sliceOut = (LC32TestSliceView){
                .bytes = fileBytes + offset,
                .size = size,
            };
            return true;
        }
    }
    return false;
}

static bool FindCodeSignature(
        LC32TestSliceView slice,
        uint32_t *offsetOut, uint32_t *sizeOut) {
    if(slice.size < sizeof(uint32_t)) return false;
    uint32_t magic = 0;
    memcpy(&magic, slice.bytes, sizeof(magic));
    size_t headerSize = 0;
    uint32_t commandCount = 0;
    uint32_t commandBytes = 0;
    if(magic == MH_MAGIC_64) {
        if(slice.size < sizeof(struct mach_header_64)) return false;
        struct mach_header_64 header;
        memcpy(&header, slice.bytes, sizeof(header));
        headerSize = sizeof(header);
        commandCount = header.ncmds;
        commandBytes = header.sizeofcmds;
    } else if(magic == MH_MAGIC) {
        if(slice.size < sizeof(struct mach_header)) return false;
        struct mach_header header;
        memcpy(&header, slice.bytes, sizeof(header));
        headerSize = sizeof(header);
        commandCount = header.ncmds;
        commandBytes = header.sizeofcmds;
    } else {
        return false;
    }
    if(commandCount == 0 || commandCount > 1000 ||
            headerSize > slice.size ||
            commandBytes > slice.size - headerSize) {
        return false;
    }

    size_t commandOffset = headerSize;
    const size_t commandsEnd = headerSize + commandBytes;
    for(uint32_t index = 0; index < commandCount; index++) {
        if(commandOffset > commandsEnd ||
                sizeof(struct load_command) > commandsEnd - commandOffset) {
            return false;
        }
        struct load_command command;
        memcpy(&command, slice.bytes + commandOffset, sizeof(command));
        if(command.cmdsize < sizeof(command) ||
                command.cmdsize > commandsEnd - commandOffset) {
            return false;
        }
        if(command.cmd == LC_CODE_SIGNATURE) {
            if(command.cmdsize < sizeof(struct linkedit_data_command)) {
                return false;
            }
            struct linkedit_data_command signature;
            memcpy(&signature, slice.bytes + commandOffset,
                sizeof(signature));
            if(signature.dataoff > slice.size ||
                    signature.datasize > slice.size - signature.dataoff) {
                return false;
            }
            if(offsetOut != NULL) *offsetOut = signature.dataoff;
            if(sizeOut != NULL) *sizeOut = signature.datasize;
            return true;
        }
        commandOffset += command.cmdsize;
    }
    return false;
}

static bool FindSuperblobBlob(
        const uint8_t *superblob, size_t capacity,
        uint32_t requestedType, LC32TestBlobView *blobOut) {
    if(superblob == NULL || capacity < 12 || blobOut == NULL) return false;
    uint32_t encodedMagic = 0;
    uint32_t encodedLength = 0;
    uint32_t encodedCount = 0;
    memcpy(&encodedMagic, superblob, 4);
    memcpy(&encodedLength, superblob + 4, 4);
    memcpy(&encodedCount, superblob + 8, 4);
    const uint32_t magic = BigToHost32(encodedMagic);
    const uint32_t length = BigToHost32(encodedLength);
    const uint32_t count = BigToHost32(encodedCount);
    if(magic != LC32_TEST_EMBEDDED_SIGNATURE_MAGIC ||
            length < 12 || length > capacity || count > 64 ||
            count > (length - 12) / 8) {
        return false;
    }

    for(uint32_t index = 0; index < count; index++) {
        uint32_t encodedType = 0;
        uint32_t encodedOffset = 0;
        memcpy(&encodedType, superblob + 12 + index * 8, 4);
        memcpy(&encodedOffset, superblob + 16 + index * 8, 4);
        const uint32_t type = BigToHost32(encodedType);
        const uint32_t offset = BigToHost32(encodedOffset);
        if(offset > length || 8 > length - offset) return false;
        uint32_t encodedBlobSize = 0;
        memcpy(&encodedBlobSize, superblob + offset + 4, 4);
        const uint32_t blobSize = BigToHost32(encodedBlobSize);
        if(blobSize < 8 || blobSize > length - offset) return false;
        if(type == requestedType) {
            *blobOut = (LC32TestBlobView){
                .bytes = superblob + offset,
                .size = blobSize,
                .type = type,
            };
            return true;
        }
    }
    return false;
}

static bool SetFixtureCodeDirectoryUInt32(
        uint8_t *sliceBytes, size_t sliceSize,
        size_t fieldOffset, uint32_t value) {
    LC32TestSliceView slice = {
        .bytes = sliceBytes,
        .size = sliceSize,
    };
    uint32_t signatureOffset = 0;
    uint32_t signatureSize = 0;
    LC32TestBlobView codeDirectoryBlob = {0};
    if(!FindCodeSignature(
            slice, &signatureOffset, &signatureSize) ||
            !FindSuperblobBlob(sliceBytes + signatureOffset, signatureSize,
                LC32_TEST_CODE_DIRECTORY_SLOT, &codeDirectoryBlob) ||
            fieldOffset > codeDirectoryBlob.size ||
            sizeof(uint32_t) > codeDirectoryBlob.size - fieldOffset) {
        return false;
    }

    const uint32_t encodedValue = OSSwapHostToBigInt32(value);
    memcpy((uint8_t *)codeDirectoryBlob.bytes + fieldOffset,
        &encodedValue, sizeof(encodedValue));
    return true;
}

static bool SetFixtureCodeDirectoryUInt8(
        uint8_t *sliceBytes, size_t sliceSize,
        size_t fieldOffset, uint8_t value) {
    LC32TestSliceView slice = {
        .bytes = sliceBytes,
        .size = sliceSize,
    };
    uint32_t signatureOffset = 0;
    uint32_t signatureSize = 0;
    LC32TestBlobView codeDirectoryBlob = {0};
    if(!FindCodeSignature(
            slice, &signatureOffset, &signatureSize) ||
            !FindSuperblobBlob(sliceBytes + signatureOffset, signatureSize,
                LC32_TEST_CODE_DIRECTORY_SLOT, &codeDirectoryBlob) ||
            fieldOffset >= codeDirectoryBlob.size) {
        return false;
    }

    ((uint8_t *)codeDirectoryBlob.bytes)[fieldOffset] = value;
    return true;
}

static bool SetFixtureEncryptionRange(
        uint8_t *sliceBytes, size_t sliceSize,
        uint32_t cryptOffset, uint32_t cryptSize) {
    if(sliceSize < sizeof(struct mach_header)) return false;
    struct mach_header header = {0};
    memcpy(&header, sliceBytes, sizeof(header));
    if(header.magic != MH_MAGIC || header.ncmds == 0 ||
            sizeof(header) > sliceSize ||
            header.sizeofcmds > sliceSize - sizeof(header)) {
        return false;
    }

    size_t commandOffset = sizeof(header);
    const size_t commandsEnd = commandOffset + header.sizeofcmds;
    for(uint32_t index = 0; index < header.ncmds; index++) {
        if(commandOffset > commandsEnd ||
                sizeof(struct load_command) >
                    commandsEnd - commandOffset) {
            return false;
        }
        struct load_command loadCommand = {0};
        memcpy(&loadCommand, sliceBytes + commandOffset,
            sizeof(loadCommand));
        if(loadCommand.cmdsize < sizeof(loadCommand) ||
                loadCommand.cmdsize > commandsEnd - commandOffset) {
            return false;
        }
        if(loadCommand.cmd == LC_ENCRYPTION_INFO) {
            if(loadCommand.cmdsize <
                    sizeof(struct encryption_info_command)) {
                return false;
            }
            struct encryption_info_command encryption = {0};
            memcpy(&encryption, sliceBytes + commandOffset,
                sizeof(encryption));
            encryption.cryptoff = cryptOffset;
            encryption.cryptsize = cryptSize;
            memcpy(sliceBytes + commandOffset, &encryption,
                sizeof(encryption));
            return true;
        }
        commandOffset += loadCommand.cmdsize;
    }
    return false;
}

static bool RefreshFixtureCodeHash(uint8_t *sliceBytes, size_t sliceSize) {
    LC32TestSliceView slice = {
        .bytes = sliceBytes,
        .size = sliceSize,
    };
    uint32_t signatureOffset = 0;
    uint32_t signatureSize = 0;
    LC32TestBlobView codeDirectoryBlob = {0};
    if(!FindCodeSignature(
            slice, &signatureOffset, &signatureSize) ||
            !FindSuperblobBlob(sliceBytes + signatureOffset, signatureSize,
                LC32_TEST_CODE_DIRECTORY_SLOT, &codeDirectoryBlob) ||
            codeDirectoryBlob.size < sizeof(LC32TestLegacyCodeDirectory)) {
        return false;
    }

    LC32TestLegacyCodeDirectory codeDirectory;
    memcpy(&codeDirectory, codeDirectoryBlob.bytes, sizeof(codeDirectory));
    const uint32_t hashOffset = BigToHost32(codeDirectory.hashOffset);
    const uint32_t codeLimit = BigToHost32(codeDirectory.codeLimit);
    const uint32_t codeSlotCount = BigToHost32(codeDirectory.nCodeSlots);
    if(codeDirectory.hashType != LC32_TEST_SHA256_TYPE ||
            codeDirectory.hashSize != CC_SHA256_DIGEST_LENGTH ||
            codeSlotCount != 1 || codeLimit > signatureOffset ||
            codeLimit > sliceSize || hashOffset > codeDirectoryBlob.size ||
            CC_SHA256_DIGEST_LENGTH > codeDirectoryBlob.size - hashOffset) {
        return false;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(sliceBytes, (CC_LONG)codeLimit, digest);
    memcpy((uint8_t *)codeDirectoryBlob.bytes + hashOffset,
        digest, sizeof(digest));
    return true;
}

static size_t ShrinkEncryptedFixtureSignatureAllocation(
        uint8_t bytes[LC32_TEST_SLICE_CAPACITY]) {
    uint32_t encodedSuperblobLength = 0;
    memcpy(&encodedSuperblobLength,
        bytes + LC32_TEST_CODE_SIGNATURE_OFFSET + 4, 4);
    const uint32_t superblobLength =
        OSSwapBigToHostInt32(encodedSuperblobLength);
    if(superblobLength < 12 || superblobLength >
            LC32_TEST_SLICE_CAPACITY -
                LC32_TEST_CODE_SIGNATURE_OFFSET) {
        return 0;
    }

    struct mach_header *header = (struct mach_header *)bytes;
    const size_t entryPointOffset = sizeof(*header) +
        2 * sizeof(struct segment_command);
    struct segment_command *linkedit = (struct segment_command *)(
        bytes + sizeof(*header) + sizeof(struct segment_command));
    struct linkedit_data_command *signature =
        (struct linkedit_data_command *)(bytes + entryPointOffset +
            sizeof(struct entry_point_command));
    if(header->magic != MH_MAGIC ||
            strncmp(linkedit->segname, SEG_LINKEDIT,
                sizeof(linkedit->segname)) != 0 ||
            signature->cmd != LC_CODE_SIGNATURE) {
        return 0;
    }
    linkedit->filesize = superblobLength;
    signature->datasize = superblobLength;
    const size_t size =
        LC32_TEST_CODE_SIGNATURE_OFFSET + superblobLength;
    return RefreshFixtureCodeHash(bytes, size) ? size : 0;
}

static uint8_t *CopyEncryptedFixtureWithRelocatedSignature(
        const uint8_t *sourceBytes, size_t sourceSize,
        uint32_t newSignatureOffset, size_t *resultSizeOut) {
    *resultSizeOut = 0;
    const LC32TestSliceView source = {
        .bytes = sourceBytes,
        .size = sourceSize,
    };
    uint32_t oldSignatureOffset = 0;
    uint32_t signatureSize = 0;
    if(!FindCodeSignature(source,
            &oldSignatureOffset, &signatureSize) ||
            newSignatureOffset <= oldSignatureOffset ||
            oldSignatureOffset > sourceSize ||
            signatureSize > sourceSize - oldSignatureOffset ||
            newSignatureOffset > SIZE_MAX - signatureSize) {
        return NULL;
    }

    const size_t resultSize =
        (size_t)newSignatureOffset + signatureSize;
    uint8_t *result = calloc(1, resultSize);
    if(result == NULL) return NULL;
    memcpy(result, sourceBytes, oldSignatureOffset);
    memcpy(result + newSignatureOffset,
        sourceBytes + oldSignatureOffset, signatureSize);

    struct mach_header *header = (struct mach_header *)result;
    const size_t entryPointOffset = sizeof(*header) +
        2 * sizeof(struct segment_command);
    struct segment_command *linkedit = (struct segment_command *)(
        result + sizeof(*header) + sizeof(struct segment_command));
    struct linkedit_data_command *signature =
        (struct linkedit_data_command *)(result + entryPointOffset +
            sizeof(struct entry_point_command));
    if(header->magic != MH_MAGIC ||
            strncmp(linkedit->segname, SEG_LINKEDIT,
                sizeof(linkedit->segname)) != 0 ||
            signature->cmd != LC_CODE_SIGNATURE ||
            signature->dataoff != oldSignatureOffset ||
            signature->datasize != signatureSize) {
        free(result);
        return NULL;
    }
    linkedit->fileoff = newSignatureOffset;
    linkedit->filesize = signatureSize;
    signature->dataoff = newSignatureOffset;
    if(!RefreshFixtureCodeHash(result, resultSize)) {
        free(result);
        return NULL;
    }

    *resultSizeOut = resultSize;
    return result;
}

static bool BytesAreZero(const uint8_t *bytes, size_t size) {
    for(size_t index = 0; index < size; index++) {
        if(bytes[index] != 0) return false;
    }
    return true;
}

static bool BlobHasMagicAndLength(
        LC32TestBlobView blob, uint32_t expectedMagic) {
    if(blob.bytes == NULL || blob.size < 8 || blob.size > UINT32_MAX) {
        return false;
    }
    uint32_t encodedMagic = 0;
    uint32_t encodedLength = 0;
    memcpy(&encodedMagic, blob.bytes, sizeof(encodedMagic));
    memcpy(&encodedLength, blob.bytes + 4, sizeof(encodedLength));
    return BigToHost32(encodedMagic) == expectedMagic &&
        BigToHost32(encodedLength) == blob.size;
}

static bool DictionaryStringEquals(
        CFDictionaryRef dictionary, CFStringRef key,
        const char *expectedValue) {
    const void *value = CFDictionaryGetValue(dictionary, key);
    if(value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        return false;
    }
    CFStringRef expected = CFStringCreateWithCString(
        kCFAllocatorDefault, expectedValue, kCFStringEncodingUTF8);
    if(expected == NULL) return false;
    const bool equal = CFEqual(value, expected);
    CFRelease(expected);
    return equal;
}

static bool DictionaryBooleanEquals(
        CFDictionaryRef dictionary, CFStringRef key, bool expectedValue) {
    const void *value = CFDictionaryGetValue(dictionary, key);
    return value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() &&
        CFBooleanGetValue((CFBooleanRef)value) == expectedValue;
}

static bool MergedEntitlementsAreValid(
        LC32TestBlobView blob, bool targetWasSigned,
        const char *expectedTeamIdentifier,
        const char *expectedApplicationIdentifier) {
    if(!BlobHasMagicAndLength(blob, LC32_TEST_ENTITLEMENTS_MAGIC) ||
            blob.size <= 8) {
        return false;
    }
    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
        blob.bytes + 8, (CFIndex)(blob.size - 8));
    if(data == NULL) return false;
    CFErrorRef error = NULL;
    CFPropertyListRef propertyList = CFPropertyListCreateWithData(
        kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, &error);
    CFRelease(data);
    if(error != NULL) CFRelease(error);
    if(propertyList == NULL ||
            CFGetTypeID(propertyList) != CFDictionaryGetTypeID()) {
        if(propertyList != NULL) CFRelease(propertyList);
        return false;
    }
    CFDictionaryRef dictionary = (CFDictionaryRef)propertyList;
    const bool targetEntitlementsAreValid = targetWasSigned ?
        (DictionaryStringEquals(dictionary,
            CFSTR("com.example.target-only"), "target") &&
         DictionaryStringEquals(dictionary,
            CFSTR("com.example.merge-conflict"), "target")) :
        (!CFDictionaryContainsKey(dictionary,
            CFSTR("com.example.target-only")) &&
         DictionaryStringEquals(dictionary,
            CFSTR("com.example.merge-conflict"), "shim"));
    const bool valid = targetEntitlementsAreValid &&
        DictionaryBooleanEquals(dictionary,
            CFSTR("com.example.shim-only"), true) &&
        DictionaryBooleanEquals(dictionary,
            CFSTR("com.apple.private.amfi.can-execute-cdhash"), true) &&
        (expectedApplicationIdentifier == NULL ||
            DictionaryStringEquals(dictionary,
                CFSTR("application-identifier"),
                expectedApplicationIdentifier)) &&
        DictionaryStringEquals(dictionary,
            CFSTR("com.apple.developer.team-identifier"),
            expectedTeamIdentifier) &&
        DictionaryStringEquals(dictionary,
            CFSTR("com.apple.private.security.container-required"),
            LC32_TEST_BUNDLE_IDENTIFIER);
    CFRelease(propertyList);
    return valid;
}

static bool BuildVersionMatches(
        LC32TestSliceView slice, uint32_t expectedSDK) {
    if(slice.size < sizeof(struct mach_header_64)) return false;

    struct mach_header_64 header = {0};
    memcpy(&header, slice.bytes, sizeof(header));
    if(header.magic != MH_MAGIC_64 || header.ncmds == 0 ||
            header.ncmds > 1000 ||
            header.sizeofcmds > slice.size - sizeof(header)) {
        return false;
    }

    bool foundBuildVersion = false;
    size_t commandOffset = sizeof(header);
    const size_t commandsEnd = commandOffset + header.sizeofcmds;
    for(uint32_t index = 0; index < header.ncmds; index++) {
        if(commandOffset > commandsEnd ||
                sizeof(struct load_command) >
                    commandsEnd - commandOffset) {
            return false;
        }
        struct load_command command = {0};
        memcpy(&command, slice.bytes + commandOffset, sizeof(command));
        if(command.cmdsize < sizeof(command) ||
                command.cmdsize > commandsEnd - commandOffset) {
            return false;
        }
        if(command.cmd == LC_BUILD_VERSION) {
            if(foundBuildVersion ||
                    command.cmdsize < sizeof(struct build_version_command)) {
                return false;
            }
            struct build_version_command buildVersion = {0};
            memcpy(&buildVersion, slice.bytes + commandOffset,
                sizeof(buildVersion));
            if(buildVersion.ntools >
                    (buildVersion.cmdsize - sizeof(buildVersion)) /
                        sizeof(struct build_tool_version) ||
                    buildVersion.platform != PLATFORM_IOS ||
                    buildVersion.minos != LC32_TEST_IOS_11_VERSION ||
                    buildVersion.sdk != expectedSDK) {
                return false;
            }
            foundBuildVersion = true;
        }
        commandOffset += command.cmdsize;
    }
    return foundBuildVersion && commandOffset == commandsEnd;
}

static bool InjectedSignatureIsValidWithTeam(
        LC32TestSliceView slice, const char *expectedIdentifier,
        bool targetWasSigned, const char *expectedTeamIdentifier,
        const char *expectedApplicationIdentifier,
        uint32_t expectedSDK) {
    uint32_t signatureOffset = 0;
    uint32_t signatureSize = 0;
    if(!BuildVersionMatches(slice, expectedSDK) ||
            !FindCodeSignature(
            slice, &signatureOffset, &signatureSize) || signatureSize < 12) {
        return false;
    }
    const uint8_t *superblob = slice.bytes + signatureOffset;
    LC32TestBlobView codeDirectoryBlob = {0};
    LC32TestBlobView entitlementsBlob = {0};
    LC32TestBlobView derEntitlementsBlob = {0};
    LC32TestBlobView cmsBlob = {0};
    if(!FindSuperblobBlob(superblob, signatureSize,
            LC32_TEST_CODE_DIRECTORY_SLOT, &codeDirectoryBlob) ||
            !FindSuperblobBlob(superblob, signatureSize,
                LC32_TEST_ENTITLEMENTS_SLOT, &entitlementsBlob) ||
            !FindSuperblobBlob(superblob, signatureSize,
                LC32_TEST_DER_ENTITLEMENTS_SLOT,
                &derEntitlementsBlob) ||
            !FindSuperblobBlob(superblob, signatureSize,
                LC32_TEST_CMS_SIGNATURE_SLOT, &cmsBlob) ||
            codeDirectoryBlob.size <
                sizeof(LC32TestLegacyCodeDirectory) ||
            !BlobHasMagicAndLength(
                derEntitlementsBlob,
                LC32_TEST_DER_ENTITLEMENTS_MAGIC) ||
            derEntitlementsBlob.size <= 8 ||
            !BlobHasMagicAndLength(
                cmsBlob, LC32_TEST_BLOB_WRAPPER_MAGIC) ||
            cmsBlob.size != 8 ||
            !MergedEntitlementsAreValid(
                entitlementsBlob, targetWasSigned,
                expectedTeamIdentifier,
                expectedApplicationIdentifier)) {
        return false;
    }

    LC32TestCodeDirectory codeDirectory = {0};
    memcpy(&codeDirectory, codeDirectoryBlob.bytes,
        sizeof(LC32TestLegacyCodeDirectory));
    codeDirectory.magic = BigToHost32(codeDirectory.magic);
    codeDirectory.length = BigToHost32(codeDirectory.length);
    codeDirectory.version = BigToHost32(codeDirectory.version);
    codeDirectory.flags = BigToHost32(codeDirectory.flags);
    codeDirectory.hashOffset = BigToHost32(codeDirectory.hashOffset);
    codeDirectory.identOffset = BigToHost32(codeDirectory.identOffset);
    codeDirectory.nSpecialSlots = BigToHost32(
        codeDirectory.nSpecialSlots);
    codeDirectory.nCodeSlots = BigToHost32(codeDirectory.nCodeSlots);
    codeDirectory.codeLimit = BigToHost32(codeDirectory.codeLimit);
    codeDirectory.spare2 = BigToHost32(codeDirectory.spare2);
    codeDirectory.scatterOffset = BigToHost32(
        codeDirectory.scatterOffset);
    codeDirectory.teamOffset = BigToHost32(codeDirectory.teamOffset);
    size_t codeDirectoryHeaderSize =
        sizeof(LC32TestLegacyCodeDirectory);
    if(codeDirectory.version >= 0x20300) {
        codeDirectoryHeaderSize = offsetof(
            LC32TestCodeDirectory, execSegBase);
        if(codeDirectoryBlob.size < codeDirectoryHeaderSize) return false;
        memcpy((uint8_t *)&codeDirectory +
                sizeof(LC32TestLegacyCodeDirectory),
            codeDirectoryBlob.bytes +
                sizeof(LC32TestLegacyCodeDirectory),
            codeDirectoryHeaderSize -
                sizeof(LC32TestLegacyCodeDirectory));
        codeDirectory.spare3 = BigToHost32(codeDirectory.spare3);
        codeDirectory.codeLimit64 = BigToHost64(
            codeDirectory.codeLimit64);
    }
    if(codeDirectory.version >= 0x20400) {
        codeDirectoryHeaderSize = sizeof(LC32TestCodeDirectory);
        if(codeDirectoryBlob.size < codeDirectoryHeaderSize) return false;
        memcpy((uint8_t *)&codeDirectory +
                offsetof(LC32TestCodeDirectory, execSegBase),
            codeDirectoryBlob.bytes +
                offsetof(LC32TestCodeDirectory, execSegBase),
            sizeof(LC32TestCodeDirectory) -
                offsetof(LC32TestCodeDirectory, execSegBase));
        codeDirectory.execSegBase = BigToHost64(
            codeDirectory.execSegBase);
        codeDirectory.execSegLimit = BigToHost64(
            codeDirectory.execSegLimit);
        codeDirectory.execSegFlags = BigToHost64(
            codeDirectory.execSegFlags);
    }
    if(codeDirectory.magic != LC32_TEST_CODE_DIRECTORY_MAGIC ||
            codeDirectory.length != codeDirectoryBlob.size ||
            codeDirectory.version < 0x20200 ||
            (codeDirectory.flags & LC32_TEST_ADHOC_FLAG) == 0 ||
            codeDirectory.hashType != LC32_TEST_SHA256_TYPE ||
            codeDirectory.hashSize != CC_SHA256_DIGEST_LENGTH ||
            codeDirectory.pageSize >= 31 ||
            codeDirectory.codeLimit != signatureOffset ||
            codeDirectory.codeLimit > slice.size ||
            codeDirectory.spare2 != 0 ||
            codeDirectory.scatterOffset != 0 ||
            (codeDirectory.version >= 0x20300 &&
                (codeDirectory.spare3 != 0 ||
                 codeDirectory.codeLimit64 != 0)) ||
            (codeDirectory.version >= 0x20400 &&
                (codeDirectory.execSegBase != 0 ||
                 codeDirectory.execSegLimit != signatureOffset ||
                 (codeDirectory.execSegFlags &
                    LC32_TEST_EXECSEG_MAIN_BINARY) == 0)) ||
            codeDirectory.identOffset < codeDirectoryHeaderSize ||
            codeDirectory.identOffset >= codeDirectoryBlob.size ||
            codeDirectory.teamOffset < codeDirectoryHeaderSize ||
            codeDirectory.teamOffset >= codeDirectoryBlob.size ||
            codeDirectory.nSpecialSlots <
                LC32_TEST_DER_ENTITLEMENTS_SLOT) {
        return false;
    }

    const char *identifier = (const char *)codeDirectoryBlob.bytes +
        codeDirectory.identOffset;
    const size_t identifierCapacity =
        codeDirectoryBlob.size - codeDirectory.identOffset;
    const char *identifierEnd = memchr(identifier, '\0', identifierCapacity);
    const char *teamIdentifier = (const char *)codeDirectoryBlob.bytes +
        codeDirectory.teamOffset;
    const size_t teamCapacity =
        codeDirectoryBlob.size - codeDirectory.teamOffset;
    const char *teamEnd = memchr(teamIdentifier, '\0', teamCapacity);
    if(identifierEnd == NULL || teamEnd == NULL ||
            strcmp(identifier, expectedIdentifier) != 0 ||
            strcmp(teamIdentifier, expectedTeamIdentifier) != 0) {
        return false;
    }

    const uint64_t specialHashBytes =
        (uint64_t)codeDirectory.nSpecialSlots * codeDirectory.hashSize;
    const uint64_t codeHashBytes =
        (uint64_t)codeDirectory.nCodeSlots * codeDirectory.hashSize;
    if(codeDirectory.hashOffset < specialHashBytes ||
            codeDirectory.hashOffset > codeDirectoryBlob.size ||
            codeHashBytes > codeDirectoryBlob.size -
                codeDirectory.hashOffset) {
        return false;
    }
    const uint8_t *infoHash = codeDirectoryBlob.bytes +
        codeDirectory.hashOffset - codeDirectory.hashSize;
    if(!BytesAreZero(infoHash, codeDirectory.hashSize)) return false;

    if(entitlementsBlob.size > UINT32_MAX ||
            derEntitlementsBlob.size > UINT32_MAX) {
        return false;
    }
    uint8_t expectedHash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(entitlementsBlob.bytes,
        (CC_LONG)entitlementsBlob.size, expectedHash);
    const uint8_t *xmlHash = codeDirectoryBlob.bytes +
        codeDirectory.hashOffset -
            LC32_TEST_ENTITLEMENTS_SLOT * codeDirectory.hashSize;
    if(memcmp(xmlHash, expectedHash, sizeof(expectedHash)) != 0) {
        return false;
    }

    CC_SHA256(derEntitlementsBlob.bytes,
        (CC_LONG)derEntitlementsBlob.size, expectedHash);
    const uint8_t *derHash = codeDirectoryBlob.bytes +
        codeDirectory.hashOffset -
            LC32_TEST_DER_ENTITLEMENTS_SLOT * codeDirectory.hashSize;
    if(memcmp(derHash, expectedHash, sizeof(expectedHash)) != 0) {
        return false;
    }

    const uint32_t pageSize = UINT32_C(1) << codeDirectory.pageSize;
    const uint64_t expectedCodeSlotCount =
        ((uint64_t)codeDirectory.codeLimit + pageSize - 1) / pageSize;
    if(expectedCodeSlotCount > UINT32_MAX ||
            codeDirectory.nCodeSlots != expectedCodeSlotCount) {
        return false;
    }
    for(uint32_t index = 0; index < codeDirectory.nCodeSlots; index++) {
        const uint64_t pageOffset = (uint64_t)index * pageSize;
        if(pageOffset >= codeDirectory.codeLimit) return false;
        const uint32_t remaining = codeDirectory.codeLimit - pageOffset;
        const uint32_t amount = remaining < pageSize ? remaining : pageSize;
        CC_SHA256(slice.bytes + pageOffset, amount, expectedHash);
        const uint8_t *actualHash = codeDirectoryBlob.bytes +
            codeDirectory.hashOffset + index * codeDirectory.hashSize;
        if(memcmp(actualHash, expectedHash, sizeof(expectedHash)) != 0) {
            return false;
        }
    }
    return true;
}

static bool InjectedSignatureIsValid(
        LC32TestSliceView slice, const char *expectedIdentifier,
        bool targetWasSigned, uint32_t expectedSDK) {
    return InjectedSignatureIsValidWithTeam(
        slice, expectedIdentifier, targetWasSigned,
        LC32_TEST_DEFAULT_TEAM_IDENTIFIER, NULL, expectedSDK);
}

static bool EncryptedSignatureUsesShimDonorsAndPreservesCodeHashes(
        LC32TestSliceView original, LC32TestSliceView transformed,
        LC32TestSliceView signedShim,
        const char *expectedIdentifier,
        const char *expectedTeamIdentifier,
        uint32_t expectedOriginalVersion) {
    uint32_t originalSignatureOffset = 0;
    uint32_t originalSignatureSize = 0;
    uint32_t transformedSignatureOffset = 0;
    uint32_t transformedSignatureSize = 0;
    uint32_t shimSignatureOffset = 0;
    uint32_t shimSignatureSize = 0;
    if(original.size != transformed.size ||
            !FindCodeSignature(original,
                &originalSignatureOffset, &originalSignatureSize) ||
            !FindCodeSignature(transformed,
                &transformedSignatureOffset, &transformedSignatureSize) ||
            !FindCodeSignature(signedShim,
                &shimSignatureOffset, &shimSignatureSize) ||
            originalSignatureOffset != transformedSignatureOffset ||
            originalSignatureSize != transformedSignatureSize ||
            memcmp(original.bytes, transformed.bytes,
                originalSignatureOffset) != 0 ||
            memcmp(original.bytes + originalSignatureOffset +
                    originalSignatureSize,
                transformed.bytes + transformedSignatureOffset +
                    transformedSignatureSize,
                original.size - originalSignatureOffset -
                    originalSignatureSize) != 0) {
        return false;
    }

    const uint8_t *originalSuperblob =
        original.bytes + originalSignatureOffset;
    const uint8_t *transformedSuperblob =
        transformed.bytes + transformedSignatureOffset;
    const uint8_t *shimSuperblob = signedShim.bytes + shimSignatureOffset;
    LC32TestBlobView originalCodeDirectory = {0};
    LC32TestBlobView transformedCodeDirectory = {0};
    LC32TestBlobView transformedRequirements = {0};
    LC32TestBlobView transformedEntitlements = {0};
    LC32TestBlobView transformedDEREntitlements = {0};
    LC32TestBlobView transformedCMS = {0};
    LC32TestBlobView shimRequirements = {0};
    LC32TestBlobView shimEntitlements = {0};
    LC32TestBlobView shimDEREntitlements = {0};
    LC32TestBlobView shimCMS = {0};
    if(!FindSuperblobBlob(originalSuperblob, originalSignatureSize,
            LC32_TEST_CODE_DIRECTORY_SLOT, &originalCodeDirectory) ||
            !FindSuperblobBlob(transformedSuperblob,
                transformedSignatureSize,
                LC32_TEST_CODE_DIRECTORY_SLOT,
                &transformedCodeDirectory) ||
            !FindSuperblobBlob(transformedSuperblob,
                transformedSignatureSize,
                LC32_TEST_REQUIREMENTS_SLOT,
                &transformedRequirements) ||
            !FindSuperblobBlob(transformedSuperblob,
                transformedSignatureSize,
                LC32_TEST_ENTITLEMENTS_SLOT,
                &transformedEntitlements) ||
            !FindSuperblobBlob(transformedSuperblob,
                transformedSignatureSize,
                LC32_TEST_DER_ENTITLEMENTS_SLOT,
                &transformedDEREntitlements) ||
            !FindSuperblobBlob(transformedSuperblob,
                transformedSignatureSize,
                LC32_TEST_CMS_SIGNATURE_SLOT, &transformedCMS) ||
            !FindSuperblobBlob(shimSuperblob, shimSignatureSize,
                LC32_TEST_REQUIREMENTS_SLOT, &shimRequirements) ||
            !FindSuperblobBlob(shimSuperblob, shimSignatureSize,
                LC32_TEST_ENTITLEMENTS_SLOT, &shimEntitlements) ||
            !FindSuperblobBlob(shimSuperblob, shimSignatureSize,
                LC32_TEST_DER_ENTITLEMENTS_SLOT,
                &shimDEREntitlements) ||
            !FindSuperblobBlob(shimSuperblob, shimSignatureSize,
                LC32_TEST_CMS_SIGNATURE_SLOT, &shimCMS) ||
            !BlobHasMagicAndLength(
                transformedRequirements, LC32_TEST_REQUIREMENTS_MAGIC) ||
            !BlobHasMagicAndLength(transformedEntitlements,
                LC32_TEST_ENTITLEMENTS_MAGIC) ||
            !BlobHasMagicAndLength(transformedDEREntitlements,
                LC32_TEST_DER_ENTITLEMENTS_MAGIC) ||
            !BlobHasMagicAndLength(
                transformedCMS, LC32_TEST_BLOB_WRAPPER_MAGIC) ||
            transformedCMS.size != 8 ||
            transformedRequirements.size != shimRequirements.size ||
            memcmp(transformedRequirements.bytes,
                shimRequirements.bytes, shimRequirements.size) != 0 ||
            transformedEntitlements.size != shimEntitlements.size ||
            memcmp(transformedEntitlements.bytes,
                shimEntitlements.bytes, shimEntitlements.size) != 0 ||
            transformedDEREntitlements.size != shimDEREntitlements.size ||
            memcmp(transformedDEREntitlements.bytes,
                shimDEREntitlements.bytes,
                shimDEREntitlements.size) != 0 ||
            transformedCMS.size != shimCMS.size ||
            memcmp(transformedCMS.bytes, shimCMS.bytes,
                shimCMS.size) != 0) {
        return false;
    }

    if(originalCodeDirectory.size <
                sizeof(LC32TestLegacyCodeDirectory) ||
            transformedCodeDirectory.size <
                sizeof(LC32TestLegacyCodeDirectory)) {
        return false;
    }
    LC32TestLegacyCodeDirectory originalDirectory = {0};
    LC32TestLegacyCodeDirectory transformedDirectory = {0};
    memcpy(&originalDirectory, originalCodeDirectory.bytes,
        sizeof(originalDirectory));
    memcpy(&transformedDirectory, transformedCodeDirectory.bytes,
        sizeof(transformedDirectory));
    const uint32_t originalVersion = BigToHost32(
        originalDirectory.version);
    const uint32_t originalHashOffset = BigToHost32(
        originalDirectory.hashOffset);
    const uint32_t originalCodeSlotCount = BigToHost32(
        originalDirectory.nCodeSlots);
    const uint32_t transformedVersion = BigToHost32(
        transformedDirectory.version);
    const uint32_t transformedFlags = BigToHost32(
        transformedDirectory.flags);
    const uint32_t transformedHashOffset = BigToHost32(
        transformedDirectory.hashOffset);
    const uint32_t transformedSpecialSlotCount = BigToHost32(
        transformedDirectory.nSpecialSlots);
    const uint32_t transformedCodeSlotCount = BigToHost32(
        transformedDirectory.nCodeSlots);
    const uint32_t transformedIdentifierOffset = BigToHost32(
        transformedDirectory.identOffset);
    const uint32_t transformedTeamOffset = BigToHost32(
        transformedDirectory.teamOffset);
    const uint8_t hashSize = transformedDirectory.hashSize;
    const uint64_t codeHashBytes =
        (uint64_t)transformedCodeSlotCount * hashSize;
    if(originalVersion != expectedOriginalVersion ||
            transformedVersion < 0x20200 ||
            (transformedFlags & LC32_TEST_ADHOC_FLAG) == 0 ||
            transformedSpecialSlotCount <
                LC32_TEST_DER_ENTITLEMENTS_SLOT ||
            originalDirectory.hashType != transformedDirectory.hashType ||
            originalDirectory.hashSize != hashSize || hashSize == 0 ||
            originalCodeSlotCount != transformedCodeSlotCount ||
            originalHashOffset > originalCodeDirectory.size ||
            codeHashBytes >
                originalCodeDirectory.size - originalHashOffset ||
            transformedHashOffset > transformedCodeDirectory.size ||
            codeHashBytes >
                transformedCodeDirectory.size - transformedHashOffset ||
            memcmp(originalCodeDirectory.bytes + originalHashOffset,
                transformedCodeDirectory.bytes + transformedHashOffset,
                (size_t)codeHashBytes) != 0 ||
            transformedIdentifierOffset >= transformedCodeDirectory.size ||
            transformedTeamOffset >= transformedCodeDirectory.size ||
            memchr(transformedCodeDirectory.bytes +
                    transformedIdentifierOffset, '\0',
                transformedCodeDirectory.size -
                    transformedIdentifierOffset) == NULL ||
            memchr(transformedCodeDirectory.bytes + transformedTeamOffset,
                '\0', transformedCodeDirectory.size -
                    transformedTeamOffset) == NULL ||
            strcmp((const char *)transformedCodeDirectory.bytes +
                    transformedIdentifierOffset,
                expectedIdentifier) != 0 ||
            strcmp((const char *)transformedCodeDirectory.bytes +
                    transformedTeamOffset,
                expectedTeamIdentifier) != 0) {
        return false;
    }

    const struct {
        uint32_t slot;
        LC32TestBlobView blob;
    } specialSlots[] = {
        { LC32_TEST_REQUIREMENTS_SLOT, transformedRequirements },
        { LC32_TEST_ENTITLEMENTS_SLOT, transformedEntitlements },
        { LC32_TEST_DER_ENTITLEMENTS_SLOT,
            transformedDEREntitlements },
    };
    for(size_t index = 0;
            index < sizeof(specialSlots) / sizeof(specialSlots[0]);
            index++) {
        if(transformedDirectory.hashType != LC32_TEST_SHA256_TYPE ||
                hashSize != CC_SHA256_DIGEST_LENGTH ||
                specialSlots[index].blob.size > UINT32_MAX) {
            return false;
        }
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(specialSlots[index].blob.bytes,
            (CC_LONG)specialSlots[index].blob.size, digest);
        const uint64_t slotBytes =
            (uint64_t)specialSlots[index].slot * hashSize;
        if(slotBytes > transformedHashOffset ||
                memcmp(transformedCodeDirectory.bytes +
                        transformedHashOffset - slotBytes,
                    digest, sizeof(digest)) != 0) {
            return false;
        }
    }

    if(transformedVersion >= 0x20400) {
        if(transformedCodeDirectory.size <
                sizeof(LC32TestCodeDirectory)) {
            return false;
        }
        uint64_t encodedExecSegFlags = 0;
        memcpy(&encodedExecSegFlags, transformedCodeDirectory.bytes +
            offsetof(LC32TestCodeDirectory, execSegFlags),
            sizeof(encodedExecSegFlags));
        if((BigToHost64(encodedExecSegFlags) &
                LC32_TEST_EXECSEG_MAIN_BINARY) != 0) {
            return false;
        }
    }
    return true;
}

static bool FatContainsExactSlice(
        const uint8_t *fileBytes, size_t fileSize,
        cpu_type_t cpuType, cpu_subtype_t cpuSubtype,
        const uint8_t *expectedBytes, size_t expectedSize) {
    if(fileSize < sizeof(struct fat_header)) return false;
    const struct fat_header *header =
        (const struct fat_header *)fileBytes;
    if(BigToHost32(header->magic) != FAT_MAGIC) return false;

    const uint32_t count = BigToHost32(header->nfat_arch);
    const size_t tableSize = sizeof(*header) +
        (size_t)count * sizeof(struct fat_arch);
    if(count == 0 || count > 16 || tableSize > fileSize) return false;

    const struct fat_arch *architectures =
        (const struct fat_arch *)(fileBytes + sizeof(*header));
    for(uint32_t index = 0; index < count; index++) {
        const cpu_type_t candidateType = (cpu_type_t)BigToHost32(
            (uint32_t)architectures[index].cputype);
        const cpu_subtype_t candidateSubtype = (cpu_subtype_t)BigToHost32(
            (uint32_t)architectures[index].cpusubtype);
        const uint32_t offset = BigToHost32(architectures[index].offset);
        const uint32_t size = BigToHost32(architectures[index].size);
        if(candidateType == cpuType && candidateSubtype == cpuSubtype) {
            return size == expectedSize && offset <= fileSize &&
                size <= fileSize - offset &&
                memcmp(fileBytes + offset, expectedBytes, size) == 0;
        }
    }
    return false;
}

static uint8_t *ReadFile(const char *path, size_t *size) {
    int fd = open(path, O_RDONLY);
    if(fd < 0) return NULL;
    struct stat status = {0};
    if(fstat(fd, &status) != 0 || status.st_size < 0 ||
            (uint64_t)status.st_size > SIZE_MAX) {
        close(fd);
        return NULL;
    }

    const size_t allocationSize = status.st_size == 0 ?
        1 : (size_t)status.st_size;
    uint8_t *bytes = malloc(allocationSize);
    if(bytes == NULL) {
        close(fd);
        return NULL;
    }
    size_t completed = 0;
    while(completed < (size_t)status.st_size) {
        const ssize_t amount = read(fd, bytes + completed,
            (size_t)status.st_size - completed);
        if(amount <= 0) {
            free(bytes);
            close(fd);
            return NULL;
        }
        completed += (size_t)amount;
    }
    close(fd);
    *size = (size_t)status.st_size;
    return bytes;
}

static bool MakeFatARMTarget(
        const char *path,
        const uint8_t *armv7, size_t armv7Size,
        const uint8_t *armv7s, size_t armv7sSize) {
    const uint32_t armv7Offset = 0x1000;
    const uint32_t armv7sOffset = 0x2000;
    const size_t fileSize = armv7sOffset + armv7sSize;
    uint8_t *bytes = calloc(1, fileSize);
    if(bytes == NULL) return false;

    struct fat_header *header = (struct fat_header *)bytes;
    header->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    header->nfat_arch = OSSwapHostToBigInt32(2);
    struct fat_arch *architectures =
        (struct fat_arch *)(bytes + sizeof(*header));
    architectures[0] = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM_V7),
        .offset = OSSwapHostToBigInt32(armv7Offset),
        .size = OSSwapHostToBigInt32((uint32_t)armv7Size),
        .align = OSSwapHostToBigInt32(12),
    };
    architectures[1] = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM_V7S),
        .offset = OSSwapHostToBigInt32(armv7sOffset),
        .size = OSSwapHostToBigInt32((uint32_t)armv7sSize),
        .align = OSSwapHostToBigInt32(12),
    };
    memcpy(bytes + armv7Offset, armv7, armv7Size);
    memcpy(bytes + armv7sOffset, armv7s, armv7sSize);
    const bool succeeded = WriteFile(path, bytes, fileSize, 0751);
    free(bytes);
    return succeeded;
}

static bool MakeFatShim(
        const char *path,
        const uint8_t *arm64e, size_t arm64eSize,
        const uint8_t *arm64, size_t arm64Size) {
    const uint32_t arm64eOffset = 0x4000;
    const uint32_t arm64Offset = 0x8000;
    const size_t fileSize = arm64Offset + arm64Size;
    uint8_t *bytes = calloc(1, fileSize);
    if(bytes == NULL) return false;

    struct fat_header *header = (struct fat_header *)bytes;
    header->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    header->nfat_arch = OSSwapHostToBigInt32(2);
    struct fat_arch *architectures =
        (struct fat_arch *)(bytes + sizeof(*header));
    architectures[0] = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM64),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM64E),
        .offset = OSSwapHostToBigInt32(arm64eOffset),
        .size = OSSwapHostToBigInt32((uint32_t)arm64eSize),
        .align = OSSwapHostToBigInt32(14),
    };
    architectures[1] = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM64),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM64_ALL),
        .offset = OSSwapHostToBigInt32(arm64Offset),
        .size = OSSwapHostToBigInt32((uint32_t)arm64Size),
        .align = OSSwapHostToBigInt32(14),
    };
    memcpy(bytes + arm64eOffset, arm64e, arm64eSize);
    memcpy(bytes + arm64Offset, arm64, arm64Size);
    const bool succeeded = WriteFile(path, bytes, fileSize, 0755);
    free(bytes);
    return succeeded;
}

static int TestThinInjection(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "thin-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "shim")) {
        return Fail("could not format thin test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeSignedThinExecutableWithVersionMin(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x71,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements,
        LC32_TEST_IOS_8_VERSION, LC32_TEST_IOS_14_4_VERSION);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x64,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(!WriteFile(targetPath, target, targetSize, 0751) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create thin test inputs");
    }
    static const char metadata[] = "preserved";
    static const char metadataName[] = "com.kdt.LiveExec32.test";
    if(setxattr(targetPath, metadataName,
            metadata, sizeof(metadata), 0, 0) != 0) {
        return Fail("could not set thin target metadata");
    }

    char error[512];
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) !=
                LC32MachOInjectionSucceeded) {
        fprintf(stderr, "FatMachOTests: thin injection failed: %s\n", error);
        return 1;
    }

    size_t injectedSize = 0;
    uint8_t *injected = ReadFile(targetPath, &injectedSize);
    LC32TestSliceView injectedShim = {0};
    if(injected == NULL ||
            !FatListsShimFirstWithTrailingData(injected, injectedSize, 2) ||
            !FatContainsExactSlice(injected, injectedSize,
                CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, target, targetSize) ||
            !FindFatSlice(injected, injectedSize,
                CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) ||
            !InjectedSignatureIsValid(injectedShim,
                LC32_TEST_CODE_IDENTIFIER, true,
                LC32_TEST_IOS_14_4_VERSION)) {
        free(injected);
        return Fail("thin injection did not produce the expected signed slices");
    }

    struct stat status = {0};
    if(stat(targetPath, &status) != 0 || (status.st_mode & 07777) != 0751) {
        free(injected);
        return Fail("thin injection did not preserve executable mode");
    }
    char copiedMetadata[sizeof(metadata)] = {0};
    if(getxattr(targetPath, metadataName,
            copiedMetadata, sizeof(copiedMetadata), 0, 0) !=
                (ssize_t)sizeof(metadata) ||
            memcmp(copiedMetadata, metadata, sizeof(metadata)) != 0) {
        free(injected);
        return Fail("thin injection did not preserve extended metadata");
    }
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) !=
                LC32MachOInjectionNotApplicable) {
        free(injected);
        return Fail("reinjection was not treated as already complete");
    }

    size_t reinjectedSize = 0;
    uint8_t *reinjected = ReadFile(targetPath, &reinjectedSize);
    const bool unchanged = reinjected != NULL &&
        reinjectedSize == injectedSize &&
        memcmp(reinjected, injected, injectedSize) == 0;
    free(reinjected);
    free(injected);
    return unchanged ? 0 : Fail("reinjection modified the target");
}

static int TestFatInjection(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "fat-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "fat-shim")) {
        return Fail("could not format fat test paths");
    }

    uint8_t armv7[LC32_TEST_SLICE_CAPACITY];
    uint8_t armv7s[LC32_TEST_SLICE_CAPACITY];
    uint8_t arm64eShim[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t armv7Size = MakeSignedThinExecutableWithVersionMin(
        armv7, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x70,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements,
        LC32_TEST_IOS_8_VERSION, LC32_TEST_IOS_10_3_VERSION);
    const size_t armv7sSize = MakeSignedThinExecutableWithVersionMin(
        armv7s, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S, 0x7f,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements,
        LC32_TEST_IOS_8_VERSION, LC32_TEST_IOS_10_3_VERSION);
    const size_t arm64eShimSize = MakeSignedThinExecutable(
        arm64eShim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E, 0xe6,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xa6,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(!MakeFatARMTarget(
            targetPath, armv7, armv7Size, armv7s, armv7sSize) ||
            !MakeFatShim(shimPath,
                arm64eShim, arm64eShimSize, shim, shimSize)) {
        return Fail("could not create fat test inputs");
    }

    char error[512];
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) !=
                LC32MachOInjectionSucceeded) {
        fprintf(stderr, "FatMachOTests: fat injection failed: %s\n", error);
        return 1;
    }

    size_t injectedSize = 0;
    uint8_t *injected = ReadFile(targetPath, &injectedSize);
    LC32TestSliceView injectedShim = {0};
    const bool valid = injected != NULL &&
        FatListsShimFirstWithTrailingData(injected, injectedSize, 3) &&
        FatContainsExactSlice(injected, injectedSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, armv7, armv7Size) &&
        FatContainsExactSlice(injected, injectedSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S, armv7s, armv7sSize) &&
        FindFatSlice(injected, injectedSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        InjectedSignatureIsValid(
            injectedShim, LC32_TEST_CODE_IDENTIFIER, true,
            LC32_TEST_IOS_11_VERSION);
    free(injected);
    return valid ? 0 : Fail("fat injection did not preserve all slices");
}

static int TestMalformedTargetIsUnchanged(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "bad-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "bad-shim")) {
        return Fail("could not format malformed test paths");
    }

    static const uint8_t invalidTarget[] = {0xde, 0xad, 0xbe, 0xef};
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t shimSize = MakeThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x46);
    if(!WriteFile(targetPath, invalidTarget, sizeof(invalidTarget), 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create malformed test inputs");
    }

    char error[512];
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) !=
                LC32MachOInjectionFailed || error[0] == '\0') {
        return Fail("malformed target did not produce a useful failure");
    }

    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = result != NULL &&
        resultSize == sizeof(invalidTarget) &&
        memcmp(result, invalidTarget, sizeof(invalidTarget)) == 0;
    free(result);
    return unchanged ? 0 : Fail("malformed target was modified");
}

static int TestMalformedCodeSignatureIsUnchanged(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "bad-signature-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "bad-signature-shim")) {
        return Fail("could not format malformed signature test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeSignedThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x31,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x64,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    uint32_t invalidMagic = 0;
    memcpy(target + LC32_TEST_CODE_SIGNATURE_OFFSET,
        &invalidMagic, sizeof(invalidMagic));
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create malformed signature test inputs");
    }

    char error[512];
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = injectionResult == LC32MachOInjectionFailed &&
        error[0] != '\0' && result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    return unchanged ? 0 :
        Fail("malformed code signature was accepted or modified");
}

static int TestVersionedCodeDirectoryBoundsAreRejected(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "versioned-codedirectory-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "versioned-codedirectory-shim")) {
        return Fail("could not format versioned CodeDirectory test paths");
    }

    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x65,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(shimSize == 0 || !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create versioned CodeDirectory test shim");
    }

    static const struct {
        uint32_t version;
        uint32_t identifierOffset;
        uint32_t teamOffset;
        uint32_t truncatedLength;
        const char *description;
    } cases[] = {
        {
            .version = 0x20300,
            .identifierOffset = sizeof(LC32TestLegacyCodeDirectory),
            .truncatedLength = sizeof(LC32TestLegacyCodeDirectory),
            .description = "truncated v0x20300 CodeDirectory",
        },
        {
            .version = 0x20300,
            .identifierOffset = sizeof(LC32TestLegacyCodeDirectory),
            .description = "v0x20300 identifier inside header extension",
        },
        {
            .version = 0x20400,
            .teamOffset = 0x40,
            .description = "v0x20400 team identifier inside header extension",
        },
    };

    for(size_t index = 0; index < sizeof(cases) / sizeof(cases[0]);
            index++) {
        uint8_t target[LC32_TEST_SLICE_CAPACITY];
        const size_t targetSize = MakeSignedThinExecutable(
            target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x32,
            LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements);
        bool mutated = targetSize != 0 &&
            SetFixtureCodeDirectoryUInt32(target, targetSize,
                offsetof(LC32TestLegacyCodeDirectory, version),
                cases[index].version) &&
            SetFixtureCodeDirectoryUInt32(target, targetSize,
                offsetof(LC32TestLegacyCodeDirectory, identOffset),
                cases[index].identifierOffset) &&
            SetFixtureCodeDirectoryUInt32(target, targetSize,
                offsetof(LC32TestLegacyCodeDirectory, teamOffset),
                cases[index].teamOffset);
        if(mutated && cases[index].truncatedLength != 0) {
            mutated = SetFixtureCodeDirectoryUInt32(target, targetSize,
                offsetof(LC32TestLegacyCodeDirectory, length),
                cases[index].truncatedLength);
        }
        if(!mutated || !WriteFile(targetPath, target, targetSize, 0755)) {
            return Fail("could not create versioned CodeDirectory fixture");
        }

        char error[512];
        const LC32MachOInjectionResult injectionResult =
            LC32InjectArm64ExecutableSlice(
                targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
                error, sizeof(error));
        size_t resultSize = 0;
        uint8_t *result = ReadFile(targetPath, &resultSize);
        const bool unchanged =
            injectionResult == LC32MachOInjectionFailed &&
            error[0] != '\0' && result != NULL &&
            resultSize == targetSize &&
            memcmp(result, target, targetSize) == 0;
        free(result);
        if(!unchanged) {
            fprintf(stderr, "FatMachOTests: accepted or modified %s\n",
                cases[index].description);
            return 1;
        }
    }

    return 0;
}

static int TestUnsignedTargetUsesFallbackIdentifier(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "unsigned-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "unsigned-target-shim")) {
        return Fail("could not format unsigned target test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x32);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x64,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create unsigned target test inputs");
    }

    char error[512];
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) != LC32MachOInjectionSucceeded) {
        fprintf(stderr,
            "FatMachOTests: unsigned target injection failed: %s\n",
            error);
        return 1;
    }
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    LC32TestSliceView injectedShim = {0};
    const bool valid = result != NULL &&
        FatListsShimFirstWithTrailingData(result, resultSize, 2) &&
        FatContainsExactSlice(result, resultSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, target, targetSize) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        InjectedSignatureIsValid(injectedShim,
            LC32_TEST_FALLBACK_CODE_IDENTIFIER, false,
            LC32_TEST_IOS_11_VERSION);
    free(result);
    return valid ? 0 :
        Fail("unsigned target did not use the fallback signing metadata");
}

static int TestApplicationIdentifierDerivesTeamIdentifier(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "derived-team-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "derived-team-shim")) {
        return Fail("could not format derived-team test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeSignedThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x39,
        LC32_TEST_CODE_IDENTIFIER, LC32TestDerivedTeamEntitlements);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x69,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create derived-team test inputs");
    }

    char error[512] = {0};
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) != LC32MachOInjectionSucceeded) {
        fprintf(stderr,
            "FatMachOTests: derived-team injection failed: %s\n", error);
        return 1;
    }

    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    LC32TestSliceView injectedShim = {0};
    const bool valid = result != NULL &&
        FatListsShimFirstWithTrailingData(result, resultSize, 2) &&
        FatContainsExactSlice(result, resultSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, target, targetSize) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        InjectedSignatureIsValidWithTeam(injectedShim,
            LC32_TEST_CODE_IDENTIFIER, true,
            LC32_TEST_DERIVED_TEAM_IDENTIFIER,
            LC32_TEST_APPLICATION_IDENTIFIER,
            LC32_TEST_IOS_11_VERSION);
    free(result);
    return valid ? 0 :
        Fail("application-identifier did not provide the signing team");
}

static int TestExplicitTeamIdentifierOverridesOtherSources(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "explicit-team-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "explicit-team-shim")) {
        return Fail("could not format explicit-team test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeSignedThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x3a,
        LC32_TEST_CODE_IDENTIFIER, LC32TestExplicitTeamEntitlements);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x6a,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create explicit-team test inputs");
    }

    char error[512] = {0};
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) != LC32MachOInjectionSucceeded) {
        fprintf(stderr,
            "FatMachOTests: explicit-team injection failed: %s\n", error);
        return 1;
    }

    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    LC32TestSliceView injectedShim = {0};
    const bool valid = result != NULL &&
        FatListsShimFirstWithTrailingData(result, resultSize, 2) &&
        FatContainsExactSlice(result, resultSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, target, targetSize) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        InjectedSignatureIsValidWithTeam(injectedShim,
            LC32_TEST_CODE_IDENTIFIER, true,
            LC32_TEST_EXPLICIT_TEAM_IDENTIFIER,
            LC32_TEST_APPLICATION_IDENTIFIER,
            LC32_TEST_IOS_11_VERSION);
    free(result);
    return valid ? 0 :
        Fail("explicit target Team ID did not override other sources");
}

static int TestEmptyBundleIdentifierIsUnchanged(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "empty-bundle-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "empty-bundle-shim")) {
        return Fail("could not format empty bundle-ID test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeSignedThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x33,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0x64,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create empty bundle-ID test inputs");
    }

    char error[512];
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, "", error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = injectionResult == LC32MachOInjectionFailed &&
        error[0] != '\0' && result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    return unchanged ? 0 :
        Fail("empty bundle identifier was accepted or modified target");
}

static int TestEncryptedTargetSignatureIsModernized(
        const char *directory, uint32_t originalCodeDirectoryVersion) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "encrypted-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "encrypted-shim")) {
        return Fail("could not format encrypted test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeEncryptedARMExecutable(
        target, originalCodeDirectoryVersion);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xe6,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create encrypted test inputs");
    }

    char error[512] = {0};
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) !=
                LC32MachOInjectionSucceeded) {
        fprintf(stderr,
            "FatMachOTests: encrypted injection failed: %s\n", error);
        return 1;
    }

    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    LC32TestSliceView injectedTarget = {0};
    LC32TestSliceView injectedShim = {0};
    const LC32TestSliceView originalTarget = {
        .bytes = target,
        .size = targetSize,
    };
    const bool transformed = result != NULL &&
        FatListsShimFirstWithTrailingData(result, resultSize, 2) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, &injectedTarget) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        InjectedSignatureIsValidWithTeam(injectedShim,
            LC32_TEST_CODE_IDENTIFIER, true,
            LC32_TEST_DERIVED_TEAM_IDENTIFIER,
            LC32_TEST_APPLICATION_IDENTIFIER,
            LC32_TEST_IOS_11_VERSION) &&
        EncryptedSignatureUsesShimDonorsAndPreservesCodeHashes(
            originalTarget, injectedTarget, injectedShim,
            LC32_TEST_CODE_IDENTIFIER,
            LC32_TEST_DERIVED_TEAM_IDENTIFIER,
            originalCodeDirectoryVersion);
    free(result);
    return transformed ? 0 :
        Fail("encrypted target signature was not modernized safely");
}

static int TestEncryptedSignatureWithoutCapacityIsUnchanged(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "encrypted-small-signature-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "encrypted-small-signature-shim")) {
        return Fail("could not format small-signature test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    if(MakeEncryptedARMExecutable(target, 0x20100) == 0) {
        return Fail("could not create the encrypted fixture");
    }
    const size_t targetSize =
        ShrinkEncryptedFixtureSignatureAllocation(target);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xe7,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(targetSize == 0 || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create small-signature test inputs");
    }

    char error[512] = {0};
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged =
        injectionResult == LC32MachOInjectionFailed &&
        strstr(error, "allocation is too small") != NULL &&
        result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    return unchanged ? 0 :
        Fail("undersized encrypted signature was modified or accepted");
}

static int TestUnsafeEncryptedSignatureLayoutsAreUnchanged(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "unsafe-encrypted-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "unsafe-encrypted-shim")) {
        return Fail("could not format unsafe encrypted test paths");
    }

    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xe8,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(shimSize == 0 || !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create unsafe encrypted test shim");
    }

    static const char *const descriptions[] = {
        "overlapping encrypted and code-signature ranges",
        "code hash coverage extending into the signature",
        "inconsistent CodeDirectory page coverage",
    };
    for(size_t index = 0;
            index < sizeof(descriptions) / sizeof(descriptions[0]);
            index++) {
        uint8_t target[LC32_TEST_SLICE_CAPACITY];
        const size_t targetSize =
            MakeEncryptedARMExecutable(target, 0x20100);
        bool mutated = targetSize != 0;
        switch(index) {
            case 0:
                mutated = mutated && SetFixtureEncryptionRange(
                    target, targetSize,
                    LC32_TEST_CODE_SIGNATURE_OFFSET, 16);
                break;
            case 1:
                mutated = mutated && SetFixtureCodeDirectoryUInt32(
                    target, targetSize,
                    offsetof(LC32TestLegacyCodeDirectory, codeLimit),
                    LC32_TEST_CODE_SIGNATURE_OFFSET + 1);
                break;
            case 2:
                mutated = mutated && SetFixtureCodeDirectoryUInt8(
                    target, targetSize,
                    offsetof(LC32TestLegacyCodeDirectory, pageSize), 9);
                break;
            default:
                mutated = false;
                break;
        }
        if(!mutated ||
                !WriteFile(targetPath, target, targetSize, 0755)) {
            return Fail("could not create unsafe encrypted fixture");
        }

        char error[512] = {0};
        const LC32MachOInjectionResult injectionResult =
            LC32InjectArm64ExecutableSlice(
                targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
                error, sizeof(error));
        size_t resultSize = 0;
        uint8_t *result = ReadFile(targetPath, &resultSize);
        const bool unchanged =
            injectionResult == LC32MachOInjectionFailed &&
            error[0] != '\0' && result != NULL &&
            resultSize == targetSize &&
            memcmp(result, target, targetSize) == 0;
        free(result);
        if(!unchanged) {
            fprintf(stderr, "FatMachOTests: accepted or modified %s\n",
                descriptions[index]);
            return 1;
        }
    }
    return 0;
}

static int TestEncryptedSignatureBeyondCopyChunk(
        const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "large-signature-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "large-signature-shim")) {
        return Fail("could not format large-signature test paths");
    }

    uint8_t smallTarget[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t smallTargetSize =
        MakeEncryptedARMExecutable(smallTarget, 0x20100);
    size_t targetSize = 0;
    uint8_t *target = smallTargetSize == 0 ? NULL :
        CopyEncryptedFixtureWithRelocatedSignature(
            smallTarget, smallTargetSize,
            LC32_TEST_LARGE_CODE_SIGNATURE_OFFSET, &targetSize);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xe9,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(target == NULL || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        free(target);
        return Fail("could not create large-signature test inputs");
    }

    char error[512] = {0};
    if(LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error)) != LC32MachOInjectionSucceeded) {
        fprintf(stderr,
            "FatMachOTests: large-signature injection failed: %s\n",
            error);
        free(target);
        return 1;
    }

    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    LC32TestSliceView injectedTarget = {0};
    LC32TestSliceView injectedShim = {0};
    const LC32TestSliceView originalTarget = {
        .bytes = target,
        .size = targetSize,
    };
    const bool transformed = result != NULL &&
        FatListsShimFirstWithTrailingData(result, resultSize, 2) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, &injectedTarget) &&
        FindFatSlice(result, resultSize,
            CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, &injectedShim) &&
        EncryptedSignatureUsesShimDonorsAndPreservesCodeHashes(
            originalTarget, injectedTarget, injectedShim,
            LC32_TEST_CODE_IDENTIFIER,
            LC32_TEST_DERIVED_TEAM_IDENTIFIER, 0x20100);
    free(result);
    free(target);
    return transformed ? 0 :
        Fail("large-offset encrypted signature was not rewritten safely");
}

static int TestByteSwappedTargetIsUnchanged(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "byte-swapped-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "byte-swapped-shim")) {
        return Fail("could not format byte-swapped test paths");
    }

    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t targetSize = MakeByteSwappedARMExecutable(target);
    const size_t shimSize = MakeThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xb5);
    if(!WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create byte-swapped test inputs");
    }

    char error[512] = {0};
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = injectionResult == LC32MachOInjectionFailed &&
        strcmp(error,
            "byte-swapped ARM executable slices are not supported") == 0 &&
        result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    return unchanged ? 0 :
        Fail("byte-swapped ARM target was accepted or modified");
}

static int ExpectParserFailure(
        const char *directory, const char *shimPath,
        const char *caseName, const uint8_t *target, size_t targetSize) {
    char targetPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "parser-failure-target") ||
            !WriteFile(targetPath, target, targetSize, 0755)) {
        return Fail("could not create parser-failure target");
    }

    char error[512] = {0};
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = injectionResult == LC32MachOInjectionFailed &&
        strcmp(error,
            "could not parse the target executable Mach-O") == 0 &&
        result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    if(!unchanged) {
        fprintf(stderr,
            "FatMachOTests: parser case '%s' returned %d: %s\n",
            caseName, injectionResult, error);
        return 1;
    }
    return 0;
}

static int TestCodeSignatureOutsideLinkeditIsRejected(
        const char *directory, const char *shimPath) {
    uint8_t target[LC32_TEST_SLICE_CAPACITY];
    const size_t signedSize = MakeSignedThinExecutable(
        target, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x7c,
        LC32_TEST_CODE_IDENTIFIER, LC32TestTargetEntitlements);
    const size_t targetSize = signedSize + 16;
    if(signedSize == 0 || targetSize > sizeof(target)) {
        return Fail("could not create misplaced-signature target");
    }

    const size_t linkeditCommandOffset =
        sizeof(struct mach_header) + sizeof(struct segment_command);
    struct segment_command linkedit;
    memcpy(&linkedit, target + linkeditCommandOffset, sizeof(linkedit));
    if(strncmp(linkedit.segname, SEG_LINKEDIT,
            sizeof(linkedit.segname)) != 0) {
        return Fail("signed fixture has no unique __LINKEDIT segment");
    }

    /*
     * Keep both ranges inside the file but make them adjacent: the signature
     * ends where the unique __LINKEDIT segment begins.
     */
    memset(target + signedSize, 0, targetSize - signedSize);
    linkedit.fileoff = (uint32_t)signedSize;
    linkedit.filesize = (uint32_t)(targetSize - signedSize);
    memcpy(target + linkeditCommandOffset, &linkedit, sizeof(linkedit));
    if(!RefreshFixtureCodeHash(target, targetSize)) {
        return Fail("could not refresh misplaced-signature fixture hash");
    }

    return ExpectParserFailure(
        directory, shimPath,
        "code signature outside the unique __LINKEDIT segment",
        target, targetSize);
}

static int TestParserFailuresAreGenericAndUnchanged(
        const char *directory) {
    char shimPath[1024];
    if(!FormatTestPath(shimPath, sizeof(shimPath),
            directory, "parser-failure-shim")) {
        return Fail("could not format parser-failure shim path");
    }
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xc3,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    if(!WriteFile(shimPath, shim, shimSize, 0755)) {
        return Fail("could not create parser-failure shim");
    }

    int result = TestCodeSignatureOutsideLinkeditIsRejected(
        directory, shimPath);
    if(result != 0) return result;

    static const struct {
        const char *name;
        uint32_t commandCount;
        uint32_t declaredCommandBytes;
        uint32_t commandSize;
    } truncatedCommandCases[] = {
        {"zero-sized thin load command", 1,
            sizeof(struct load_command), 0},
        {"truncated thin load-command count", 2,
            2 * sizeof(struct load_command), sizeof(struct load_command)},
        {"oversized truncated thin load-command table", 1,
            8u * 1024u * 1024u + 4u,
            8u * 1024u * 1024u + 4u},
    };
    uint8_t truncatedCommand[
        sizeof(struct mach_header) + sizeof(struct load_command)];
    for(size_t index = 0;
            index < sizeof(truncatedCommandCases) /
                sizeof(truncatedCommandCases[0]); index++) {
        const size_t targetSize = MakeTruncatedLoadCommandExecutable(
            truncatedCommand,
            truncatedCommandCases[index].commandCount,
            truncatedCommandCases[index].declaredCommandBytes,
            truncatedCommandCases[index].commandSize);
        const int result = ExpectParserFailure(
            directory, shimPath, truncatedCommandCases[index].name,
            truncatedCommand, targetSize);
        if(result != 0) return result;
    }

    size_t excessiveCommandsSize = 0;
    uint8_t *excessiveCommands = MakeRepeatedLoadCommandsExecutable(
        1001, sizeof(struct load_command), &excessiveCommandsSize);
    if(excessiveCommands == NULL) {
        return Fail("could not create excessive load-command target");
    }
    result = ExpectParserFailure(
        directory, shimPath, "excessive thin load-command count",
        excessiveCommands, excessiveCommandsSize);
    free(excessiveCommands);
    if(result != 0) return result;

    const size_t malformedThinSize = MakeTruncatedLoadCommandExecutable(
        truncatedCommand, 1, 8u * 1024u * 1024u + 4u,
        8u * 1024u * 1024u + 4u);
    size_t malformedFatSize = 0;
    uint8_t *malformedFat = MakeSingleSliceFatImage(
        truncatedCommand, malformedThinSize, &malformedFatSize);
    if(malformedFat == NULL) {
        return Fail("could not create malformed fat load-command target");
    }
    result = ExpectParserFailure(
        directory, shimPath, "fat slice with truncated load commands",
        malformedFat, malformedFatSize);
    free(malformedFat);
    if(result != 0) return result;

    uint8_t outOfBoundsFat[
        sizeof(struct fat_header) + sizeof(struct fat_arch)] = {0};
    struct fat_header *outOfBoundsHeader =
        (struct fat_header *)outOfBoundsFat;
    outOfBoundsHeader->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    outOfBoundsHeader->nfat_arch = OSSwapHostToBigInt32(1);
    struct fat_arch *outOfBoundsArchitecture = (struct fat_arch *)(
        outOfBoundsFat + sizeof(struct fat_header));
    *outOfBoundsArchitecture = (struct fat_arch){
        .cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM),
        .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
            CPU_SUBTYPE_ARM_V7),
        .offset = OSSwapHostToBigInt32(0x1000),
        .size = OSSwapHostToBigInt32(0x1000),
        .align = OSSwapHostToBigInt32(12),
    };
    result = ExpectParserFailure(
        directory, shimPath, "out-of-bounds fat descriptor",
        outOfBoundsFat, sizeof(outOfBoundsFat));
    if(result != 0) return result;

    const struct fat_header truncatedFatTable = {
        .magic = OSSwapHostToBigInt32(FAT_MAGIC),
        .nfat_arch = OSSwapHostToBigInt32(1),
    };
    result = ExpectParserFailure(
        directory, shimPath, "truncated fat descriptor table",
        (const uint8_t *)&truncatedFatTable, sizeof(truncatedFatTable));
    if(result != 0) return result;

    uint8_t validThin[LC32_TEST_SLICE_CAPACITY];
    const size_t validThinSize = MakeThinExecutable(
        validThin, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0xa5);
    size_t excessiveSlicesSize = 0;
    uint8_t *excessiveSlices = MakeRepeatedSliceFatImage(
        validThin, validThinSize, 6, &excessiveSlicesSize);
    if(excessiveSlices == NULL) {
        return Fail("could not create excessive fat-slice target");
    }
    result = ExpectParserFailure(
        directory, shimPath, "fat image with more than five slices",
        excessiveSlices, excessiveSlicesSize);
    free(excessiveSlices);
    if(result != 0) return result;

    return 0;
}

static int TestFiveSliceTargetIsUnchanged(const char *directory) {
    char targetPath[1024];
    char shimPath[1024];
    if(!FormatTestPath(targetPath, sizeof(targetPath),
            directory, "five-slice-target") ||
            !FormatTestPath(shimPath, sizeof(shimPath),
                directory, "five-slice-shim")) {
        return Fail("could not format five-slice test paths");
    }

    uint8_t thinTarget[LC32_TEST_SLICE_CAPACITY];
    uint8_t shim[LC32_TEST_SLICE_CAPACITY];
    const size_t thinTargetSize = MakeThinExecutable(
        thinTarget, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, 0x5a);
    const size_t shimSize = MakeSignedThinExecutable(
        shim, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, 0xc4,
        "com.kdt.LiveExec32", LC32TestShimEntitlements);
    size_t targetSize = 0;
    uint8_t *target = MakeFiveSliceARMFatImage(
        thinTarget, thinTargetSize, &targetSize);
    if(target == NULL || shimSize == 0 ||
            !WriteFile(targetPath, target, targetSize, 0755) ||
            !WriteFile(shimPath, shim, shimSize, 0755)) {
        free(target);
        return Fail("could not create five-slice test inputs");
    }

    char error[512] = {0};
    const LC32MachOInjectionResult injectionResult =
        LC32InjectArm64ExecutableSlice(
            targetPath, shimPath, LC32_TEST_BUNDLE_IDENTIFIER,
            error, sizeof(error));
    size_t resultSize = 0;
    uint8_t *result = ReadFile(targetPath, &resultSize);
    const bool unchanged = injectionResult == LC32MachOInjectionFailed &&
        strcmp(error,
            "target executable has too many slices to add arm64") == 0 &&
        result != NULL && resultSize == targetSize &&
        memcmp(result, target, targetSize) == 0;
    free(result);
    free(target);
    return unchanged ? 0 :
        Fail("five-slice target was not rejected early and unchanged");
}

static void CleanupTestDirectory(const char *directory) {
    static const char *const names[] = {
        "thin-target", "shim", "fat-target",
        "fat-shim", "bad-target", "bad-shim",
        "bad-signature-target", "bad-signature-shim",
        "versioned-codedirectory-target", "versioned-codedirectory-shim",
        "unsigned-target", "unsigned-target-shim",
        "derived-team-target", "derived-team-shim",
        "explicit-team-target", "explicit-team-shim",
        "empty-bundle-target", "empty-bundle-shim",
        "encrypted-target", "encrypted-shim",
        "encrypted-small-signature-target",
        "encrypted-small-signature-shim",
        "unsafe-encrypted-target", "unsafe-encrypted-shim",
        "large-signature-target", "large-signature-shim",
        "byte-swapped-target", "byte-swapped-shim",
        "parser-failure-target", "parser-failure-shim",
        "five-slice-target", "five-slice-shim",
    };
    for(size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        char path[1024];
        if(FormatTestPath(path, sizeof(path), directory, names[index])) {
            (void)unlink(path);
        }
    }
    (void)rmdir(directory);
}

int main(void) {
    (void)alarm(LC32_TEST_TIMEOUT_SECONDS);

    char temporaryDirectory[] =
        "/tmp/LiveExec32FatMachOTests.XXXXXX";
    if(mkdtemp(temporaryDirectory) == NULL) {
        return Fail("could not create temporary directory");
    }

    const int thinResult = TestThinInjection(temporaryDirectory);
    const int fatResult = thinResult == 0 ?
        TestFatInjection(temporaryDirectory) : thinResult;
    const int malformedResult = fatResult == 0 ?
        TestMalformedTargetIsUnchanged(temporaryDirectory) : fatResult;
    const int malformedSignatureResult = malformedResult == 0 ?
        TestMalformedCodeSignatureIsUnchanged(temporaryDirectory) :
            malformedResult;
    const int versionedCodeDirectoryResult =
        malformedSignatureResult == 0 ?
            TestVersionedCodeDirectoryBoundsAreRejected(
                temporaryDirectory) : malformedSignatureResult;
    const int missingSignatureResult = versionedCodeDirectoryResult == 0 ?
        TestUnsignedTargetUsesFallbackIdentifier(temporaryDirectory) :
            versionedCodeDirectoryResult;
    const int derivedTeamResult = missingSignatureResult == 0 ?
        TestApplicationIdentifierDerivesTeamIdentifier(
            temporaryDirectory) : missingSignatureResult;
    const int explicitTeamResult = derivedTeamResult == 0 ?
        TestExplicitTeamIdentifierOverridesOtherSources(
            temporaryDirectory) : derivedTeamResult;
    const int emptyBundleResult = explicitTeamResult == 0 ?
        TestEmptyBundleIdentifierIsUnchanged(temporaryDirectory) :
            explicitTeamResult;
    const int parserResult = emptyBundleResult == 0 ?
        TestParserFailuresAreGenericAndUnchanged(temporaryDirectory) :
            emptyBundleResult;
    const int sliceLimitResult = parserResult == 0 ?
        TestFiveSliceTargetIsUnchanged(temporaryDirectory) : parserResult;
    const int byteSwappedResult = sliceLimitResult == 0 ?
        TestByteSwappedTargetIsUnchanged(temporaryDirectory) :
            sliceLimitResult;
    const int earliestEncryptedResult = byteSwappedResult == 0 ?
        TestEncryptedTargetSignatureIsModernized(
            temporaryDirectory, 0x20001) : byteSwappedResult;
    const int encryptedResult = earliestEncryptedResult == 0 ?
        TestEncryptedTargetSignatureIsModernized(
            temporaryDirectory, 0x20100) : earliestEncryptedResult;
    const int encryptedCapacityResult = encryptedResult == 0 ?
        TestEncryptedSignatureWithoutCapacityIsUnchanged(
            temporaryDirectory) : encryptedResult;
    const int unsafeEncryptedResult = encryptedCapacityResult == 0 ?
        TestUnsafeEncryptedSignatureLayoutsAreUnchanged(
            temporaryDirectory) : encryptedCapacityResult;
    const int largeSignatureResult = unsafeEncryptedResult == 0 ?
        TestEncryptedSignatureBeyondCopyChunk(
            temporaryDirectory) : unsafeEncryptedResult;
    CleanupTestDirectory(temporaryDirectory);
    (void)alarm(0);
    if(largeSignatureResult == 0) {
        printf("FatMachOTests: all tests passed\n");
    }
    return largeSignatureResult;
}
