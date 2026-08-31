#include "FatMachO.h"
#include "AdHocSigner.h"
#include "MachOImage.h"

#include <CoreFoundation/CoreFoundation.h>
#include <copyfile.h>
#include <errno.h>
#include <fcntl.h>
#include <libkern/OSByteOrder.h>
#include <limits.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/stdio.h>
#include <sys/types.h>
#include <unistd.h>

#define LC32_OUTPUT_MIN_ALIGN_EXPONENT 14u
#define LC32_COPY_BUFFER_SIZE (256u * 1024u)
#define LC32_MAX_CODE_SIGNATURE_BLOBS 64u
#define LC32_MAX_CODE_SIGNATURE_SIZE (16u * 1024u * 1024u)
#define LC32_MAX_SIGNED_SHIM_SIZE (128u * 1024u * 1024u)
#define LC32_MAX_SIGNING_STRING_SIZE 4096u
#define LC32_SIGNING_STAGING_NAME "shim"
#define LC32_REPLACEMENT_STAGING_NAME "replacement"
#define LC32_IOS_11_VERSION (11u << 16)

#define LC32_CS_MAGIC_CODE_DIRECTORY 0xfade0c02u
#define LC32_CS_MAGIC_EMBEDDED_SIGNATURE 0xfade0cc0u
#define LC32_CS_MAGIC_EMBEDDED_ENTITLEMENTS 0xfade7171u
#define LC32_CS_SLOT_CODE_DIRECTORY 0u
#define LC32_CS_SLOT_ENTITLEMENTS 5u
#define LC32_CS_SLOT_ALTERNATE_DIRECTORIES 0x1000u
#define LC32_CS_SLOT_ALTERNATE_DIRECTORY_LIMIT 0x1005u
#define LC32_CS_HASH_SHA1 1u
#define LC32_CS_HASH_SHA256 2u
#define LC32_CS_HASH_SHA256_TRUNCATED 3u
#define LC32_CS_HASH_SHA384 4u

static const CFStringRef LC32TeamIdentifierEntitlement =
    CFSTR("com.apple.developer.team-identifier");
static const CFStringRef LC32ContainerRequiredEntitlement =
    CFSTR("com.apple.private.security.container-required");

typedef struct {
    int sourceFD;
    uint64_t sourceOffset;
    const uint8_t *sourceBytes;
    uint64_t size;
    cpu_type_t cpuType;
    cpu_subtype_t cpuSubtype;
    uint32_t fileType;
    uint32_t sourceAlignExponent;
    bool is64Bit;
    bool encrypted;
    uint32_t outputOffset;
    uint32_t outputAlignExponent;
} LC32OutputSlice;

static uint32_t LC32OutputIndexForFatDescriptor(
        uint32_t descriptorIndex, uint32_t targetSliceCount) {
    return descriptorIndex == 0 ?
        targetSliceCount : descriptorIndex - 1;
}

/* Code-signing blob layouts are copied from ChOma's public headers. */
typedef struct __BlobIndex {
    uint32_t type;
    uint32_t offset;
} CS_BlobIndex;

typedef struct __SuperBlob {
    uint32_t magic;
    uint32_t length;
    uint32_t count;
    CS_BlobIndex index[];
} CS_SuperBlob;

typedef struct __GenericBlob {
    uint32_t magic;
    uint32_t length;
    char data[];
} CS_GenericBlob;

typedef struct __CodeDirectory {
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

    /* Version 0x20100 */
    uint32_t scatterOffset;

    /* Version 0x20200 */
    uint32_t teamOffset;

    /* Version 0x20300 */
    uint32_t spare3;
    uint64_t codeLimit64;

    /* Version 0x20400 */
    uint64_t execSegBase;
    uint64_t execSegLimit;
    uint64_t execSegFlags;

    /* Version 0x20500 */
    uint32_t runtime;
    uint32_t preEncryptOffset;

    /* Version 0x20600 */
    uint8_t linkageHashType;
    uint8_t linkageApplicationType;
    uint16_t linkageApplicationSubType;
    uint32_t linkageOffset;
    uint32_t linkageSize;
} CS_CodeDirectory
__attribute__((aligned(1)));

_Static_assert(offsetof(CS_CodeDirectory, linkageSize) +
        sizeof(uint32_t) == 108,
    "version 0x20600 CodeDirectory header must be 108 bytes");

typedef struct {
    char *identifier;
    char *teamIdentifier;
    CFMutableDictionaryRef entitlements;
    bool hasCodeSignature;
} LC32CodeSignatureMetadata;

static void LC32SetError(
        char *buffer, size_t capacity, const char *format, ...) {
    if(buffer == NULL || capacity == 0) return;

    va_list arguments;
    va_start(arguments, format);
    (void)vsnprintf(buffer, capacity, format, arguments);
    va_end(arguments);
}

static void LC32SetErrnoError(
        char *buffer, size_t capacity,
        const char *operation, const char *path, int errorNumber) {
    LC32SetError(buffer, capacity, "%s %s: %s",
        operation, path ? path : "(null)", strerror(errorNumber));
}

static bool LC32AddUInt64(
        uint64_t left, uint64_t right, uint64_t *result) {
    if(UINT64_MAX - left < right) return false;
    *result = left + right;
    return true;
}

static bool LC32AlignUInt64(
        uint64_t value, uint64_t alignment, uint64_t *result) {
    if(alignment == 0 || (alignment & (alignment - 1)) != 0) return false;
    const uint64_t mask = alignment - 1;
    if(value > UINT64_MAX - mask) return false;
    *result = (value + mask) & ~mask;
    return true;
}

static bool LC32RangeFits(
        uint64_t offset, uint64_t size, uint64_t containerSize) {
    return offset <= containerSize && size <= containerSize - offset;
}

