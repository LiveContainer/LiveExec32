#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s/Accelerate.framework/Accelerate"}
expected='vDSP_dotpr vDSP_svesq vDSP_vadd vDSP_vdist vDSP_vdiv
vDSP_vintb vDSP_vmul vDSP_vsdiv vDSP_vsmul vDSP_vsub'
actual=$(nm -gU "$image" | awk '{print $NF}')
missing=0
for symbol in $expected; do
    if ! printf '%s\n' "$actual" | rg -q -F -x -- "_$symbol"; then
        echo "missing _$symbol" >&2
        missing=$((missing + 1))
    fi
done
test "$(otool -D "$image" | tail -n 1)" = \
    /System/Library/Frameworks/Accelerate.framework/Accelerate
echo "Accelerate required symbols: 10 expected, $missing missing"
test "$missing" -eq 0
