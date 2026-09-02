#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

RAMDISK_ROOT=${RAMDISK_ROOT:-"$REPO_ROOT/Resources/RootFS"}
IOS_SYSTEM_ROOT=${IOS_SYSTEM_ROOT:-}
FRAMEWORK_INFO_ROOT=${FRAMEWORK_INFO_ROOT:-"$SCRIPT_DIR/FrameworkInfoPlists"}
BUILD_ROOT=${BUILD_ROOT:-"$SCRIPT_DIR/.theos/obj/armv7s"}

# The guest root is the iOS 10.3.3 restore ramdisk.  If it has not been set
# up yet, download and extract it from the IPSW, then copy it into place
# with rsync -aH.  (7z would break the HFS symlinks and dylib hardlink
# pairs that the guest dyld relies on.)  This only runs once, before the
# first pack.
RAMDISK_IPSW_URL=${RAMDISK_IPSW_URL:-"http://appldnld.apple.com/ios10.3.3/091-23384-20170719-CA966D80-6977-11E7-9F96-3E9100BA0AE3/iPhone_4.0_32bit_10.3.3_14G60_Restore.ipsw"}
RAMDISK_IPSW_COMPONENT=${RAMDISK_IPSW_COMPONENT:-"058-75249-062.dmg"}
RAMDISK_IPSW_COMPONENT_SHA256=${RAMDISK_IPSW_COMPONENT_SHA256:-"d50dff8eae1a17cc91369929fdea4dc0cdf815c6b8e11f5809cc16629f3f1a44"}
RAMDISK_IMAGE_SHA256=${RAMDISK_IMAGE_SHA256:-"3564d16366b053503107288be6cb335b2283cf14838ab64a88017c17a2a6a1bc"}
RAMDISK_SETUP_DIR=${RAMDISK_SETUP_DIR:-"$REPO_ROOT/tmp/ipsw"}

RAMDISK_ROOT=$(python3 -c \
    'import os, sys; print(os.path.realpath(sys.argv[1]))' "$RAMDISK_ROOT")
case "$RAMDISK_ROOT" in
    /|/Applications|/Library|/System|/Users|/bin|/private|/private/tmp|/sbin|/tmp|/usr|/var)
        echo "Refusing unsafe RAMDISK_ROOT: $RAMDISK_ROOT" >&2
        exit 1
        ;;
