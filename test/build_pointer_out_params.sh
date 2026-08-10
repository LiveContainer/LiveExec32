#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-pointer-out-params}
OBJECT=${OUTPUT}.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -c "$SCRIPT_DIR/pointer_out_params.m" -o "$OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$OBJECT" -F"$FRAMEWORK_DIR" -framework Foundation -framework LC32 \
    -fno-autolink \
    -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
