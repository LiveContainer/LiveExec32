#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/LiveExec32-ObjectOutPointers.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

# Allows the full-regeneration workflow to reuse the generator it just built.
if [ "${SKIP_GENERATOR_BUILD:-0}" != 1 ]; then
    "$SCRIPT_DIR/build.sh"
fi
"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/Tests/object-out-pointers.plist" "$TEMP_ROOT/captured" \
    >"$TEMP_ROOT/captured.log" 2>&1

# Keep the summary honest when runtime-derived classes contribute disabled
# methods too. A missing private UIKit class is host-version dependent; the
# checks below accept only the generator's documented unavailable-class exit.
runtime_status=0
"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/Tests/object-out-pointers.plist" "$TEMP_ROOT/runtime" \
    --runtime-uikit >"$TEMP_ROOT/runtime.log" 2>&1 || runtime_status=$?

"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/../templates/generated.plist" "$TEMP_ROOT/full" \
    --framework-map "$SCRIPT_DIR/../templates/generated-framework-map.plist" \
    >"$TEMP_ROOT/full.log" 2>&1

python3 - "$TEMP_ROOT" "$runtime_status" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
disabled_marker = "#if 0 // FIXME: has unhandled types"


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def methods(path):
    """Index generated methods together with their enclosing disabled guard."""
    source = path.read_text()
    result = {}
    pattern = r"(?m)^(#if 0 // FIXME: has unhandled types\n)?([+-]) ([^\n]+) \{\n(.*?)^\}"
    for match in re.finditer(pattern, source, re.S | re.M):
        guard, kind, declaration, body = match.groups()
        selector = "".join(re.findall(r"([A-Za-z][A-Za-z0-9_]*:)", declaration))
        require(selector, f"Unrecognized fixture method: {declaration}")
        key = kind + selector
        require(key not in result, f"Duplicate generated method: {key}")
        result[key] = (bool(guard), declaration, body)
    return result


fixture = methods(root / "captured/UIKit/LC32ObjectOutPointerFixture.m")


def enabled(key, table=fixture):
    require(key in table, f"Missing generated method: {key}")
    disabled, declaration, body = table[key]
    require(not disabled, f"Supported object output is still disabled: {key}")
    require("unhandled type" not in body, f"Unhandled enabled method: {key}")
    return declaration, body


def check_output(key, indices, table=fixture):
    declaration, body = enabled(key, table)
    for index in indices:
        arg = f"guest_arg{index}"
        host = f"host_arg{index}"
        for line in (
            f"uint64_t {host} = 0;",
            f"LC32HostIndirectArgument({arg} ? &{host} : NULL)",
            f"if({arg}) *{arg} = {host} ? LC32HostToGuestObject({host}) : nil;",
        ):
            require(line in body, f"Missing {key} output handling: {line}")
        require(f"[{arg} host_self]" not in body and f"*{arg} host_self" not in body,
                f"Output cell incorrectly reads a guest input value: {key}")
    require("LC32HostToGuestOwnedObject" not in body,
            f"Output incorrectly consumes host ownership: {key}")
    if declaration.startswith("(void)"):
        require("(void)LC32InvokeHostSelector(" in body and "host_ret" not in body,
                f"Void output method has an unused return value: {key}")
    return declaration, body


for name, spelling in (
    ("bareObject", "id *"), ("bareClass", "Class *"),
    ("outObject", "out id *"), ("outClass", "out Class *"),
):
    declaration, _ = check_output("-" + name + ":", [0])
    require(f"{name}:({spelling})guest_arg0" in declaration,
            f"Incorrect object output declaration: {declaration}")
check_output("+produceObject:", [0])
check_output("-produceObject:class:error:", [0, 1, 2])
_, body = check_output("-objectWithError:", [0])
require("id guest_ret = LC32InvokeHostObjectSelector(" in body and
        "return LC32ReturnBorrowedGuestObject(guest_ret);" in body,
        "Object-returning method lost borrowed return handling")

unsupported = (
    "constObject:", "inputObject:", "inoutObject:",
    "constClass:", "inputClass:", "inoutClass:",
    "constOutObject:", "outInputObject:", "nestedObject:",
    "outNestedClass:",
    "structurePointer:", "arrayPointer:", "functionPointer:",
    "complexPointer:", "consumeInputObjects:count:", "consumeConstClasses:count:",
)
for selector in unsupported:
    key = "-" + selector
    require(key in fixture, f"Unsupported method disappeared instead of being disabled: {key}")
    require(fixture[key][0], f"Unsafe pointer method is enabled: {key}")

for key, indices, count_index in (
    ("-consumeObjects:count:", [0], 1),
    ("-consumeObjects:forKeys:count:", [0, 1], 2),
):
    _, body = enabled(key)
    for index in indices:
        for line in (
            f"LC32CreateHostObjectArray(guest_arg{index}, (uint32_t)guest_arg{count_index}, {count_index})",
            f"LC32HostObjectArrayArgument(host_arg{index})",
            f"LC32DestroyHostObjectArray(host_arg{index});",
        ):
            require(line in body, f"Counted array staging regressed in {key}: {line}")
    require("LC32HostIndirectArgument" not in body and "LC32HostToGuestObject" not in body,
            f"Counted input array was treated as an object output: {key}")

