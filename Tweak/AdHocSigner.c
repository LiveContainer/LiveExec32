#include "AdHocSigner.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecBase.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define LC32_SIGNER_MAX_MACHO_SIZE (128u * 1024u * 1024u)
#define LC32_SIGNER_MAX_ENTITLEMENTS_SIZE (16u * 1024u * 1024u)
#define LC32_SIGNER_MAX_STRING_SIZE 4096u
#define LC32_SIGNER_ENTITLEMENTS_MAGIC UINT32_C(0xfade7171)
#define LC32_SIGNER_DEFAULT_FLAGS 0u

typedef struct __LC32SecCodeSigner *LC32SecCodeSignerRef;
typedef const struct __LC32SecStaticCode *LC32SecStaticCodeRef;

extern OSStatus SecCodeSignerCreate(
    CFDictionaryRef parameters,
    uint32_t flags,
    LC32SecCodeSignerRef *signerOut)
    __attribute__((weak_import));

extern OSStatus SecStaticCodeCreateWithPathAndAttributes(
    CFURLRef path,
    uint32_t flags,
    CFDictionaryRef attributes,
    LC32SecStaticCodeRef *staticCodeOut)
    __attribute__((weak_import));

extern OSStatus SecCodeSignerAddSignatureWithErrors(
    LC32SecCodeSignerRef signer,
    LC32SecStaticCodeRef staticCode,
    uint32_t flags,
    CFErrorRef *errorsOut)
    __attribute__((weak_import));

typedef struct {
    dev_t device;
} LC32SignerFileIdentity;

static void LC32SignerSetError(
        char *buffer, size_t capacity, const char *format, ...) {
    if(buffer == NULL || capacity == 0) return;

    va_list arguments;
    va_start(arguments, format);
    (void)vsnprintf(buffer, capacity, format, arguments);
    va_end(arguments);
}

static bool LC32SignerCStringLength(
        const char *string, size_t maximumLength, size_t *lengthOut) {
    if(string == NULL || lengthOut == NULL) return false;
    for(size_t index = 0; index < maximumLength; index++) {
        if(string[index] == '\0') {
            if(index == 0) return false;
            *lengthOut = index;
            return true;
        }
    }
    return false;
}

static uint32_t LC32SignerHostToBigUInt32(uint32_t value) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    return __builtin_bswap32(value);
#else
    return value;
#endif
}

static void LC32SignerSetSecurityError(
        char *buffer, size_t capacity,
        const char *operation, OSStatus status, CFErrorRef error) {
    char description[512] = {0};
    CFStringRef descriptionString = error == NULL ? NULL :
        CFErrorCopyDescription(error);
    if(descriptionString != NULL) {
        (void)CFStringGetCString(descriptionString,
            description, sizeof(description), kCFStringEncodingUTF8);
        CFRelease(descriptionString);
    }

    if(description[0] != '\0') {
        LC32SignerSetError(buffer, capacity,
            "%s failed (OSStatus %d): %s",
            operation, (int)status, description);
    } else {
        LC32SignerSetError(buffer, capacity,
            "%s failed with OSStatus %d", operation, (int)status);
    }
}

static bool LC32SignerReadAt(
        int descriptor, void *buffer, size_t size, off_t offset) {
    size_t completed = 0;
    while(completed < size) {
        const ssize_t amount = pread(descriptor,
            (uint8_t *)buffer + completed, size - completed,
            offset + (off_t)completed);
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

static bool LC32SignerValidateThinExecutable(
        const char *path, LC32SignerFileIdentity *identityOut,
        char *errorBuffer, size_t errorBufferCapacity) {
    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(descriptor < 0) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not open signing input %s: %s",
            path, strerror(errno));
        return false;
    }

    struct stat status = {0};
    struct mach_header_64 header = {0};
    const bool readHeader = LC32SignerReadAt(
        descriptor, &header, sizeof(header), 0);
    const int readError = errno;
    const bool validStatus = fstat(descriptor, &status) == 0;
    const int statError = errno;
    const int closeResult = close(descriptor);
    const int closeError = errno;

    if(!validStatus) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not stat signing input %s: %s",
            path, strerror(statError));
        return false;
    }
    if(closeResult != 0) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not close signing input %s: %s",
            path, strerror(closeError));
        return false;
    }
    if(!readHeader) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not read signing input %s: %s",
            path, strerror(readError));
        return false;
    }
    if(!S_ISREG(status.st_mode) || status.st_nlink != 1 ||
            status.st_size < (off_t)sizeof(header) ||
            (uint64_t)status.st_size > LC32_SIGNER_MAX_MACHO_SIZE ||
            header.magic != MH_MAGIC_64 ||
            header.cputype != CPU_TYPE_ARM64 ||
            header.filetype != MH_EXECUTE) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "signing input must be a private, thin arm64 executable");
        return false;
    }

    identityOut->device = status.st_dev;
    return true;
}

