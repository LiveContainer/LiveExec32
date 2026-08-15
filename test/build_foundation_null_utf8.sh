#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-foundation-null-utf8}
OBJECT=${OUTPUT}.o

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fno-objc-arc -c "$SCRIPT_DIR/foundation_null_utf8.m" -o "$OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$OBJECT" -framework Foundation -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
