#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
object_root=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s"}
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-legacy-symbols.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

frameworks="NewsstandKit PushKit ReplayKit Speech Twitter"
total_expected=0
total_missing=0

expected_baseline() {
    case $1 in
        NewsstandKit) echo 1 ;;
        PushKit) echo 2 ;;
        ReplayKit) echo 1 ;;
        Speech | Twitter) echo 0 ;;
        *) return 1 ;;
    esac
}

for framework in $frameworks; do
    ast="$audit_dir/$framework.ast"
    header_raw="$audit_dir/$framework.header.raw"
    header_symbols="$audit_dir/$framework.header"
    tbd_raw="$audit_dir/$framework.tbd.raw"
    tbd_symbols="$audit_dir/$framework.tbd"
    expected_symbols="$audit_dir/$framework.expected"
    actual_symbols="$audit_dir/$framework.actual"
    missing_symbols="$audit_dir/$framework.missing"
    image="$object_root/$framework.framework/$framework"

    test -f "$image" || {
        echo "$framework: missing built framework at $image" >&2
        exit 1
    }

    clang -target armv7s-apple-ios10.3 -isysroot "$sdk" \
        -fsyntax-only -x objective-c -Xclang -ast-dump \
        -include "$framework/$framework.h" /dev/null > "$ast"
    perl -ne '
        if(/FunctionDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''/) {
            print "_$1\n";
        } elsif(/[^A-Za-z]VarDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''.* extern$/) {
            print "_$1\n";
        }
    ' "$ast" > "$header_raw"
    LC_ALL=C sort -u "$header_raw" > "$header_symbols"
    rg -o '_[A-Za-z$][A-Za-z0-9_$]*' \
        "$sdk/System/Library/Frameworks/$framework.framework/$framework.tbd" \
        > "$tbd_raw"
    LC_ALL=C sort -u "$tbd_raw" > "$tbd_symbols"
    comm -12 "$header_symbols" "$tbd_symbols" > "$expected_symbols"

    nm -gU "$image" > "$audit_dir/$framework.nm"
    awk '{print $NF}' "$audit_dir/$framework.nm" \
        > "$audit_dir/$framework.actual.raw"
    LC_ALL=C sort -u "$audit_dir/$framework.actual.raw" \
        > "$actual_symbols"
    comm -23 "$expected_symbols" "$actual_symbols" > "$missing_symbols"

    expected=$(awk 'END { print NR + 0 }' "$expected_symbols")
    baseline=$(expected_baseline "$framework")
    if test "$expected" -ne "$baseline"; then
        echo "$framework: public symbol extraction changed: " \
            "expected $baseline entries, got $expected" >&2
        exit 1
    fi
    missing=$(awk 'END { print NR + 0 }' "$missing_symbols")
    total_expected=$((total_expected + expected))
    total_missing=$((total_missing + missing))
    printf '%-14s expected=%-2s missing=%s\n' \
        "$framework" "$expected" "$missing"
    if test "$missing" -ne 0; then
        sed 's/^/  /' "$missing_symbols"
    fi
done

printf 'total          expected=%-2s missing=%s\n' \
    "$total_expected" "$total_missing"
test "$total_expected" -eq 4
test "$total_missing" -eq 0