esac
case "$REPO_ROOT/" in
    "$RAMDISK_ROOT"/*)
        echo "RAMDISK_ROOT must not contain the repository: $RAMDISK_ROOT" >&2
        exit 1
        ;;
esac

file_sha256() {
    shasum -a 256 "$1" | awk '{ print $1 }'
}

verify_sha256() {
    [ -f "$1" ] && [ "$(file_sha256 "$1")" = "$2" ]
}

setup_ramdisk() {
    echo "Setting up guest ramdisk at $RAMDISK_ROOT" >&2
    mkdir -p "$RAMDISK_SETUP_DIR" "$(dirname "$RAMDISK_ROOT")"
    encrypted_image="$RAMDISK_SETUP_DIR/$RAMDISK_IPSW_COMPONENT"
    decrypted_image="$RAMDISK_SETUP_DIR/ramdisk.dmg"

    if ! verify_sha256 "$decrypted_image" "$RAMDISK_IMAGE_SHA256"; then
        rm -f "$decrypted_image"
        if ! verify_sha256 "$encrypted_image" "$RAMDISK_IPSW_COMPONENT_SHA256"; then
            rm -f "$encrypted_image"
            echo "Downloading $RAMDISK_IPSW_COMPONENT from the iOS 10.3.3 IPSW" >&2
            download_attempt=1
            while :; do
                download_dir=$(mktemp -d "$RAMDISK_SETUP_DIR/.download.XXXXXX")
                if (cd "$download_dir" && pzb -g "$RAMDISK_IPSW_COMPONENT" "$RAMDISK_IPSW_URL") \
                        && verify_sha256 "$download_dir/$RAMDISK_IPSW_COMPONENT" \
                            "$RAMDISK_IPSW_COMPONENT_SHA256"; then
                    mv "$download_dir/$RAMDISK_IPSW_COMPONENT" "$encrypted_image"
                    rm -rf "$download_dir"
                    break
                fi
                rm -rf "$download_dir"
                download_attempt=$((download_attempt + 1))
                if [ "$download_attempt" -gt 3 ]; then
                    echo "Failed to download $RAMDISK_IPSW_COMPONENT" >&2
                    exit 1
                fi
                echo "Download failed; retrying ($download_attempt/3)" >&2
                sleep 2
            done
        fi

        echo "Extracting ramdisk image from Img3" >&2
        python3 "$SCRIPT_DIR/extract-img3.py" \
            "$encrypted_image" "$decrypted_image"
        if ! verify_sha256 "$decrypted_image" "$RAMDISK_IMAGE_SHA256"; then
            echo "Extracted ramdisk image checksum mismatch" >&2
            exit 1
        fi
    fi

    mount_point=$(mktemp -d "$RAMDISK_ROOT.attach.XXXXXX")
    cleanup() {
        hdiutil detach "$mount_point" >/dev/null 2>&1 || true
        rm -rf "$mount_point"
    }
    trap cleanup EXIT HUP INT TERM

    echo "Mounting decrypted ramdisk" >&2
    hdiutil attach -nobrowse -readonly "$decrypted_image" -mountpoint "$mount_point" >/dev/null

    mkdir -p "$RAMDISK_ROOT"
    # -a preserves symlinks and permissions; -H preserves the dylib hardlink
    # pairs.  The HFS image's root-owned .Trashes directory is unreadable to
    # a normal user, so exclude it (and the HFS+ private data dir) outright.
    rsync -aH \
        --exclude='.Trashes' \
        --exclude='.HFS+ Private Directory Data' \
        --exclude='System/Library/AppleUSBDevice' \
        --exclude='System/Library/CoreServices/DumpPanic' \
        --exclude='System/Library/CoreServices/ReportCrash' \
        --exclude='System/Library/Extensions/*' \
        --exclude='System/Library/Filesystems/*' \
        --exclude='System/Library/Frameworks/*' \
        --exclude='System/Library/LaunchDaemons/*' \
        --exclude='System/Library/Lockdown' \
        --exclude='System/Library/PrivateFrameworks/*' \
        --exclude='usr/lib/updaters' \
        --exclude='usr/lib/IOABPLib.dylib' \
        --exclude='usr/lib/libamsupport.dylib' \
        --exclude='usr/lib/libauthinstall.dylib' \
        --exclude='usr/lib/libARI.dylib' \
        --exclude='usr/lib/libATCommandStudioDynamic.dylib' \
        --exclude='usr/lib/libBasebandUSB.dylib' \
        --exclude='usr/lib/libBBUpdaterDynamic.dylib' \
        --exclude='usr/lib/libCRFSuite.dylib' \
        --exclude='usr/lib/libFDR.dylib' \
        --exclude='usr/lib/libH5Dynamic.dylib' \
        --exclude='usr/lib/libIOAccessoryManager.dylib' \
        --exclude='usr/lib/libKTLDynamic.dylib' \
        --exclude='usr/lib/libmav_ipc_router_dynamic.dylib' \
        --exclude='usr/lib/libPCITransport.dylib' \
        --exclude='usr/lib/libQMIParserDynamic.dylib' \
        --exclude='usr/lib/libReverseProxyDevice.dylib' \
        --exclude='usr/lib/libTelephony*.dylib' \
        --exclude='usr/lib/libTiSerialFlasher.dylib' \
        --exclude='usr/local' \
        --exclude='usr/share/progressui' \
        --exclude='usr/standalone' \
        --exclude='usr/bin/*' \
        --exclude='usr/sbin/*' \
        --exclude='usr/libexec/*' \
        --exclude='bin/*' \
        --exclude='sbin/*' \
        --exclude='mnt*' \
        "$mount_point/" "$RAMDISK_ROOT/"
    hdiutil detach "$mount_point" >/dev/null
    rm -rf "$mount_point"
    trap - EXIT HUP INT TERM

    if [ ! -d "$RAMDISK_ROOT/System/Library" ]; then
        echo "Ramdisk setup failed: missing System/Library in $RAMDISK_ROOT" >&2
        exit 1
    fi
}

make_ramdisk_writable() {
    # The restore image intentionally contains 0444/0555 entries.  rsync -aH
    # preserves those modes, and the openrsync shipped by macOS does not apply
    # relative --chmod expressions reliably.  Add only owner-write permission
    # after copying: this keeps executable and special bits intact, does not
    # follow symlinks, and also repairs RootFS trees created by older runs.
    find "$RAMDISK_ROOT" -xdev \( -type f -o -type d \) \
        ! -perm -u+w -exec chmod u+w {} +

    read_only_path=$(find "$RAMDISK_ROOT" -xdev \( -type f -o -type d \) \
        ! -perm -u+w -print -quit)
    if [ -n "$read_only_path" ]; then
        echo "Ramdisk path remains read-only: $read_only_path" >&2
        exit 1
    fi
}

if [ ! -d "$RAMDISK_ROOT/System/Library" ]; then
    setup_ramdisk
fi
make_ramdisk_writable
if [ -n "$IOS_SYSTEM_ROOT" ] && [ ! -d "$IOS_SYSTEM_ROOT/System/Library" ]; then
    echo "iOS system root is unavailable: $IOS_SYSTEM_ROOT" >&2
    exit 1
fi

framework_count=0
framework_names=
for source_dir in \
    "$REPO_ROOT"/GuestFrameworks/* \
    "$REPO_ROOT"/GuestFrameworks/.generated/*; do
    [ -d "$source_dir" ] || continue
    framework_name=${source_dir##*/}
    case " $framework_names " in
        *" $framework_name "*) continue ;;
    esac
    framework_names="$framework_names $framework_name"
