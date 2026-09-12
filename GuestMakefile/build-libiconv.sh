#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

COMMIT=${LC32_LIBICONV_COMMIT:-6bcfda8c4720659e855c04ce72a8335fb4a67b0b}
ARCHIVE=${LC32_LIBICONV_ARCHIVE:-"$REPO_ROOT/tmp/libiconv-$COMMIT.tar.gz"}
SOURCE_URL=${LC32_LIBICONV_URL:-"https://github.com/apple-oss-distributions/libiconv/archive/$COMMIT.tar.gz"}
EXPECTED_SHA256=${LC32_LIBICONV_SHA256:-22adfd2a93219669384a0cf603a6a738118015bf2e8d7fb09796ff8eafb192e6}
SDK_ROOT=${LC32_GUEST_SDK:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
OUTPUT=${LC32_LIBICONV_OUTPUT:-"$SCRIPT_DIR/.theos/obj/armv7s/libiconv.2.dylib"}
WORK_ROOT=${LC32_LIBICONV_WORK_ROOT:-"$REPO_ROOT/tmp/libiconv-$COMMIT"}
SOURCE_ROOT="$WORK_ROOT/libiconv-$COMMIT"
BUILD_ROOT="$WORK_ROOT/build"
LOCK_FILE="$WORK_ROOT.lock"

# The new Xcode linker can drop ARM32 Thumb bits from initializer pointers.
# Select a real classic linker, not the ignored modern -ld_classic switch.
GUEST_LINKER=${LC32_GUEST_LINKER:-}
if [ -z "$GUEST_LINKER" ]; then
    GUEST_LINKER=$(xcrun --find ld-classic 2>/dev/null || true)
fi
if [ -z "$GUEST_LINKER" ]; then
    echo "Classic ARM32 linker unavailable: xcrun --find ld-classic failed" >&2
    echo "Select a toolchain with ld-classic or set LC32_GUEST_LINKER=/absolute/path/to/ld-classic" >&2
    exit 1
fi
if [ ! -f "$GUEST_LINKER" ] || [ ! -x "$GUEST_LINKER" ]; then
    echo "ARM32 guest linker is not an executable file: $GUEST_LINKER" >&2
    exit 1
fi

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
    expected_prefix="libiconv-$COMMIT"
    tar -tzf "$1" | awk -v prefix="$expected_prefix" '
        BEGIN { entries = 0 }
        {
            name = $0
            sub(/^\.\//, "", name)
            if (name != prefix "/" && index(name, prefix "/") != 1)
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

validate_source() {
    candidate=$1
    [ -f "$candidate/libiconv/lib/iconv.c" ] &&
        [ -f "$candidate/libiconv/libcharset/lib/localcharset.c" ] &&
        [ -f "$candidate/libiconv/libcharset/lib/relocatable.c" ] &&
        [ -f "$candidate/libiconv/lib/charset.alias" ] &&
        [ -f "$candidate/libiconv/COPYING.LIB" ]
}

mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$OUTPUT")"

# The guest build can be invoked in parallel with several framework targets.
# Keep extraction and compilation atomic without relying on a stale lock file.
if [ "${LC32_LIBICONV_LOCKED:-0}" != 1 ] && command -v lockf >/dev/null 2>&1; then
    LC32_LIBICONV_LOCKED=1 exec lockf -k "$LOCK_FILE" "$0"
fi

if [ ! -f "$SDK_ROOT/usr/lib/libSystem.tbd" ]; then
    echo "iOS 10.3 guest SDK is unavailable: $SDK_ROOT" >&2
    exit 1
fi

download_tmp=
stage=
output_tmp=
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    [ -z "$download_tmp" ] || rm -f "$download_tmp"
    [ -z "$stage" ] || rm -rf "$stage"
    [ -z "$output_tmp" ] || rm -f "$output_tmp"
    exit "$status"
}
trap cleanup EXIT HUP INT TERM

if ! verify_archive "$ARCHIVE"; then
    download_tmp=$(mktemp "$(dirname "$ARCHIVE")/.libiconv.tar.gz.XXXXXX")
    echo "Downloading Apple libiconv-50 source from $SOURCE_URL" >&2
    curl --fail --location --retry 3 --retry-delay 1 \
        --output "$download_tmp" "$SOURCE_URL"
    if ! verify_archive "$download_tmp"; then
        actual_sha256=$(archive_sha256 "$download_tmp" 2>/dev/null || echo unavailable)
        echo "Apple libiconv-50 checksum mismatch" >&2
        echo "  expected: $EXPECTED_SHA256" >&2
        echo "  actual:   $actual_sha256" >&2
        exit 1
    fi
    mv -f "$download_tmp" "$ARCHIVE"
    download_tmp=
fi

if ! validate_archive_layout "$ARCHIVE"; then
    echo "Unexpected paths in Apple libiconv-50 archive: $ARCHIVE" >&2
    exit 1
fi

if ! validate_source "$SOURCE_ROOT"; then
    if [ -e "$WORK_ROOT" ]; then
        echo "Existing libiconv work path is incomplete; refusing to replace it: $WORK_ROOT" >&2
        exit 1
    fi
    stage=$(mktemp -d "$(dirname "$WORK_ROOT")/.libiconv.stage.XXXXXX")
    tar -xzf "$ARCHIVE" -C "$stage"
    if ! validate_source "$stage/libiconv-$COMMIT"; then
        echo "Extracted Apple libiconv-50 source is incomplete" >&2
        exit 1
    fi
    mv "$stage" "$WORK_ROOT"
    stage=
fi

mkdir -p "$BUILD_ROOT"
CC=$(xcrun --find clang)

compile() {
    "$CC" -arch armv7s -isysroot "$SDK_ROOT" \
        -miphoneos-version-min=10.3 -Os -fPIC -fvisibility=default \
        -std=gnu89 -Wno-deprecated-non-prototype \
        -DHAVE_CONFIG_H -DBUILDING_LIBICONV -DBUILDING_LIBCHARSET \
        -DBUILDING_DLL -DENABLE_RELOCATABLE -DIN_LIBRARY -DNO_XMALLOC -DPIC \
        -Drelocate=libiconv_relocate \
        -Dset_relocation_prefix=libiconv_set_relocation_prefix \
        -I"$SOURCE_ROOT/libiconv/libcharset" \
        -I"$SOURCE_ROOT/libiconv/include" \
        -I"$SOURCE_ROOT/libiconv/lib" \
        -I"$SOURCE_ROOT/libiconv/libcharset/include" \
        -I"$SOURCE_ROOT/libiconv/libcharset/lib" \
        -c "$1" -o "$2"
}

compile "$SOURCE_ROOT/libiconv/lib/iconv.c" "$BUILD_ROOT/iconv.o"
compile "$SOURCE_ROOT/libiconv/libcharset/lib/localcharset.c" \
    "$BUILD_ROOT/localcharset.o"
compile "$SOURCE_ROOT/libiconv/libcharset/lib/relocatable.c" \
    "$BUILD_ROOT/relocatable.o"

# Xcode's Apple-generic versioning step generated these two public symbols in
# the iOS 10.3.3 system image. Define them explicitly when building without
# Apple's internal CoreOS makefiles.
cat > "$BUILD_ROOT/version.c" <<'EOF'
__attribute__((visibility("default"), used))
const unsigned char __iconv_2VersionString[] =
    "@(#)PROGRAM:iconv.2  PROJECT:libiconv-50\n";

__attribute__((visibility("default"), used))
const double __iconv_2VersionNumber = 50.0;
EOF
compile "$BUILD_ROOT/version.c" "$BUILD_ROOT/version.o"

output_tmp=$(mktemp "$(dirname "$OUTPUT")/.libiconv.2.dylib.XXXXXX")
"$CC" -arch armv7s -isysroot "$SDK_ROOT" -miphoneos-version-min=10.3 \
    -fuse-ld="$GUEST_LINKER" \
    -dynamiclib -Wl,-install_name,/usr/lib/libiconv.2.dylib \
    -Wl,-compatibility_version,7 -Wl,-current_version,7 -Wl,-dead_strip \
    "$BUILD_ROOT/iconv.o" "$BUILD_ROOT/localcharset.o" \
    "$BUILD_ROOT/relocatable.o" "$BUILD_ROOT/version.o" \
    -o "$output_tmp"
chmod 0755 "$output_tmp"
mv -f "$output_tmp" "$OUTPUT"
output_tmp=

install -m 0644 "$SOURCE_ROOT/libiconv/lib/charset.alias" \
    "$(dirname "$OUTPUT")/charset.alias"
install -m 0644 "$SOURCE_ROOT/libiconv/COPYING.LIB" \
    "$(dirname "$OUTPUT")/libiconv.LICENSE"

echo "Built Apple libiconv-50 for the armv7s guest: $OUTPUT" >&2
