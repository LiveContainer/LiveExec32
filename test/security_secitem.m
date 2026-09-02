#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <stdio.h>
#include <unistd.h>

enum { LC32ErrSecMissingEntitlement = -34018 };

typedef enum {
    kSecECCurveNone = -1,
    kSecECCurveSecp256r1 = 23,
    kSecECCurveSecp384r1 = 24,
    kSecECCurveSecp521r1 = 25,
} SecECNamedCurve;

extern SecCertificateRef SecCertificateCreateWithBytes(
    CFAllocatorRef allocator, const UInt8 *bytes, CFIndex length);
extern const UInt8 *SecCertificateGetBytePtr(
    SecCertificateRef certificate);
extern CFIndex SecCertificateGetLength(SecCertificateRef certificate);
extern CFDataRef SecECKeyCopyPublicBits(SecKeyRef key);
extern SecECNamedCurve SecECKeyGetNamedCurve(SecKeyRef key);
extern CFDataRef SecKeyCopyExponent(SecKeyRef key);
extern CFDataRef SecKeyCopyModulus(SecKeyRef key);
extern CFIndex SecKeyGetAlgorithmId(SecKeyRef key);
extern OSStatus SecTrustSetSignedCertificateTimestamps(
    SecTrustRef trust, CFArrayRef sctArray);

