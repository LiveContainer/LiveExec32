#!/bin/sh
set -eu

# No arguments: compile and audit the fixture using the guest build's classic
# linker selection. Arguments: read-only audit of existing unstripped, thin
# ARM32 guest images. No guest launcher or network access is required.
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
fixture=0
if [ "$#" -eq 0 ]; then
    guest_sdk=${LC32_GUEST_SDK:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
    guest_linker=${LC32_GUEST_LINKER:-$(xcrun --find ld-classic)}
    if [ ! -d "$guest_sdk" ] || [ ! -x "$guest_linker" ]; then
        echo "Guest SDK or classic linker missing; set LC32_GUEST_SDK/LC32_GUEST_LINKER" >&2
        exit 1
    fi
    audit_work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-thumb-linker.XXXXXX")
    trap 'rm -rf "$audit_work"' EXIT HUP INT TERM
    xcrun clang -target armv7s-apple-ios10.3 -mthumb -O0 \
        -Wall -Wextra -Werror -isysroot "$guest_sdk" \
        --ld-path="$guest_linker" "$SCRIPT_DIR/guest_thumb_linker.c" \
        -o "$audit_work/guest-thumb-linker"
    echo "Guest Thumb linker: $guest_linker"
    set -- "$audit_work/guest-thumb-linker"
    fixture=1
fi

# Read pointer words directly: nm reports the function's Thumb metadata, but
# cannot establish that the linker retained bit zero in relocated data slots.
python3 - "$fixture" "$@" <<'PY'
import pathlib
import struct
import sys

def audit(path, fixture):
    data = pathlib.Path(path).read_bytes()
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    def unpack(fmt, offset):
        return struct.unpack_from('<' + fmt, data, offset)
    require(len(data) >= 28, 'truncated Mach-O header')
    magic, cpu, _, filetype, ncmds, cmdbytes, _ = unpack('7I', 0)
    require(magic == 0xfeedface and cpu == 12,
            'expected a thin little-endian ARM32 Mach-O')
    require(filetype in (2, 6, 8), 'expected a linked executable/dylib/bundle')
    require(28 + cmdbytes <= len(data), 'truncated load commands')
    sections, symtab, cursor = [], None, 28
    for _ in range(ncmds):
        command, size = unpack('2I', cursor)
        require(size >= 8 and cursor + size <= 28 + cmdbytes,
                'invalid load command extent')
        if command == 1:  # LC_SEGMENT, section records are 68 bytes each.
            nsects = unpack('I', cursor + 48)[0]
            require(56 + nsects * 68 <= size, 'truncated section records')
            for index in range(nsects):
                record = unpack('16s16s9I', cursor + 56 + index * 68)
                name = record[0].rstrip(b'\0').decode('ascii')
                sections.append((name, record[2], record[3], record[4], record[8]))
        elif command == 2:  # LC_SYMTAB
            symtab = unpack('4I', cursor + 8)
        cursor += size
    require(symtab is not None, 'symbol table required (audit unstripped images)')
    symoff, nsyms, stroff, strsize = symtab
    require(symoff + 12 * nsyms <= len(data) and stroff + strsize <= len(data),
            'truncated symbol/string table')
    symbols = {}
    for index in range(nsyms):
        strx, kind, sect, desc, value = unpack('IBBHI', symoff + 12 * index)
        if kind & 0xe0 or kind & 0x0e != 0x0e:  # Skip STAB/non-section symbols.
            continue
        require(strx < strsize, 'invalid symbol string offset')
        end = data.find(b'\0', stroff + strx, stroff + strsize)
        require(end >= 0, 'unterminated symbol name')
        symbols[data[stroff + strx:end].decode('utf-8')] = (value, desc, sect)
    def pointer_at(address):
        for _, base, size, offset, flags in sections:
            if base <= address and address + 4 <= base + size:
                require(flags & 0xff not in (1, 12, 18), 'pointer is zero-fill')
                return unpack('I', offset + address - base)[0]
        raise ValueError('pointer slot outside a section')
    def check_pointer(pointer, label):
        require(pointer & 1, f'{label}: missing Thumb bit (0x{pointer:08x})')
        matches = [s for s in symbols.values() if s[0] & ~1 == pointer & ~1]
        require(any(s[1] & 8 for s in matches),
                f'{label}: target lacks N_ARM_THUMB_DEF (0x{pointer:08x})')
    initializers = 0
    for name, address, size, _, flags in sections:
        if flags & 0xff == 9:  # S_MOD_INIT_FUNC_POINTERS
            require(size % 4 == 0, 'misaligned initializer section')
            for offset in range(0, size, 4):
                check_pointer(pointer_at(address + offset), f'{name}+0x{offset:x}')
                initializers += 1
    callback = symbols.get('_lc32_thumb_callback_pointer')
    if callback:
        pointer = pointer_at(callback[0])
        check_pointer(pointer, 'data callback')
        target = symbols.get('_lc32_thumb_callback')
        require(target and pointer & ~1 == target[0] & ~1,
                'data callback points to the wrong function')
    if fixture:
        require(initializers == 1 and callback is not None,
                'fixture must contain one initializer and its data callback')
    print(f'{path}: PASS ({initializers} Thumb initializers; '
          f'{int(callback is not None)} fixture data callbacks)')

failed = False
for path in sys.argv[2:]:
    try:
        audit(path, sys.argv[1] == '1')
    except (OSError, ValueError, struct.error) as error:
        print(f'{path}: FAIL: {error}', file=sys.stderr)
        failed = True
sys.exit(int(failed))
PY
