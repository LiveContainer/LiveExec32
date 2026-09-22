#!/bin/sh
# Exercise the actual dispatcher in an isolated directory, with no SDK, Theos,
# device access, ramdisk downloads, or changes to the real RootFS.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-guest-install.XXXXXX")
trap 'rm -rf -- "$workdir"' EXIT
cp "$repo_root/GuestMakefile/Makefile" "$workdir/Makefile"
cp "$repo_root/test/guest_install_fixture.sh" "$workdir/pack-ramdisk.sh"
cp "$repo_root/test/guest_install_fixture.sh" "$workdir/make"
chmod +x "$workdir/pack-ramdisk.sh" "$workdir/make"
make_tool=${LC32_TEST_MAKE:-gmake}
export LC32_INSTALL_TEST_TRACE="$workdir/trace"

run_make() {
    "$make_tool" --no-print-directory -C "$workdir" \
        THEOS="$workdir/no-theos" THEOS_DEVICE_IP=must-not-connect \
        PREINSTALL_TARGET_PROCESSES=must-not-kill INSTALL_TARGET_PROCESSES=must-not-kill \
        MAKE="$workdir/make" RAMDISK_ROOT="$workdir/root with spaces" \
        BUILD_ROOT="$workdir/products" LC32_UIKIT_COMPATIBILITY=0 "$@" \
        >"$workdir/output" 2>&1
}

run_make install
test "$(wc -l < "$LC32_INSTALL_TEST_TRACE" | tr -d ' ')" = 1
grep -Fxq "pack root=$workdir/root with spaces build=$workdir/products mode=0" "$LC32_INSTALL_TEST_TRACE"
echo 'PASS install only packs; overrides survive; Theos/device hooks are not loaded'

: > "$LC32_INSTALL_TEST_TRACE"
run_make -j8 all install
test "$(wc -l < "$LC32_INSTALL_TEST_TRACE" | tr -d ' ')" = 2
test "$(sed -n '1p' "$LC32_INSTALL_TEST_TRACE")" = 'build -f Makefile all'
grep -q '^pack ' "$LC32_INSTALL_TEST_TRACE"
echo 'PASS parallel all install builds once before packing'

: > "$LC32_INSTALL_TEST_TRACE"
run_make -j8 install clean all
test "$(sed -n '1p' "$LC32_INSTALL_TEST_TRACE")" = 'build -f Makefile clean all'
test "$(wc -l < "$LC32_INSTALL_TEST_TRACE" | tr -d ' ')" = 2
echo 'PASS multiple non-install goals retain order in one recursive make'

: > "$LC32_INSTALL_TEST_TRACE"
export LC32_INSTALL_TEST_BUILD_STATUS=7
if run_make -j8 all install; then
    echo 'FAIL build failure was ignored' >&2; exit 1
fi
test "$(wc -l < "$LC32_INSTALL_TEST_TRACE" | tr -d ' ')" = 1
grep -q '^build ' "$LC32_INSTALL_TEST_TRACE"
unset LC32_INSTALL_TEST_BUILD_STATUS
echo 'PASS build failure prevents packing'

: > "$LC32_INSTALL_TEST_TRACE"
export LC32_INSTALL_TEST_PACK_STATUS=9
if run_make install; then
    echo 'FAIL packer failure was ignored' >&2; exit 1
fi
grep -q '^pack ' "$LC32_INSTALL_TEST_TRACE"
echo 'PASS packer failure propagates'