static int report(const char *name, BOOL passed, OSStatus status) {
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int passed = 1;

    @autoreleasepool {
        const BOOL constantsValid =
            CFEqual(kSecAttrAccessibleAfterFirstUnlock, CFSTR("ck")) &&
            CFEqual(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    CFSTR("cku")) &&
            CFEqual(kSecAttrAccessibleAlways, CFSTR("dk")) &&
            CFEqual(kSecAttrAccessibleAlwaysThisDeviceOnly,
                    CFSTR("dku")) &&
            CFEqual(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                    CFSTR("akpu")) &&
            CFEqual(kSecAttrAccessGroup, CFSTR("agrp")) &&
            CFEqual(kSecAttrAccessibleWhenUnlocked, CFSTR("ak")) &&
            CFEqual(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    CFSTR("aku")) &&
            CFEqual(kSecAttrApplicationLabel, CFSTR("klbl")) &&
            CFEqual(kSecAttrCanDecrypt, CFSTR("decr")) &&
            CFEqual(kSecAttrCanDerive, CFSTR("drve")) &&
            CFEqual(kSecAttrCanEncrypt, CFSTR("encr")) &&
            CFEqual(kSecAttrCanSign, CFSTR("sign")) &&
            CFEqual(kSecAttrCanUnwrap, CFSTR("unwp")) &&
            CFEqual(kSecAttrCanVerify, CFSTR("vrfy")) &&
            CFEqual(kSecAttrCanWrap, CFSTR("wrap")) &&
            CFEqual(kSecAttrComment, CFSTR("icmt")) &&
            CFEqual(kSecAttrCreationDate, CFSTR("cdat")) &&
            CFEqual(kSecAttrDescription, CFSTR("desc")) &&
            CFEqual(kSecAttrEffectiveKeySize, CFSTR("esiz")) &&
            CFEqual(kSecAttrIsPermanent, CFSTR("perm")) &&
            CFEqual(kSecAttrKeyClassPrivate, CFSTR("1")) &&
            CFEqual(kSecAttrKeyClassSymmetric, CFSTR("2")) &&
            CFEqual(kSecAttrKeySizeInBits, CFSTR("bsiz")) &&
            CFEqual(kSecAttrLabel, CFSTR("labl")) &&
            CFEqual(kSecAttrModificationDate, CFSTR("mdat")) &&
            CFEqual(kSecAttrSynchronizable, CFSTR("sync")) &&
            CFEqual(kSecAttrSynchronizableAny, CFSTR("syna")) &&
            CFEqual(kSecClassCertificate, CFSTR("cert")) &&
            CFEqual(kSecClassIdentity, CFSTR("idnt")) &&
            CFEqual(kSecClassInternetPassword, CFSTR("inet")) &&
            CFEqual(kSecMatchLimitAll, CFSTR("m_LimitAll")) &&
            CFEqual(kSecValuePersistentRef,
                    CFSTR("v_PersistentRef")) &&
            CFEqual(kSecValueRef, CFSTR("v_Ref")) &&
            CFEqual(kSecReturnAttributes, CFSTR("r_Attributes")) &&
            CFEqual(kSecUseNoAuthenticationUI, CFSTR("u_NoAuthUI")) &&
            CFEqual(kSecUseOperationPrompt, CFSTR("u_OpPrompt")) &&
            CFEqual(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1,
                    CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA1")) &&
            CFEqual(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256,
                    CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256")) &&
            CFEqual(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384,
                    CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA384")) &&
            CFEqual(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512,
                    CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA512"));
        passed &= report("security-constants", constantsValid, noErr);

        SecCertificateRef copiedCertificate =
            (SecCertificateRef)(uintptr_t)1;
        SecKeyRef copiedPrivateKey = (SecKeyRef)(uintptr_t)1;
        CFErrorRef signatureError = (CFErrorRef)(uintptr_t)1;
        size_t plainTextLength = 1;
        size_t signatureLength = 1;

        const SecCertificateRef createdCertificate =
            SecCertificateCreateWithBytes(NULL, NULL, 0);
        const UInt8 *certificateBytes = SecCertificateGetBytePtr(NULL);
        const CFIndex certificateLength = SecCertificateGetLength(NULL);
        const CFTypeID certificateType = SecCertificateGetTypeID();
        const CFDataRef publicBits = SecECKeyCopyPublicBits(NULL);
        const SecECNamedCurve namedCurve = SecECKeyGetNamedCurve(NULL);
        const OSStatus copyCertificateStatus =
            SecIdentityCopyCertificate(NULL, &copiedCertificate);
        const OSStatus copyPrivateKeyStatus =
            SecIdentityCopyPrivateKey(NULL, &copiedPrivateKey);
        const CFTypeID identityType = SecIdentityGetTypeID();
        const CFDataRef exponent = SecKeyCopyExponent(NULL);
        const CFDataRef modulus = SecKeyCopyModulus(NULL);
        const CFDataRef signature = SecKeyCreateSignature(
            NULL, kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256,
            NULL, &signatureError);
        const OSStatus decryptStatus = SecKeyDecrypt(
            NULL, kSecPaddingNone, NULL, 0, NULL, &plainTextLength);
        const CFIndex algorithmID = SecKeyGetAlgorithmId(NULL);
        const OSStatus signStatus = SecKeyRawSign(
            NULL, kSecPaddingNone, NULL, 0, NULL, &signatureLength);
        const SecPolicyRef sslPolicy = SecPolicyCreateSSL(false, NULL);
        const CFTypeID policyType = SecPolicyGetTypeID();
        const OSStatus evaluateAsyncStatus = SecTrustEvaluateAsync(
            NULL, NULL, (SecTrustCallback)NULL);
        const CFTypeID trustType = SecTrustGetTypeID();
        const OSStatus ocspStatus = SecTrustSetOCSPResponse(NULL, NULL);
        const OSStatus sctStatus =
            SecTrustSetSignedCertificateTimestamps(NULL, NULL);

        const BOOL failureStubsValid =
            createdCertificate == NULL &&
            certificateBytes == NULL && certificateLength == 0 &&
            certificateType == 0 && publicBits == NULL &&
            namedCurve == kSecECCurveNone &&
            copyCertificateStatus == errSecUnimplemented &&
            copiedCertificate == NULL &&
            copyPrivateKeyStatus == errSecUnimplemented &&
            copiedPrivateKey == NULL && identityType == 0 &&
            exponent == NULL && modulus == NULL && signature == NULL &&
            signatureError == NULL &&
            decryptStatus == errSecUnimplemented &&
            plainTextLength == 0 && algorithmID == 0 &&
            signStatus == errSecUnimplemented && signatureLength == 0 &&
            sslPolicy == NULL && policyType == 0 &&
            evaluateAsyncStatus == errSecUnimplemented &&
            trustType == 0 && ocspStatus == errSecUnimplemented &&
            sctStatus == errSecUnimplemented;
        passed &= report("security-failure-stubs", failureStubsValid,
            noErr);

        CFTypeRef invalidResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus invalidStatus =
            SecItemCopyMatching(NULL, &invalidResult);
        passed &= report("security-native-invalid-query",
            invalidStatus == errSecParam && invalidResult == NULL,
            invalidStatus);

        NSString *service = [NSString stringWithFormat:
            @"org.liveexec32.security-test.%d", getpid()];
        NSString *account = @"guest-account";
        NSData *firstData = [@"guest-secret-one"
            dataUsingEncoding:NSUTF8StringEncoding];
        NSData *secondData = [@"guest-secret-two"
            dataUsingEncoding:NSUTF8StringEncoding];

        NSDictionary *identity = @{
            (id)kSecClass: (id)kSecClassGenericPassword,
            (id)kSecAttrService: service,
            (id)kSecAttrAccount: account,
        };
        const OSStatus predeleteStatus = SecItemDelete(
            (CFDictionaryRef)identity);
        if(predeleteStatus == errSecNotAvailable ||
           predeleteStatus == LC32ErrSecMissingEntitlement) {
            CFTypeRef unavailableResult = (CFTypeRef)(uintptr_t)1;
            NSMutableDictionary *unavailableAdd =
                [identity mutableCopy];
            unavailableAdd[(id)kSecValueData] = firstData;
            const OSStatus unavailableStatus = SecItemAdd(
                (CFDictionaryRef)unavailableAdd, &unavailableResult);
            passed &= report("security-host-keychain-unavailable",
                unavailableStatus == predeleteStatus &&
                    unavailableResult == NULL,
                unavailableStatus);
            printf("security-keychain-cycle: SKIP (host keychain unavailable)\n");
            [unavailableAdd release];
            return !passed;
        }
        passed &= report("security-predelete",
            predeleteStatus == errSecSuccess ||
                predeleteStatus == errSecItemNotFound,
            predeleteStatus);

        NSMutableDictionary *add = [identity mutableCopy];
        add[(id)kSecValueData] = firstData;
        add[(id)kSecReturnPersistentRef] = (id)kCFBooleanTrue;
        CFTypeRef persistentReference = NULL;
        const OSStatus addStatus = SecItemAdd(
            (CFDictionaryRef)add, &persistentReference);
        const BOOL addValid = addStatus == errSecSuccess &&
            persistentReference != NULL &&
            CFGetTypeID(persistentReference) == CFDataGetTypeID();
        passed &= report("security-add-persistent-ref", addValid,
            addStatus);

        CFTypeRef duplicateResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus duplicateStatus = SecItemAdd(
            (CFDictionaryRef)add, &duplicateResult);
        passed &= report("security-duplicate-result-zeroed",
            duplicateStatus == errSecDuplicateItem &&
                duplicateResult == NULL,
            duplicateStatus);

        NSDictionary *updatedAttributes = @{
            (id)kSecValueData: secondData,
        };
        const OSStatus updateStatus = SecItemUpdate(
            (CFDictionaryRef)identity,
            (CFDictionaryRef)updatedAttributes);
        passed &= report("security-update", updateStatus == errSecSuccess,
            updateStatus);

        NSMutableDictionary *dataQuery = [identity mutableCopy];
        dataQuery[(id)kSecReturnData] = (id)kCFBooleanTrue;
        dataQuery[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
        CFTypeRef copiedData = NULL;
        const OSStatus copyStatus = SecItemCopyMatching(
            (CFDictionaryRef)dataQuery, &copiedData);
        const BOOL copyValid = copyStatus == errSecSuccess &&
            copiedData && CFEqual(copiedData, (CFDataRef)secondData);
        passed &= report("security-copy-updated-data", copyValid,
            copyStatus);
        if(copiedData) CFRelease(copiedData);

        if(persistentReference) {
            NSDictionary *persistentQuery = @{
                (id)kSecValuePersistentRef: (id)persistentReference,
                (id)kSecReturnData: (id)kCFBooleanTrue,
            };
            CFTypeRef persistentData = NULL;
            const OSStatus persistentStatus = SecItemCopyMatching(
                (CFDictionaryRef)persistentQuery, &persistentData);
            const BOOL persistentValid =
                persistentStatus == errSecSuccess && persistentData &&
                CFEqual(persistentData, (CFDataRef)secondData);
            passed &= report("security-persistent-ref-roundtrip",
                persistentValid, persistentStatus);
            if(persistentData) CFRelease(persistentData);
            CFRelease(persistentReference);
        }

        const OSStatus deleteStatus = SecItemDelete(
            (CFDictionaryRef)identity);
        passed &= report("security-delete", deleteStatus == errSecSuccess,
            deleteStatus);

        CFTypeRef missingResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus missingStatus = SecItemCopyMatching(
            (CFDictionaryRef)dataQuery, &missingResult);
        passed &= report("security-missing-result-zeroed",
            missingStatus == errSecItemNotFound && missingResult == NULL,
            missingStatus);

        [add release];
        [dataQuery release];
    }

    return !passed;
}
