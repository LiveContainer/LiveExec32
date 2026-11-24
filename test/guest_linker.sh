#!/bin/sh
# Compile with real modern ld, audit the outputs, optionally execute through an
# existing Catalyst runtime: LC32_TEST_RUNTIME=/path/to/LiveExec32.app/LiveExec32
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-modern-linker-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
sdk=${LC32_GUEST_SDK:-"$repo/tmp/iPhoneOS10.3.sdk"}
python3 "$repo/test/guest_linker.py" -v
compile() {
    xcrun clang -target armv7s-apple-ios10.3 -isysroot "$sdk" \
        "$@"
}
link() {
    compile --ld-path="$repo/Scripts/guest-ld" "$@"
}
for optimization in 0 2; do
    link -mthumb -O"$optimization" "$repo/test/guest_thumb_linker.c" -o "$work/thumb-O$optimization"
    sh "$repo/test/guest_thumb_linker.sh" "$work/thumb-O$optimization"
done
compile -marm -O2 -c "$repo/test/guest_linker_arm.c" -o "$work/arm.o"
link -mthumb -O0 -fblocks -fno-objc-arc -std=c++11 \
    -Wl,-export_dynamic -lc++ -framework Foundation \
    -Wl,-F,"$repo/GuestMakefile/.theos/obj/armv7s" \
    "$repo/test/guest_linker_mixed.mm" "$work/arm.o" -o "$work/mixed"
python3 "$repo/Scripts/arm32_thumb_fixups.py" "$work/mixed"

# A rejected invocation must not replace an existing output.
cp "$work/thumb-O0" "$work/unchanged"
if "$repo/Scripts/guest-ld" -arch armv7s -no_pie -o "$work/unchanged" \
        >"$work/rejected.log" 2>&1; then
    echo 'FAIL: non-PIE output was accepted' >&2; exit 1
fi
cmp "$work/thumb-O0" "$work/unchanged"
echo 'guest linker wrapper failure preserves previous output: PASS'

if [ -n "${LC32_TEST_RUNTIME:-}" ]; then
    for executable in "$work/thumb-O0" "$work/thumb-O2" "$work/mixed"; do
        perl -e 'alarm 30; exec @ARGV; die $!' "$LC32_TEST_RUNTIME" "$executable" >"$work/run.log" 2>&1 || {
            cat "$work/run.log"; exit 1;
        }
        cat "$work/run.log"
        ! grep -q ': FAIL' "$work/run.log"
        case "$executable" in
            */mixed) grep -q '^guest-linker-mixed: PASS$' "$work/run.log" ;;
            *) grep -q '^guest-thumb-computed-pointer: PASS$' "$work/run.log" ;;
        esac
    done
else
    echo 'guest linker runtime: SKIP (set LC32_TEST_RUNTIME to a Catalyst launcher)'
fi
