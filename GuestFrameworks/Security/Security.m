// Minimal Security.framework compatibility for legacy applications.
//
// Keep these values in guest memory. A legacy binary binds to the address of
// each exported variable and then dereferences it to obtain the CFStringRef;
// leaving a weak import unresolved therefore produces a NULL dictionary key
// before any Security function is called.

#import <Security/Security.h>
#import <LC32/LC32.h>

#import "LC32SecurityBridge.h"

#include <stdlib.h>

/*
 * These are the literal payloads exported by the iOS 10.3 Security image.
 * They are intentionally not the public C symbol spellings: Security uses
 * compact strings as the keys and values in SecItem dictionaries.
 */
const CFStringRef kSecAttrAccessible = CFSTR("pdmn");
const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly =
    CFSTR("cku");
const CFStringRef kSecAttrAccount = CFSTR("acct");
const CFStringRef kSecAttrApplicationTag = CFSTR("atag");
const CFStringRef kSecAttrGeneric = CFSTR("gena");
const CFStringRef kSecAttrKeyClass = CFSTR("kcls");
const CFStringRef kSecAttrKeyClassPublic = CFSTR("0");
const CFStringRef kSecAttrKeyType = CFSTR("type");
const CFStringRef kSecAttrKeyTypeRSA = CFSTR("42");
const CFStringRef kSecAttrService = CFSTR("svce");

const CFStringRef kSecClass = CFSTR("class");
const CFStringRef kSecClassGenericPassword = CFSTR("genp");
const CFStringRef kSecClassKey = CFSTR("keys");

const CFStringRef kSecMatchLimit = CFSTR("m_Limit");
const CFStringRef kSecMatchLimitOne = CFSTR("m_LimitOne");

const CFStringRef kSecReturnData = CFSTR("r_Data");
const CFStringRef kSecReturnAttributes = CFSTR("r_Attributes");
const CFStringRef kSecReturnPersistentRef = CFSTR("r_PersistentRef");
const CFStringRef kSecReturnRef = CFSTR("r_Ref");
const CFStringRef kSecValueData = CFSTR("v_Data");
const CFStringRef kSecValuePersistentRef = CFSTR("v_PersistentRef");
const CFStringRef kSecValueRef = CFSTR("v_Ref");

/* The default generator is represented by NULL in the original framework. */
const SecRandomRef kSecRandomDefault = NULL;

uint32_t LC32SecurityDispatch(LC32SecurityOpcode opcode,
                              const uint64_t *slots,
                              uint32_t slotCount,
                              OSStatus *status);

static inline uint64_t LC32SecurityHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

#define LC32_SECURITY_CALL(opcode, status, ...) \
    LC32SecurityDispatch((opcode), \
        (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / \
                   sizeof(uint64_t)), (status))
#define LC32_SECURITY_HOST(value) \
    LC32SecurityHostObject((const void *)(value))

static OSStatus LC32SecurityFinishItemResult(OSStatus status,
                                              uint32_t guestResult,
                                              CFTypeRef *result) {
    if(status == errSecSuccess && result) {
        *result = (CFTypeRef)(uintptr_t)guestResult;
    } else if(guestResult) {
        /* Balance the native and guest +1s if status copyout failed. */
        CFRelease((CFTypeRef)(uintptr_t)guestResult);
    }
    return status;
}

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if(result) *result = NULL;
    OSStatus status = errSecUnimplemented;
    const uint32_t guestResult = LC32_SECURITY_CALL(
        LC32SecurityOpItemAdd, &status,
        LC32_SECURITY_HOST(attributes), (uint64_t)(result != NULL));
    return LC32SecurityFinishItemResult(status, guestResult, result);
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if(result) *result = NULL;
    OSStatus status = errSecUnimplemented;
    const uint32_t guestResult = LC32_SECURITY_CALL(
        LC32SecurityOpItemCopyMatching, &status,
        LC32_SECURITY_HOST(query), (uint64_t)(result != NULL));
    return LC32SecurityFinishItemResult(status, guestResult, result);
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    OSStatus status = errSecUnimplemented;
    (void)LC32_SECURITY_CALL(LC32SecurityOpItemDelete, &status,
        LC32_SECURITY_HOST(query));
    return status;
}

OSStatus SecItemUpdate(CFDictionaryRef query,
                       CFDictionaryRef attributesToUpdate) {
    OSStatus status = errSecUnimplemented;
    (void)LC32_SECURITY_CALL(LC32SecurityOpItemUpdate, &status,
        LC32_SECURITY_HOST(query),
        LC32_SECURITY_HOST(attributesToUpdate));
    return status;
}

/*
 * SecureTransport cannot be forwarded by pointer: SSLSetIOFuncs receives
 * ARM32 callbacks and an opaque guest connection token.  Export the legacy
 * entry points with explicit failure semantics until that callback bridge is
 * implemented, so a lazy bind fails as an API call rather than terminating
 * the process for a missing symbol.
 */
