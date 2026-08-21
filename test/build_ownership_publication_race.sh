#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-ownership-publication-race}
MRC_OBJECT=${OUTPUT}.mrc.o
ARC_OBJECT=${OUTPUT}.arc.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fno-objc-arc -c "$SCRIPT_DIR/ownership_publication_race.m" \
    -o "$MRC_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fobjc-arc -c "$SCRIPT_DIR/ownership_publication_race_weak.m" \
    -o "$ARC_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fobjc-arc "$MRC_OBJECT" "$ARC_OBJECT" \
    -F"$FRAMEWORK_DIR" \
    -framework Foundation -framework LC32 \
    -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
