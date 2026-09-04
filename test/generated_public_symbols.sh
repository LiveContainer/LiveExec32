#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
object_root=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s"}
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-generated-symbols.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

frameworks="Contacts CoreImage CoreSpotlight HealthKit HomeKit NetworkExtension GLKit AddressBookUI"
total_expected=0
total_missing=0

expected_baseline() {
    case $1 in
        Contacts) echo 102 ;;
        CoreImage) echo 177 ;;
        CoreSpotlight) echo 14 ;;
        HealthKit) echo 155 ;;
        HomeKit) echo 211 ;;
        NetworkExtension) echo 12 ;;
        GLKit) echo 34 ;;
        AddressBookUI) echo 24 ;;
        *) return 1 ;;
    esac
}

for framework in $frameworks; do
    ast="$audit_dir/$framework.ast"
    header_raw="$audit_dir/$framework.header.raw"
    header_symbols="$audit_dir/$framework.header"
    tbd_raw="$audit_dir/$framework.tbd.raw"
    tbd_symbols="$audit_dir/$framework.tbd"
    public_symbols="$audit_dir/$framework.public"
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
    comm -12 "$header_symbols" "$tbd_symbols" > "$public_symbols"

    case "$framework" in
        CoreImage)
            # These declarations are explicitly unavailable on iOS 10.3.
            grep -Ev '^_(kCIFormatRGBA16|kCIImageTexture(Target|Format)|kCIApplyOption(Extent|Definition|UserInfo|ColorSpace))$' \
                "$public_symbols" > "$expected_symbols"
            ;;
        GLKit)
            # `index` is a libc re-export, not GLKit API. Matrix-stack calls
            # are the one stateful opaque-CF family intentionally deferred.
            grep -Ev '^(_index|_GLKMatrixStack)' \
                "$public_symbols" > "$expected_symbols"
            ;;
        *)
            cp "$public_symbols" "$expected_symbols"
            ;;
    esac

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
    printf '%-18s expected=%-3s missing=%s\n' \
        "$framework" "$expected" "$missing"
    if test "$missing" -ne 0; then
        sed 's/^/  /' "$missing_symbols"
    fi
done

printf 'total              expected=%-3s missing=%s\n' \
    "$total_expected" "$total_missing"
test "$total_expected" -eq 729
test "$total_missing" -eq 0