SSLContextRef SSLCreateContext(CFAllocatorRef allocator,
                               SSLProtocolSide side,
                               SSLConnectionType type) {
    (void)allocator;
    (void)side;
    (void)type;
    return NULL;
}

#define LC32_SSL_UNIMPLEMENTED1(name, type1, arg1) \
    OSStatus name(type1 arg1) { \
        (void)arg1; \
        return errSecUnimplemented; \
    }

LC32_SSL_UNIMPLEMENTED1(SSLClose, SSLContextRef, context)
LC32_SSL_UNIMPLEMENTED1(SSLHandshake, SSLContextRef, context)
#undef LC32_SSL_UNIMPLEMENTED1

OSStatus SSLGetBufferedReadSize(SSLContextRef context, size_t *bufferSize) {
    (void)context;
    if(bufferSize) *bufferSize = 0;
    return errSecUnimplemented;
}

OSStatus SSLRead(SSLContextRef context, void *data, size_t dataLength,
                 size_t *processed) {
    (void)context;
    (void)data;
    (void)dataLength;
    if(processed) *processed = 0;
    return errSecUnimplemented;
}

OSStatus SSLWrite(SSLContextRef context, const void *data,
                  size_t dataLength, size_t *processed) {
    (void)context;
    (void)data;
    (void)dataLength;
    if(processed) *processed = 0;
    return errSecUnimplemented;
}

OSStatus SSLSetCertificate(SSLContextRef context, CFArrayRef certificates) {
    (void)context;
    (void)certificates;
    return errSecUnimplemented;
}

OSStatus SSLSetConnection(SSLContextRef context,
                          SSLConnectionRef connection) {
    (void)context;
    (void)connection;
    return errSecUnimplemented;
}

OSStatus SSLSetEnabledCiphers(SSLContextRef context,
                              const SSLCipherSuite *ciphers,
                              size_t cipherCount) {
    (void)context;
    (void)ciphers;
    (void)cipherCount;
    return errSecUnimplemented;
}

OSStatus SSLSetIOFuncs(SSLContextRef context, SSLReadFunc readFunction,
                       SSLWriteFunc writeFunction) {
    (void)context;
    (void)readFunction;
    (void)writeFunction;
    return errSecUnimplemented;
}

OSStatus SSLSetPeerDomainName(SSLContextRef context, const char *peerName,
                              size_t peerNameLength) {
    (void)context;
    (void)peerName;
    (void)peerNameLength;
    return errSecUnimplemented;
}

OSStatus SSLSetProtocolVersionMax(SSLContextRef context,
                                  SSLProtocol maximumVersion) {
    (void)context;
    (void)maximumVersion;
    return errSecUnimplemented;
}

OSStatus SSLSetProtocolVersionMin(SSLContextRef context,
                                  SSLProtocol minimumVersion) {
    (void)context;
    (void)minimumVersion;
    return errSecUnimplemented;
}

OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding,
                         const uint8_t *signedData,
                         size_t signedDataLength,
                         const uint8_t *signature,
                         size_t signatureLength) {
    (void)key;
    (void)padding;
    (void)signedData;
    (void)signedDataLength;
    (void)signature;
    (void)signatureLength;
    return errSecVerifyFailed;
}

SecCertificateRef SecCertificateCreateWithData(CFAllocatorRef allocator,
                                                CFDataRef data) {
    (void)allocator;
    (void)data;
    return NULL;
}

SecPolicyRef SecPolicyCreateBasicX509(void) {
    return NULL;
}

OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates,
                                        CFTypeRef policies,
                                        SecTrustRef *trust) {
    (void)certificates;
    (void)policies;
    if(trust) *trust = NULL;
    return errSecUnimplemented;
}

OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
    (void)trust;
    if(result) *result = kSecTrustResultInvalid;
    return errSecUnimplemented;
}

SecKeyRef SecTrustCopyPublicKey(SecTrustRef trust) {
    (void)trust;
    return NULL;
}

size_t SecKeyGetBlockSize(SecKeyRef key) {
    (void)key;
    return 0;
}

OSStatus SecKeyEncrypt(SecKeyRef key, SecPadding padding,
                       const uint8_t *plainText, size_t plainTextLen,
                       uint8_t *cipherText, size_t *cipherTextLen) {
    (void)key;
    (void)padding;
    (void)plainText;
    (void)plainTextLen;
    (void)cipherText;
    if(cipherTextLen) *cipherTextLen = 0;
    return errSecUnimplemented;
}

int SecRandomCopyBytes(SecRandomRef random, size_t count, uint8_t *bytes) {
    (void)random;
    if(count && !bytes) return -1;
    arc4random_buf(bytes, count);
    return 0;
}

void LC32SecurityCompatibilityStub(void) {
}
