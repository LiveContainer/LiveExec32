#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
MANIFEST="$REPO_ROOT/Generator/templates/opengles-supported-symbols.txt"
SOURCE="$REPO_ROOT/GuestFrameworks/OpenGLES/OpenGLES.m"
EAGL_SOURCE="$REPO_ROOT/GuestFrameworks/OpenGLES/EAGL.m"
EAGL_HEADERS="$SDKROOT/System/Library/Frameworks/OpenGLES.framework/Headers"
BRIDGE_HEADER="$REPO_ROOT/GuestFrameworks/OpenGLES/LC32OpenGLESBridge.h"
HOST_SOURCE="$REPO_ROOT/HostFrameworks/OpenGLES/OpenGLES.mm"
LINKED_IMAGE=${1:-}
TEMP_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-opengles-symbols.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

if [ -n "$LINKED_IMAGE" ] && [ ! -f "$LINKED_IMAGE" ]; then
    echo "OpenGLES linked image does not exist: $LINKED_IMAGE" >&2
    exit 1
fi

LC_ALL=C sort -c -u "$MANIFEST"

ES1_GL_HEADER="$EAGL_HEADERS/ES1/gl.h"
ES1_GLEXT_HEADER="$EAGL_HEADERS/ES1/glext.h"
ES2_GL_HEADER="$EAGL_HEADERS/ES2/gl.h"
ES2_GLEXT_HEADER="$EAGL_HEADERS/ES2/glext.h"
ES3_GL_HEADER="$EAGL_HEADERS/ES3/gl.h"
ES3_GLEXT_HEADER="$EAGL_HEADERS/ES3/glext.h"

for header in "$ES1_GL_HEADER" "$ES1_GLEXT_HEADER" \
        "$ES2_GL_HEADER" "$ES2_GLEXT_HEADER" \
        "$ES3_GL_HEADER" "$ES3_GLEXT_HEADER"; do
    if [ ! -f "$header" ]; then
        echo "OpenGLES SDK header does not exist: $header" >&2
        exit 1
    fi
done

