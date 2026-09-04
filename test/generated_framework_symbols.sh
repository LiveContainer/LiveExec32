#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
FRAMEWORKS="Accounts AssetsLibrary CloudKit CoreBluetooth CoreMIDI Intents JavaScriptCore SceneKit"

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-generated-symbols.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

append_simple_functions() {
    case $1 in
        CoreMIDI)
            cat <<'EOF'
MIDIPacketListAdd
MIDIPacketListInit
MIDIThruConnectionParamsInitialize
kMIDIPropertyName
EOF
            ;;
        JavaScriptCore)
            cat <<'EOF'
JSStringCopyCFString
JSStringCreateWithCFString
JSStringCreateWithCharacters
JSStringCreateWithUTF8CString
JSStringGetCharactersPtr
JSStringGetLength
JSStringGetMaximumUTF8CStringSize
JSStringGetUTF8CString
JSStringIsEqual
JSStringIsEqualToUTF8CString
JSStringRelease
JSStringRetain
EOF
            ;;
        SceneKit)
            cat <<'EOF'
SCNMatrix4EqualToMatrix4
SCNMatrix4FromGLKMatrix4
SCNMatrix4Invert
SCNMatrix4IsIdentity
SCNMatrix4MakeRotation
SCNMatrix4Mult
SCNMatrix4Rotate
SCNMatrix4Scale
SCNMatrix4ToGLKMatrix4
SCNVector3EqualToVector3
SCNVector4EqualToVector4
EOF
            ;;
    esac
}

expected_baseline() {
    case $1 in
        Accounts) echo 13 ;;
        AssetsLibrary) echo 22 ;;
        CloudKit) echo 18 ;;
        CoreBluetooth) echo 31 ;;
        CoreMIDI) echo 50 ;;
        Intents) echo 66 ;;
        JavaScriptCore) echo 19 ;;
        SceneKit) echo 118 ;;
        *) return 1 ;;
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
        > "$work/$framework.ast" 2> "$work/$framework.ast.err"
    FRAMEWORK="$framework" perl -ne '
        if(/VarDecl .*\/\Q$ENV{FRAMEWORK}\E\.framework\/Headers\/.*\b(?:used )?([A-Za-z_]\w*) \x27[^\x27]+\x27(?:\x3a\x27[^\x27]+\x27)? extern$/) {
            print "$1\n";
        }
    ' "$work/$framework.ast" > "$work/$framework.declared.raw"
    LC_ALL=C sort -u "$work/$framework.declared.raw" \
        > "$work/$framework.declared"

    xcrun nm -gjU "$tbd" > "$work/$framework.sdk-nm" 2>/dev/null
    sed 's/^_//' "$work/$framework.sdk-nm" \
        > "$work/$framework.sdk-exports.raw"
    LC_ALL=C sort -u "$work/$framework.sdk-exports.raw" \
        > "$work/$framework.sdk-exports"
    awk 'NR == FNR { exported[$0] = 1; next }
         $0 in exported { print }' \
        "$work/$framework.sdk-exports" "$work/$framework.declared" \
        > "$work/$framework.constants.raw"
    sed -E \
            -e '/^(ACAccountTypeIdentifierLinkedIn|ACLinkedInAppIdKey|ACLinkedInPermissionsKey)$/d' \
            -e '/^(SCNSceneSourceConvertToYUpKey|SCNSceneSourceConvertUnitsToMetersKey)$/d' \
        "$work/$framework.constants.raw" \
        > "$work/$framework.constants"

    {
        cat "$work/$framework.constants"
        append_simple_functions "$framework"
    } > "$work/$framework.expected.raw"
    LC_ALL=C sort -u "$work/$framework.expected.raw" \
        > "$work/$framework.expected"
    xcrun nm -gjU "$image" > "$work/$framework.actual-nm"
    sed 's/^_//' "$work/$framework.actual-nm" \
        > "$work/$framework.actual.raw"
    LC_ALL=C sort -u "$work/$framework.actual.raw" \
        > "$work/$framework.actual"
    comm -23 "$work/$framework.expected" "$work/$framework.actual" \
        > "$work/$framework.missing"
    if [ -s "$work/$framework.missing" ]; then
        echo "$framework is missing public guest symbols:" >&2
        sed 's/^/  /' "$work/$framework.missing" >&2
        exit 1
    fi

    count=$(awk 'END { print NR + 0 }' "$work/$framework.expected")
    baseline=$(expected_baseline "$framework")
    if [ "$count" -ne "$baseline" ]; then
        echo "$framework public symbol extraction changed: " \
            "expected $baseline entries, got $count" >&2
        exit 1
    fi
    total=$((total + count))
    echo "$framework generated symbol audit: PASS ($count exports)"
done

if [ "$total" -ne 337 ]; then
    echo "Generated framework symbol baseline changed: " \
        "expected 337, got $total" >&2
    exit 1
fi
echo "Generated framework symbol audit: PASS ($total exports)"
