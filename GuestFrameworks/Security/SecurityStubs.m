// Safe bindings for public iOS 10 Security and SecureTransport entry points
// whose opaque objects cannot yet cross the guest/host boundary.
//
// Exporting these symbols lets optional legacy code paths fail as API calls
// instead of terminating at dyld's lazy binder.  Every out parameter is
// initialized before returning.

#import <Security/Security.h>
#import <Security/SecureTransport.h>

#include <stdbool.h>

static void LC32SecurityClearError(CFErrorRef *error) {
    if(error) *error = NULL;
}

CFTypeID SecAccessControlGetTypeID(void) {
    return 0;
}

SecAccessControlRef SecAccessControlCreateWithFlags(
    CFAllocatorRef allocator, CFTypeRef protection,
    SecAccessControlCreateFlags flags, CFErrorRef *error) {
    (void)allocator;
    (void)protection;
    (void)flags;
    LC32SecurityClearError(error);
    return NULL;
}

CFDataRef SecCertificateCopyData(SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

CFStringRef SecCertificateCopySubjectSummary(
    SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

OSStatus SecCertificateCopyCommonName(SecCertificateRef certificate,
                                      CFStringRef *commonName) {
    (void)certificate;
    if(commonName) *commonName = NULL;
    return errSecUnimplemented;
}

OSStatus SecCertificateCopyEmailAddresses(SecCertificateRef certificate,
                                          CFArrayRef *emailAddresses) {
    (void)certificate;
    if(emailAddresses) *emailAddresses = NULL;
    return errSecUnimplemented;
}

CFDataRef SecCertificateCopyNormalizedIssuerSequence(
    SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

CFDataRef SecCertificateCopyNormalizedSubjectSequence(
    SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

SecKeyRef SecCertificateCopyPublicKey(SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

CFDataRef SecCertificateCopySerialNumber(SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

CFStringRef SecCreateSharedWebCredentialPassword(void) {
    return NULL;
}

CFTypeID SecKeyGetTypeID(void) {
    return 0;
}

OSStatus SecKeyGeneratePair(CFDictionaryRef parameters,
                            SecKeyRef *publicKey,
                            SecKeyRef *privateKey) {
    (void)parameters;
    if(publicKey) *publicKey = NULL;
    if(privateKey) *privateKey = NULL;
    return errSecUnimplemented;
}

SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef parameters,
                                CFErrorRef *error) {
    (void)parameters;
    LC32SecurityClearError(error);
    return NULL;
}

SecKeyRef SecKeyCreateWithData(CFDataRef keyData,
                               CFDictionaryRef attributes,
                               CFErrorRef *error) {
    (void)keyData;
    (void)attributes;
    LC32SecurityClearError(error);
    return NULL;
}

CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key,
                                           CFErrorRef *error) {
    (void)key;
    LC32SecurityClearError(error);
    return NULL;
}

CFDictionaryRef SecKeyCopyAttributes(SecKeyRef key) {
    (void)key;
    return NULL;
}

SecKeyRef SecKeyCopyPublicKey(SecKeyRef key) {
    (void)key;
    return NULL;
}

Boolean SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm,
                              CFDataRef signedData, CFDataRef signature,
                              CFErrorRef *error) {
    (void)key;
    (void)algorithm;
    (void)signedData;
    (void)signature;
    LC32SecurityClearError(error);
    return false;
}

CFDataRef SecKeyCreateEncryptedData(SecKeyRef key,
                                    SecKeyAlgorithm algorithm,
                                    CFDataRef plaintext,
                                    CFErrorRef *error) {
    (void)key;
    (void)algorithm;
    (void)plaintext;
    LC32SecurityClearError(error);
    return NULL;
}

CFDataRef SecKeyCreateDecryptedData(SecKeyRef key,
                                    SecKeyAlgorithm algorithm,
                                    CFDataRef ciphertext,
                                    CFErrorRef *error) {
    (void)key;
    (void)algorithm;
    (void)ciphertext;
    LC32SecurityClearError(error);
    return NULL;
}

CFDataRef SecKeyCopyKeyExchangeResult(SecKeyRef privateKey,
                                      SecKeyAlgorithm algorithm,
                                      SecKeyRef publicKey,
                                      CFDictionaryRef parameters,
                                      CFErrorRef *error) {
    (void)privateKey;
    (void)algorithm;
    (void)publicKey;
    (void)parameters;
    LC32SecurityClearError(error);
    return NULL;
}

Boolean SecKeyIsAlgorithmSupported(SecKeyRef key,
                                   SecKeyOperationType operation,
                                   SecKeyAlgorithm algorithm) {
    (void)key;
    (void)operation;
    (void)algorithm;
    return false;
}

OSStatus SecPKCS12Import(CFDataRef data, CFDictionaryRef options,
                         CFArrayRef *items) {
    (void)data;
    (void)options;
    if(items) *items = NULL;
    return errSecUnimplemented;
}

CFDictionaryRef SecPolicyCopyProperties(SecPolicyRef policy) {
    (void)policy;
    return NULL;
}

SecPolicyRef SecPolicyCreateRevocation(CFOptionFlags flags) {
    (void)flags;
    return NULL;
}

SecPolicyRef SecPolicyCreateWithProperties(CFTypeRef identifier,
                                           CFDictionaryRef properties) {
    (void)identifier;
    (void)properties;
    return NULL;
}

OSStatus SecTrustSetPolicies(SecTrustRef trust, CFTypeRef policies) {
    (void)trust;
    (void)policies;
    return errSecUnimplemented;
}

OSStatus SecTrustCopyPolicies(SecTrustRef trust, CFArrayRef *policies) {
    (void)trust;
    if(policies) *policies = NULL;
    return errSecUnimplemented;
}

OSStatus SecTrustSetNetworkFetchAllowed(SecTrustRef trust, Boolean allow) {
    (void)trust;
    (void)allow;
    return errSecUnimplemented;
}

OSStatus SecTrustGetNetworkFetchAllowed(SecTrustRef trust, Boolean *allow) {
    (void)trust;
    if(allow) *allow = false;
    return errSecUnimplemented;
}

OSStatus SecTrustSetAnchorCertificates(SecTrustRef trust,
                                       CFArrayRef anchors) {
    (void)trust;
    (void)anchors;
    return errSecUnimplemented;
}

OSStatus SecTrustSetAnchorCertificatesOnly(SecTrustRef trust,
                                           Boolean anchorsOnly) {
    (void)trust;
    (void)anchorsOnly;
    return errSecUnimplemented;
}

OSStatus SecTrustCopyCustomAnchorCertificates(SecTrustRef trust,
                                              CFArrayRef *anchors) {
    (void)trust;
    if(anchors) *anchors = NULL;
    return errSecUnimplemented;
}

OSStatus SecTrustSetVerifyDate(SecTrustRef trust, CFDateRef verifyDate) {
    (void)trust;
    (void)verifyDate;
    return errSecUnimplemented;
}

CFAbsoluteTime SecTrustGetVerifyTime(SecTrustRef trust) {
    (void)trust;
    return 0;
}

OSStatus SecTrustGetTrustResult(SecTrustRef trust,
                                SecTrustResultType *result) {
    (void)trust;
    if(result) *result = kSecTrustResultInvalid;
    return errSecUnimplemented;
}

CFIndex SecTrustGetCertificateCount(SecTrustRef trust) {
    (void)trust;
    return 0;
}

SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust,
                                                 CFIndex index) {
    (void)trust;
    (void)index;
    return NULL;
}

CFDataRef SecTrustCopyExceptions(SecTrustRef trust) {
    (void)trust;
    return NULL;
}

bool SecTrustSetExceptions(SecTrustRef trust, CFDataRef exceptions) {
    (void)trust;
    (void)exceptions;
    return false;
}

CFArrayRef SecTrustCopyProperties(SecTrustRef trust) {
    (void)trust;
    return NULL;
}

CFDictionaryRef SecTrustCopyResult(SecTrustRef trust) {
    (void)trust;
    return NULL;
}

CFTypeID SSLContextGetTypeID(void) {
    return 0;
}

OSStatus SSLGetSessionState(SSLContextRef context, SSLSessionState *state) {
    (void)context;
    if(state) *state = kSSLIdle;
    return errSecUnimplemented;
}

OSStatus SSLSetSessionOption(SSLContextRef context, SSLSessionOption option,
                             Boolean value) {
    (void)context;
    (void)option;
    (void)value;
    return errSecUnimplemented;
}

OSStatus SSLGetSessionOption(SSLContextRef context, SSLSessionOption option,
                             Boolean *value) {
    (void)context;
    (void)option;
    if(value) *value = false;
    return errSecUnimplemented;
}

OSStatus SSLSetSessionConfig(SSLContextRef context, CFStringRef config) {
    (void)context;
    (void)config;
    return errSecUnimplemented;
}

OSStatus SSLGetProtocolVersionMin(SSLContextRef context,
                                  SSLProtocol *version) {
    (void)context;
    if(version) *version = kSSLProtocolUnknown;
    return errSecUnimplemented;
}

OSStatus SSLGetProtocolVersionMax(SSLContextRef context,
                                  SSLProtocol *version) {
    (void)context;
    if(version) *version = kSSLProtocolUnknown;
    return errSecUnimplemented;
}

OSStatus SSLGetConnection(SSLContextRef context,
                          SSLConnectionRef *connection) {
    (void)context;
    if(connection) *connection = NULL;
    return errSecUnimplemented;
}

OSStatus SSLGetPeerDomainNameLength(SSLContextRef context, size_t *length) {
    (void)context;
    if(length) *length = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetPeerDomainName(SSLContextRef context, char *peerName,
                              size_t *length) {
    (void)context;
    if(peerName && length && *length) peerName[0] = '\0';
    if(length) *length = 0;
    return errSecUnimplemented;
}

OSStatus SSLCopyRequestedPeerName(SSLContextRef context, char *peerName,
                                  size_t *length) {
    (void)context;
    if(peerName && length && *length) peerName[0] = '\0';
    if(length) *length = 0;
    return errSecUnimplemented;
}

OSStatus SSLCopyRequestedPeerNameLength(SSLContextRef context,
                                        size_t *length) {
    (void)context;
    if(length) *length = 0;
    return errSecUnimplemented;
}

OSStatus SSLSetDatagramHelloCookie(SSLContextRef context,
                                   const void *cookie,
                                   size_t cookieLength) {
    (void)context;
    (void)cookie;
    (void)cookieLength;
    return errSecUnimplemented;
}

OSStatus SSLSetMaxDatagramRecordSize(SSLContextRef context, size_t size) {
    (void)context;
    (void)size;
    return errSecUnimplemented;
}

OSStatus SSLGetMaxDatagramRecordSize(SSLContextRef context, size_t *size) {
    (void)context;
    if(size) *size = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetNegotiatedProtocolVersion(SSLContextRef context,
                                         SSLProtocol *version) {
    (void)context;
    if(version) *version = kSSLProtocolUnknown;
    return errSecUnimplemented;
}

OSStatus SSLGetNumberSupportedCiphers(SSLContextRef context, size_t *count) {
    (void)context;
    if(count) *count = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetSupportedCiphers(SSLContextRef context,
                                SSLCipherSuite *ciphers, size_t *count) {
    (void)context;
    (void)ciphers;
    if(count) *count = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetNumberEnabledCiphers(SSLContextRef context, size_t *count) {
    (void)context;
    if(count) *count = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetEnabledCiphers(SSLContextRef context,
                              SSLCipherSuite *ciphers, size_t *count) {
    (void)context;
    (void)ciphers;
    if(count) *count = 0;
    return errSecUnimplemented;
}

OSStatus SSLCopyPeerTrust(SSLContextRef context, SecTrustRef *trust) {
    (void)context;
    if(trust) *trust = NULL;
    return errSecUnimplemented;
}

OSStatus SSLSetPeerID(SSLContextRef context, const void *peerID,
                      size_t peerIDLength) {
    (void)context;
    (void)peerID;
    (void)peerIDLength;
    return errSecUnimplemented;
}

OSStatus SSLGetPeerID(SSLContextRef context, const void **peerID,
                      size_t *peerIDLength) {
    (void)context;
    if(peerID) *peerID = NULL;
    if(peerIDLength) *peerIDLength = 0;
    return errSecUnimplemented;
}

OSStatus SSLGetNegotiatedCipher(SSLContextRef context,
                                SSLCipherSuite *cipher) {
    (void)context;
    if(cipher) *cipher = SSL_NULL_WITH_NULL_NULL;
    return errSecUnimplemented;
}

OSStatus SSLSetEncryptionCertificate(SSLContextRef context,
                                     CFArrayRef certificates) {
    (void)context;
    (void)certificates;
    return errSecUnimplemented;
}

OSStatus SSLSetClientSideAuthenticate(SSLContextRef context,
                                      SSLAuthenticate auth) {
    (void)context;
    (void)auth;
    return errSecUnimplemented;
}

OSStatus SSLAddDistinguishedName(SSLContextRef context,
                                 const void *name, size_t nameLength) {
    (void)context;
    (void)name;
    (void)nameLength;
    return errSecUnimplemented;
}

OSStatus SSLCopyDistinguishedNames(SSLContextRef context,
                                   CFArrayRef *names) {
    (void)context;
    if(names) *names = NULL;
    return errSecUnimplemented;
}

OSStatus SSLGetClientCertificateState(SSLContextRef context,
                                      SSLClientCertificateState *state) {
    (void)context;
    if(state) *state = kSSLClientCertNone;
    return errSecUnimplemented;
}

OSStatus SSLReHandshake(SSLContextRef context) {
    (void)context;
    return errSecUnimplemented;
}

OSStatus SSLGetDatagramWriteSize(SSLContextRef context, size_t *size) {
    (void)context;
    if(size) *size = 0;
    return errSecUnimplemented;
}
