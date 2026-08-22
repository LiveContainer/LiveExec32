// Minimal Security.framework compatibility for legacy applications.
//
// Keep these values in guest memory. A legacy binary binds to the address of
// each exported variable and then dereferences it to obtain the CFStringRef;
// leaving a weak import unresolved therefore produces a NULL dictionary key
// before any Security function is called.

#import <Security/Security.h>

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
const CFStringRef kSecReturnPersistentRef = CFSTR("r_PersistentRef");
const CFStringRef kSecReturnRef = CFSTR("r_Ref");
const CFStringRef kSecValueData = CFSTR("v_Data");

/* The default generator is represented by NULL in the original framework. */
const SecRandomRef kSecRandomDefault = NULL;

/*
 * Keychain and SecKey objects cannot safely be represented by an arbitrary
 * guest pointer. Until that opaque-object bridge exists, report failure and
 * always initialize caller-owned result storage. This preserves the Create /
 * Copy ownership contract: a non-NULL result would have to be returned at +1.
 */
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    (void)attributes;
    if(result) *result = NULL;
    return errSecUnimplemented;
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    (void)query;
    if(result) *result = NULL;
    return errSecItemNotFound;
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    (void)query;
    return errSecUnimplemented;
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
