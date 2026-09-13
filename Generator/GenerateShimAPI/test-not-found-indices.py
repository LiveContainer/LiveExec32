#!/usr/bin/env python3
"""Check index-sentinel generation without regenerating GuestFrameworks.

Uses the captured ARM32 signatures, plus isolated class/kind/width controls.
All generated sources and the native arithmetic harness live in one temporary
directory. Every child process has a timeout; no guest application is launched.
"""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
EXPECTED = {
    "NSArray": (
        "indexOfObject:", "indexOfObject:inRange:",
        "indexOfObjectIdenticalTo:", "indexOfObjectIdenticalTo:inRange:",
        "indexOfObjectPassingTest:", "indexOfObjectWithOptions:passingTest:",
        "indexOfObjectAtIndexes:options:passingTest:",
        "indexOfObject:inSortedRange:options:usingComparator:",
    ),
    "NSOrderedSet": (
        "indexOfObject:", "indexOfObjectPassingTest:",
        "indexOfObjectWithOptions:passingTest:",
        "indexOfObjectAtIndexes:options:passingTest:",
        "indexOfObject:inSortedRange:options:usingComparator:",
    ),
    "NSIndexSet": (
        "firstIndex", "lastIndex", "indexGreaterThanIndex:",
        "indexLessThanIndex:", "indexGreaterThanOrEqualToIndex:",
        "indexLessThanOrEqualToIndex:", "indexPassingTest:",
        "indexWithOptions:passingTest:", "indexInRange:options:passingTest:",
    ),
}
CONTROLS = {
    "NSArray": ("count", "hash", "indexOfObject:matchingComparison:",
                "indexOfSpecifierWithID:"),
    "NSOrderedSet": ("count", "hash", "indexOfObject:inRange:"),
    "NSIndexSet": ("count", "hash", "rangeCount"),
}
NARROW = "host_ret == INT64_MAX ? INT32_MAX : host_ret"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(arguments, *, timeout=30):
    result = subprocess.run([str(arg) for arg in arguments], timeout=timeout,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True)
    require(result.returncode == 0,
            f"Command failed ({result.returncode}): {arguments}\n{result.stdout}")
    return result.stdout


def methods(path):
    result = {}
    pattern = r"^([+-]) \([^\n]+?\)([^\n]+) \{\n(.*?)^\}"
    for match in re.finditer(pattern, path.read_text(), re.M | re.S):
        kind, declaration, body = match.groups()
        selector = "".join(re.findall(r"([A-Za-z_]\w*:)", declaration))
        selector = selector or declaration.strip()
        key = (kind, selector)
        require(key not in result, f"Duplicate method {path}: {key}")
        result[key] = body
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true",
                        help="reuse a generator just built from current sources")
    args = parser.parse_args()
    if not args.skip_build:
        print(run(["sh", HERE / "build.sh"], timeout=180), end="")

    captured = plistlib.loads((HERE.parent / "templates/generated.plist").read_bytes())["Foundation"]
    selected = {}
    unrelated = {}
    for name, selectors in EXPECTED.items():
        original = captured[name]["-"]
        require(all(original[selector].startswith("I") for selector in selectors),
                f"Captured {name} index signatures no longer have the expected ARM32 width")
        target = {selector: original[selector] for selector in selectors}
        instance = dict(target)
        instance.update({selector: original[selector] for selector in CONTROLS[name]})
        selected[name] = {
            "-": instance,
            # A same-named class method must never inherit the instance policy.
            "+": dict(target),
        }
        unrelated.update(target)
    selected["LC32IndexSentinelFixture"] = {"-": unrelated}

    fixtures = {"Captured": selected}
    # Keep the actual argument lists while varying only the return encoding.
    for encoding in "iIlLqQfdB@":
        # Numeric names stay distinct on the usual case-insensitive volume.
        fixtures[f"Encoding_{ord(encoding)}"] = {
            name: {"-": {selector: encoding + captured[name]["-"][selector][1:]
                         for selector in selectors}}
            for name, selectors in EXPECTED.items()
        }

    with tempfile.TemporaryDirectory(prefix="LiveExec32-IndexSentinels-") as directory:
        root = Path(directory)
        fixture = root / "signatures.plist"
        fixture.write_bytes(plistlib.dumps(fixtures))
        print(run([HERE / "GenerateShimObjC", fixture, root / "generated"]), end="")
        checks = 0
        expressions = set()
        for framework, classes in fixtures.items():
            for name, kinds in classes.items():
                source = root / "generated" / framework / f"{name}.m"
                generated = methods(source)
                for kind, signatures in kinds.items():
                    for selector, encoding in signatures.items():
                        key = (kind, selector)
                        require(key in generated, f"Missing generated {framework}/{name} {key}")
                        body = generated[key]
                        expected = (name in EXPECTED and selector in EXPECTED[name]
                                    and kind == "-" and encoding[0] in "iIlL")
                        require((NARROW in body) == expected,
                                f"Incorrect sentinel policy: {framework}/{name} {key} {encoding}")
                        if expected:
                            require("unhandled type" not in body,
                                    f"Index method was disabled: {framework}/{name} {key}")
                            expression = re.search(r"return ([^;]+);", body)
                            require(expression, f"Missing return expression: {source} {key}")
                            expressions.add(expression.group(1))
                        checks += 1

        # Execute the expressions actually emitted for all four 32-bit integer
        # spellings. Ordinary values and all-ones/-1 must remain normal casts;
        # only the native NSIntegerMax sentinel is translated.
        require(len(expressions) == 4, f"Expected four integral spellings, got {expressions}")
        functions = "\n".join(
            f"static uint32_t narrow_{i}(uint64_t host_ret) {{ return {expression}; }}"
            for i, expression in enumerate(sorted(expressions)))
        calls = "\n".join(
            f"if(narrow_{i}(value) != expected) return {i + 1};"
            for i in range(len(expressions)))
        harness = root / "narrow.c"
        harness.write_text("#include <stdint.h>\n#include <stddef.h>\n" + functions + "\n" +
            "int main(void) {\n"
            "const uint64_t values[] = {0, 1, 42, INT32_MAX - 1, INT32_MAX, "
            "UINT32_MAX, UINT64_C(0x123456789), INT64_MAX, UINT64_MAX};\n"
            "for(size_t i = 0; i < sizeof(values)/sizeof(values[0]); ++i) {\n"
            "uint64_t value = values[i];\n"
            "uint32_t expected = value == INT64_MAX ? INT32_MAX : (uint32_t)value;\n" +
            calls + "\n}\nreturn 0;\n}\n")
        run(["xcrun", "--sdk", "macosx", "clang", "-std=c11", "-Wall", "-Wextra",
             "-Werror", harness, "-o", root / "narrow"])
        run([root / "narrow"])
        print(f"GenerateShimAPI index sentinels: PASS ({checks} method gates; "
              f"{len(expressions) * 9} native arithmetic checks)")


if __name__ == "__main__":
    main()
