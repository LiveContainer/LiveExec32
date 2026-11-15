#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/LiveExec32-SelectorAlias.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

if [ "${SKIP_GENERATOR_BUILD:-0}" != 1 ]; then
    "$SCRIPT_DIR/build.sh"
fi
"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/Tests/selector-alias.plist" "$TEMP_ROOT/generated"

# Compile the actual generated methods against a host-call recorder. Their
# scalar/object bridge calls are architecture-neutral; no GPU or UIKit runtime
# is needed to exercise Objective-C method exchange and alias dispatch.
python3 - "$TEMP_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
source = (root / "generated/UIKit/LC32SelectorAliasFixture.m").read_text()
implementation = source[source.index("@implementation "):source.rindex("@end") + 4]
(root / "generated-methods.inc").write_text(implementation + "\n")
PY

cat > "$TEMP_ROOT/test.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static unsigned failures, hostCalls, instanceHooks, classHooks;
static id expectedDrawable;
static void check(BOOL pass, const char *message) {
    if(!pass) { fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
static BOOL LC32ObjCTraceEnabled(void) { return NO; }

@interface NSObject (LC32TestHostSelf)
+ (uint64_t)host_self;
- (uint64_t)host_self;
@end
@implementation NSObject (LC32TestHostSelf)
+ (uint64_t)host_self { return (uintptr_t)self; }
- (uint64_t)host_self { return (uintptr_t)self; }
@end

@interface LC32SelectorAliasFixture : NSObject
+ (char)setCurrentContext:(id)context;
- (char)renderbufferStorage:(unsigned int)target fromDrawable:(id)drawable;
- (char)savedRenderbufferStorage:(unsigned int)target fromDrawable:(id)drawable;
@end

// Match the bridge's per-IMP cache: the first selector passed is retained.
static uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL returnsStruct) {
    check(!returnsStruct, "scalar return unexpectedly marked as a structure");
    if(!*cache) memcpy(cache, &selector, sizeof(selector));
    return *cache;
}
static uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...) {
    ++hostCalls;
    id receiver = (__bridge id)(void *)(uintptr_t)object;
    BOOL isClass = object_isClass(receiver);
    SEL expected = isClass ? @selector(setCurrentContext:)
                           : @selector(renderbufferStorage:fromDrawable:);
    check(sel_isEqual((SEL)(uintptr_t)selector, expected), "host received the guest alias selector");
    va_list arguments;
    va_start(arguments, selector);
    if(!isClass) check(va_arg(arguments, uint64_t) == 0x8d41, "renderbuffer target changed");
    check(va_arg(arguments, uint64_t) == (uintptr_t)expectedDrawable, "object argument changed");
    check(va_arg(arguments, uint64_t) == 0, "bridge terminator changed");
    va_end(arguments);
    return 1;
}

#include "generated-methods.inc"

@interface LC32SelectorAliasFixture (RecordingHooks)
+ (char)recordingSetCurrentContext:(id)context;
- (char)renderbufferStorageEveryplay:(unsigned int)target fromDrawable:(id)drawable;
@end
@implementation LC32SelectorAliasFixture (RecordingHooks)
+ (char)recordingSetCurrentContext:(id)context {
    ++classHooks;
    return [self recordingSetCurrentContext:context];
}
- (char)renderbufferStorageEveryplay:(unsigned int)target fromDrawable:(id)drawable {
    ++instanceHooks;
    return [self renderbufferStorageEveryplay:target fromDrawable:drawable];
}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL warm = argc > 1 && !strcmp(argv[1], "--warm");
        LC32SelectorAliasFixture *context = [LC32SelectorAliasFixture new];
        expectedDrawable = [NSObject new];
        if(warm) {
            check([context renderbufferStorage:0x8d41 fromDrawable:expectedDrawable], "warm instance return");
            check([LC32SelectorAliasFixture setCurrentContext:expectedDrawable], "warm class return");
        }

        Class cls = LC32SelectorAliasFixture.class;
        Method original = class_getInstanceMethod(cls, @selector(renderbufferStorage:fromDrawable:));
        check(class_addMethod(cls, @selector(savedRenderbufferStorage:fromDrawable:),
            method_getImplementation(original), method_getTypeEncoding(original)), "save original IMP");
        method_exchangeImplementations(original, class_getInstanceMethod(cls,
            @selector(renderbufferStorageEveryplay:fromDrawable:)));
        method_exchangeImplementations(class_getClassMethod(cls, @selector(setCurrentContext:)),
            class_getClassMethod(cls, @selector(recordingSetCurrentContext:)));

        check([context renderbufferStorage:0x8d41 fromDrawable:expectedDrawable], "swizzled instance return");
        check([LC32SelectorAliasFixture setCurrentContext:expectedDrawable], "swizzled class return");
        check([context savedRenderbufferStorage:0x8d41 fromDrawable:expectedDrawable], "copied IMP return");
        check(instanceHooks == 1 && classHooks == 1, "guest hooks were skipped or reentered");
        check(hostCalls == (warm ? 5 : 3), "unexpected number of host invocations");
        expectedDrawable = nil;
        printf("generated selector aliases (%s cache): %s\n",
            warm ? "warm" : "cold", failures ? "FAIL" : "PASS");
    }
    return failures != 0;
}
EOF

xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-incomplete-implementation -framework Foundation \
    "$TEMP_ROOT/test.m" -o "$TEMP_ROOT/test"
"$TEMP_ROOT/test"
"$TEMP_ROOT/test" --warm