static CFStringRef LC32SignerCreateUTF8String(
        const char *value, size_t length,
        const char *description,
        char *errorBuffer, size_t errorBufferCapacity) {
    CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault,
        (const UInt8 *)value, (CFIndex)length,
        kCFStringEncodingUTF8, false);
    if(string == NULL) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "%s is not valid UTF-8", description);
    }
    return string;
}

static CFDataRef LC32SignerCreateEntitlementsBlob(
        const void *xmlEntitlements, size_t xmlEntitlementsSize,
        char *errorBuffer, size_t errorBufferCapacity) {
    CFDataRef xmlData = CFDataCreate(kCFAllocatorDefault,
        xmlEntitlements, (CFIndex)xmlEntitlementsSize);
    if(xmlData == NULL) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not allocate XML entitlements data");
        return NULL;
    }

    CFPropertyListFormat propertyListFormat = 0;
    CFErrorRef propertyListError = NULL;
    CFPropertyListRef propertyList = CFPropertyListCreateWithData(
        kCFAllocatorDefault, xmlData, kCFPropertyListImmutable,
        &propertyListFormat, &propertyListError);
    if(propertyListError != NULL) CFRelease(propertyListError);
    if(propertyList == NULL ||
            propertyListFormat != kCFPropertyListXMLFormat_v1_0 ||
            CFGetTypeID(propertyList) != CFDictionaryGetTypeID()) {
        if(propertyList != NULL) CFRelease(propertyList);
        CFRelease(xmlData);
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "entitlements must be an XML property-list dictionary");
        return NULL;
    }
    CFRelease(propertyList);
    CFRelease(xmlData);

    if(xmlEntitlementsSize > UINT32_MAX - 8u) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "XML entitlements are too large");
        return NULL;
    }
    const size_t blobSize = xmlEntitlementsSize + 8u;
    uint8_t *blobBytes = malloc(blobSize);
    if(blobBytes == NULL) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not allocate the entitlements blob");
        return NULL;
    }
    const uint32_t magic = LC32SignerHostToBigUInt32(
        LC32_SIGNER_ENTITLEMENTS_MAGIC);
    const uint32_t length = LC32SignerHostToBigUInt32(
        (uint32_t)blobSize);
    memcpy(blobBytes, &magic, sizeof(magic));
    memcpy(blobBytes + sizeof(magic), &length, sizeof(length));
    memcpy(blobBytes + 8u, xmlEntitlements, xmlEntitlementsSize);

    CFDataRef blob = CFDataCreate(kCFAllocatorDefault,
        blobBytes, (CFIndex)blobSize);
    free(blobBytes);
    if(blob == NULL) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "could not create the entitlements blob");
    }
    return blob;
}

