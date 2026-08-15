#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-nsrange-bridge}
OBJECT=${OUTPUT}.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"
MODULE_CACHE=${CLANG_MODULE_CACHE_PATH:-/private/tmp/lc32-test-module-cache}

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fmodules -fmodules-cache-path="$MODULE_CACHE" \
    -I"$REPO_ROOT/GuestFrameworks" -I"$REPO_ROOT/include" \
    -c "$SCRIPT_DIR/nsrange_bridge.m" -o "$OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$OBJECT" -F"$FRAMEWORK_DIR" \
    -framework Foundation -framework LC32 -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
