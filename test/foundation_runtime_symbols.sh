#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/Foundation.framework/Foundation"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
SDK_STUB="$SDKROOT/System/Library/Frameworks/Foundation.framework/Foundation.tbd"

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-foundation-runtime-symbols.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat > "$work/expected" <<'EOF'
NSCreateZone
NSDefaultMallocZone
NSProtocolFromString
NSRealMemoryAvailable
NSRecycleZone
NSSetZoneName
NSZoneCalloc
NSZoneFree
NSZoneFromPointer
NSZoneMalloc
NSZoneName
NSZoneRealloc
EOF

if [ ! -f "$FRAMEWORK" ] || [ ! -f "$SDK_STUB" ]; then
    echo "Foundation guest image or iOS 10.3 SDK stub is missing" >&2
    exit 1
fi

LC_ALL=C sort -u "$work/expected" -o "$work/expected"
xcrun nm -gjU "$SDK_STUB" 2>/dev/null | sed 's/^_//' | LC_ALL=C sort -u \
    > "$work/sdk"
xcrun nm -gjU "$FRAMEWORK" | sed 's/^_//' | LC_ALL=C sort -u \
    > "$work/actual"

comm -23 "$work/expected" "$work/sdk" > "$work/not-in-sdk"
if [ -s "$work/not-in-sdk" ]; then
    echo "Foundation helper symbols are not public in the iOS 10.3 SDK:" >&2
    sed 's/^/  /' "$work/not-in-sdk" >&2
    exit 1
fi

comm -23 "$work/expected" "$work/actual" > "$work/missing"
if [ -s "$work/missing" ]; then
    echo "Foundation guest image is missing helper symbols:" >&2
    sed 's/^/  /' "$work/missing" >&2
    exit 1
fi

echo "Foundation runtime helper symbol audit: PASS (12 exports)"