bool LC32AdHocSignMachOAtPath(
        const char *path,
        const char *identifier,
        const char *teamIdentifier,
        const void *xmlEntitlements,
        size_t xmlEntitlementsSize,
        char *errorBuffer,
        size_t errorBufferCapacity) {
    if(errorBuffer != NULL && errorBufferCapacity != 0) {
        errorBuffer[0] = '\0';
    }

    size_t pathLength = 0;
    size_t identifierLength = 0;
    size_t teamIdentifierLength = 0;
    if(!LC32SignerCStringLength(path, PATH_MAX, &pathLength)) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "signing path is empty or too long");
        return false;
    }
    if(!LC32SignerCStringLength(identifier,
            LC32_SIGNER_MAX_STRING_SIZE, &identifierLength) ||
            !LC32SignerCStringLength(teamIdentifier,
                LC32_SIGNER_MAX_STRING_SIZE,
                &teamIdentifierLength)) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "signing identifier or team identifier is invalid");
        return false;
    }
    if(xmlEntitlements == NULL || xmlEntitlementsSize == 0 ||
            xmlEntitlementsSize > LC32_SIGNER_MAX_ENTITLEMENTS_SIZE ||
            xmlEntitlementsSize > INT32_MAX) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "XML entitlements have an unsupported size");
        return false;
    }

    LC32SignerFileIdentity originalIdentity = {0};
    if(!LC32SignerValidateThinExecutable(path, &originalIdentity,
            errorBuffer, errorBufferCapacity)) {
        return false;
    }

    if(SecCodeSignerCreate == NULL ||
            SecStaticCodeCreateWithPathAndAttributes == NULL ||
            SecCodeSignerAddSignatureWithErrors == NULL) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "Security.framework code-signing SPI is unavailable");
        return false;
    }

    bool success = false;
    CFStringRef identifierString = NULL;
    CFStringRef teamIdentifierString = NULL;
    CFDataRef entitlementsBlob = NULL;
    CFNumberRef cmsSizeNumber = NULL;
    CFURLRef pathURL = NULL;
    CFMutableDictionaryRef parameters = NULL;
    CFDictionaryRef attributes = NULL;
    LC32SecCodeSignerRef signer = NULL;
    LC32SecStaticCodeRef staticCode = NULL;
    CFErrorRef signingError = NULL;

    identifierString = LC32SignerCreateUTF8String(identifier,
        identifierLength, "signing identifier",
        errorBuffer, errorBufferCapacity);
    teamIdentifierString = LC32SignerCreateUTF8String(teamIdentifier,
        teamIdentifierLength, "team identifier",
        errorBuffer, errorBufferCapacity);
    entitlementsBlob = LC32SignerCreateEntitlementsBlob(
        xmlEntitlements, xmlEntitlementsSize,
        errorBuffer, errorBufferCapacity);
    const int32_t cmsSize = 8;
    cmsSizeNumber = CFNumberCreate(kCFAllocatorDefault,
        kCFNumberSInt32Type, &cmsSize);
    pathURL = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, (const UInt8 *)path,
        (CFIndex)pathLength, false);
    parameters = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    attributes = CFDictionaryCreate(kCFAllocatorDefault,
        NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(identifierString == NULL || teamIdentifierString == NULL ||
            entitlementsBlob == NULL || cmsSizeNumber == NULL ||
            pathURL == NULL ||
            parameters == NULL || attributes == NULL) {
        if(errorBuffer != NULL && errorBufferCapacity != 0 &&
                errorBuffer[0] == '\0') {
            LC32SignerSetError(errorBuffer, errorBufferCapacity,
                "could not allocate code-signing parameters");
        }
        goto cleanup;
    }

    CFDictionarySetValue(parameters, CFSTR("signer"), kCFNull);
    CFDictionarySetValue(parameters,
        CFSTR("identifier"), identifierString);
    CFDictionarySetValue(parameters,
        CFSTR("teamidentifier"), teamIdentifierString);
    CFDictionarySetValue(parameters,
        CFSTR("entitlements"), entitlementsBlob);
    CFDictionarySetValue(parameters,
        CFSTR("cmssize"), cmsSizeNumber);

    OSStatus status = SecCodeSignerCreate(parameters,
        LC32_SIGNER_DEFAULT_FLAGS, &signer);
    if(status != errSecSuccess || signer == NULL) {
        LC32SignerSetSecurityError(errorBuffer, errorBufferCapacity,
            "SecCodeSignerCreate", status, NULL);
        goto cleanup;
    }

    status = SecStaticCodeCreateWithPathAndAttributes(pathURL,
        LC32_SIGNER_DEFAULT_FLAGS, attributes, &staticCode);
    if(status != errSecSuccess || staticCode == NULL) {
        LC32SignerSetSecurityError(errorBuffer, errorBufferCapacity,
            "SecStaticCodeCreateWithPathAndAttributes", status, NULL);
        goto cleanup;
    }

    status = SecCodeSignerAddSignatureWithErrors(signer, staticCode,
        LC32_SIGNER_DEFAULT_FLAGS, &signingError);
    if(status != errSecSuccess) {
        LC32SignerSetSecurityError(errorBuffer, errorBufferCapacity,
            "SecCodeSignerAddSignatureWithErrors",
            status, signingError);
        goto cleanup;
    }

    LC32SignerFileIdentity signedIdentity = {0};
    if(!LC32SignerValidateThinExecutable(path, &signedIdentity,
            errorBuffer, errorBufferCapacity)) {
        goto cleanup;
    }
    if(signedIdentity.device != originalIdentity.device) {
        LC32SignerSetError(errorBuffer, errorBufferCapacity,
            "signed output unexpectedly moved to another filesystem");
        goto cleanup;
    }
    success = true;

cleanup:
    if(signingError != NULL) CFRelease(signingError);
    if(staticCode != NULL) CFRelease(staticCode);
    if(signer != NULL) CFRelease(signer);
    if(attributes != NULL) CFRelease(attributes);
    if(parameters != NULL) CFRelease(parameters);
    if(pathURL != NULL) CFRelease(pathURL);
    if(cmsSizeNumber != NULL) CFRelease(cmsSizeNumber);
    if(entitlementsBlob != NULL) CFRelease(entitlementsBlob);
    if(teamIdentifierString != NULL) CFRelease(teamIdentifierString);
    if(identifierString != NULL) CFRelease(identifierString);
    return success;
}