static bool LC32ReadAt(
        int fd, void *buffer, size_t size, uint64_t offset) {
    if(offset > INT64_MAX || size > (uint64_t)INT64_MAX - offset) {
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

static bool LC32WriteAt(
        int fd, const void *buffer, size_t size, uint64_t offset) {
    if(offset > INT64_MAX || size > (uint64_t)INT64_MAX - offset) {
        errno = EOVERFLOW;
        return false;
    }

    size_t completed = 0;
    while(completed < size) {
        const ssize_t amount = pwrite(fd,
            (const uint8_t *)buffer + completed, size - completed,
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

static uint32_t LC32BaseCPUSubtype(cpu_subtype_t subtype) {
    return (uint32_t)subtype & ~(uint32_t)CPU_SUBTYPE_MASK;
}

static uint32_t LC32ReadBigUInt32(const void *bytes) {
    uint32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return OSSwapBigToHostInt32(value);
}

static unsigned LC32CodeDirectoryRank(uint8_t hashType) {
    switch(hashType) {
        case LC32_CS_HASH_SHA1:
            return 1;
        case LC32_CS_HASH_SHA256_TRUNCATED:
            return 2;
        case LC32_CS_HASH_SHA256:
            return 3;
        case LC32_CS_HASH_SHA384:
            return 4;
        default:
            return 0;
    }
}

static size_t LC32CodeDirectoryHeaderSize(uint32_t version) {
    if(version >= 0x20600) {
        return offsetof(CS_CodeDirectory, linkageSize) + sizeof(uint32_t);
    }
    if(version >= 0x20500) {
        return offsetof(CS_CodeDirectory, linkageHashType);
    }
    if(version >= 0x20400) {
        return offsetof(CS_CodeDirectory, runtime);
    }
    if(version >= 0x20300) {
        return offsetof(CS_CodeDirectory, execSegBase);
    }
    if(version >= 0x20200) {
        return offsetof(CS_CodeDirectory, spare3);
    }
    if(version >= 0x20100) {
        return offsetof(CS_CodeDirectory, teamOffset);
    }
    return offsetof(CS_CodeDirectory, scatterOffset);
}

static void LC32FreeCodeSignatureMetadata(
        LC32CodeSignatureMetadata *metadata) {
    if(metadata == NULL) return;
    free(metadata->identifier);
    free(metadata->teamIdentifier);
    if(metadata->entitlements != NULL) {
        CFRelease(metadata->entitlements);
    }
    memset(metadata, 0, sizeof(*metadata));
}

static CFMutableDictionaryRef LC32CreateEntitlementsDictionary(void) {
    return CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
}

static bool LC32ReadCodeSignatureMetadata(
        int fd, const LC32MachOSlice *slice,
        LC32CodeSignatureMetadata *metadata,
        char *errorBuffer, size_t errorBufferCapacity) {
    memset(metadata, 0, sizeof(*metadata));
    metadata->entitlements = LC32CreateEntitlementsDictionary();
    if(metadata->entitlements == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not allocate an entitlements dictionary");
        return false;
    }

    if(!slice->hasCodeSignature) return true;
    metadata->hasCodeSignature = true;
    if(slice->codeSignatureOffset > slice->size ||
            slice->codeSignatureSize >
                slice->size - slice->codeSignatureOffset ||
            slice->codeSignatureSize < sizeof(CS_SuperBlob) ||
            slice->codeSignatureSize > LC32_MAX_CODE_SIGNATURE_SIZE) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "Mach-O code signature is too large or truncated");
        goto fail;
    }

    uint64_t signatureFileOffset = 0;
    if(!LC32AddUInt64(slice->offset, slice->codeSignatureOffset,
            &signatureFileOffset)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "Mach-O code-signature offset overflowed");
        goto fail;
    }
    uint8_t *signature = malloc(slice->codeSignatureSize);
    if(signature == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not allocate the code-signature buffer");
        goto fail;
    }
    if(!LC32ReadAt(fd, signature, slice->codeSignatureSize,
            signatureFileOffset)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not read Mach-O code signature: %s", strerror(errno));
        free(signature);
        goto fail;
    }

    const uint32_t magic = LC32ReadBigUInt32(
        signature + offsetof(CS_SuperBlob, magic));
    const uint32_t signatureLength = LC32ReadBigUInt32(
        signature + offsetof(CS_SuperBlob, length));
    const uint32_t blobCount = LC32ReadBigUInt32(
        signature + offsetof(CS_SuperBlob, count));
    uint64_t indexBytes = 0;
    if(magic != LC32_CS_MAGIC_EMBEDDED_SIGNATURE ||
            signatureLength < sizeof(CS_SuperBlob) ||
            signatureLength > slice->codeSignatureSize ||
            blobCount == 0 || blobCount > LC32_MAX_CODE_SIGNATURE_BLOBS ||
            !LC32AddUInt64(sizeof(CS_SuperBlob),
                (uint64_t)blobCount * sizeof(CS_BlobIndex), &indexBytes) ||
            indexBytes > signatureLength) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "Mach-O has a malformed embedded code signature");
        free(signature);
        goto fail;
    }

    uint32_t blobOffsets[LC32_MAX_CODE_SIGNATURE_BLOBS] = {0};
    uint32_t blobLengths[LC32_MAX_CODE_SIGNATURE_BLOBS] = {0};
    uint32_t codeDirectoryCount = 0;
    bool foundEntitlements = false;
    unsigned bestCodeDirectoryRank = 0;
    for(uint32_t index = 0; index < blobCount; index++) {
        const uint8_t *indexBytesPointer = signature +
            sizeof(CS_SuperBlob) +
                (size_t)index * sizeof(CS_BlobIndex);
        const uint32_t type = LC32ReadBigUInt32(
            indexBytesPointer + offsetof(CS_BlobIndex, type));
        const uint32_t blobOffset = LC32ReadBigUInt32(
            indexBytesPointer + offsetof(CS_BlobIndex, offset));
        if(blobOffset < indexBytes ||
                !LC32RangeFits(blobOffset,
                    sizeof(CS_GenericBlob), signatureLength)) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "code-signature blob %u has an invalid offset", index);
            free(signature);
            goto fail;
        }

        const uint8_t *blob = signature + blobOffset;
        const uint32_t blobMagic = LC32ReadBigUInt32(
            blob + offsetof(CS_GenericBlob, magic));
        const uint32_t blobLength = LC32ReadBigUInt32(
            blob + offsetof(CS_GenericBlob, length));
        if(blobLength < sizeof(CS_GenericBlob) ||
                !LC32RangeFits(blobOffset, blobLength, signatureLength)) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "code-signature blob %u has an invalid length", index);
            free(signature);
            goto fail;
        }
        for(uint32_t previous = 0; previous < index; previous++) {
            if(blobOffset < blobOffsets[previous] + blobLengths[previous] &&
                    blobOffsets[previous] < blobOffset + blobLength) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "code-signature blobs overlap");
                free(signature);
                goto fail;
            }
        }
        blobOffsets[index] = blobOffset;
        blobLengths[index] = blobLength;

        const bool isCodeDirectory = type == LC32_CS_SLOT_CODE_DIRECTORY ||
            (type >= LC32_CS_SLOT_ALTERNATE_DIRECTORIES &&
             type < LC32_CS_SLOT_ALTERNATE_DIRECTORY_LIMIT);
        if(isCodeDirectory) {
            const size_t baseCodeDirectorySize =
                offsetof(CS_CodeDirectory, spare2) + sizeof(uint32_t);
            if(blobMagic != LC32_CS_MAGIC_CODE_DIRECTORY ||
                    blobLength < baseCodeDirectorySize) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "code signature contains a malformed CodeDirectory");
                free(signature);
                goto fail;
            }
            const uint8_t hashType =
                blob[offsetof(CS_CodeDirectory, hashType)];
            const uint32_t version = LC32ReadBigUInt32(
                blob + offsetof(CS_CodeDirectory, version));
            if(version > 0x20600) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "CodeDirectory uses an unsupported version");
                free(signature);
                goto fail;
            }
            const size_t codeDirectoryHeaderSize =
                LC32CodeDirectoryHeaderSize(version);
            if(blobLength < codeDirectoryHeaderSize) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "code signature contains a truncated CodeDirectory");
                free(signature);
                goto fail;
            }
            const unsigned rank = LC32CodeDirectoryRank(hashType);
            if(rank == 0) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "CodeDirectory uses an unsupported hash type");
                free(signature);
                goto fail;
            }
            codeDirectoryCount++;

            const uint32_t identifierOffset = LC32ReadBigUInt32(
                blob + offsetof(CS_CodeDirectory, identOffset));
            if(identifierOffset != 0) {
                if(identifierOffset < codeDirectoryHeaderSize ||
                        identifierOffset >= blobLength) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectory identifier has an invalid offset");
                    free(signature);
                    goto fail;
                }
                const char *identifier =
                    (const char *)blob + identifierOffset;
                const size_t remaining = blobLength - identifierOffset;
                const char *terminator = memchr(identifier, '\0', remaining);
                const size_t identifierLength = terminator == NULL ? 0 :
                    (size_t)(terminator - identifier);
                if(terminator == NULL || identifierLength == 0 ||
                        identifierLength >= LC32_MAX_SIGNING_STRING_SIZE) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectory identifier is missing or too long");
                    free(signature);
                    goto fail;
                }
                if(metadata->identifier != NULL &&
                        strcmp(metadata->identifier, identifier) != 0) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectories use conflicting identifiers");
                    free(signature);
                    goto fail;
                }
                if(metadata->identifier == NULL ||
                        rank > bestCodeDirectoryRank) {
                    char *copy = malloc(identifierLength + 1);
                    if(copy == NULL) {
                        LC32SetError(errorBuffer, errorBufferCapacity,
                            "could not copy the CodeDirectory identifier");
                        free(signature);
                        goto fail;
                    }
                    memcpy(copy, identifier, identifierLength + 1);
                    free(metadata->identifier);
                    metadata->identifier = copy;
                    bestCodeDirectoryRank = rank;
                }
            }

            const uint32_t teamOffset = version < 0x20200 ? 0 :
                LC32ReadBigUInt32(
                    blob + offsetof(CS_CodeDirectory, teamOffset));
            if(teamOffset != 0) {
                if(teamOffset < codeDirectoryHeaderSize ||
                        teamOffset >= blobLength) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectory team identifier has an invalid offset");
                    free(signature);
                    goto fail;
                }
                const char *teamIdentifier =
                    (const char *)blob + teamOffset;
                const size_t remaining = blobLength - teamOffset;
                const char *terminator = memchr(
                    teamIdentifier, '\0', remaining);
                const size_t teamIdentifierLength =
                    terminator == NULL ? 0 :
                        (size_t)(terminator - teamIdentifier);
                if(terminator == NULL || teamIdentifierLength == 0 ||
                        teamIdentifierLength >=
                            LC32_MAX_SIGNING_STRING_SIZE) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectory team identifier is missing or too long");
                    free(signature);
                    goto fail;
                }
                if(metadata->teamIdentifier != NULL &&
                        strcmp(metadata->teamIdentifier,
                            teamIdentifier) != 0) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "CodeDirectories use conflicting team identifiers");
                    free(signature);
                    goto fail;
                }
                if(metadata->teamIdentifier == NULL) {
                    metadata->teamIdentifier = malloc(
                        teamIdentifierLength + 1);
                    if(metadata->teamIdentifier == NULL) {
                        LC32SetError(errorBuffer, errorBufferCapacity,
                            "could not copy the CodeDirectory team identifier");
                        free(signature);
                        goto fail;
                    }
                    memcpy(metadata->teamIdentifier, teamIdentifier,
                        teamIdentifierLength + 1);
                }
            }
        } else if(type == LC32_CS_SLOT_ENTITLEMENTS) {
            if(foundEntitlements ||
                    blobMagic != LC32_CS_MAGIC_EMBEDDED_ENTITLEMENTS ||
                    blobLength == sizeof(CS_GenericBlob)) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "code signature contains malformed XML entitlements");
                free(signature);
                goto fail;
            }
            foundEntitlements = true;
            const UInt8 *propertyListBytes =
                blob + sizeof(CS_GenericBlob);
            const CFIndex propertyListLength =
                (CFIndex)(blobLength - sizeof(CS_GenericBlob));
            CFDataRef propertyListData = CFDataCreate(kCFAllocatorDefault,
                propertyListBytes, propertyListLength);
            CFErrorRef propertyListError = NULL;
            CFPropertyListRef propertyList = propertyListData == NULL ? NULL :
                CFPropertyListCreateWithData(kCFAllocatorDefault,
                    propertyListData,
                    kCFPropertyListMutableContainersAndLeaves,
                    NULL, &propertyListError);
            if(propertyListData != NULL) CFRelease(propertyListData);
            if(propertyListError != NULL) CFRelease(propertyListError);
            if(propertyList == NULL ||
                    CFGetTypeID(propertyList) != CFDictionaryGetTypeID()) {
                if(propertyList != NULL) CFRelease(propertyList);
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "code-signature entitlements are not a valid plist dictionary");
                free(signature);
                goto fail;
            }
            CFMutableDictionaryRef copiedEntitlements =
                CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0,
                    (CFDictionaryRef)propertyList);
            CFRelease(propertyList);
            if(copiedEntitlements == NULL) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "could not copy code-signature entitlements");
                free(signature);
                goto fail;
            }
            CFRelease(metadata->entitlements);
            metadata->entitlements = copiedEntitlements;
        }
    }
    free(signature);
    if(codeDirectoryCount == 0) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "embedded signature contains no CodeDirectory");
        goto fail;
    }
    return true;

