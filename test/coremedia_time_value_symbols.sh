#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${LC32_GUEST_SDK:-"$repo_root/tmp/iPhoneOS10.3.sdk"}
image=${1:-"$repo_root/GuestMakefile/.theos/obj/armv7s/CoreMedia.framework/CoreMedia"}
audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-coremedia-time.XXXXXX")
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

test -f "$image" || {
    echo "missing CoreMedia guest image: $image" >&2
    exit 1
}

clang -target armv7s-apple-ios10.3 -isysroot "$sdk" \
    -fsyntax-only -x objective-c -Xclang -ast-dump \
    -include CoreMedia/CoreMedia.h /dev/null > "$audit_dir/ast"
perl -ne '
    if(/FunctionDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''/) {
        print "_$1\n";
    } elsif(/[^A-Za-z]VarDecl.*\s([A-Za-z_\$][A-Za-z0-9_\$]*) '\''.* extern$/) {
        print "_$1\n";
    }
' "$audit_dir/ast" | sort -u > "$audit_dir/header"
rg -o '_[A-Za-z$][A-Za-z0-9_$]*' \
    "$sdk/System/Library/Frameworks/CoreMedia.framework/CoreMedia.tbd" \
    | sort -u > "$audit_dir/tbd"
comm -12 "$audit_dir/header" "$audit_dir/tbd" \
    | rg '^_(CMTime|kCMTime)' \
    | rg -v '^_(CMTime(Code|base)|kCMTime(Code|base))' \
    > "$audit_dir/expected"
nm -gU "$image" | awk '{print $NF}' | sort -u > "$audit_dir/actual"
comm -23 "$audit_dir/expected" "$audit_dir/actual" > "$audit_dir/missing"

expected=$(wc -l < "$audit_dir/expected" | tr -d ' ')
missing=$(wc -l < "$audit_dir/missing" | tr -d ' ')
printf 'CoreMedia time values expected=%s missing=%s\n' "$expected" "$missing"
if test "$missing" -ne 0; then
    sed 's/^/  /' "$audit_dir/missing"
fi
test "$expected" -eq 55
test "$missing" -eq 0
