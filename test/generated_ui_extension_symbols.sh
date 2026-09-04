#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
FRAMEWORKS="ContactsUI CoreAudioKit EventKitUI HealthKitUI Messages MetalKit NotificationCenter PhotosUI QuickLook UserNotificationsUI"

WORK_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-ui-extension-symbols.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

expected_count() {
    case $1 in
        Messages) echo 2 ;;
        MetalKit) echo 22 ;;
        *) echo 0 ;;
    esac
}

total=0
for framework in $FRAMEWORKS; do
    image="$FRAMEWORK_DIR/$framework.framework/$framework"
    tbd="$SDKROOT/System/Library/Frameworks/$framework.framework/$framework.tbd"
    if [ ! -f "$image" ] || [ ! -f "$tbd" ]; then
        echo "$framework image or SDK stub is missing" >&2
        exit 1
    fi

    xcrun clang -target armv7-apple-ios10.3 -isysroot "$SDKROOT" \
        -fno-modules -fsyntax-only -x objective-c \
        -include "$framework/$framework.h" -Xclang -ast-dump /dev/null \
        > "$WORK_DIR/$framework.ast"

    FRAMEWORK="$framework" perl -ne '
        $framework = $ENV{"FRAMEWORK"};
        if(/VarDecl .*\Q$framework.framework\/Headers\/\E.*\b(?:used )?([A-Za-z_]\w*) \x27[^\x27]+\x27(?:\x3a\x27[^\x27]+\x27)? extern$/) {
            print "$1\n";
        } elsif(/FunctionDecl .*\Q$framework.framework\/Headers\/\E.*\b([A-Za-z_]\w*) \x27[^\x27]+\x27/) {
            print "$1\n";
        }
    ' "$WORK_DIR/$framework.ast" | LC_ALL=C sort -u \
        > "$WORK_DIR/$framework.declared"

    xcrun nm -gjU "$tbd" 2>/dev/null | sed 's/^_//' | LC_ALL=C sort -u \
        > "$WORK_DIR/$framework.sdk-exports"
    awk 'NR == FNR { exported[$0] = 1; next }
         $0 in exported { print }' \
        "$WORK_DIR/$framework.sdk-exports" \
        "$WORK_DIR/$framework.declared" \
        > "$WORK_DIR/$framework.expected"

    count=$(wc -l < "$WORK_DIR/$framework.expected" | tr -d ' ')
    known_count=$(expected_count "$framework")
    if [ "$count" -ne "$known_count" ]; then
        echo "$framework SDK audit found $count symbols; expected $known_count" >&2
        exit 1
    fi

    xcrun nm -gjU "$image" | sed 's/^_//' | LC_ALL=C sort -u \
        > "$WORK_DIR/$framework.actual"
    comm -23 "$WORK_DIR/$framework.expected" \
        "$WORK_DIR/$framework.actual" > "$WORK_DIR/$framework.missing"
    if [ -s "$WORK_DIR/$framework.missing" ]; then
        echo "$framework is missing public guest symbols:" >&2
        sed 's/^/  /' "$WORK_DIR/$framework.missing" >&2
        exit 1
    fi

    total=$((total + count))
    echo "$framework generated UI symbol audit: PASS ($count exports)"
done

echo "Generated UI extension framework symbol audit: PASS ($total exports)"