fail:
    LC32FreeCodeSignatureMetadata(metadata);
    return false;
}

static void LC32OverlayEntitlement(
        const void *key, const void *value, void *context) {
    CFDictionarySetValue((CFMutableDictionaryRef)context, key, value);
}

static void LC32OverlayEntitlements(
        CFMutableDictionaryRef destination,
        CFDictionaryRef source) {
    CFDictionaryApplyFunction(
        source, LC32OverlayEntitlement, destination);
}

static char *LC32CopyCFStringUTF8(
        CFTypeRef value, const char *description,
        char *errorBuffer, size_t errorBufferCapacity) {
    if(value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "%s is not a string", description);
        return NULL;
    }
    const CFIndex length = CFStringGetLength((CFStringRef)value);
    const CFIndex maximumBytes = CFStringGetMaximumSizeForEncoding(
        length, kCFStringEncodingUTF8);
    if(length == 0 || maximumBytes < 0 ||
            (uint64_t)maximumBytes + 1 > LC32_MAX_SIGNING_STRING_SIZE) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "%s is empty or too long", description);
        return NULL;
    }
    char *string = malloc((size_t)maximumBytes + 1);
    if(string == NULL || !CFStringGetCString((CFStringRef)value,
            string, maximumBytes + 1, kCFStringEncodingUTF8)) {
        free(string);
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not encode %s as UTF-8", description);
        return NULL;
    }
    return string;
}

static bool LC32CreateSigningMetadata(
        int targetFD, const LC32MachOImage *targetImage,
        int shimFD, const LC32MachOSlice *shimSlice,
        const char *bundleIdentifier,
        CFMutableDictionaryRef *entitlementsOut,
        char **identifierOut, char **teamIdentifierOut,
        char *errorBuffer, size_t errorBufferCapacity) {
    *entitlementsOut = NULL;
    *identifierOut = NULL;
    *teamIdentifierOut = NULL;

    LC32CodeSignatureMetadata shimMetadata = {0};
    LC32CodeSignatureMetadata targetMetadata = {0};
    CFMutableDictionaryRef firstTargetEntitlements = NULL;
    CFMutableDictionaryRef mergedEntitlements = NULL;
    CFStringRef bundleIdentifierString = NULL;
    char *targetIdentifier = NULL;
    char *teamIdentifier = NULL;
    char *finalIdentifier = NULL;
    bool success = false;

    const size_t bundleIdentifierLength = strnlen(
        bundleIdentifier, LC32_MAX_SIGNING_STRING_SIZE);
    if(bundleIdentifierLength == 0 ||
            bundleIdentifierLength == LC32_MAX_SIGNING_STRING_SIZE) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "bundle identifier is empty or too long");
        goto cleanup;
    }
    bundleIdentifierString = CFStringCreateWithCString(kCFAllocatorDefault,
        bundleIdentifier, kCFStringEncodingUTF8);
    if(bundleIdentifierString == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "bundle identifier is not valid UTF-8");
        goto cleanup;
    }

    if(!LC32ReadCodeSignatureMetadata(shimFD, shimSlice,
            &shimMetadata, errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    if(!shimMetadata.hasCodeSignature) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "arm64 shim has no embedded code signature");
        goto cleanup;
    }
    mergedEntitlements = CFDictionaryCreateMutableCopy(
        kCFAllocatorDefault, 0, shimMetadata.entitlements);
    if(mergedEntitlements == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not copy the shim entitlements");
        goto cleanup;
    }

    for(uint32_t index = 0; index < targetImage->count; index++) {
        LC32FreeCodeSignatureMetadata(&targetMetadata);
        if(!LC32ReadCodeSignatureMetadata(targetFD,
                &targetImage->slices[index], &targetMetadata,
                errorBuffer, errorBufferCapacity)) {
            goto cleanup;
        }
        if(firstTargetEntitlements == NULL) {
            firstTargetEntitlements = CFDictionaryCreateMutableCopy(
                kCFAllocatorDefault, 0, targetMetadata.entitlements);
            if(firstTargetEntitlements == NULL) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "could not copy the ARM32 entitlements");
                goto cleanup;
            }
        } else if(!CFEqual(
                firstTargetEntitlements, targetMetadata.entitlements)) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "ARM32 slices use conflicting entitlements");
            goto cleanup;
        }

        if(targetMetadata.identifier != NULL) {
            if(targetIdentifier != NULL && strcmp(targetIdentifier,
                    targetMetadata.identifier) != 0) {
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "ARM32 slices use conflicting identifiers");
                goto cleanup;
            }
            if(targetIdentifier == NULL) {
                targetIdentifier = strdup(targetMetadata.identifier);
                if(targetIdentifier == NULL) {
                    LC32SetError(errorBuffer, errorBufferCapacity,
                        "could not copy the ARM32 identifier");
                    goto cleanup;
                }
            }
        }
    }
    if(firstTargetEntitlements != NULL) {
        LC32OverlayEntitlements(
            mergedEntitlements, firstTargetEntitlements);
    }

    CFTypeRef teamValue = CFDictionaryGetValue(
        mergedEntitlements, LC32TeamIdentifierEntitlement);
    if(teamValue == NULL) {
        CFDictionarySetValue(mergedEntitlements,
            LC32TeamIdentifierEntitlement,
            CFSTR("T8ALTGMVXN"));
        teamValue = CFDictionaryGetValue(
            mergedEntitlements, LC32TeamIdentifierEntitlement);
    }
    teamIdentifier = LC32CopyCFStringUTF8(teamValue,
        "com.apple.developer.team-identifier entitlement",
        errorBuffer, errorBufferCapacity);
    if(teamIdentifier == NULL) goto cleanup;

    CFDictionarySetValue(mergedEntitlements,
        LC32ContainerRequiredEntitlement, bundleIdentifierString);

    if(targetIdentifier != NULL) {
        finalIdentifier = strdup(targetIdentifier);
        if(finalIdentifier == NULL) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "could not copy the signing identifier");
            goto cleanup;
        }
    } else {
        const size_t teamLength = strlen(teamIdentifier);
        if(teamLength > SIZE_MAX - bundleIdentifierLength - 2 ||
                teamLength + bundleIdentifierLength + 2 >
                    LC32_MAX_SIGNING_STRING_SIZE) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "fallback signing identifier is too long");
            goto cleanup;
        }
        finalIdentifier = malloc(
            teamLength + bundleIdentifierLength + 2);
        if(finalIdentifier == NULL) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "could not allocate the fallback signing identifier");
            goto cleanup;
        }
        memcpy(finalIdentifier, teamIdentifier, teamLength);
        finalIdentifier[teamLength] = '.';
        memcpy(finalIdentifier + teamLength + 1,
            bundleIdentifier, bundleIdentifierLength + 1);
    }

    *entitlementsOut = mergedEntitlements;
    mergedEntitlements = NULL;
    *identifierOut = finalIdentifier;
    finalIdentifier = NULL;
    *teamIdentifierOut = teamIdentifier;
    teamIdentifier = NULL;
    success = true;

cleanup:
    free(finalIdentifier);
    free(teamIdentifier);
    free(targetIdentifier);
    if(bundleIdentifierString != NULL) CFRelease(bundleIdentifierString);
    if(mergedEntitlements != NULL) CFRelease(mergedEntitlements);
    if(firstTargetEntitlements != NULL) {
        CFRelease(firstTargetEntitlements);
    }
    LC32FreeCodeSignatureMetadata(&targetMetadata);
    LC32FreeCodeSignatureMetadata(&shimMetadata);
    return success;
}

static char *LC32CreatePathByAppendingComponent(
        const char *directoryPath, const char *component) {
    const size_t directoryLength = strlen(directoryPath);
    const size_t componentLength = strlen(component);
    if(directoryLength > SIZE_MAX - componentLength - 2) {
        errno = ENAMETOOLONG;
        return NULL;
    }

    char *path = malloc(directoryLength + componentLength + 2);
    if(path == NULL) return NULL;
    memcpy(path, directoryPath, directoryLength);
    path[directoryLength] = '/';
    memcpy(path + directoryLength + 1,
        component, componentLength + 1);
    return path;
}

