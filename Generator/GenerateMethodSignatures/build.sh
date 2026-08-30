#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)
cd "$SCRIPT_DIR"

if [ -z "${THEOS:-}" ]; then
    echo "THEOS must point to a Theos installation with an armv7-capable SDK" >&2
    exit 1
fi

GENERATOR_SDK_PATH="${IOS_SDK_PATH:-${THEOS}/sdks/iPhoneOS16.5.sdk}"
if [ ! -d "$GENERATOR_SDK_PATH" ]; then
    echo "iOS SDK not found at $GENERATOR_SDK_PATH" >&2
    echo "Set IOS_SDK_PATH to an armv7-capable iPhoneOS SDK" >&2
    exit 1
fi

GENERATOR_MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-$REPO_ROOT/.theos/module-cache}"
mkdir -p "$GENERATOR_MODULE_CACHE"

xcrun --sdk iphoneos clang \
    -target armv7s-apple-ios10.3 \
    -isysroot "$GENERATOR_SDK_PATH" \
    -fmodules \
    -fmodules-cache-path="$GENERATOR_MODULE_CACHE" \
    main.m \
    -o GenerateMethodSignatures
