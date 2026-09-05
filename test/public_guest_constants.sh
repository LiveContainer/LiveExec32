#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-public-constants.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

extract() {
    framework=$1
    expression=$2
    raw="$work/$framework.extract.raw"
    perl -0777 -ne "while(/$expression/sg) { print \"\$1\\n\" }" \
        "$SDKROOT/System/Library/Frameworks/$framework.framework/Headers/"*.h \
        > "$raw"
    LC_ALL=C sort -u "$raw"
}

audit() {
    framework=$1
    expected=$2
    baseline=$3
    image="$FRAMEWORK_DIR/$framework.framework/$framework"
    if [ ! -f "$image" ]; then
        echo "$framework guest framework not found: $image" >&2
        exit 1
    fi

    count=$(awk 'END { print NR + 0 }' "$expected")
    if [ "$count" -ne "$baseline" ]; then
        echo "$framework public symbol extraction changed: " \
            "expected $baseline entries, got $count" >&2
        exit 1
    fi

    xcrun nm -gjU "$image" > "$work/$framework.nm"
    sed 's/^_//' "$work/$framework.nm" > "$work/$framework.names"
    LC_ALL=C sort -u "$work/$framework.names" \
        > "$work/$framework.actual"
    comm -23 "$expected" "$work/$framework.actual" \
        > "$work/$framework.missing"
    if [ -s "$work/$framework.missing" ]; then
        echo "$framework is missing public guest symbols:" >&2
        sed 's/^/  /' "$work/$framework.missing" >&2
        exit 1
    fi

    total=$((total + count))
    echo "$framework public guest symbol audit: PASS ($count exports)"
}

extract MobileCoreServices \
    'extern\s+const\s+CFStringRef\s+(kUT[A-Za-z0-9_]+)' \
    > "$work/MobileCoreServices.expected"
extract CoreText \
    'CT_EXPORT\s+const\s+CFStringRef\s+(kCT[A-Za-z0-9_]+)' \
    > "$work/CoreText.expected"
extract CoreMedia \
    'CM_EXPORT\s+const\s+CFStringRef\s+(kCM[A-Za-z0-9_]+)' \
    > "$work/CoreMedia.expected"
extract AddressBook \
    'AB_EXTERN\s+const\s+(?:CFStringRef|CFNumberRef|ABPropertyID|int)\s+((?:kAB[A-Za-z0-9_]+|ABAddressBookErrorDomain))' \
    > "$work/AddressBook.expected"
extract AudioToolbox \
    'extern\s+const\s+CFStringRef\s+(kAudio[A-Za-z0-9_]+)' \
    > "$work/AudioToolbox.expected"
for manifest in cfnetwork_symbols.txt cfnetwork_simple_symbols.txt; do
    if [ ! -f "$SCRIPT_DIR/$manifest" ]; then
        echo "CFNetwork symbol manifest not found: $SCRIPT_DIR/$manifest" >&2
        exit 1
    fi
done
cat "$SCRIPT_DIR/cfnetwork_symbols.txt" \
    "$SCRIPT_DIR/cfnetwork_simple_symbols.txt" \
    > "$work/CFNetwork.raw"
sed '/^$/d' "$work/CFNetwork.raw" > "$work/CFNetwork.filtered"
LC_ALL=C sort -u "$work/CFNetwork.filtered" \
    > "$work/CFNetwork.expected"
cat > "$work/SystemConfiguration.expected" <<'EOF'
kCFErrorDomainSystemConfiguration
kCNNetworkInfoKeyBSSID
kCNNetworkInfoKeySSID
kCNNetworkInfoKeySSIDData
EOF

total=0
audit MobileCoreServices "$work/MobileCoreServices.expected" 141
audit CoreText "$work/CoreText.expected" 117
audit CoreMedia "$work/CoreMedia.expected" 251
audit AddressBook "$work/AddressBook.expected" 90
audit AudioToolbox "$work/AudioToolbox.expected" 26
audit CFNetwork "$work/CFNetwork.expected" 181
audit SystemConfiguration "$work/SystemConfiguration.expected" 4

if [ "$total" -ne 810 ]; then
    echo "Public guest symbol baseline changed: expected 810, got $total" >&2
    exit 1
fi
echo "Public guest symbol audit: PASS ($total exports)"
