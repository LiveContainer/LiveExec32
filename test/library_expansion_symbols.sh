#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo/tmp/iPhoneOS10.3.sdk"}
objects=${1:-"$repo/GuestMakefile/.theos/obj/armv7s"}
audit=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-library-symbols.XXXXXX")
trap 'rm -rf "$audit"' EXIT HUP INT TERM
count=0
for framework in CoreFoundation CoreGraphics ImageIO; do
    awk -v framework="$framework" '$1 == framework { print "_" $2 }' \
        "$repo/test/library_expansion_symbols.txt" | LC_ALL=C sort -u > "$audit/expected"
    xcrun nm -arch armv7s -gjU \
        "$sdk/System/Library/Frameworks/$framework.framework/$framework.tbd" | \
        LC_ALL=C sort -u > "$audit/sdk"
    xcrun nm -gjU "$objects/$framework.framework/$framework" | \
        LC_ALL=C sort -u > "$audit/actual"
    for source in sdk actual; do
        comm -23 "$audit/expected" "$audit/$source" > "$audit/missing"
        if test -s "$audit/missing"; then
            echo "$framework missing from $source:" >&2
            sed 's/^/  /' "$audit/missing" >&2
            exit 1
        fi
    done
    size=$(awk 'END { print NR + 0 }' "$audit/expected")
    count=$((count + size))
    echo "$framework library expansion: PASS ($size exports)"
done
test "$count" -eq 99
echo "Library expansion audit: PASS ($count exports)"