static bool LC32PatchShimBuildVersion(
        uint8_t *shimBytes, size_t shimSize,
        const LC32MachOSlice *shimSlice, uint32_t requestedSDK,
        char *errorBuffer, size_t errorBufferCapacity) {
    if(shimBytes == NULL || shimSlice == NULL ||
            shimSlice->isByteSwapped || !shimSlice->hasBuildVersion ||
            shimSlice->buildVersionCommandOffset > shimSize ||
            sizeof(struct build_version_command) >
                shimSize - shimSlice->buildVersionCommandOffset) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "arm64 shim has no usable LC_BUILD_VERSION");
        return false;
    }

    struct build_version_command command = {0};
    memcpy(&command,
        shimBytes + shimSlice->buildVersionCommandOffset,
        sizeof(command));
    if(command.cmd != LC_BUILD_VERSION ||
            command.cmdsize < sizeof(command) ||
            command.platform != shimSlice->buildVersionPlatform ||
            command.minos != shimSlice->buildVersionMinOS ||
            command.sdk != shimSlice->buildVersionSDK) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "arm64 shim LC_BUILD_VERSION changed while it was copied");
        return false;
    }

    command.minos = LC32_IOS_11_VERSION;
    command.sdk = requestedSDK < LC32_IOS_11_VERSION ?
        LC32_IOS_11_VERSION : requestedSDK;
    memcpy(shimBytes + shimSlice->buildVersionCommandOffset,
        &command, sizeof(command));
    return true;
}

static bool LC32CreateSignedShimBytes(
        const char *stagingDirectoryPath, int stagingDirectoryFD,
        int shimFD, const LC32MachOSlice *shimSlice,
        CFDictionaryRef entitlements,
        const char *identifier, const char *teamIdentifier,
        uint32_t requestedSDK,
        uint8_t **signedBytesOut, size_t *signedSizeOut,
        char *errorBuffer, size_t errorBufferCapacity) {
    *signedBytesOut = NULL;
    *signedSizeOut = 0;

    if(shimSlice->is32Bit || shimSlice->size == 0 ||
            shimSlice->size > LC32_MAX_SIGNED_SHIM_SIZE ||
            shimSlice->size > SIZE_MAX) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "arm64 shim has an unsupported size or header width");
        return false;
    }

    bool success = false;
    bool signingEntryIdentityIsKnown = false;
    int temporaryFD = -1;
    char *signingPath = NULL;
    uint8_t *shimBytes = NULL;
    uint8_t *signedBytes = NULL;
    CFDataRef entitlementsData = NULL;
    LC32MachOImage signedImage = {0};
    LC32CodeSignatureMetadata signedMetadata = {0};
    struct stat signingEntryStat = {0};

    CFErrorRef propertyListError = NULL;
    entitlementsData = CFPropertyListCreateData(
        kCFAllocatorDefault, entitlements,
        kCFPropertyListXMLFormat_v1_0, 0, &propertyListError);
    if(propertyListError != NULL) CFRelease(propertyListError);
    if(entitlementsData == NULL || CFDataGetLength(entitlementsData) <= 0) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not serialize the merged entitlements");
        goto cleanup;
    }

    shimBytes = malloc((size_t)shimSlice->size);
    if(shimBytes == NULL || !LC32ReadAt(shimFD, shimBytes,
            (size_t)shimSlice->size, shimSlice->offset)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not copy the arm64 shim: %s",
            shimBytes == NULL ? "out of memory" : strerror(errno));
        goto cleanup;
    }
    if(!LC32PatchShimBuildVersion(
            shimBytes, (size_t)shimSlice->size,
            shimSlice, requestedSDK,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }

    signingPath = LC32CreatePathByAppendingComponent(
        stagingDirectoryPath, LC32_SIGNING_STAGING_NAME);
    if(signingPath == NULL) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create an arm64 signing path in",
            stagingDirectoryPath, errno);
        goto cleanup;
    }
    temporaryFD = openat(stagingDirectoryFD,
        LC32_SIGNING_STAGING_NAME,
        O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0700);
    if(temporaryFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create", signingPath, errno);
        goto cleanup;
    }
    if(fstat(temporaryFD, &signingEntryStat) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not stat", signingPath, errno);
        goto cleanup;
    }
    signingEntryIdentityIsKnown = true;
    if(!LC32WriteAt(temporaryFD, shimBytes,
                (size_t)shimSlice->size, 0) ||
            fsync(temporaryFD) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not stage the arm64 shim at", signingPath, errno);
        goto cleanup;
    }
    free(shimBytes);
    shimBytes = NULL;
    if(close(temporaryFD) != 0) {
        const int closeError = errno;
        temporaryFD = -1;
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not close", signingPath, closeError);
        goto cleanup;
    }
    temporaryFD = -1;

    /* Security.framework replaces the staged file atomically. Until the new
     * inode is reopened and verified, cleanup must not assume ownership of
     * whatever currently resolves at this pathname. */
    signingEntryIdentityIsKnown = false;
    if(!LC32AdHocSignMachOAtPath(
        signingPath,
        identifier, teamIdentifier,
        CFDataGetBytePtr(entitlementsData),
        (size_t)CFDataGetLength(entitlementsData),
        errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }

    temporaryFD = openat(stagingDirectoryFD,
        LC32_SIGNING_STAGING_NAME,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(temporaryFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not reopen the signed arm64 shim at",
            signingPath, errno);
        goto cleanup;
    }
    struct stat signedStatus = {0};
    struct stat signedPathStatus = {0};
    if(fstat(temporaryFD, &signedStatus) != 0 ||
            fstatat(stagingDirectoryFD, LC32_SIGNING_STAGING_NAME,
                &signedPathStatus, AT_SYMLINK_NOFOLLOW) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not validate the signed arm64 shim at",
            signingPath, errno);
        goto cleanup;
    }
    if(!S_ISREG(signedStatus.st_mode) ||
            !S_ISREG(signedPathStatus.st_mode) ||
            signedStatus.st_dev != signedPathStatus.st_dev ||
            signedStatus.st_ino != signedPathStatus.st_ino ||
            signedStatus.st_size <= 0 ||
            (uint64_t)signedStatus.st_size > LC32_MAX_SIGNED_SHIM_SIZE) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "signed arm64 shim is not a supported regular file");
        goto cleanup;
    }
    signingEntryStat = signedStatus;
    signingEntryIdentityIsKnown = true;

    char parserError[256] = {0};
    if(!LC32MachOImageParseFD(temporaryFD, &signedImage,
            parserError, sizeof(parserError)) ||
            signedImage.isFat || signedImage.count != 1) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "Security.framework produced a malformed arm64 shim");
        goto cleanup;
    }
    const LC32MachOSlice *signedSlice = &signedImage.slices[0];
    if(signedSlice->offset != 0 ||
            signedSlice->size != (uint64_t)signedStatus.st_size ||
            signedSlice->cpuType != shimSlice->cpuType ||
            signedSlice->cpuSubtype != shimSlice->cpuSubtype ||
            signedSlice->fileType != shimSlice->fileType ||
            signedSlice->is32Bit || signedSlice->isByteSwapped ||
            signedSlice->encrypted || !signedSlice->hasCodeSignature ||
            !signedSlice->hasBuildVersion ||
            signedSlice->buildVersionPlatform !=
                shimSlice->buildVersionPlatform ||
            signedSlice->buildVersionMinOS != LC32_IOS_11_VERSION ||
            signedSlice->buildVersionSDK != requestedSDK) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "signed arm64 shim failed architecture verification");
        goto cleanup;
    }
    if(!LC32ReadCodeSignatureMetadata(temporaryFD, signedSlice,
            &signedMetadata, errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    if(!signedMetadata.hasCodeSignature ||
            signedMetadata.identifier == NULL ||
            signedMetadata.teamIdentifier == NULL ||
            strcmp(signedMetadata.identifier, identifier) != 0 ||
            strcmp(signedMetadata.teamIdentifier, teamIdentifier) != 0 ||
            !CFEqual(signedMetadata.entitlements, entitlements)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "signed arm64 shim does not contain the requested metadata");
        goto cleanup;
    }

    const size_t signedSize = (size_t)signedStatus.st_size;
    signedBytes = malloc(signedSize);
    if(signedBytes == NULL ||
            !LC32ReadAt(temporaryFD, signedBytes, signedSize, 0)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not read the signed arm64 shim: %s",
            signedBytes == NULL ? "out of memory" : strerror(errno));
        goto cleanup;
    }

    *signedBytesOut = signedBytes;
    signedBytes = NULL;
    *signedSizeOut = signedSize;
    success = true;

