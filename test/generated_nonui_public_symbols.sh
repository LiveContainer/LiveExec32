#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
object_root=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s"}
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-nonui-symbols.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

frameworks="CoreData CoreLocation CoreTelephony GameKit StoreKit Social iAd"
total_expected=0
total_missing=0

for framework in $frameworks; do
    headers="$sdk/System/Library/Frameworks/$framework.framework/Headers"
    tbd="$sdk/System/Library/Frameworks/$framework.framework/$framework.tbd"
    image="$object_root/$framework.framework/$framework"
    ast="$audit_dir/$framework.ast"
    header_symbols="$audit_dir/$framework.header"
    tbd_symbols="$audit_dir/$framework.tbd"
    expected_symbols="$audit_dir/$framework.expected"
    actual_symbols="$audit_dir/$framework.actual"
    missing_symbols="$audit_dir/$framework.missing"

    test -d "$headers" || {
        echo "$framework: missing iOS 10.3 public headers" >&2
        exit 1
    }
    test -f "$tbd" || {
        echo "$framework: missing iOS 10.3 TBD" >&2
        exit 1
    }
    test -f "$image" || {
        echo "$framework: missing built guest image at $image" >&2
        exit 1
    }

    set -- clang -target armv7s-apple-ios10.3 -isysroot "$sdk" \
        -fsyntax-only -x objective-c -Xclang -ast-dump
    if test -f "$headers/$framework.h"; then
        set -- "$@" -include "$framework/$framework.h"
    else
        # CoreTelephony 10.3 has no umbrella header. Audit every public
        # framework header rather than silently producing an empty set.
        for header in "$headers"/*.h; do
            set -- "$@" -include "$framework/$(basename "$header")"
        done
    fi
    "$@" /dev/null > "$ast"

    perl -ne '
        if(/FunctionDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''/) {
            print "_$1\n";
        } elsif(/[^A-Za-z]VarDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''.* extern$/) {
            print "_$1\n";
        }
    ' "$ast" | sort -u > "$header_symbols"
    rg -o '_[A-Za-z$][A-Za-z0-9_$]*' "$tbd" \
        | sort -u > "$tbd_symbols"
    comm -12 "$header_symbols" "$tbd_symbols" > "$expected_symbols"

    # This batch has no exclusions: every header-and-TBD public data/function
    # export is either a value constant or a straightforward value function.
    nm -gU "$image" | awk '{print $NF}' | sort -u > "$actual_symbols"
    comm -23 "$expected_symbols" "$actual_symbols" > "$missing_symbols"

    expected=$(wc -l < "$expected_symbols" | tr -d ' ')
    missing=$(wc -l < "$missing_symbols" | tr -d ' ')
    total_expected=$((total_expected + expected))
    total_missing=$((total_missing + missing))
    printf '%-15s expected=%-3s missing=%s\n' \
        "$framework" "$expected" "$missing"
    if test "$missing" -ne 0; then
        sed 's/^/  /' "$missing_symbols"
    fi
done

printf 'total           expected=%-3s missing=%s\n' \
    "$total_expected" "$total_missing"
test "$total_expected" -eq 135
test "$total_missing" -eq 0
