#!/bin/sh
# Recording stand-in for either a recursive make or the ramdisk packer.
set -eu
case "${0##*/}" in
    make)
        printf 'build %s\n' "$*" >> "$LC32_INSTALL_TEST_TRACE"
        [ "${LC32_INSTALL_TEST_BUILD_STATUS:-0}" -eq 0 ] || exit "$LC32_INSTALL_TEST_BUILD_STATUS"
        ;;
    pack-ramdisk.sh)
        printf 'pack root=%s build=%s mode=%s\n' \
            "${RAMDISK_ROOT:-}" "${BUILD_ROOT:-}" "${LC32_UIKIT_COMPATIBILITY:-}" \
            >> "$LC32_INSTALL_TEST_TRACE"
        exit "${LC32_INSTALL_TEST_PACK_STATUS:-0}"
        ;;
    *) exit 2 ;;
esac
