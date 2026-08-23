#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
MANIFEST="$REPO_ROOT/Generator/templates/opengles-supported-symbols.txt"
SOURCE="$REPO_ROOT/GuestFrameworks/OpenGLES/OpenGLES.m"
LINKED_IMAGE=${1:-}
TEMP_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-opengles-symbols.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

if [ -n "$LINKED_IMAGE" ] && [ ! -f "$LINKED_IMAGE" ]; then
    echo "OpenGLES linked image does not exist: $LINKED_IMAGE" >&2
    exit 1
fi

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

symbol_address() {
    image=$1
    symbol=$2
    xcrun nm -n "$image" | awk -v symbol="_$symbol" '
        $NF == symbol { count++; address = $1 }
        END {
            if (count != 1) exit 1
            print address
        }'
}

check_thumb_symbol() {
    image=$1
    symbol=$2
    if ! xcrun nm -nm "$image" | awk -v symbol="_$symbol" '
        $NF == symbol {
            count++
            if (index($0, "[Thumb]") != 0) thumb++
        }
        END { exit !(count == 1 && thumb == 1) }'; then
        echo "OpenGLES alias is not a unique external Thumb symbol: $symbol" >&2
        exit 1
    fi
}

check_alias() {
    alias_name=$1
    target_name=$2
    alias_address=
    target_address=
    if ! alias_address=$(symbol_address "$TEMP_DIR/OpenGLES.o" "$alias_name") || \
       ! target_address=$(symbol_address "$TEMP_DIR/OpenGLES.o" "$target_name") || \
       [ "$alias_address" != "$target_address" ]; then
        echo "OpenGLES alias address mismatch: $alias_name -> $target_name " \
             "($alias_address != $target_address)" >&2
        exit 1
    fi

    if [ -n "$LINKED_IMAGE" ]; then
        if ! alias_address=$(symbol_address "$LINKED_IMAGE" "$alias_name") || \
           ! target_address=$(symbol_address "$LINKED_IMAGE" "$target_name") || \
           [ "$alias_address" != "$target_address" ]; then
            echo "Linked OpenGLES alias address mismatch: " \
                 "$alias_name -> $target_name " \
                 "($alias_address != $target_address)" >&2
            exit 1
        fi
        check_thumb_symbol "$LINKED_IMAGE" "$alias_name"
    fi
}

check_alias glBindFramebufferOES glBindFramebuffer
check_alias glBindRenderbufferOES glBindRenderbuffer
check_alias glBlendEquationOES glBlendEquation
check_alias glBlendEquationSeparateOES glBlendEquationSeparate
check_alias glBlendFuncSeparateOES glBlendFuncSeparate
check_alias glCheckFramebufferStatusOES glCheckFramebufferStatus
check_alias glDeleteFramebuffersOES glDeleteFramebuffers
check_alias glDeleteRenderbuffersOES glDeleteRenderbuffers
check_alias glFramebufferRenderbufferOES glFramebufferRenderbuffer
check_alias glFramebufferTexture2DOES glFramebufferTexture2D
check_alias glGenFramebuffersOES glGenFramebuffers
check_alias glGenRenderbuffersOES glGenRenderbuffers
check_alias glGenerateMipmapOES glGenerateMipmap
check_alias glGetFramebufferAttachmentParameterivOES \
    glGetFramebufferAttachmentParameteriv
check_alias glGetRenderbufferParameterivOES \
    glGetRenderbufferParameteriv
check_alias glIsFramebufferOES glIsFramebuffer
check_alias glIsRenderbufferOES glIsRenderbuffer
check_alias glRenderbufferStorageOES glRenderbufferStorage

echo "OpenGLES symbol audit: PASS (ES2 core, GLES1 compatibility, and EAGL globals)"
