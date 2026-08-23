#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
IMAGE=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s/Security.framework/Security"}

if [ ! -f "$IMAGE" ]; then
    echo "Security linked image does not exist: $IMAGE" >&2
    exit 1
fi

SYMBOLS=$(mktemp "${TMPDIR:-/private/tmp}/lc32-security-symbols.XXXXXX")
trap 'rm -f "$SYMBOLS"' EXIT HUP INT TERM
xcrun nm -gjU "$IMAGE" > "$SYMBOLS"

for symbol in \
    kSecAttrAccessible \
    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly \
    kSecAttrAccount \
    kSecAttrApplicationTag \
    kSecAttrGeneric \
    kSecAttrKeyType \
    kSecAttrKeyTypeRSA \
    kSecAttrService \
    kSecClass \
    kSecClassGenericPassword \
    kSecClassKey \
    kSecMatchLimit \
    kSecMatchLimitOne \
    kSecReturnData \
    kSecReturnAttributes \
    kSecReturnPersistentRef \
    kSecReturnRef \
    kSecValueData \
    kSecValuePersistentRef \
    kSecValueRef \
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
    SecKeyRawVerify; do
    if ! grep -qx "_$symbol" "$SYMBOLS"; then
        echo "Security bridge is missing export: $symbol" >&2
        exit 1
    fi
done

echo "Security symbol audit: PASS"
