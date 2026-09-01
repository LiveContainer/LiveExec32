#ifndef LC32_MACH_O_IMAGE_H
#define LC32_MACH_O_IMAGE_H

#include <mach/machine.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LC32_MAX_MACH_O_SLICES 5u

/*
 * All offsets below are relative to the beginning of the Mach-O slice except
 * for offset, which is relative to the beginning of the containing file.
 */
typedef struct {
    cpu_type_t cpuType;
    cpu_subtype_t cpuSubtype;
    uint32_t fileType;
    uint64_t offset;
    uint64_t size;
    uint32_t alignExponent;

    bool is32Bit;
    bool isByteSwapped;
    bool encrypted;
    bool hasCodeSignature;
    bool hasLinkedit;
    bool hasBuildVersion;
    bool hasVersionMinIPhoneOS;

    uint32_t headerSize;
    uint32_t loadCommandCount;
    uint32_t loadCommandBytes;

    uint32_t codeSignatureOffset;
    uint32_t codeSignatureSize;
    uint32_t codeSignatureCommandOffset;

    uint32_t encryptionOffset;
    uint32_t encryptionSize;
    uint32_t encryptionIdentifier;

    uint32_t buildVersionCommandOffset;
    uint32_t buildVersionPlatform;
    uint32_t buildVersionMinOS;
    uint32_t buildVersionSDK;
    uint32_t versionMinIPhoneOSSDK;

    uint32_t linkeditCommandOffset;
    uint64_t linkeditVMAddress;
    uint64_t linkeditVMSize;
    uint64_t linkeditFileOffset;
    uint64_t linkeditFileSize;
} LC32MachOSlice;

typedef struct {
    LC32MachOSlice slices[LC32_MAX_MACH_O_SLICES];
    uint32_t count;
    uint64_t fileSize;
    bool isFat;
    bool isFat64;
    bool isFatByteSwapped;
} LC32MachOImage;

/*
 * Parses and validates a thin, FAT32, or FAT64 Mach-O from fd. The descriptor
 * remains owned by the caller; the parser does not retain or close fd.
 */
bool LC32MachOImageParseFD(
    int fd,
    LC32MachOImage *image,
    char *errorBuffer,
    size_t errorBufferCapacity);

/*
 * Prefers an exact CPU subtype match. If there is no exact match, capability
 * bits are ignored only when that identifies a single slice; an ambiguous
 * base-subtype lookup returns NULL.
 */
const LC32MachOSlice *LC32MachOImageFindSlice(
    const LC32MachOImage *image,
    cpu_type_t cpuType,
    cpu_subtype_t cpuSubtype);

/* The image currently owns no allocation; this clears it for API symmetry. */
void LC32MachOImageFree(LC32MachOImage *image);

#endif