plist = methods(root / "captured/UIKit/NSPropertyListSerialization.m")
manual_selectors = (
    "dataWithPropertyList:format:options:error:",
    "propertyListWithData:options:format:error:",
    "dataFromPropertyList:format:errorDescription:",
    "propertyListFromData:mutabilityOption:format:errorDescription:",
)
for selector in manual_selectors:
    require("+" + selector not in plist, f"Manual plist method was generated: +{selector}")
# Filtering must be scoped to the four class methods, not all plist error
# outputs, instance methods, or the same selector on another class.
check_output("+writePropertyList:toStream:format:options:error:", [4], plist)
check_output("-dataWithPropertyList:format:options:error:", [3], plist)
check_output("+dataWithPropertyList:format:options:error:", [3])

# These UIKit lifecycle methods must stay in the shared manual adapter. A
# generated end method would bypass expiration/duplicate-end bookkeeping.
application = (root / "full/UIKit/UIApplication.m").read_text()
for selector in (
    "beginBackgroundTaskWithExpirationHandler:",
    "beginBackgroundTaskWithName:",
    "endBackgroundTask:",
):
    require(selector not in application, f"Manual background-task method was generated: {selector}")
require("backgroundTimeRemaining" in application,
        "Background-task filtering accidentally removed other UIApplication methods")

for mode in ("captured", "runtime", "full"):
    log = (root / f"{mode}.log").read_text()
    summaries = re.findall(
        r"^Disabled (\d+) methods with unhandled types \(wrapped in #if 0\)\.$", log, re.M)
    require(len(summaries) == 1, f"Missing or duplicate disabled-method summary ({mode}):\n{log}")
    sources = [path.read_text() for path in (root / mode).rglob("*.m")]
    emitted = sum(source.count(disabled_marker) for source in sources)
    require(int(summaries[0]) == emitted,
            f"Disabled-method summary ({mode}) says {summaries[0]}, emitted {emitted}")
    if mode == "captured":
        require(emitted == len(unsupported),
                f"Expected only {len(unsupported)} unsupported fixture methods, got {emitted}")
    elif mode == "runtime":
        runtime_summary = re.search(r"added (\d+) runtime UIKit classes, (\d+) unavailable", log)
        require(runtime_summary, f"Missing runtime UIKit summary:\n{log}")
        generated, unavailable = map(int, runtime_summary.groups())
        require(int(sys.argv[2]) == (1 if unavailable else 0),
                f"Unexpected runtime generation failure:\n{log}")
        require("Could not " not in log and "Captured UIKit appearance method not found:" not in log,
                f"Runtime generation had errors besides unavailable classes:\n{log}")
        require(log.count("Runtime UIKit class not found:") == unavailable,
                f"Inconsistent unavailable-class summary:\n{log}")
        runtime_sources = [source for source in sources if "// WARNING: types came from" in source]
        require(len(runtime_sources) == generated,
                f"Runtime class summary does not match emitted sources:\n{log}")
        print(f"Disabled-method summary: {emitted} total, "
              f"{sum(source.count(disabled_marker) for source in runtime_sources)} from runtime extras")
        if unavailable:
            print(f"Runtime UIKit coverage: {unavailable} private classes unavailable on this host")
    else:
        # The captured-template baseline was 1855. Out-pointer support enables
        # 21 methods and manual plist filtering removes another four. Runtime
        # extras are excluded here because they vary with the host SDK.
        require(emitted <= 1830,
                f"Full captured-template disabled-method ratchet regressed: {emitted} > 1830")
        print(f"Full captured-template disabled-method ratchet: {emitted} <= 1830")
PY

# Compile the actual generated file, including mixed id/Class outputs and
# counted arrays, with the guest's 32-bit ABI and the production bridge header.
GUEST_SDK=${LC32_GUEST_SDK:-$REPO_ROOT/tmp/iPhoneOS10.3.sdk}
if [ -d "$GUEST_SDK" ]; then
    CLANG=$(xcrun --sdk macosx --find clang)
    "$CLANG" -target armv7s-apple-ios10.3 -isysroot "$GUEST_SDK" \
        -fsyntax-only -fobjc-arc -fblocks -fmodules \
        -fmodules-cache-path="$TEMP_ROOT/module-cache" \
        -Wall -Wextra -Werror -Wno-deprecated-declarations \
        -Wno-deprecated-module-dot-map \
        -I"$REPO_ROOT/include" -I"$REPO_ROOT/GuestFrameworks" \
        -include "$SCRIPT_DIR/Tests/object-out-pointers.h" \
        "$TEMP_ROOT/captured/UIKit/LC32ObjectOutPointerFixture.m"
    echo "Generated object output ARMv7 syntax: PASS"
else
    echo "Generated object output ARMv7 syntax: SKIP (guest SDK missing: $GUEST_SDK)"
fi

echo "GenerateShimAPI object out pointer fixture: PASS"
