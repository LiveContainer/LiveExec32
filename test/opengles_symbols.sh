#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
MANIFEST="$REPO_ROOT/Generator/templates/opengles-supported-symbols.txt"
SOURCE="$REPO_ROOT/GuestFrameworks/OpenGLES/OpenGLES.m"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-opengles-symbols.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

LC_ALL=C sort -c -u "$MANIFEST"

xcrun --sdk iphoneos clang -target armv7s-apple-ios10.3 \
    -isysroot "$SDKROOT" -I"$REPO_ROOT/GuestFrameworks" \
    -I"$REPO_ROOT/include" \
    -fmodules -fmodules-cache-path="$TEMP_DIR/modules" \
    -Wno-deprecated-module-dot-map -Wno-deprecated-declarations \
    -c "$SOURCE" -o "$TEMP_DIR/OpenGLES.o"

xcrun nm -gjU "$TEMP_DIR/OpenGLES.o" | \
    sed -E -n 's/^_(EAGLGetVersion|gl[A-Za-z0-9_]*)$/\1/p' | \
    LC_ALL=C sort -u > "$TEMP_DIR/bridge-symbols.txt"
diff -u "$MANIFEST" "$TEMP_DIR/bridge-symbols.txt"

sed -E -n 's/^GL_API.*GL_APIENTRY (gl[A-Za-z0-9_]+) \(.*/\1/p' \
    "$SDKROOT/System/Library/Frameworks/OpenGLES.framework/Headers/ES2/gl.h" | \
    LC_ALL=C sort -u > "$TEMP_DIR/sdk-symbols.txt"
comm -23 "$TEMP_DIR/sdk-symbols.txt" "$MANIFEST" > "$TEMP_DIR/missing-es2-symbols.txt"
if [ -s "$TEMP_DIR/missing-es2-symbols.txt" ]; then
    echo "OpenGLES bridge is missing ES2 core symbols:" >&2
    cat "$TEMP_DIR/missing-es2-symbols.txt" >&2
    exit 1
fi

for symbol in \
    kEAGLColorFormatRGBA8 \
    kEAGLDrawablePropertyColorFormat \
    kEAGLDrawablePropertyRetainedBacking; do
    if ! xcrun nm -gjU "$TEMP_DIR/OpenGLES.o" | grep -qx "_$symbol"; then
        echo "OpenGLES bridge is missing data export: $symbol" >&2
        exit 1
    fi
done

echo "OpenGLES symbol audit: PASS (ES2 core, GLES1 compatibility, and EAGL globals)"