cleanup:
    if(stagingDirectoryFD >= 0 && signingEntryIdentityIsKnown) {
        struct stat cleanupFDStat = {0};
        struct stat cleanupPathStat = {0};
        const bool descriptorMatches = temporaryFD < 0 ||
            (fstat(temporaryFD, &cleanupFDStat) == 0 &&
             cleanupFDStat.st_dev == signingEntryStat.st_dev &&
             cleanupFDStat.st_ino == signingEntryStat.st_ino);
        if(descriptorMatches &&
                fstatat(stagingDirectoryFD,
                    LC32_SIGNING_STAGING_NAME,
                    &cleanupPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISREG(cleanupPathStat.st_mode) &&
                cleanupPathStat.st_dev == signingEntryStat.st_dev &&
                cleanupPathStat.st_ino == signingEntryStat.st_ino) {
            (void)unlinkat(stagingDirectoryFD,
                LC32_SIGNING_STAGING_NAME, 0);
        }
    }
    if(temporaryFD >= 0) close(temporaryFD);
    LC32FreeCodeSignatureMetadata(&signedMetadata);
    LC32MachOImageFree(&signedImage);
    if(entitlementsData != NULL) CFRelease(entitlementsData);
    free(signedBytes);
    free(shimBytes);
    free(signingPath);
    return success;
}

static bool LC32CreateMachOImageFromFD(
        int fd, const char *description, LC32MachOImage *image,
        char *errorBuffer, size_t errorBufferCapacity) {
    char parserError[256] = {0};
    if(!LC32MachOImageParseFD(
            fd, image, parserError, sizeof(parserError))) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not parse the %s Mach-O", description);
        return false;
    }
    return true;
}

static bool LC32CopyOutputSliceToFD(
        const LC32OutputSlice *source, int destinationFD,
        uint64_t destinationOffset, void *buffer, size_t bufferSize) {
    uint64_t completed = 0;
    while(completed < source->size) {
        const uint64_t remaining = source->size - completed;
        const size_t amount = remaining < bufferSize ?
            (size_t)remaining : bufferSize;
        const void *bytes = source->sourceBytes == NULL ? buffer :
            source->sourceBytes + completed;
        if(source->sourceBytes == NULL &&
                !LC32ReadAt(source->sourceFD, buffer, amount,
                    source->sourceOffset + completed)) {
            return false;
        }
        if(!LC32WriteAt(destinationFD, bytes, amount,
                destinationOffset + completed)) {
            return false;
        }
        completed += amount;
    }
    return true;
}

static bool LC32OutputSliceMatchesFD(
        const LC32OutputSlice *source,
        int fd, uint64_t fdOffset,
        void *sourceBuffer, void *fileBuffer, size_t bufferSize) {
    uint64_t completed = 0;
    while(completed < source->size) {
        const uint64_t remaining = source->size - completed;
        const size_t amount = remaining < bufferSize ?
            (size_t)remaining : bufferSize;
        const void *sourceBytes = source->sourceBytes == NULL ?
            sourceBuffer : source->sourceBytes + completed;
        if((source->sourceBytes == NULL &&
                !LC32ReadAt(source->sourceFD, sourceBuffer, amount,
                    source->sourceOffset + completed)) ||
                !LC32ReadAt(fd, fileBuffer, amount, fdOffset + completed) ||
                memcmp(sourceBytes, fileBuffer, amount) != 0) {
            return false;
        }
        completed += amount;
    }
    return true;
}

