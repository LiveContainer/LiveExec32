#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)
cd "$SCRIPT_DIR"

MACOSX_SDK_DIR=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
MODULE_CACHE=${CLANG_MODULE_CACHE_PATH:-$REPO_ROOT/.theos/module-cache}
mkdir -p "$MODULE_CACHE"

compile_catalyst() {
    "$CLANG" \
        -target arm64-apple-ios13.1-macabi \
        -isysroot "$MACOSX_SDK_DIR" \
        -isystem "$MACOSX_SDK_DIR/System/iOSSupport/usr/include" \
        -iframework "$MACOSX_SDK_DIR/System/iOSSupport/System/Library/Frameworks" \
        -fmodules \
        -fmodules-cache-path="$MODULE_CACHE" \
        -g \
        -Wno-deprecated-declarations \
        "$@"
}

compile_catalyst -fobjc-arc main.m ObjCMethod.m \
    -framework QuartzCore \
    -framework UIKit \
    -o GenerateShimObjC
compile_catalyst opengles.m \
    -framework QuartzCore \
    -o GenerateShimOpenGLES

# These are host-side Catalyst generators. The linker gives them a valid ad-hoc
# signature; applying the iOS guest entitlements with ldid makes them unlaunchable
# on macOS.
/usr/bin/codesign --verify --strict GenerateShimObjC
/usr/bin/codesign --verify --strict GenerateShimOpenGLES
