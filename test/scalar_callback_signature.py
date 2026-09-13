#!/usr/bin/env python3
"""Compile and exercise the actual scalar callback scanner without Foundation.

No Theos, prepared guest SDK, simulator, or network is required. The scanner is
extracted verbatim; this deliberately does not duplicate its parser logic.
"""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
START = "static bool LC32ScanScalarCallbackTypes("
END = "static bool LC32ScalarKindsMatch("
HEADERS = r"""
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/mman.h>
#include <unistd.h>
"""

HARNESS = r'''
static unsigned cases, failures;

static void run(const char *label, const char *types, bool expected,
                char expectedReturn = 0, const char *expectedArguments = "") {
    struct { unsigned char before; char kinds[6]; unsigned char after; }
        arguments = {0xa5, {}, 0x5a};
    struct { unsigned char before; char kind; unsigned char after; }
        result = {0xc3, 0, 0x3c};
    struct { uint32_t before; unsigned count; uint32_t after; }
        count = {0x12345678, 0, 0x87654321};
    bool accepted = LC32ScanScalarCallbackTypes(types, result.kind,
        arguments.kinds, count.count);
    bool passed = accepted == expected && arguments.before == 0xa5 &&
        arguments.after == 0x5a && result.before == 0xc3 && result.after == 0x3c &&
        count.before == 0x12345678 && count.after == 0x87654321;
    if(expected && accepted) {
        size_t expectedCount = strlen(expectedArguments);
        passed = passed && result.kind == expectedReturn && count.count == expectedCount &&
            memcmp(arguments.kinds, expectedArguments, expectedCount) == 0;
    }
    ++cases;
    if(!passed) {
        ++failures;
        fprintf(stderr, "scalar-callback-signature/%s: FAIL (accepted=%d, return=%c, count=%u)\n",
            label, accepted, result.kind ? result.kind : '?', count.count);
    }
}

int main() {
    // Exact signature captured from the old game's C++ method metadata. This
    // must be rejected by the scalar gate before Foundation sees its records.
    run("legacy-game-cpp-record",
        "v16@0:4i8r^{Message=^^?iI{PropertyList={map<std::basic_string<char>, Walaber::Property, std::less<std::basic_string<char> >, std::allocator<std::pair<const std::basic_string<char>, Walaber::Property> > >={_Rb_tree<std::basic_string<char>, std::pair<const std::basic_string<char>, Walaber::Property>, std::_Select1st<std::pair<const std::basic_string<char>, Walaber::Property> >, std::less<std::basic_string<char> >, std::allocator<std::pair<const std::basic_string<char>, Walaber::Property> > >={_Rb_tree_impl<std::less<std::basic_string<char> >, false>={less<std::basic_string<char> >=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_node_base}^{_Rb_tree_node_base}}I}}}}}12",
        false);
    const char *scalarKinds = "BcCsSiIlLqQfd@#:";
    for(const char *kind = scalarKinds; *kind; ++kind) {
        std::string label = std::string("return-") + *kind;
        std::string signature = std::string(1, *kind) + "@:i";
        run(label.c_str(), signature.c_str(), true, *kind, "i");
        label = std::string("argument-") + *kind;
        signature = std::string("v@:") + *kind;
        char argument[] = {*kind, 0};
        run(label.c_str(), signature.c_str(), true, 'v', argument);
    }
    run("game-bool-class", "c12@0:4#8", true, 'c', "#");
    run("native-bool-double", "B24@0:8d16", true, 'B', "d");
    run("class-self", "d24#0:8f16", true, 'd', "f");
    run("six-mixed-arguments", "Q64@0:8i16q20d28f36@40:48", true, 'Q', "iqdf@:");
    run("all-qualifiers", "rnNoORVAQ32r@0n:4Oq8V@16", true, 'Q', "q@");
    run("signed-offsets", "Q+32@-0:+4q-8@+16", true, 'Q', "q@");
    run("quoted-object-types", R"(r@"Result<NSCopying>"32@"Receiver"0:8n@"Argument"16)", true, '@', "@");
    run("escaped-quoted-object-types", R"(@"A\"B\\C"@:@"D\"E")", true, '@', "@");
    run("empty-quoted-object", R"(v@:@"")", true, 'v', "@");

    run("null", nullptr, false);
    const char *invalid[] = {
        "", "v", "v@", "v@:", "v#:", "vii", "v@@i", "v@:v", "v#:v",
        "v@#i", "v^@:#", "v@:iiiiiii", "v@:iiiiiiiiiiiiiiiiiiiiiiii",
        "v@:^i", "v@:^?", "v@:*", "v@:@?", "@?@:i", "v@:{Point=ff}",
        "{Point=ff}@:i", "v@:(Union=id)", "v@:[4i]", "v@:b3", "v@:![4f]",
        "v@:?", "v@:z", "v@:r", "v@:+1", "v@:i+", "v@:i-", "v@:i+x",
        "v@:i-@", "v@:i++1", "v@:i ", "v@:i/", "v@:@\"unterminated",
        "v@:@\"terminal\\", "v@:@\"valid\"?", "v@:@\"valid\"^i",
    };
    unsigned index = 0;
    for(const char *signature : invalid) {
        std::string label = "malformed-" + std::to_string(index++);
        run(label.c_str(), signature, false);
    }

    std::string longest = "v@:f" + std::string(4091, '0');
    run("4095-byte-valid-encoding", longest.c_str(), true, 'v', "f");
    longest.push_back('0');
    run("4096-byte-encoding-rejected", longest.c_str(), false);
    longest.append(4096, '0');
    run("oversized-encoding-rejected", longest.c_str(), false);

    // Put the 4096-byte scanner limit directly against inaccessible memory.
    // A missing bound or an attempted read beyond it must fail this process.
    long pageSize = sysconf(_SC_PAGESIZE);
    if(pageSize < 4096) { fprintf(stderr, "unsupported native page size\n"); return 2; }
    void *region = mmap(nullptr, (size_t)pageSize * 2, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANON, -1, 0);
    if(region == MAP_FAILED) { perror("mmap fixture"); return 2; }
    if(mprotect((char *)region + pageSize, (size_t)pageSize, PROT_NONE)) {
        perror("mprotect fixture"); munmap(region, (size_t)pageSize * 2); return 2;
    }
    char *bounded = (char *)region + pageSize - 4096;
    memset(bounded, 'r', 4096);
    run("unterminated-4096-bytes-at-guard-page", bounded, false);
    memcpy(bounded, "v@:f", 4);
    memset(bounded + 4, '0', 4091);
    bounded[4095] = 0;
    run("valid-encoding-ending-at-guard-page", bounded, true, 'v', "f");
    munmap(region, (size_t)pageSize * 2);
    printf("scalar callback signature summary: %u cases, %u failures\n", cases, failures);
    return failures ? 1 : 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "HostFrameworks/LC32/bridge.mm")
    arguments = parser.parse_args()
    text = arguments.source.read_text(encoding="utf-8")
    if text.count(START) != 1 or text.count(END) != 1:
        parser.error("expected one scalar scanner and its LC32ScalarKindsMatch boundary")
    start, end = text.index(START), text.index(END)
    if end <= start:
        parser.error("scalar scanner boundaries are out of order")
    scanner = text[start:end]
    compiler = shlex.split(os.environ.get("HOST_CXX", "xcrun --sdk macosx clang++"))
    if not compiler:
        parser.error("HOST_CXX is empty")
    with tempfile.TemporaryDirectory(prefix="lc32-scalar-callback-signature-") as directory:
        source = Path(directory) / "scanner.cpp"
        executable = Path(directory) / "scanner"
        source.write_text(HEADERS + "\n" + scanner + "\n" + HARNESS, encoding="utf-8")
        subprocess.run(compiler + ["-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic",
                       "-O2", str(source), "-o", str(executable)], check=True, timeout=30)
        subprocess.run([str(executable)], check=True, timeout=10)


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        print(f"scalar callback signature test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