# Public declarations have several spellings: GL_APIENTRY is optional and
# pointer returns may place the star immediately before the function name.
# Match the gl-prefixed identifier followed by '(' rather than one layout.
awk '
    /^[[:space:]]*GL_API/ {
        if(match($0, /gl[A-Za-z0-9_]+[[:space:]]*\(/)) {
            symbol = substr($0, RSTART, RLENGTH)
            sub(/[[:space:]]*\($/, "", symbol)
            print symbol
        }
    }
' "$ES1_GL_HEADER" "$ES1_GLEXT_HEADER" \
    "$ES2_GL_HEADER" "$ES2_GLEXT_HEADER" \
    "$ES3_GL_HEADER" "$ES3_GLEXT_HEADER" | \
    LC_ALL=C sort -u > "$TEMP_DIR/sdk-symbols.txt"

{
    echo EAGLGetVersion
    cat "$TEMP_DIR/sdk-symbols.txt"
} | LC_ALL=C sort -u > "$TEMP_DIR/required-symbols.txt"

xcrun --sdk iphoneos clang -target armv7s-apple-ios10.3 \
    -isysroot "$SDKROOT" -I"$REPO_ROOT/GuestFrameworks" \
    -I"$REPO_ROOT/include" \
    -fmodules -fmodules-cache-path="$TEMP_DIR/modules" \
    -Wno-deprecated-module-dot-map -Wno-deprecated-declarations \
    -c "$SOURCE" -o "$TEMP_DIR/OpenGLES.o"
xcrun --sdk iphoneos clang -target armv7s-apple-ios10.3 \
    -isysroot "$SDKROOT" \
    -Wno-deprecated-declarations \
    -c "$EAGL_SOURCE" -o "$TEMP_DIR/EAGL.o"

{
    xcrun nm -gjU "$TEMP_DIR/OpenGLES.o"
    xcrun nm -gjU "$TEMP_DIR/EAGL.o"
} | sed -E -n 's/^_(EAGLGetVersion|gl[A-Za-z0-9_]*)$/\1/p' | \
    LC_ALL=C sort -u > "$TEMP_DIR/bridge-symbols.txt"

failures=0

report_missing() {
    description=$1
    required=$2
    actual=$3
    output=$4
    comm -23 "$required" "$actual" > "$output"
    if [ -s "$output" ]; then
        echo "$description:" >&2
        cat "$output" >&2
        failures=1
    fi
}

report_missing \
    "OpenGLES manifest is missing public ES1/ES2/ES3 symbols" \
    "$TEMP_DIR/required-symbols.txt" "$MANIFEST" \
    "$TEMP_DIR/missing-manifest-symbols.txt"
report_missing \
    "OpenGLES guest objects are missing public ES1/ES2/ES3 exports" \
    "$TEMP_DIR/required-symbols.txt" "$TEMP_DIR/bridge-symbols.txt" \
    "$TEMP_DIR/missing-object-symbols.txt"

if ! diff -u "$MANIFEST" "$TEMP_DIR/bridge-symbols.txt" \
        > "$TEMP_DIR/manifest-objects.diff"; then
    echo "OpenGLES manifest and guest object exports differ:" >&2
    cat "$TEMP_DIR/manifest-objects.diff" >&2
    failures=1
fi

if [ -n "$LINKED_IMAGE" ]; then
    xcrun nm -gjU "$LINKED_IMAGE" | \
        sed -E -n 's/^_(EAGLGetVersion|gl[A-Za-z0-9_]*)$/\1/p' | \
        LC_ALL=C sort -u > "$TEMP_DIR/linked-symbols.txt"
    report_missing \
        "Linked OpenGLES image is missing public ES1/ES2/ES3 exports" \
        "$TEMP_DIR/required-symbols.txt" "$TEMP_DIR/linked-symbols.txt" \
        "$TEMP_DIR/missing-linked-symbols.txt"
    if ! diff -u "$MANIFEST" "$TEMP_DIR/linked-symbols.txt" \
            > "$TEMP_DIR/manifest-linked.diff"; then
        echo "OpenGLES manifest and linked image exports differ:" >&2
        cat "$TEMP_DIR/manifest-linked.diff" >&2
        failures=1
    fi
fi

find "$EAGL_HEADERS" -type f -name '*.h' -exec \
    sed -E -n \
        's/^EAGL_EXTERN[[:space:]]+.*[[:space:]](kEAGL[A-Za-z0-9_]+)([[:space:]][^;]*)?;$/\1/p' \
        {} + | LC_ALL=C sort -u > "$TEMP_DIR/sdk-eagl-data-symbols.txt"

if [ ! -s "$TEMP_DIR/sdk-eagl-data-symbols.txt" ]; then
    echo "OpenGLES symbol audit could not derive public EAGL data constants" >&2
    exit 1
fi

check_eagl_data_exports() {
    label=$1
    shift
    xcrun nm -gjU "$@" | \
        sed -E -n 's/^_(kEAGL[A-Za-z0-9_]*)$/\1/p' | \
        LC_ALL=C sort -u > "$TEMP_DIR/$label-eagl-data-symbols.txt"
    comm -23 "$TEMP_DIR/sdk-eagl-data-symbols.txt" \
        "$TEMP_DIR/$label-eagl-data-symbols.txt" > \
        "$TEMP_DIR/$label-missing-eagl-data-symbols.txt"
    if [ -s "$TEMP_DIR/$label-missing-eagl-data-symbols.txt" ]; then
        echo "OpenGLES $label is missing public EAGL data exports:" >&2
        cat "$TEMP_DIR/$label-missing-eagl-data-symbols.txt" >&2
        exit 1
    fi
}

check_eagl_data_exports objects "$TEMP_DIR/OpenGLES.o" "$TEMP_DIR/EAGL.o"
if [ -n "$LINKED_IMAGE" ]; then
    check_eagl_data_exports linked-image "$LINKED_IMAGE"
fi

# A public export that packs an opcode but has no matching host case resolves
# at dyld time and then silently reports GL_INVALID_OPERATION.  Audit both
# halves of the private ABI alongside the public symbol surface.  These four
# historical OES opcodes remain reserved after the guest symbols became true
# aliases of their promoted core functions.
perl -ne 'print "$1\t$2\n" if
    /\b(LC32OpenGLESOp[A-Z][A-Za-z0-9_]*)\s*=\s*([0-9]+)/' \
    "$BRIDGE_HEADER" > "$TEMP_DIR/opcode-values.txt"

cut -f1 "$TEMP_DIR/opcode-values.txt" | LC_ALL=C sort \
    > "$TEMP_DIR/all-opcodes-unsimplified.txt"
uniq "$TEMP_DIR/all-opcodes-unsimplified.txt" \
    > "$TEMP_DIR/all-opcodes.txt"
uniq -d "$TEMP_DIR/all-opcodes-unsimplified.txt" \
    > "$TEMP_DIR/duplicate-opcode-names.txt"
cut -f2 "$TEMP_DIR/opcode-values.txt" | LC_ALL=C sort | uniq -d \
    > "$TEMP_DIR/duplicate-opcode-values.txt"
if [ ! -s "$TEMP_DIR/all-opcodes.txt" ]; then
    echo "OpenGLES symbol audit could not derive bridge opcodes" >&2
    exit 1
fi
if [ -s "$TEMP_DIR/duplicate-opcode-names.txt" ]; then
    echo "OpenGLES bridge has duplicate opcode names:" >&2
    cat "$TEMP_DIR/duplicate-opcode-names.txt" >&2
    failures=1
fi
if [ -s "$TEMP_DIR/duplicate-opcode-values.txt" ]; then
    echo "OpenGLES bridge has duplicate opcode values:" >&2
    cat "$TEMP_DIR/duplicate-opcode-values.txt" >&2
    failures=1
fi

{
    echo LC32OpenGLESOpBindRenderbufferOES
    echo LC32OpenGLESOpFramebufferRenderbufferOES
    echo LC32OpenGLESOpGenRenderbuffersOES
    echo LC32OpenGLESOpRenderbufferStorageOES
} | LC_ALL=C sort > "$TEMP_DIR/reserved-opcodes.txt"
comm -23 "$TEMP_DIR/all-opcodes.txt" "$TEMP_DIR/reserved-opcodes.txt" \
    > "$TEMP_DIR/active-opcodes.txt"

perl -ne 'while(/\b(LC32OpenGLESOp[A-Z][A-Za-z0-9_]*)\b/g) {
    print "$1\n" }' "$SOURCE" "$EAGL_SOURCE" | LC_ALL=C sort -u \
    > "$TEMP_DIR/guest-opcodes.txt"
perl -ne 'while(/\bcase\s+(LC32OpenGLESOp[A-Z][A-Za-z0-9_]*)\s*:/g) {
    print "$1\n" }' "$HOST_SOURCE" \
    > "$TEMP_DIR/host-opcode-cases-unsorted.txt"
