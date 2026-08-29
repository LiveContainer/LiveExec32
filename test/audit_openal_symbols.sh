#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
BINARY=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/OpenAL.framework/OpenAL"}
SDKROOT=${2:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
TBD="$SDKROOT/System/Library/Frameworks/OpenAL.framework/OpenAL.tbd"

if [ ! -f "$BINARY" ]; then
    echo "OpenAL guest framework is missing: $BINARY" >&2
    exit 1
fi
if [ ! -f "$TBD" ]; then
    echo "OpenAL SDK export list is missing: $TBD" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-openal-symbols.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

tr '[], ' '\n\n\n\n' < "$TBD" |
    sed -n 's/^_\(al[^[:space:]]*\)$/\1/p' |
    sort -u > "$work/expected"
nm -gjU "$BINARY" |
    sed -n 's/^_\(al[^[:space:]]*\)$/\1/p' |
    sort -u > "$work/actual"
comm -23 "$work/expected" "$work/actual" > "$work/missing"

expected_count=$(wc -l < "$work/expected" | tr -d ' ')
if [ "$expected_count" -ne 93 ]; then
    echo "Unexpected iOS SDK OpenAL symbol count: $expected_count" >&2
    exit 1
fi
if [ -s "$work/missing" ]; then
    echo "Missing OpenAL guest exports:" >&2
    sed 's/^/  /' "$work/missing" >&2
    exit 1
fi

echo "OpenAL export audit passed: all $expected_count iOS 10 symbols are present"
