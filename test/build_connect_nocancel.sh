#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-connect-nocancel}

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$SCRIPT_DIR/connect_nocancel.c" \
    "$SCRIPT_DIR/connect_nocancel.S" -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
