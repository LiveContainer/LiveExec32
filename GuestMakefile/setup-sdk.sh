#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

SDK_ROOT=${LC32_GUEST_SDK:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
ARCHIVE=${LC32_GUEST_SDK_ARCHIVE:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk.tar.gz"}
SDK_URL=${LC32_GUEST_SDK_URL:-"https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1/iPhoneOS10.3.sdk.tar.gz"}
EXPECTED_SHA256=${LC32_GUEST_SDK_SHA256:-"fcbbd539d18597b0a07883d97385d5ccac08ab5c02f4493421113a1f8e1ceb80"}
STAMP=${LC32_GUEST_SDK_STAMP:-"$SDK_ROOT/.lc32-sdk-ready"}
SDK_PARENT=$(dirname "$SDK_ROOT")
LOCK_FILE="$SDK_PARENT/.iPhoneOS10.3.sdk.lock"

validate_sdk() {
    candidate=$1
    [ -f "$candidate/SDKSettings.plist" ] &&
        [ -f "$candidate/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h" ] &&
        [ -f "$candidate/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ] &&
        [ -f "$candidate/System/Library/Frameworks/OpenGLES.framework/Headers/ES1/gl.h" ] &&
        [ -f "$candidate/usr/lib/libSystem.tbd" ]
}

archive_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        echo "Neither shasum nor sha256sum is available" >&2
        return 1
    fi
}

verify_archive() {
    [ -f "$1" ] || return 1
    actual_sha256=$(archive_sha256 "$1") || return 1
    [ "$actual_sha256" = "$EXPECTED_SHA256" ]
}

validate_archive_layout() {
    tar -tzf "$1" | awk '
        BEGIN { entries = 0 }
        {
            name = $0
            sub(/^\.\//, "", name)
            if (name != "iPhoneOS10.3.sdk" &&
                    index(name, "iPhoneOS10.3.sdk/") != 1)
                exit 1
            count = split(name, component, "/")
            for (i = 1; i <= count; ++i)
                if (component[i] == "..")
                    exit 1
            ++entries
        }
        END { if (entries == 0) exit 1 }
    '
}

mkdir -p "$SDK_PARENT" "$(dirname "$ARCHIVE")"

# lockf releases its advisory lock automatically on normal exit and signals,
# avoiding stale lock directories when concurrent make processes invoke make -j.
if [ "${LC32_GUEST_SDK_LOCKED:-0}" != 1 ] && command -v lockf >/dev/null 2>&1; then
    LC32_GUEST_SDK_LOCKED=1 exec lockf -k "$LOCK_FILE" "$0"
fi

if validate_sdk "$SDK_ROOT"; then
    if [ ! -f "$STAMP" ]; then
        echo "Using existing iOS 10.3 SDK at $SDK_ROOT" >&2
    fi
    : > "$STAMP"
    exit 0
fi

if [ -e "$SDK_ROOT" ]; then
    echo "Existing SDK path is incomplete; refusing to replace it: $SDK_ROOT" >&2
    exit 1
fi

download_tmp=
stage=
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$download_tmp" ]; then
        rm -f "$download_tmp"
    fi
    if [ -n "$stage" ]; then
        rm -rf "$stage"
    fi
    exit "$status"
}
trap cleanup EXIT HUP INT TERM

if ! verify_archive "$ARCHIVE"; then
    download_tmp=$(mktemp "$SDK_PARENT/.iPhoneOS10.3.sdk.tar.gz.XXXXXX")
    echo "Downloading the iOS 10.3 guest SDK from $SDK_URL" >&2
    curl --fail --location --retry 3 --retry-delay 1 \
        --output "$download_tmp" "$SDK_URL"
    if ! verify_archive "$download_tmp"; then
        actual_sha256=$(archive_sha256 "$download_tmp" 2>/dev/null || echo unavailable)
        echo "iOS 10.3 SDK checksum mismatch" >&2
        echo "  expected: $EXPECTED_SHA256" >&2
        echo "  actual:   $actual_sha256" >&2
        exit 1
    fi
    mv -f "$download_tmp" "$ARCHIVE"
    download_tmp=
fi

if ! validate_archive_layout "$ARCHIVE"; then
    echo "Unexpected paths in iOS 10.3 SDK archive: $ARCHIVE" >&2
    exit 1
fi

stage=$(mktemp -d "$SDK_PARENT/.iPhoneOS10.3.sdk.stage.XXXXXX")
tar -xzf "$ARCHIVE" -C "$stage"
extracted="$stage/iPhoneOS10.3.sdk"
if ! validate_sdk "$extracted"; then
    echo "Extracted iOS 10.3 SDK is incomplete" >&2
    exit 1
fi

: > "$extracted/.lc32-sdk-ready"
mv "$extracted" "$SDK_ROOT"
rm -rf "$stage"
stage=
echo "Installed iOS 10.3 guest SDK at $SDK_ROOT" >&2
