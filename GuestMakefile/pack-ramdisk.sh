#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

RAMDISK_ROOT=${RAMDISK_ROOT:-"$REPO_ROOT/tmp/ramdisk"}
IOS_SYSTEM_ROOT=${IOS_SYSTEM_ROOT:-/Volumes/Greensburg14G60.N41N42N48N49OS}
BUILD_ROOT=${BUILD_ROOT:-"$SCRIPT_DIR/.theos/obj/debug/armv7s"}

# The guest root is the iOS 10.3.3 restore ramdisk.  If it has not been set
# up yet, download and decrypt it from the IPSW, then copy it into place
# with rsync -aH.  (7z would break the HFS symlinks and dylib hardlink
# pairs that the guest dyld relies on.)  This only runs once, before the
# first pack.
RAMDISK_IPSW_URL=${RAMDISK_IPSW_URL:-
    "http://appldnld.apple.com/ios10.3.3/091-23384-20170719-CA966D80-6977-11E7-9F96-3E9100BA0AE3/iPhone_4.0_32bit_10.3.3_14G60_Restore.ipsw"}
RAMDISK_IPSW_COMPONENT=${RAMDISK_IPSW_COMPONENT:-"058-75249-062.dmg"}
RAMDISK_SETUP_DIR=${RAMDISK_SETUP_DIR:-"$REPO_ROOT/tmp/ipsw"}

setup_ramdisk() {
    echo "Setting up guest ramdisk at $RAMDISK_ROOT" >&2
    mkdir -p "$RAMDISK_SETUP_DIR"
    encrypted_image="$RAMDISK_SETUP_DIR/$RAMDISK_IPSW_COMPONENT"
    decrypted_image="$RAMDISK_SETUP_DIR/ramdisk.dmg"

    if [ ! -f "$encrypted_image" ]; then
        echo "Downloading $RAMDISK_IPSW_COMPONENT from the iOS 10.3.3 IPSW" >&2
        download_attempt=1
        while :; do
            if (cd "$RAMDISK_SETUP_DIR" && pzb -g "$RAMDISK_IPSW_COMPONENT" "$RAMDISK_IPSW_URL") \
                    && [ -f "$encrypted_image" ]; then
                break
            fi
            download_attempt=$((download_attempt + 1))
            if [ "$download_attempt" -gt 3 ]; then
                echo "Failed to download $RAMDISK_IPSW_COMPONENT" >&2
                exit 1
            fi
            echo "Download failed; retrying ($download_attempt/3)" >&2
            sleep 2
        done
    fi

    if [ ! -f "$decrypted_image" ]; then
        echo "Decrypting ramdisk image" >&2
        xpwntool "$encrypted_image" "$decrypted_image" -k
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
        --exclude='System/Library/CoreServices/DumpPanic' \
        --exclude='System/Library/CoreServices/ReportCrash' \
        --exclude='System/Library/Extensions/*' \
        --exclude='System/Library/Filesystems/*' \
        --exclude='System/Library/Frameworks/*' \
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

if [ ! -d "$RAMDISK_ROOT/System/Library" ]; then
    setup_ramdisk
fi
if [ ! -d "$IOS_SYSTEM_ROOT/System/Library" ]; then
    echo "iOS system root is unavailable; reusing ramdisk metadata" >&2
    IOS_SYSTEM_ROOT=$RAMDISK_ROOT
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
            source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
            if [ ! -f "$source_plist" ]; then
                source_plist="$IOS_SYSTEM_ROOT/System/Library/Frameworks/AVFoundation.framework/Frameworks/AVFAudio.framework/Info.plist"
            fi
            ;;
        FileProvider)
            relative_bundle=System/Library/PrivateFrameworks/FileProvider.framework
            source_plist="$IOS_SYSTEM_ROOT/$relative_bundle/Info.plist"
            ;;
        LC32)
            relative_bundle=System/Library/Frameworks/LC32.framework
            source_plist="$REPO_ROOT/GuestFrameworks/LC32/Info.plist"
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

echo "Installed and verified $framework_count guest frameworks in $RAMDISK_ROOT"