LC_ALL=C sort -u "$TEMP_DIR/host-opcode-cases-unsorted.txt" \
    > "$TEMP_DIR/host-opcodes.txt"

report_missing \
    "OpenGLES guest sources are missing active opcode references" \
    "$TEMP_DIR/active-opcodes.txt" "$TEMP_DIR/guest-opcodes.txt" \
    "$TEMP_DIR/missing-guest-opcodes.txt"
report_missing \
    "OpenGLES host dispatcher is missing active opcode cases" \
    "$TEMP_DIR/active-opcodes.txt" "$TEMP_DIR/host-opcodes.txt" \
    "$TEMP_DIR/missing-host-opcodes.txt"

LC_ALL=C sort "$TEMP_DIR/host-opcode-cases-unsorted.txt" | uniq -d \
    > "$TEMP_DIR/duplicate-host-opcodes.txt"
if [ -s "$TEMP_DIR/duplicate-host-opcodes.txt" ]; then
    echo "OpenGLES host dispatcher has duplicate opcode cases:" >&2
    cat "$TEMP_DIR/duplicate-host-opcodes.txt" >&2
    failures=1
fi

comm -13 "$TEMP_DIR/all-opcodes.txt" "$TEMP_DIR/guest-opcodes.txt" \
    > "$TEMP_DIR/unknown-guest-opcodes.txt"
if [ -s "$TEMP_DIR/unknown-guest-opcodes.txt" ]; then
    echo "OpenGLES guest sources reference unknown opcodes:" >&2
    cat "$TEMP_DIR/unknown-guest-opcodes.txt" >&2
    failures=1
fi
comm -13 "$TEMP_DIR/all-opcodes.txt" "$TEMP_DIR/host-opcodes.txt" \
    > "$TEMP_DIR/unknown-host-opcodes.txt"
if [ -s "$TEMP_DIR/unknown-host-opcodes.txt" ]; then
    echo "OpenGLES host dispatcher references unknown opcodes:" >&2
    cat "$TEMP_DIR/unknown-host-opcodes.txt" >&2
    failures=1
fi

symbol_address() {
    image=$1
    symbol=$2
    xcrun nm -n "$image" | awk -v symbol="_$symbol" '
        $NF == symbol { count++; address = $1 }
        END {
            if (count != 1) exit 1
            print address
        }'
}

check_thumb_symbol() {
    image=$1
    symbol=$2
    if ! xcrun nm -nm "$image" | awk -v symbol="_$symbol" '
        $NF == symbol {
            count++
            if (index($0, "[Thumb]") != 0) thumb++
        }
        END { exit !(count == 1 && thumb == 1) }'; then
        echo "OpenGLES alias is not a unique external Thumb symbol: $symbol" >&2
        exit 1
    fi
}