static void LC32ClearTemporaryRestrictiveFlags(
        int temporaryFD, int stagingDirectoryFD,
        const char *stagingName) {
    int cleanupFD = temporaryFD;
    bool closeCleanupFD = false;
    if(cleanupFD < 0 && stagingDirectoryFD >= 0 && stagingName != NULL) {
        cleanupFD = openat(stagingDirectoryFD, stagingName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        closeCleanupFD = cleanupFD >= 0;
    }

    if(cleanupFD >= 0) {
        struct stat status = {0};
        if(fstat(cleanupFD, &status) == 0) {
            const uint32_t restrictiveFlags =
                UF_IMMUTABLE | UF_APPEND |
                SF_IMMUTABLE | SF_APPEND |
                SF_RESTRICTED | SF_NOUNLINK;
            const uint32_t remainingFlags =
                (uint32_t)status.st_flags & ~restrictiveFlags;
            if(remainingFlags != (uint32_t)status.st_flags) {
                (void)fchflags(cleanupFD, remainingFlags);
            }
        }
    }

    if(closeCleanupFD) close(cleanupFD);
}

static int LC32OpenParentDirectory(const char *path) {
    char *parentPath = strdup(path);
    if(parentPath == NULL) return -1;

    char *lastSlash = strrchr(parentPath, '/');
    if(lastSlash == NULL) {
        free(parentPath);
        return open(".", O_RDONLY | O_CLOEXEC | O_DIRECTORY);
    }
    if(lastSlash == parentPath) {
        lastSlash[1] = '\0';
    } else {
        *lastSlash = '\0';
    }

    const int directoryFD = open(parentPath,
        O_RDONLY | O_CLOEXEC | O_DIRECTORY);
    free(parentPath);
    return directoryFD;
}

static bool LC32SameFileState(
        const struct stat *left, const struct stat *right) {
    return left->st_dev == right->st_dev &&
        left->st_ino == right->st_ino &&
        left->st_size == right->st_size &&
        left->st_mode == right->st_mode &&
        left->st_uid == right->st_uid &&
        left->st_gid == right->st_gid &&
        left->st_flags == right->st_flags &&
        left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
        left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
        left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
        left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static bool LC32SameFileStateAfterRename(
        const struct stat *left, const struct stat *right) {
    /* renameatx_np may advance ctime even though file contents and metadata
     * are unchanged, so compare every stable field used by the injector. */
    return left->st_dev == right->st_dev &&
        left->st_ino == right->st_ino &&
        left->st_size == right->st_size &&
        left->st_mode == right->st_mode &&
        left->st_uid == right->st_uid &&
        left->st_gid == right->st_gid &&
        left->st_flags == right->st_flags &&
        left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
        left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec;
}

static bool LC32CreatePrivateStagingDirectory(
        const char *targetPath, int parentDirectoryFD,
        char **pathOut, int *directoryFDOut,
        struct stat *directoryStatOut,
        char *errorBuffer, size_t errorBufferCapacity) {
    *pathOut = NULL;
    *directoryFDOut = -1;
    memset(directoryStatOut, 0, sizeof(*directoryStatOut));

    static const char suffixPrefix[] = ".liveexec32.";
    static const char hexadecimalDigits[] = "0123456789abcdef";
    enum {
        LC32_STAGING_RANDOM_BYTE_COUNT = 16,
        LC32_STAGING_RANDOM_CHARACTER_COUNT =
            LC32_STAGING_RANDOM_BYTE_COUNT * 2,
        LC32_STAGING_CREATION_ATTEMPTS = 128,
    };

    bool directoryIdentityIsKnown = false;
    int directoryFD = -1;
    const size_t targetPathLength = strlen(targetPath);
    const size_t suffixPrefixLength = sizeof(suffixPrefix) - 1;
    const size_t suffixLength = suffixPrefixLength +
        LC32_STAGING_RANDOM_CHARACTER_COUNT;
    if(targetPathLength >= PATH_MAX ||
            suffixLength >= PATH_MAX - targetPathLength ||
            targetPathLength > SIZE_MAX - suffixLength - 1) {
        errno = ENAMETOOLONG;
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create a staging path beside", targetPath, errno);
        return false;
    }

    char *path = malloc(targetPathLength + suffixLength + 1);
    if(path == NULL) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create a staging path beside", targetPath, errno);
        goto fail;
    }
    memcpy(path, targetPath, targetPathLength);
    memcpy(path + targetPathLength,
        suffixPrefix, suffixPrefixLength);
    char *randomCharacters = path + targetPathLength +
        suffixPrefixLength;
    randomCharacters[LC32_STAGING_RANDOM_CHARACTER_COUNT] = '\0';

    const char *name = strrchr(path, '/');
    name = name == NULL ? path : name + 1;

    bool directoryCreated = false;
    for(unsigned int attempt = 0;
            attempt < LC32_STAGING_CREATION_ATTEMPTS; attempt++) {
        uint8_t randomBytes[LC32_STAGING_RANDOM_BYTE_COUNT];
        arc4random_buf(randomBytes, sizeof(randomBytes));
        for(size_t index = 0; index < sizeof(randomBytes); index++) {
            randomCharacters[index * 2] =
                hexadecimalDigits[randomBytes[index] >> 4];
            randomCharacters[index * 2 + 1] =
                hexadecimalDigits[randomBytes[index] & 0x0fu];
        }
        if(mkdirat(parentDirectoryFD, name, 0700) == 0) {
            directoryCreated = true;
            break;
        }
        if(errno != EEXIST) break;
    }
    if(!directoryCreated) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create private staging directory", path, errno);
        goto fail;
    }

    if(fstatat(parentDirectoryFD, name, directoryStatOut,
            AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISDIR(directoryStatOut->st_mode) ||
            (directoryStatOut->st_mode & 0777) != 0700) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not capture the private staging directory identity");
        goto fail;
    }
    directoryIdentityIsKnown = true;

    directoryFD = openat(parentDirectoryFD, name,
        O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    struct stat openedDirectoryStat = {0};
    struct stat directoryPathStat = {0};
    if(directoryFD < 0 ||
            fstat(directoryFD, &openedDirectoryStat) != 0 ||
            fstatat(parentDirectoryFD, name, &directoryPathStat,
                AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISDIR(openedDirectoryStat.st_mode) ||
            !S_ISDIR(directoryPathStat.st_mode) ||
            !LC32SameFileState(directoryStatOut, &openedDirectoryStat) ||
            !LC32SameFileState(directoryStatOut, &directoryPathStat)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "private staging directory failed verification");
        goto fail;
    }

    struct stat absolutePathStat = {0};
    if(lstat(path, &absolutePathStat) != 0 ||
            !S_ISDIR(absolutePathStat.st_mode) ||
            !LC32SameFileState(directoryStatOut, &absolutePathStat)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "private staging directory path failed verification");
        goto fail;
    }

    *pathOut = path;
    *directoryFDOut = directoryFD;
    return true;

fail:
    if(directoryIdentityIsKnown) {
        struct stat cleanupPathStat = {0};
        if(fstatat(parentDirectoryFD, name, &cleanupPathStat,
                    AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISDIR(cleanupPathStat.st_mode) &&
                directoryStatOut->st_dev == cleanupPathStat.st_dev &&
                directoryStatOut->st_ino == cleanupPathStat.st_ino) {
            (void)unlinkat(parentDirectoryFD, name, AT_REMOVEDIR);
        }
    }
    if(directoryFD >= 0) close(directoryFD);
    free(path);
    return false;
}

LC32MachOInjectionResult LC32InjectArm64ExecutableSlice(
        const char *targetPath,
        const char *shimPath,
        const char *bundleIdentifier,
        char *errorBuffer,
        size_t errorBufferCapacity) {
    if(errorBuffer != NULL && errorBufferCapacity != 0) errorBuffer[0] = '\0';
    if(targetPath == NULL || targetPath[0] == '\0' ||
            shimPath == NULL || shimPath[0] == '\0' ||
            bundleIdentifier == NULL || bundleIdentifier[0] == '\0') {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "injector received an empty target, shim, or bundle identifier");
        return LC32MachOInjectionFailed;
    }

    LC32MachOInjectionResult result = LC32MachOInjectionFailed;
    int targetFD = -1;
    int shimFD = -1;
    int temporaryFD = -1;
    int parentDirectoryFD = -1;
    int stagingDirectoryFD = -1;
    char *stagingDirectoryPath = NULL;
    char *replacementPath = NULL;
    void *copyBuffer = NULL;
    void *comparisonBuffer = NULL;
    uint8_t *outputHeader = NULL;
    uint8_t *signedShimBytes = NULL;
    size_t signedShimSize = 0;
    LC32MachOImage targetImage = {0};
    LC32MachOImage shimImage = {0};
    LC32MachOImage verificationImage = {0};
    LC32OutputSlice outputSlices[LC32_MAX_MACH_O_SLICES + 1] = {0};
    CFMutableDictionaryRef mergedEntitlements = NULL;
    char *signingIdentifier = NULL;
    char *teamIdentifier = NULL;
    bool preserveStagingDirectory = false;
    bool stagingContainsOriginalTarget = false;
    bool replacementIdentityIsKnown = false;
    struct stat targetStat = {0};
    struct stat shimStat = {0};
    struct stat stagingDirectoryStat = {0};
    struct stat replacementStat = {0};

    const char *targetName = strrchr(targetPath, '/');
    targetName = targetName == NULL ? targetPath : targetName + 1;
    if(targetName[0] == '\0') {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "target executable path ends with a slash");
        goto cleanup;
    }

    /*
     * Do not flock these files: installd's sandbox rejects flock(2) with
     * EPERM. The tweak serializes injector calls with its process mutex, and
     * this function revalidates both descriptors against their paths before
     * committing the atomic rename.
     */
    parentDirectoryFD = LC32OpenParentDirectory(targetPath);
    if(parentDirectoryFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not open the parent directory of", targetPath, errno);
        goto cleanup;
    }
    targetFD = openat(parentDirectoryFD, targetName,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(targetFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not open", targetPath, errno);
        goto cleanup;
    }
    struct stat initialTargetPathStat = {0};
    if(fstat(targetFD, &targetStat) != 0 ||
            fstatat(parentDirectoryFD, targetName,
                &initialTargetPathStat, AT_SYMLINK_NOFOLLOW) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not stat", targetPath, errno);
        goto cleanup;
    }
    if(!S_ISREG(targetStat.st_mode) ||
            !S_ISREG(initialTargetPathStat.st_mode) ||
            !LC32SameFileState(&targetStat, &initialTargetPathStat) ||
            targetStat.st_size <= 0) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "target executable is not a nonempty regular file");
        goto cleanup;
    }

    if(!LC32CreateMachOImageFromFD(targetFD,
            "target executable", &targetImage,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    const uint32_t targetSliceCount = targetImage.count;
    if(targetSliceCount >= LC32_MAX_MACH_O_SLICES) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "target executable has too many slices to add arm64");
        goto cleanup;
    }

    bool hasARM32Executable = false;
    bool targetSDKIsSet = false;
    uint32_t targetSDK = LC32_IOS_11_VERSION;
    for(uint32_t index = 0; index < targetSliceCount; index++) {
        const LC32MachOSlice *slice = &targetImage.slices[index];
        if(slice->cpuType == CPU_TYPE_ARM64) {
            result = LC32MachOInjectionNotApplicable;
            goto cleanup;
        }
        if(slice->cpuType != CPU_TYPE_ARM || slice->fileType != MH_EXECUTE) {
            result = LC32MachOInjectionNotApplicable;
            goto cleanup;
        }
        if(slice->isByteSwapped) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "byte-swapped ARM executable slices are not supported");
            goto cleanup;
        }
        if(slice->encrypted) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "ARM executable slice is encrypted; decrypt it before "
                "installing with LiveExec32");
            goto cleanup;
        }
        const uint32_t sliceSDK =
            slice->hasVersionMinIPhoneOS &&
                slice->versionMinIPhoneOSSDK >= LC32_IOS_11_VERSION ?
                    slice->versionMinIPhoneOSSDK : LC32_IOS_11_VERSION;
        if(targetSDKIsSet && targetSDK != sliceSDK) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "ARM32 slices use conflicting iOS SDK versions");
            goto cleanup;
        }
        targetSDK = sliceSDK;
        targetSDKIsSet = true;
        hasARM32Executable = true;
    }
    if(!hasARM32Executable) {
        result = LC32MachOInjectionNotApplicable;
        goto cleanup;
    }

    shimFD = open(shimPath, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(shimFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not open", shimPath, errno);
        goto cleanup;
    }
    if(fstat(shimFD, &shimStat) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not stat", shimPath, errno);
        goto cleanup;
    }
    if(!S_ISREG(shimStat.st_mode) || shimStat.st_size <= 0) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "shim executable is not a nonempty regular file");
        goto cleanup;
    }

    if(!LC32CreateMachOImageFromFD(shimFD,
            "shim executable", &shimImage,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }

    const LC32MachOSlice *shimSlice = NULL;
    for(uint32_t index = 0; index < shimImage.count; index++) {
        const LC32MachOSlice *candidate = &shimImage.slices[index];
        if(candidate->fileType != MH_EXECUTE) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "shim contains a non-executable Mach-O slice");
            goto cleanup;
        }
        if(candidate->isByteSwapped) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "shim contains a byte-swapped Mach-O slice");
            goto cleanup;
        }
        if(shimSlice == NULL &&
                candidate->cpuType == CPU_TYPE_ARM64 &&
                LC32BaseCPUSubtype(candidate->cpuSubtype) ==
                    CPU_SUBTYPE_ARM64_ALL &&
                !candidate->encrypted) {
            shimSlice = candidate;
        }
    }
    if(shimSlice == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "shim has no generic arm64 executable slice");
        goto cleanup;
    }
    if(!shimSlice->hasBuildVersion) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "arm64 shim has no LC_BUILD_VERSION");
        goto cleanup;
    }

    if(!LC32CreateSigningMetadata(
            targetFD, &targetImage, shimFD, shimSlice, bundleIdentifier,
            &mergedEntitlements, &signingIdentifier, &teamIdentifier,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    if(!LC32CreatePrivateStagingDirectory(
            targetPath, parentDirectoryFD,
            &stagingDirectoryPath, &stagingDirectoryFD,
            &stagingDirectoryStat,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    replacementPath = LC32CreatePathByAppendingComponent(
        stagingDirectoryPath, LC32_REPLACEMENT_STAGING_NAME);
    if(replacementPath == NULL) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create a replacement path in",
            stagingDirectoryPath, errno);
        goto cleanup;
    }
    if(!LC32CreateSignedShimBytes(
        stagingDirectoryPath, stagingDirectoryFD,
        shimFD, shimSlice, mergedEntitlements,
        signingIdentifier, teamIdentifier,
        targetSDK,
        &signedShimBytes, &signedShimSize,
        errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }

    const uint32_t outputCount = targetSliceCount + 1;
    for(uint32_t index = 0; index < targetSliceCount; index++) {
        const LC32MachOSlice *source = &targetImage.slices[index];
        outputSlices[index] = (LC32OutputSlice){
            .sourceFD = targetFD,
            .sourceOffset = source->offset,
            .size = source->size,
            .cpuType = source->cpuType,
            .cpuSubtype = source->cpuSubtype,
            .fileType = source->fileType,
            .sourceAlignExponent = source->alignExponent,
            .is64Bit = !source->is32Bit,
            .encrypted = source->encrypted,
        };
    }
    outputSlices[targetSliceCount] = (LC32OutputSlice){
        .sourceFD = -1,
        .sourceBytes = signedShimBytes,
        .size = signedShimSize,
        .cpuType = shimSlice->cpuType,
        .cpuSubtype = shimSlice->cpuSubtype,
        .fileType = shimSlice->fileType,
        .sourceAlignExponent = shimSlice->alignExponent,
        .is64Bit = !shimSlice->is32Bit,
        .encrypted = false,
    };

    const size_t outputHeaderSize = sizeof(struct fat_header) +
        (size_t)outputCount * sizeof(struct fat_arch);
    uint64_t outputSize = outputHeaderSize;
    for(uint32_t index = 0; index < outputCount; index++) {
        LC32OutputSlice *output = &outputSlices[index];
        output->outputAlignExponent = output->sourceAlignExponent <
            LC32_OUTPUT_MIN_ALIGN_EXPONENT ?
                LC32_OUTPUT_MIN_ALIGN_EXPONENT :
                output->sourceAlignExponent;
        if(output->outputAlignExponent > 30 ||
                !LC32AlignUInt64(outputSize,
                    UINT64_C(1) << output->outputAlignExponent,
                    &outputSize) ||
                outputSize > UINT32_MAX ||
                output->size > UINT32_MAX) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "output architecture offsets exceed FAT32 limits");
            goto cleanup;
        }
        output->outputOffset = (uint32_t)outputSize;
        if(!LC32AddUInt64(outputSize, output->size, &outputSize) ||
                outputSize > UINT32_MAX) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "output Mach-O exceeds FAT32 size limits");
            goto cleanup;
        }
    }

    outputHeader = calloc(1, outputHeaderSize);
    if(outputHeader == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not allocate the FAT header");
        goto cleanup;
    }
    struct fat_header *fatHeader = (struct fat_header *)outputHeader;
    fatHeader->magic = OSSwapHostToBigInt32(FAT_MAGIC);
    fatHeader->nfat_arch = OSSwapHostToBigInt32(outputCount);
    struct fat_arch *fatArchitectures =
        (struct fat_arch *)(outputHeader + sizeof(*fatHeader));
    /* Keep the physical target-slice layout unchanged, but advertise the
     * arm64 shim first so MobileInstallation examines it first. */
    for(uint32_t descriptorIndex = 0;
            descriptorIndex < outputCount; descriptorIndex++) {
        const uint32_t outputIndex = LC32OutputIndexForFatDescriptor(
            descriptorIndex, targetSliceCount);
        const LC32OutputSlice *output = &outputSlices[outputIndex];
        fatArchitectures[descriptorIndex] = (struct fat_arch){
            .cputype = (cpu_type_t)OSSwapHostToBigInt32(
                (uint32_t)output->cpuType),
            .cpusubtype = (cpu_subtype_t)OSSwapHostToBigInt32(
                (uint32_t)output->cpuSubtype),
            .offset = OSSwapHostToBigInt32(output->outputOffset),
            .size = OSSwapHostToBigInt32((uint32_t)output->size),
            .align = OSSwapHostToBigInt32(
                output->outputAlignExponent),
        };
    }

    temporaryFD = openat(stagingDirectoryFD,
        LC32_REPLACEMENT_STAGING_NAME,
        O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if(temporaryFD < 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not create", replacementPath, errno);
        goto cleanup;
    }
    if(fstat(temporaryFD, &replacementStat) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not stat", replacementPath, errno);
        goto cleanup;
    }
    replacementIdentityIsKnown = true;

    if(ftruncate(temporaryFD, (off_t)outputSize) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not initialize", replacementPath, errno);
        goto cleanup;
    }

    if(!LC32WriteAt(temporaryFD,
            outputHeader, outputHeaderSize, 0)) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not write", replacementPath, errno);
        goto cleanup;
    }
    free(outputHeader);
    outputHeader = NULL;

    copyBuffer = malloc(LC32_COPY_BUFFER_SIZE);
    comparisonBuffer = malloc(LC32_COPY_BUFFER_SIZE);
    if(copyBuffer == NULL || comparisonBuffer == NULL) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "could not allocate the slice-copy buffer");
        goto cleanup;
    }
    for(uint32_t index = 0; index < outputCount; index++) {
        const LC32OutputSlice *output = &outputSlices[index];
        if(!LC32CopyOutputSliceToFD(
                output, temporaryFD, output->outputOffset,
                copyBuffer, LC32_COPY_BUFFER_SIZE)) {
            LC32SetErrnoError(errorBuffer, errorBufferCapacity,
                "could not write", replacementPath, errno);
            goto cleanup;
        }
    }

    struct stat currentShimFDStat = {0};
    struct stat currentShimPathStat = {0};
    if(fstat(shimFD, &currentShimFDStat) != 0 ||
            lstat(shimPath, &currentShimPathStat) != 0 ||
            !S_ISREG(currentShimPathStat.st_mode) ||
            !LC32SameFileState(&shimStat, &currentShimFDStat) ||
            !LC32SameFileState(&shimStat, &currentShimPathStat)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "shim executable changed while it was being copied");
        goto cleanup;
    }

    if(fcopyfile(targetFD, temporaryFD, NULL, COPYFILE_METADATA) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not preserve metadata for", replacementPath, errno);
        goto cleanup;
    }
    if(fchown(temporaryFD, targetStat.st_uid, targetStat.st_gid) != 0 ||
            fchmod(temporaryFD, targetStat.st_mode & 07777) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not preserve metadata for", replacementPath, errno);
        goto cleanup;
    }
    if(fsync(temporaryFD) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not sync", replacementPath, errno);
        goto cleanup;
    }

    if(!LC32CreateMachOImageFromFD(temporaryFD,
            "replacement", &verificationImage,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    if(verificationImage.count != outputCount) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "replacement Mach-O has an unexpected slice count");
        goto cleanup;
    }
    for(uint32_t descriptorIndex = 0;
            descriptorIndex < outputCount; descriptorIndex++) {
        const uint32_t outputIndex = LC32OutputIndexForFatDescriptor(
            descriptorIndex, targetSliceCount);
        const LC32OutputSlice *expected = &outputSlices[outputIndex];
        const LC32MachOSlice *actual =
            &verificationImage.slices[descriptorIndex];
        if(actual->cpuType != expected->cpuType ||
                actual->cpuSubtype != expected->cpuSubtype ||
                actual->size != expected->size ||
                actual->offset != expected->outputOffset ||
                actual->alignExponent != expected->outputAlignExponent ||
                actual->fileType != expected->fileType ||
                actual->is32Bit == expected->is64Bit ||
                actual->encrypted != expected->encrypted) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "replacement Mach-O architecture verification failed");
            goto cleanup;
        }

        if(!LC32OutputSliceMatchesFD(expected,
                temporaryFD, expected->outputOffset,
                copyBuffer, comparisonBuffer,
                LC32_COPY_BUFFER_SIZE)) {
            LC32SetError(errorBuffer, errorBufferCapacity,
                "replacement Mach-O slice bytes failed verification");
            goto cleanup;
        }
    }

    struct stat replacementPathStat = {0};
    if(fstat(temporaryFD, &replacementStat) != 0 ||
            fstatat(stagingDirectoryFD, LC32_REPLACEMENT_STAGING_NAME,
                &replacementPathStat, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISREG(replacementPathStat.st_mode) ||
            !LC32SameFileState(&replacementStat, &replacementPathStat)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "replacement staging file changed during verification");
        goto cleanup;
    }

    struct stat currentFDStat = {0};
    struct stat currentPathStat = {0};
    if(fstat(targetFD, &currentFDStat) != 0 ||
            fstatat(parentDirectoryFD, targetName,
                &currentPathStat, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISREG(currentPathStat.st_mode) ||
            !LC32SameFileState(&targetStat, &currentFDStat) ||
            !LC32SameFileState(&targetStat, &currentPathStat)) {
        LC32SetError(errorBuffer, errorBufferCapacity,
            "target executable changed while it was being rewritten");
        goto cleanup;
    }

    if(renameatx_np(stagingDirectoryFD, LC32_REPLACEMENT_STAGING_NAME,
            parentDirectoryFD, targetName, RENAME_SWAP) != 0) {
        LC32SetErrnoError(errorBuffer, errorBufferCapacity,
            "could not replace", targetPath, errno);
        goto cleanup;
    }
    stagingContainsOriginalTarget = true;

    struct stat displacedFDStat = {0};
    struct stat displacedPathStat = {0};
    struct stat installedFDStat = {0};
    struct stat installedPathStat = {0};
    const bool swapIsValid =
        fstat(targetFD, &displacedFDStat) == 0 &&
        fstat(temporaryFD, &installedFDStat) == 0 &&
        fstatat(stagingDirectoryFD, LC32_REPLACEMENT_STAGING_NAME,
            &displacedPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
        fstatat(parentDirectoryFD, targetName,
            &installedPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
        S_ISREG(displacedPathStat.st_mode) &&
        S_ISREG(installedPathStat.st_mode) &&
        LC32SameFileStateAfterRename(&targetStat, &displacedFDStat) &&
        LC32SameFileStateAfterRename(&targetStat, &displacedPathStat) &&
        LC32SameFileStateAfterRename(&replacementStat, &installedFDStat) &&
        LC32SameFileStateAfterRename(&replacementStat, &installedPathStat) &&
        displacedFDStat.st_dev == displacedPathStat.st_dev &&
        displacedFDStat.st_ino == displacedPathStat.st_ino &&
        installedFDStat.st_dev == installedPathStat.st_dev &&
        installedFDStat.st_ino == installedPathStat.st_ino;
    if(!swapIsValid) {
        struct stat rollbackOriginalFDStat = {0};
        struct stat rollbackOriginalPathStat = {0};
        struct stat rollbackReplacementFDStat = {0};
        struct stat rollbackReplacementPathStat = {0};
        const bool rollbackCanBeAttempted =
            fstat(targetFD, &rollbackOriginalFDStat) == 0 &&
            fstat(temporaryFD, &rollbackReplacementFDStat) == 0 &&
            fstatat(stagingDirectoryFD,
                LC32_REPLACEMENT_STAGING_NAME,
                &rollbackOriginalPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
            fstatat(parentDirectoryFD, targetName,
                &rollbackReplacementPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISREG(rollbackOriginalPathStat.st_mode) &&
            S_ISREG(rollbackReplacementPathStat.st_mode) &&
            LC32SameFileStateAfterRename(
                &targetStat, &rollbackOriginalFDStat) &&
            LC32SameFileStateAfterRename(
                &targetStat, &rollbackOriginalPathStat) &&
            LC32SameFileStateAfterRename(
                &replacementStat, &rollbackReplacementFDStat) &&
            LC32SameFileStateAfterRename(
                &replacementStat, &rollbackReplacementPathStat) &&
            rollbackOriginalFDStat.st_dev ==
                rollbackOriginalPathStat.st_dev &&
            rollbackOriginalFDStat.st_ino ==
                rollbackOriginalPathStat.st_ino &&
            rollbackReplacementFDStat.st_dev ==
                rollbackReplacementPathStat.st_dev &&
            rollbackReplacementFDStat.st_ino ==
                rollbackReplacementPathStat.st_ino;
        if(!rollbackCanBeAttempted) {
            preserveStagingDirectory = true;
            LC32SetError(errorBuffer, errorBufferCapacity,
                "target changed during replacement; rollback was not safe");
        } else if(renameatx_np(stagingDirectoryFD,
                LC32_REPLACEMENT_STAGING_NAME,
                parentDirectoryFD, targetName, RENAME_SWAP) != 0) {
            preserveStagingDirectory = true;
            LC32SetError(errorBuffer, errorBufferCapacity,
                "target changed during replacement and rollback failed");
        } else {
            struct stat restoredOriginalFDStat = {0};
            struct stat restoredOriginalPathStat = {0};
            struct stat restoredReplacementFDStat = {0};
            struct stat restoredReplacementPathStat = {0};
            const bool rollbackIsValid =
                fstat(targetFD, &restoredOriginalFDStat) == 0 &&
                fstat(temporaryFD, &restoredReplacementFDStat) == 0 &&
                fstatat(parentDirectoryFD, targetName,
                    &restoredOriginalPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
                fstatat(stagingDirectoryFD,
                    LC32_REPLACEMENT_STAGING_NAME,
                    &restoredReplacementPathStat,
                    AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISREG(restoredOriginalPathStat.st_mode) &&
                S_ISREG(restoredReplacementPathStat.st_mode) &&
                LC32SameFileStateAfterRename(
                    &targetStat, &restoredOriginalFDStat) &&
                LC32SameFileStateAfterRename(
                    &targetStat, &restoredOriginalPathStat) &&
                LC32SameFileStateAfterRename(
                    &replacementStat, &restoredReplacementFDStat) &&
                LC32SameFileStateAfterRename(
                    &replacementStat, &restoredReplacementPathStat) &&
                restoredOriginalFDStat.st_dev ==
                    restoredOriginalPathStat.st_dev &&
                restoredOriginalFDStat.st_ino ==
                    restoredOriginalPathStat.st_ino &&
                restoredReplacementFDStat.st_dev ==
                    restoredReplacementPathStat.st_dev &&
                restoredReplacementFDStat.st_ino ==
                    restoredReplacementPathStat.st_ino;
            if(!rollbackIsValid) {
                preserveStagingDirectory = true;
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "target changed during replacement; rollback could not "
                    "be verified");
            } else {
                stagingContainsOriginalTarget = false;
                LC32SetError(errorBuffer, errorBufferCapacity,
                    "target executable changed during atomic replacement");
            }
        }
        goto cleanup;
    }
    /*
     * The replacement is already committed at this point, so a directory
     * fsync failure cannot safely be reported as an unchanged-file failure.
     * Sync it where the filesystem supports directory fsync; the rename
     * remains atomic when it does not.
     */
    if(parentDirectoryFD >= 0) (void)fsync(parentDirectoryFD);
    result = LC32MachOInjectionSucceeded;

cleanup:
    if(stagingDirectoryFD >= 0 && !preserveStagingDirectory) {
        int stagedCleanupFD = stagingContainsOriginalTarget ?
            openat(stagingDirectoryFD,
                LC32_REPLACEMENT_STAGING_NAME,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW) :
            temporaryFD;
        const bool closeStagedCleanupFD =
            stagedCleanupFD >= 0 && stagedCleanupFD != temporaryFD;
        struct stat stagedCleanupFDStat = {0};
        struct stat stagedCleanupPathStat = {0};
        const struct stat *expectedStagingStat =
            stagingContainsOriginalTarget ? &targetStat : &replacementStat;
        const bool expectedStagingIdentityIsKnown =
            stagingContainsOriginalTarget || replacementIdentityIsKnown;
        if(expectedStagingIdentityIsKnown && stagedCleanupFD >= 0 &&
                fstat(stagedCleanupFD, &stagedCleanupFDStat) == 0 &&
                fstatat(stagingDirectoryFD,
                    LC32_REPLACEMENT_STAGING_NAME,
                    &stagedCleanupPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISREG(stagedCleanupPathStat.st_mode) &&
                stagedCleanupFDStat.st_dev ==
                    stagedCleanupPathStat.st_dev &&
                stagedCleanupFDStat.st_ino ==
                    stagedCleanupPathStat.st_ino &&
                expectedStagingStat->st_dev ==
                    stagedCleanupFDStat.st_dev &&
                expectedStagingStat->st_ino ==
                    stagedCleanupFDStat.st_ino) {
            LC32ClearTemporaryRestrictiveFlags(stagedCleanupFD,
                stagingDirectoryFD, LC32_REPLACEMENT_STAGING_NAME);
            struct stat currentStagingPathStat = {0};
            if(fstatat(stagingDirectoryFD,
                    LC32_REPLACEMENT_STAGING_NAME,
                    &currentStagingPathStat, AT_SYMLINK_NOFOLLOW) == 0 &&
                    currentStagingPathStat.st_dev ==
                        stagedCleanupFDStat.st_dev &&
                    currentStagingPathStat.st_ino ==
                        stagedCleanupFDStat.st_ino) {
                (void)unlinkat(stagingDirectoryFD,
                    LC32_REPLACEMENT_STAGING_NAME, 0);
            }
        }
        if(closeStagedCleanupFD) close(stagedCleanupFD);
    }
    if(temporaryFD >= 0) close(temporaryFD);
    if(stagingDirectoryFD >= 0) {
        close(stagingDirectoryFD);
    }
    if(!preserveStagingDirectory &&
            parentDirectoryFD >= 0 && stagingDirectoryPath != NULL) {
        const char *stagingName = strrchr(stagingDirectoryPath, '/');
        stagingName = stagingName == NULL ?
            stagingDirectoryPath : stagingName + 1;
        struct stat currentStagingDirectoryStat = {0};
        if(fstatat(parentDirectoryFD, stagingName,
                &currentStagingDirectoryStat, AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISDIR(currentStagingDirectoryStat.st_mode) &&
                stagingDirectoryStat.st_dev ==
                    currentStagingDirectoryStat.st_dev &&
                stagingDirectoryStat.st_ino ==
                    currentStagingDirectoryStat.st_ino) {
            (void)unlinkat(parentDirectoryFD,
                stagingName, AT_REMOVEDIR);
        }
    }
    if(parentDirectoryFD >= 0) close(parentDirectoryFD);
    free(outputHeader);
    free(comparisonBuffer);
    free(copyBuffer);
    free(signedShimBytes);
    free(replacementPath);
    free(stagingDirectoryPath);
    free(teamIdentifier);
    free(signingIdentifier);
    if(mergedEntitlements != NULL) CFRelease(mergedEntitlements);
    LC32MachOImageFree(&verificationImage);
    LC32MachOImageFree(&shimImage);
    LC32MachOImageFree(&targetImage);
    if(shimFD >= 0) close(shimFD);
    if(targetFD >= 0) close(targetFD);
    return result;
}