done

for framework_name in $framework_names; do
    source_dir="$REPO_ROOT/GuestFrameworks/$framework_name"
    if [ ! -d "$source_dir" ]; then
        source_dir="$REPO_ROOT/GuestFrameworks/.generated/$framework_name"
    fi
    source_binary="$BUILD_ROOT/$framework_name.framework/$framework_name"

    case "$framework_name" in
        AVFAudio)
            relative_bundle=System/Library/Frameworks/AVFAudio.framework
            ;;
        FileProvider)
            relative_bundle=System/Library/PrivateFrameworks/FileProvider.framework
            ;;
        LC32)
            relative_bundle=System/Library/Frameworks/LC32.framework
            ;;
        *)
            relative_bundle="System/Library/Frameworks/$framework_name.framework"
            ;;
    esac

    if [ "$framework_name" = LC32 ]; then
        source_plist="$REPO_ROOT/GuestFrameworks/LC32/Info.plist"
    elif [ -n "$IOS_SYSTEM_ROOT" ]; then
        source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
        if [ "$framework_name" = AVFAudio ] && [ ! -f "$source_plist" ]; then
            source_plist="$IOS_SYSTEM_ROOT/System/Library/Frameworks/AVFoundation.framework/Frameworks/AVFAudio.framework/Info.plist"
        fi
    else
        source_plist="$FRAMEWORK_INFO_ROOT/$framework_name.plist"
    fi

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
    if [ "$source_plist" != "$destination_bundle/Info.plist" ]; then
        install -m 0644 "$source_plist" "$destination_bundle/Info.plist"
    fi
    install -m 0755 "$source_binary" "$destination_binary"
    if ! cmp -s "$source_binary" "$destination_binary"; then
        echo "Installed framework differs from build: $framework_name" >&2
        exit 1
    fi

    framework_count=$((framework_count + 1))
done

# Guest C libraries are plain dylibs installed straight into /usr/lib of the
# guest root. The restore ramdisk does not ship libiconv.2.dylib, so the
# locally built one is required by any app linking -liconv.
libiconv_binary="$REPO_ROOT/GuestLibraries/libiconv/.theos/obj/armv7s/libiconv.2.dylib"
if [ ! -f "$libiconv_binary" ]; then
    echo "Missing built library: $libiconv_binary" >&2
    exit 1
fi
libiconv_id=$(otool -D "$libiconv_binary" | tail -n 1)
if [ "$libiconv_id" != "/usr/lib/libiconv.2.dylib" ]; then
    echo "Unexpected install name for libiconv.2: $libiconv_id" >&2
    echo "Expected: /usr/lib/libiconv.2.dylib" >&2
    exit 1
fi
install -d -m 0755 "$RAMDISK_ROOT/usr/lib"
install -m 0755 "$libiconv_binary" "$RAMDISK_ROOT/usr/lib/libiconv.2.dylib"

avfaudio_link="$RAMDISK_ROOT/System/Library/Frameworks/AVFoundation.framework/libAVFAudio.dylib"
avfaudio_target=Frameworks/AVFAudio.framework/AVFAudio
avfaudio_compat_bundle="$RAMDISK_ROOT/System/Library/Frameworks/AVFoundation.framework/Frameworks/AVFAudio.framework"
avfaudio_source="$BUILD_ROOT/AVFAudio.framework/AVFAudio"
install -d -m 0755 "$avfaudio_compat_bundle"
install -m 0755 "$avfaudio_source" "$avfaudio_compat_bundle/AVFAudio"
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

echo "Installed and verified $framework_count guest frameworks and libiconv.2 in $RAMDISK_ROOT"
