#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-opengles-smoke}
OBJECT=${OUTPUT}.o
ES1_OBJECT=${OUTPUT}-es1.o
ES3_OBJECT=${OUTPUT}-es3.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -c "$SCRIPT_DIR/opengles_smoke.m" -o "$OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -c "$SCRIPT_DIR/opengles_es1_smoke.m" -o "$ES1_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -c "$SCRIPT_DIR/opengles_es3_smoke.m" -o "$ES3_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    "$OBJECT" "$ES1_OBJECT" "$ES3_OBJECT" \
    -F"$FRAMEWORK_DIR" -framework Foundation \
    -framework OpenGLES -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
"$SCRIPT_DIR/opengles_symbols.sh" \
    "$FRAMEWORK_DIR/OpenGLES.framework/OpenGLES"
