#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
image=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s/Foundation.framework/Foundation"}
headers="$sdk/System/Library/Frameworks/Foundation.framework/Headers"
tbd="$sdk/System/Library/Frameworks/Foundation.framework/Foundation.tbd"
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-foundation-public.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

test -d "$headers" || {
    echo "Foundation: missing iOS 10.3 public headers" >&2
    exit 1
}
test -f "$tbd" || {
    echo "Foundation: missing iOS 10.3 TBD" >&2
    exit 1
}
test -f "$image" || {
    echo "Foundation: missing built guest image at $image" >&2
    exit 1
}

clang -target armv7s-apple-ios10.3 -isysroot "$sdk" \
    -fsyntax-only -x objective-c -Xclang -ast-dump \
    -include Foundation/Foundation.h /dev/null > "$audit_dir/ast"
perl -ne '
    if(/FunctionDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''/) {
        print "_$1\n";
    } elsif(/[^A-Za-z]VarDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''.* extern$/) {
        print "_$1\n";
    }
' "$audit_dir/ast" | LC_ALL=C sort -u > "$audit_dir/header"
rg -o '_[A-Za-z$][A-Za-z0-9_$]*' "$tbd" | LC_ALL=C sort -u \
    > "$audit_dir/tbd"
comm -12 "$audit_dir/header" "$audit_dir/tbd" > "$audit_dir/public"

# NSDecimal passes a bitfield-heavy aggregate whose ARM32 ABI needs a
# dedicated bridge. The old object-copy/refcount helpers also expose runtime
# internals rather than simple Foundation wrappers. The three image/icon keys
# are marked unavailable on iOS (NS_AVAILABLE(..., NA)); the combined SDK TBD
# lists their macOS exports as well, so do not mistake them for iOS APIs.
grep -Ev '^_(NSCopyObject|NSDecimal(Add|Compact|Compare|Copy|Divide|Multiply|MultiplyByPowerOf10|Normalize|Power|Round|String|Subtract)|NS(DecrementExtraRefCountWasZero|ExtraRefCount|IncrementExtraRefCount)|NSProgressFile(AnimationImageKey|AnimationImageOriginalRectKey|IconKey))$' \
    "$audit_dir/public" > "$audit_dir/expected"
comm -23 "$audit_dir/public" "$audit_dir/expected" \
    > "$audit_dir/excluded"

nm -gU "$image" | awk '{print $NF}' | LC_ALL=C sort -u \
    > "$audit_dir/actual"
comm -23 "$audit_dir/expected" "$audit_dir/actual" \
    > "$audit_dir/missing"

public=$(wc -l < "$audit_dir/public" | tr -d ' ')
excluded=$(wc -l < "$audit_dir/excluded" | tr -d ' ')
expected=$(wc -l < "$audit_dir/expected" | tr -d ' ')
missing=$(wc -l < "$audit_dir/missing" | tr -d ' ')
printf 'Foundation public=%s excluded=%s expected=%s missing=%s\n' \
    "$public" "$excluded" "$expected" "$missing"

if test "$public" -ne 389 || test "$excluded" -ne 19 || \
   test "$expected" -ne 370; then
    echo "Foundation public API inventory changed unexpectedly" >&2
    sed 's/^/  excluded: /' "$audit_dir/excluded" >&2
    exit 1
fi
if test "$missing" -ne 0; then
    echo "Foundation guest image is missing public low-risk symbols:" >&2
    sed 's/^/  /' "$audit_dir/missing" >&2
    exit 1
fi

echo "Foundation public symbol audit: PASS (370 exports, 19 documented exclusions)"
