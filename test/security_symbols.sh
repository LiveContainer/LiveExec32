#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
IMAGE=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/Security.framework/Security"}

if [ ! -f "$IMAGE" ]; then
    echo "Security linked image does not exist: $IMAGE" >&2
    exit 1
fi

SYMBOLS=$(mktemp "${TMPDIR:-/private/tmp}/lc32-security-symbols.XXXXXX")
trap 'rm -f "$SYMBOLS"' EXIT HUP INT TERM
xcrun nm -gjU "$IMAGE" > "$SYMBOLS"

for symbol in \
    kSecAttrAccessible \
    kSecAttrAccessibleAfterFirstUnlock \
    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly \
    kSecAttrAccessibleAlways \
    kSecAttrAccessibleAlwaysThisDeviceOnly \
    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly \
    kSecAttrAccessibleWhenUnlocked \
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly \
    kSecAttrAccessGroup \
    kSecAttrAccount \
    kSecAttrApplicationLabel \
    kSecAttrApplicationTag \
    kSecAttrCanDecrypt \
    kSecAttrCanDerive \
    kSecAttrCanEncrypt \
    kSecAttrCanSign \
    kSecAttrCanUnwrap \
    kSecAttrCanVerify \
    kSecAttrCanWrap \
    kSecAttrComment \
    kSecAttrCreationDate \
    kSecAttrDescription \
    kSecAttrEffectiveKeySize \
    kSecAttrGeneric \
    kSecAttrIsPermanent \
    kSecAttrKeyClass \
    kSecAttrKeyClassPrivate \
    kSecAttrKeyClassPublic \
    kSecAttrKeyClassSymmetric \
    kSecAttrKeySizeInBits \
    kSecAttrKeyType \
    kSecAttrKeyTypeRSA \
    kSecAttrLabel \
    kSecAttrModificationDate \
    kSecAttrService \
    kSecAttrSynchronizable \
    kSecAttrSynchronizableAny \
    kSecClass \
    kSecClassCertificate \
    kSecClassGenericPassword \
    kSecClassIdentity \
    kSecClassInternetPassword \
    kSecClassKey \
    kSecMatchLimit \
    kSecMatchLimitAll \
    kSecMatchLimitOne \
    kSecReturnData \
    kSecReturnAttributes \
    kSecReturnPersistentRef \
    kSecReturnRef \
    kSecValueData \
    kSecValuePersistentRef \
    kSecValueRef \
    kSecUseNoAuthenticationUI \
    kSecUseOperationPrompt \
    kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1 \
    kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256 \
    kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384 \
    kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512 \
    kSecRandomDefault \
    SecItemAdd \
    SecItemCopyMatching \
    SecItemDelete \
    SecItemUpdate \
    SSLClose \
    SSLCreateContext \
    SSLGetBufferedReadSize \
    SSLHandshake \
    SSLRead \
    SSLSetCertificate \
    SSLSetConnection \
    SSLSetEnabledCiphers \
    SSLSetIOFuncs \
    SSLSetPeerDomainName \
    SSLSetProtocolVersionMax \
    SSLSetProtocolVersionMin \
    SSLWrite \
    SecCertificateCreateWithBytes \
    SecCertificateGetBytePtr \
    SecCertificateGetLength \
    SecCertificateGetTypeID \
    SecECKeyCopyPublicBits \
    SecECKeyGetNamedCurve \
    SecIdentityCopyCertificate \
    SecIdentityCopyPrivateKey \
    SecIdentityGetTypeID \
    SecKeyCopyExponent \
    SecKeyCopyModulus \
    SecKeyCreateSignature \
    SecKeyDecrypt \
    SecKeyGetAlgorithmId \
    SecKeyRawSign \
    SecPolicyCreateSSL \
    SecPolicyGetTypeID \
    SecTrustEvaluateAsync \
    SecTrustGetTypeID \
    SecTrustSetOCSPResponse \
    SecTrustSetSignedCertificateTimestamps \
    SecKeyRawVerify; do
    if ! grep -qx "_$symbol" "$SYMBOLS"; then
        echo "Security bridge is missing export: $symbol" >&2
        exit 1
    fi
done

echo "Security symbol audit: PASS"
