#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/LiveExec32-SimpleStructs.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

if [ "${SKIP_GENERATOR_BUILD:-0}" != 1 ]; then
    "$SCRIPT_DIR/build.sh"
fi
"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/Tests/simple-structs.plist" "$TEMP_ROOT/generated"

# Compile the generated method bodies, not copies of their marshalling logic.
# A native recorder checks the converted payloads; it does not emulate SVC or
# claim to test the ARM32/ARM64 register trampoline.
python3 - "$TEMP_ROOT" "$SCRIPT_DIR" <<'PY'
from pathlib import Path
import plistlib
import re
import subprocess
import sys

root = Path(sys.argv[1])
fixtures = root / "generated/UIKit"
for name, disabled in (("LC32SimpleStructFixture", False),
                       ("LC32UnsupportedStructFixture", True)):
    source = (fixtures / f"{name}.m").read_text()
    methods = re.findall(
        r"(?m)^(#if 0 // FIXME: has unhandled types\n)?- ([^\n]+) \{\n(.*?)^\}",
        source, re.S | re.M)
    expected = 9 if disabled else 17
    assert len(methods) == expected, (name, len(methods))
    for guard, declaration, body in methods:
        assert bool(guard) == disabled, (name, declaration, "wrong guard")
        assert ("unhandled type" in body) == disabled, declaration
    implementation = source[source.index("@implementation "):source.rindex("@end") + 4]
    (root / f"{name}.inc").write_text(implementation + "\n")
    if not disabled:
        (root / "arm32.m").write_text(
            "#import <UIKit/UIKit+LC32.h>\n#import <CoreLocation/CLLocation.h>\n"
            f"@interface {name} : NSObject\n" +
            "\n".join(f"- {declaration};" for _, declaration, _ in methods) +
            "\n@end\n" + implementation + "\n")

# Runtime-captured 64-bit encodings should select the same conversions.
script = Path(sys.argv[2])
fixture = plistlib.loads((script / "Tests/simple-structs.plist").read_bytes())
methods = fixture["UIKit"]["LC32SimpleStructFixture"]["-"]
for selector, encoding in methods.items():
    methods[selector] = re.sub(
        r"\{(CGPoint|CGSize|CGVector|UIOffset|UIEdgeInsets|CGAffineTransform)=(f+)\}",
        lambda match: "{" + match[1] + "=" + "d" * len(match[2]) + "}", encoding)
native_fixture = root / "native-encodings.plist"
native_fixture.write_bytes(plistlib.dumps(fixture))
subprocess.run([str(script / "GenerateShimObjC"), str(native_fixture),
                str(root / "native")], check=True)
assert (root / "native/UIKit/LC32SimpleStructFixture.m").read_text() == (
    fixtures / "LC32SimpleStructFixture.m").read_text(), "native encodings changed conversions"
PY

mkdir -p "$TEMP_ROOT/stubs/LC32"
# The fixture supplies only the bridge entry points it exercises.
printf '\n' > "$TEMP_ROOT/stubs/LC32/LC32.h"
MACOSX_SDK_DIR=$(xcrun --sdk macosx --show-sdk-path)
xcrun --sdk macosx clang -target arm64-apple-ios13.1-macabi \
    -isysroot "$MACOSX_SDK_DIR" \
    -isystem "$MACOSX_SDK_DIR/System/iOSSupport/usr/include" \
    -iframework "$MACOSX_SDK_DIR/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -Wall -Wextra -Werror -Wno-incomplete-implementation \
    -I"$TEMP_ROOT/stubs" -I"$REPO_ROOT/GuestFrameworks" -I"$REPO_ROOT/include" -I"$TEMP_ROOT" \
    -framework Foundation -framework UIKit \
    "$SCRIPT_DIR/Tests/simple-structs.m" -o "$TEMP_ROOT/test"
"$TEMP_ROOT/test"

# Type-check against the real ARM32 headers without invoking a linker.
GUEST_SDK=${ISYSROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
if [ -d "$GUEST_SDK" ]; then
    xcrun clang -target armv7s-apple-ios10.0 -isysroot "$GUEST_SDK" \
        -fobjc-arc -fmodules -fmodules-cache-path="$TEMP_ROOT/modules" \
        -fsyntax-only -Werror -Wno-deprecated-declarations \
        -Wno-deprecated-module-dot-map \
        -I"$REPO_ROOT/GuestFrameworks" -I"$REPO_ROOT/include" \
        "$TEMP_ROOT/arm32.m"
    echo 'generated simple structs (ARM32 syntax): PASS'
else
    echo 'generated simple structs (ARM32 syntax): SKIP (guest SDK unavailable)'
fi