check_alias() {
    alias_name=$1
    target_name=$2
    alias_address=
    target_address=
    if ! alias_address=$(symbol_address "$TEMP_DIR/OpenGLES.o" "$alias_name") || \
       ! target_address=$(symbol_address "$TEMP_DIR/OpenGLES.o" "$target_name") || \
       [ "$alias_address" != "$target_address" ]; then
        echo "OpenGLES alias address mismatch: $alias_name -> $target_name " \
             "($alias_address != $target_address)" >&2
        exit 1
    fi

    if [ -n "$LINKED_IMAGE" ]; then
        if ! alias_address=$(symbol_address "$LINKED_IMAGE" "$alias_name") || \
           ! target_address=$(symbol_address "$LINKED_IMAGE" "$target_name") || \
           [ "$alias_address" != "$target_address" ]; then
            echo "Linked OpenGLES alias address mismatch: " \
                 "$alias_name -> $target_name " \
                 "($alias_address != $target_address)" >&2
            exit 1
        fi
        check_thumb_symbol "$LINKED_IMAGE" "$alias_name"
    fi
}

check_alias glBindFramebufferOES glBindFramebuffer
check_alias glBindRenderbufferOES glBindRenderbuffer
check_alias glBlendEquationOES glBlendEquation
check_alias glBlendEquationSeparateOES glBlendEquationSeparate
check_alias glBlendFuncSeparateOES glBlendFuncSeparate
check_alias glCheckFramebufferStatusOES glCheckFramebufferStatus
check_alias glDeleteFramebuffersOES glDeleteFramebuffers
check_alias glDeleteRenderbuffersOES glDeleteRenderbuffers
check_alias glFramebufferRenderbufferOES glFramebufferRenderbuffer
check_alias glFramebufferTexture2DOES glFramebufferTexture2D
check_alias glGenFramebuffersOES glGenFramebuffers
check_alias glGenRenderbuffersOES glGenRenderbuffers
check_alias glGenerateMipmapOES glGenerateMipmap
check_alias glGetFramebufferAttachmentParameterivOES \
    glGetFramebufferAttachmentParameteriv
check_alias glGetRenderbufferParameterivOES \
    glGetRenderbufferParameteriv
check_alias glIsFramebufferOES glIsFramebuffer
check_alias glIsRenderbufferOES glIsRenderbuffer
check_alias glRenderbufferStorageOES glRenderbufferStorage

# OpenGL ES 3 promoted these extension entry points without changing their
# ABI.  The core spellings are true assembly aliases of the established
# extension bridge entry points, not forwarding wrappers.
check_alias glBeginQuery glBeginQueryEXT
check_alias glBindVertexArray glBindVertexArrayOES
check_alias glClientWaitSync glClientWaitSyncAPPLE
check_alias glDeleteQueries glDeleteQueriesEXT
check_alias glDeleteSync glDeleteSyncAPPLE
check_alias glDeleteVertexArrays glDeleteVertexArraysOES
check_alias glDrawArraysInstanced glDrawArraysInstancedEXT
check_alias glDrawElementsInstanced glDrawElementsInstancedEXT
check_alias glEndQuery glEndQueryEXT
check_alias glFenceSync glFenceSyncAPPLE
check_alias glFlushMappedBufferRange glFlushMappedBufferRangeEXT
check_alias glGenQueries glGenQueriesEXT
check_alias glGenVertexArrays glGenVertexArraysOES
check_alias glGetBufferPointerv glGetBufferPointervOES
check_alias glGetInteger64v glGetInteger64vAPPLE
check_alias glGetQueryObjectuiv glGetQueryObjectuivEXT
check_alias glGetQueryiv glGetQueryivEXT
check_alias glGetSynciv glGetSyncivAPPLE
check_alias glIsQuery glIsQueryEXT
check_alias glIsSync glIsSyncAPPLE
check_alias glIsVertexArray glIsVertexArrayOES
check_alias glMapBufferRange glMapBufferRangeEXT
check_alias glProgramParameteri glProgramParameteriEXT
check_alias glRenderbufferStorageMultisample \
    glRenderbufferStorageMultisampleAPPLE
check_alias glTexStorage2D glTexStorage2DEXT
check_alias glUnmapBuffer glUnmapBufferOES
check_alias glVertexAttribDivisor glVertexAttribDivisorEXT
check_alias glWaitSync glWaitSyncAPPLE

if [ "$failures" -ne 0 ]; then
    exit 1
fi

required_count=$(wc -l < "$TEMP_DIR/sdk-symbols.txt" | tr -d ' ')
echo "OpenGLES symbol audit: PASS ($required_count public ES1/ES2/ES3 functions, opcode coverage, aliases, and EAGL globals)"
