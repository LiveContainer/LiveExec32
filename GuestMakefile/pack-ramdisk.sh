#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

RAMDISK_ROOT=${RAMDISK_ROOT:-"$REPO_ROOT/tmp/ramdisk"}
IOS_SYSTEM_ROOT=${IOS_SYSTEM_ROOT:-/Volumes/Greensburg14G60.N41N42N48N49OS}
BUILD_ROOT=${BUILD_ROOT:-"$SCRIPT_DIR/.theos/obj/debug/armv7s"}

if [ ! -d "$RAMDISK_ROOT/System/Library" ]; then
    echo "Ramdisk root is missing System/Library: $RAMDISK_ROOT" >&2
    exit 1
fi
if [ ! -d "$IOS_SYSTEM_ROOT/System/Library" ]; then
    echo "iOS system root is missing System/Library: $IOS_SYSTEM_ROOT" >&2
    exit 1
fi

framework_count=0
for source_dir in "$REPO_ROOT"/GuestFrameworks/*; do
    [ -d "$source_dir" ] || continue
    framework_name=${source_dir##*/}
    source_binary="$BUILD_ROOT/$framework_name.framework/$framework_name"

    case "$framework_name" in
        AVFAudio)
            relative_bundle=System/Library/Frameworks/AVFoundation.framework/Frameworks/AVFAudio.framework
            source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
            ;;
        FileProvider)
            relative_bundle=System/Library/PrivateFrameworks/FileProvider.framework
            source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
            ;;
        LC32)
            relative_bundle=System/Library/Frameworks/LC32.framework
            source_plist="$source_dir/Info.plist"
            ;;
        *)
            relative_bundle="System/Library/Frameworks/$framework_name.framework"
            source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
            ;;
    esac

    expected_id="/$relative_bundle/$framework_name"
    destination_bundle="$RAMDISK_ROOT/$relative_bundle"
    destination_binary="$destination_bundle/$framework_name"

    if [ ! -f "$source_binary" ]; then
        echo "Missing built framework: $source_binary" >&2
        exit 1
    fi
    if [ ! -f "$source_plist" ]; then
        echo "Missing framework metadata: $source_plist" >&2
        exit 1
    fi
    if ! file "$source_binary" | grep -q 'arm_v7s'; then
        echo "Framework is not armv7s: $source_binary" >&2
        exit 1
    fi
    actual_id=$(otool -D "$source_binary" | tail -n 1)
    if [ "$actual_id" != "$expected_id" ]; then
        echo "Unexpected install name for $framework_name: $actual_id" >&2
        echo "Expected: $expected_id" >&2
        exit 1
    fi

    install -d -m 0755 "$destination_bundle"
    install -m 0644 "$source_plist" "$destination_bundle/Info.plist"
    install -m 0755 "$source_binary" "$destination_binary"
    if ! cmp -s "$source_binary" "$destination_binary"; then
        echo "Installed framework differs from build: $framework_name" >&2
        exit 1
    fi

    framework_count=$((framework_count + 1))
done

avfaudio_link="$RAMDISK_ROOT/System/Library/Frameworks/AVFoundation.framework/libAVFAudio.dylib"
avfaudio_target=Frameworks/AVFAudio.framework/AVFAudio
if [ -L "$avfaudio_link" ]; then
    if [ "$(readlink "$avfaudio_link")" != "$avfaudio_target" ]; then
        echo "Unexpected AVFAudio compatibility symlink: $avfaudio_link" >&2
        exit 1
    fi
elif [ -e "$avfaudio_link" ]; then
    echo "Refusing to replace non-symlink path: $avfaudio_link" >&2
    exit 1
else
    ln -s "$avfaudio_target" "$avfaudio_link"
fi

echo "Installed and verified $framework_count guest frameworks in $RAMDISK_ROOT"
