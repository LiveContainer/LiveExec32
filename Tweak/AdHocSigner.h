#ifndef LC32_AD_HOC_SIGNER_H
#define LC32_AD_HOC_SIGNER_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Ad-hoc sign a temporary thin arm64 MH_EXECUTE file in place with Apple's
 * iOS 15+ SecCodeSigner SPI.  The caller must exclusively own a regular file
 * with one link at path; symlinks and hard links are rejected.  The supplied
 * entitlements must be an XML property-list dictionary.  SecCodeSigner emits
 * the CodeDirectory and both XML and DER entitlement slots.
 *
 * The file may be partially modified if the signing operation fails, so the
 * caller should discard its temporary file on failure.  Input strings and
 * entitlement bytes are borrowed for the duration of the call.
 */
bool LC32AdHocSignMachOAtPath(
    const char *path,
    const char *identifier,
    const char *teamIdentifier,
    const void *xmlEntitlements,
    size_t xmlEntitlementsSize,
    char *errorBuffer,
    size_t errorBufferCapacity);

#ifdef __cplusplus
}
#endif

#endif /* LC32_AD_HOC_SIGNER_H */
