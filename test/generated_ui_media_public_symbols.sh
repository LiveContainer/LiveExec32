#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
object_root=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s"}
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-ui-media-symbols.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

frameworks="UIKit QuartzCore CoreGraphics AVFoundation MediaPlayer"
total_public=0
total_excluded=0
total_expected=0
total_missing=0

set_baselines() {
    case $1 in
        UIKit)
            baseline_public=411
            baseline_excluded=11
            baseline_expected=400
            ;;
        QuartzCore)
            baseline_public=120
            baseline_excluded=0
            baseline_expected=120
            ;;
        CoreGraphics)
            baseline_public=505
            baseline_excluded=436
            baseline_expected=69
            ;;
        AVFoundation)
            baseline_public=862
            baseline_excluded=0
            baseline_expected=862
            ;;
        MediaPlayer)
            baseline_public=114
            baseline_excluded=2
            baseline_expected=112
            ;;
        *) return 1 ;;
    esac
}

for framework in $frameworks; do
    headers="$sdk/System/Library/Frameworks/$framework.framework/Headers"
    tbd="$sdk/System/Library/Frameworks/$framework.framework/$framework.tbd"
    image="$object_root/$framework.framework/$framework"
    ast="$audit_dir/$framework.ast"
    header_raw="$audit_dir/$framework.header.raw"
    header_symbols="$audit_dir/$framework.header"
    tbd_raw="$audit_dir/$framework.tbd.raw"
    tbd_symbols="$audit_dir/$framework.tbd"
    public_symbols="$audit_dir/$framework.public"
    expected_symbols="$audit_dir/$framework.expected"
    excluded_symbols="$audit_dir/$framework.excluded"
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
    rg -o '_[A-Za-z$][A-Za-z0-9_$]*' "$tbd" \
        > "$tbd_raw"
    LC_ALL=C sort -u "$tbd_raw" > "$tbd_symbols"
    comm -12 "$header_symbols" "$tbd_symbols" > "$public_symbols"

    case "$framework" in
        UIKit)
            # Block/selector callbacks need a dedicated lifetime bridge.  The
            # UIGraphics PDF calls operate on UIKit's implicit opaque current
            # PDF context, so that complete stateful family is deferred too.
            grep -Ev '^_(UIAccessibilityRequestGuidedAccessSession|UISaveVideoAtPathToSavedPhotosAlbum|UIGraphics(AddPDFContext|BeginPDF|EndPDF|GetPDFContext|SetPDFContext))' \
                "$public_symbols" > "$expected_symbols"
            ;;
        CoreGraphics)
            # These public families create, consume, or mutate opaque CG/CF
            # objects (several also install C callbacks).  The guest-native
            # batch intentionally covers value arithmetic and data constants,
            # not opaque contexts, paths, PDF scanners, providers, or peers.
            grep -Ev '^_(CGBitmapContext|CGColor(ConversionInfo|Space)?|CGContext|CGDataConsumer|CGDataProvider|CGFont|CGFunction|CGGradient|CGImage|CGLayer|CGPDF|CGPath|CGPattern|CGShading|CGPoint(CreateDictionaryRepresentation|MakeWithDictionaryRepresentation)|CGRect(CreateDictionaryRepresentation|MakeWithDictionaryRepresentation)|CGSize(CreateDictionaryRepresentation|MakeWithDictionaryRepresentation)|kCGColor(Black|Clear|White)$|kCGPDF)' \
                "$public_symbols" > "$expected_symbols"
            ;;
        MediaPlayer)
            # MediaPlayer's umbrella imports the C library declarations and
            # its TBD re-exports libc.  These are not MediaPlayer APIs.
            grep -Ev '^_(index|time)$' "$public_symbols" \
                > "$expected_symbols"
            ;;
        *)
            cp "$public_symbols" "$expected_symbols"
            ;;
    esac

    comm -23 "$public_symbols" "$expected_symbols" > "$excluded_symbols"
    nm -gU "$image" > "$audit_dir/$framework.nm"
    awk '{print $NF}' "$audit_dir/$framework.nm" \
        > "$audit_dir/$framework.actual.raw"
    LC_ALL=C sort -u "$audit_dir/$framework.actual.raw" \
        > "$actual_symbols"
    comm -23 "$expected_symbols" "$actual_symbols" > "$missing_symbols"

    public=$(awk 'END { print NR + 0 }' "$public_symbols")
    excluded=$(awk 'END { print NR + 0 }' "$excluded_symbols")
    expected=$(awk 'END { print NR + 0 }' "$expected_symbols")
    set_baselines "$framework"
    if test "$public" -ne "$baseline_public" ||
       test "$excluded" -ne "$baseline_excluded" ||
       test "$expected" -ne "$baseline_expected"; then
        echo "$framework: public symbol extraction changed: expected " \
            "$baseline_public/$baseline_excluded/$baseline_expected " \
            "public/excluded/required entries, got " \
            "$public/$excluded/$expected" >&2
        exit 1
    fi
    missing=$(awk 'END { print NR + 0 }' "$missing_symbols")
    total_public=$((total_public + public))
    total_excluded=$((total_excluded + excluded))
    total_expected=$((total_expected + expected))
    total_missing=$((total_missing + missing))
    printf '%-13s public=%-3s excluded=%-3s expected=%-3s missing=%s\n' \
        "$framework" "$public" "$excluded" "$expected" "$missing"
    if test "$missing" -ne 0; then
        sed 's/^/  /' "$missing_symbols"
    fi
done

printf 'total         public=%-3s excluded=%-3s expected=%-3s missing=%s\n' \
    "$total_public" "$total_excluded" "$total_expected" "$total_missing"
test "$total_public" -eq 2012
test "$total_excluded" -eq 449
test "$total_expected" -eq 1563
test "$total_missing" -eq 0
