#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-framework-ownership.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat > "$work/expected" <<'EOF'
NSDefaultRunLoopMode Foundation CoreFoundation
NSFontAttributeName Foundation UIKit
NSGregorianCalendar Foundation CoreFoundation
NSHTTPCookieComment Foundation CFNetwork
NSHTTPCookieCommentURL Foundation CFNetwork
NSHTTPCookieDiscard Foundation CFNetwork
NSHTTPCookieDomain Foundation CFNetwork
NSHTTPCookieExpires Foundation CFNetwork
NSHTTPCookieManagerAcceptPolicyChangedNotification Foundation CFNetwork
NSHTTPCookieManagerCookiesChangedNotification Foundation CFNetwork
NSHTTPCookieMaximumAge Foundation CFNetwork
NSHTTPCookieName Foundation CFNetwork
NSHTTPCookieOriginURL Foundation CFNetwork
NSHTTPCookiePath Foundation CFNetwork
NSHTTPCookiePort Foundation CFNetwork
NSHTTPCookieSecure Foundation CFNetwork
NSHTTPCookieValue Foundation CFNetwork
NSHTTPCookieVersion Foundation CFNetwork
NSLocaleCurrencySymbol Foundation CoreFoundation
NSLocaleIdentifier Foundation CoreFoundation
NSNetServicesErrorCode Foundation CFNetwork
NSNetServicesErrorDomain Foundation CFNetwork
NSURLAuthenticationMethodClientCertificate Foundation CFNetwork
NSURLAuthenticationMethodDefault Foundation CFNetwork
NSURLAuthenticationMethodHTMLForm Foundation CFNetwork
NSURLAuthenticationMethodHTTPBasic Foundation CFNetwork
NSURLAuthenticationMethodHTTPDigest Foundation CFNetwork
NSURLAuthenticationMethodNTLM Foundation CFNetwork
NSURLAuthenticationMethodNegotiate Foundation CFNetwork
NSURLAuthenticationMethodServerTrust Foundation CFNetwork
NSURLCredentialStorageChangedNotification Foundation CFNetwork
NSURLCredentialStorageRemoveSynchronizableCredentials Foundation CFNetwork
NSURLProtectionSpaceFTP Foundation CFNetwork
NSURLProtectionSpaceFTPProxy Foundation CFNetwork
NSURLProtectionSpaceHTTP Foundation CFNetwork
NSURLProtectionSpaceHTTPProxy Foundation CFNetwork
NSURLProtectionSpaceHTTPS Foundation CFNetwork
NSURLProtectionSpaceHTTPSProxy Foundation CFNetwork
NSURLProtectionSpaceSOCKSProxy Foundation CFNetwork
NSURLSessionDownloadTaskResumeData Foundation CFNetwork
NSURLSessionTaskPriorityDefault Foundation CFNetwork
NSURLSessionTaskPriorityHigh Foundation CFNetwork
NSURLSessionTaskPriorityLow Foundation CFNetwork
NSURLSessionTransferSizeUnknown Foundation CFNetwork
kCFStreamPropertySOCKSPassword CFNetwork CoreFoundation
kCFStreamPropertySOCKSProxy CFNetwork CoreFoundation
kCFStreamPropertySOCKSProxyHost CFNetwork CoreFoundation
kCFStreamPropertySOCKSProxyPort CFNetwork CoreFoundation
kCFStreamPropertySOCKSUser CFNetwork CoreFoundation
kCFStreamPropertySOCKSVersion CFNetwork CoreFoundation
kCFStreamPropertyShouldCloseNativeSocket CFNetwork CoreFoundation
kCFStreamPropertySocketSecurityLevel CFNetwork CoreFoundation
kCFStreamSocketSOCKSVersion4 CFNetwork CoreFoundation
kCFStreamSocketSOCKSVersion5 CFNetwork CoreFoundation
kCFStreamSocketSecurityLevelNegotiatedSSL CFNetwork CoreFoundation
kCFStreamSocketSecurityLevelNone CFNetwork CoreFoundation
kCFStreamSocketSecurityLevelSSLv2 CFNetwork CoreFoundation
kCFStreamSocketSecurityLevelSSLv3 CFNetwork CoreFoundation
kCFStreamSocketSecurityLevelTLSv1 CFNetwork CoreFoundation
EOF

expected_count=$(wc -l < "$work/expected" | tr -d ' ')
if [ "$expected_count" -ne 59 ]; then
    echo "Framework ownership manifest changed: expected 59 moves, got $expected_count" >&2
    exit 1
fi

for framework in CFNetwork CoreFoundation Foundation UIKit; do
    image="$FRAMEWORK_DIR/$framework.framework/$framework"
    if [ ! -f "$image" ]; then
        echo "$framework guest framework is missing: $image" >&2
        exit 1
    fi

    # `nm -gjU` also reports indirect/reexported symbols.  Ownership is about
    # storage defined by this image, so accept only addressed external symbols.
    xcrun nm -m "$image" |
        awk '$1 ~ /^[[:xdigit:]]+$/ && / external / { print $NF }' |
        sed 's/^_//' | LC_ALL=C sort -u > "$work/$framework.direct"
done

failures=0
while read -r symbol old_framework new_framework; do
    if ! grep -Fqx "$symbol" "$work/$new_framework.direct"; then
        echo "$new_framework is missing moved direct export: $symbol" >&2
        failures=$((failures + 1))
    fi
    if grep -Fqx "$symbol" "$work/$old_framework.direct"; then
        echo "$old_framework still defines moved export: $symbol" >&2
        failures=$((failures + 1))
    fi
done < "$work/expected"

if [ "$failures" -ne 0 ]; then
    echo "Framework ownership audit failed: $failures errors" >&2
    exit 1
fi

echo "Framework symbol ownership audit: PASS ($expected_count moves)"
