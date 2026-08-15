#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-audio-file-create-packets}
OBJECT=${OUTPUT}.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -Wno-deprecated-declarations \
    -c "$SCRIPT_DIR/audio_file_create_packets.c" -o "$OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$OBJECT" -F"$FRAMEWORK_DIR" \
    -framework AudioToolbox -framework CoreFoundation -framework LC32 \
    -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
