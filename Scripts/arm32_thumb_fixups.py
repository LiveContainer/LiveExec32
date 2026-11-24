#!/usr/bin/env python3
"""Repair ld's lost ARM32 Thumb bits, before stripping/signing.

Only dyld rebase locations and LC_MAIN are eligible, and only exact code
symbols marked N_ARM_THUMB_DEF. Never scan arbitrary words for code addresses.
Bindings, export tries, instructions, ARM functions and data stay untouched.
Unsupported/ambiguous images fail without modifying the input.
"""

import argparse
from pathlib import Path
import struct


class InvalidImage(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidImage(message)


def thumb_repairs(data, *, allow_signed=False):
    """Return {file_offset: (width, old_value, new_value)} after validation."""
    def unpack(fmt, offset):
        size = struct.calcsize("<" + fmt)
        require(0 <= offset <= len(data) - size, "truncated Mach-O data")
        return struct.unpack_from("<" + fmt, data, offset)

    magic, cpu, _, kind, ncmds, cmdsize, flags = unpack("7I", 0)
    require(magic == 0xfeedface and cpu == 12, "expected a thin ARM32 Mach-O")
    require(kind in (2, 6, 8), "expected an executable, dylib or bundle")
    require(kind != 2 or flags & 0x200000, "non-PIE executable lacks complete rebase metadata")
    require(28 + cmdsize <= len(data), "truncated load commands")
    segments, sections, main = [], [], []
    symtab = rebases = None
    cursor = 28
    for _ in range(ncmds):
        command, size = unpack("2I", cursor)
        require(size >= 8 and cursor + size <= 28 + cmdsize, "invalid load command")
        if command == 1:  # LC_SEGMENT
            require(size >= 56, "truncated segment")
            _, _, name, address, vmsize, fileoff, filesize, _, _, count, _ = unpack("2I16s8I", cursor)
            require(filesize <= vmsize and fileoff + filesize <= len(data), "invalid segment extent")
            require(56 + 68 * count <= size, "truncated sections")
            segments.append((address, vmsize, fileoff, filesize, name.rstrip(b"\0")))
            for i in range(count):
                sec = unpack("16s16s9I", cursor + 56 + 68 * i)
                secname, segname = (s.rstrip(b"\0") for s in sec[:2])
                base, length, offset, _, _, _, attrs, _, _ = sec[2:]
                require(address <= base <= base + length <= address + vmsize, "section outside segment")
                if attrs & 0xff not in (1, 12, 18):  # zero-fill sections
                    require(fileoff <= offset <= offset + length <= fileoff + filesize,
                            "section outside segment file data")
                sections.append((base, length, offset, attrs, segname, secname))
        elif command == 2:  # LC_SYMTAB
            require(size >= 24 and symtab is None, "invalid/duplicate symbol table")
            symtab = unpack("4I", cursor + 8)
        elif command in (0x22, 0x80000022):  # LC_DYLD_INFO[_ONLY]
            require(size >= 48 and rebases is None, "invalid/duplicate dyld info")
            rebases = unpack("2I", cursor + 8)
        elif command == 0x80000028:  # LC_MAIN
            require(size >= 24, "truncated LC_MAIN")
            main.append(cursor + 8)
        elif command in (0x80000034, 5):
            raise InvalidImage("chained fixups/LC_UNIXTHREAD are not supported by the Thumb repair")
        elif command == 0x1d:  # LC_CODE_SIGNATURE
            require(allow_signed, "repair must run before code signing")
        cursor += size
    require(cursor == 28 + cmdsize, "load command size mismatch")
    require(symtab is not None and rebases is not None, "unstripped symbols and dyld rebase info required")
    require(len(main) == (1 if kind == 2 else 0), "unexpected LC_MAIN count")

    symoff, count, stroff, strsize = symtab
    require(symoff + 12 * count <= len(data) and stroff + strsize <= len(data), "truncated symbols")
    code = {}
    for i in range(count):
        strx, stype, sect, desc, value = unpack("IBBHI", symoff + 12 * i)
        if stype & 0xe0 or stype & 0x0e != 0x0e:
            continue
        require(0 < sect <= len(sections), "invalid symbol section")
        require(strx < strsize and data.find(b"\0", stroff + strx, stroff + strsize) >= 0,
                "invalid symbol name")
        base, length, _, attrs, _, _ = sections[sect - 1]
        if attrs & 0x80000400 and base <= (value & ~1) < base + length:
            code.setdefault(value & ~1, set()).add(bool(desc & 8))

    changes = {}

    def repair(offset, width, target):
        modes = code.get(target & ~1)
        require(modes != {False, True}, f"ambiguous ARM/Thumb symbols at 0x{target:x}")
        if modes == {True}:
            original = unpack("Q" if width == 8 else "I", offset)[0]
            if not original & 1:
                changes[offset] = (width, original, original | 1)

    rebase_offset, rebase_size = rebases
    require(rebase_offset + rebase_size <= len(data), "truncated rebase opcodes")
    cursor, end = rebase_offset, rebase_offset + rebase_size
    segment, offset, rebase_type = None, 0, None
    visited = set()

    def uleb():
        nonlocal cursor
        value = 0
        for shift in range(0, 64, 7):
            require(cursor < end, "truncated ULEB128")
            byte = data[cursor]
            cursor += 1
            value |= (byte & 127) << shift
            if not byte & 128:
                require(value <= 0xffffffffffffffff, "ULEB128 overflow")
                return value
        raise InvalidImage("ULEB128 overflow")

    def rebase(count, skip=0):
        nonlocal offset
        require(segment is not None and segment < len(segments), "invalid rebase segment")
        require(rebase_type in (1, 2), "unsupported rebase type")
        address, _, fileoff, filesize, _ = segments[segment]
        require(count <= len(data) // 4, "invalid rebase count")
        for _ in range(count):
            require(0 <= offset <= filesize - 4, "rebase outside file-backed segment")
            location = fileoff + offset
            require(location not in visited, "duplicate rebase location")
            visited.add(location)
            target = unpack("I", location)[0]
            # Unwind descriptions contain code addresses, not callable pointers.
            source = next((s for s in sections if s[0] <= address + offset < s[0] + s[1]), None)
            require(source is not None, "rebase outside a section")
            if source[5] not in (b"__eh_frame", b"__unwind_info"):
                repair(location, 4, target)
            offset += 4 + skip

    while cursor < end:
        byte = data[cursor]
        cursor += 1
        op, imm = byte & 0xf0, byte & 15
        if op == 0:
            require(imm == 0 and not any(data[cursor:end]), "invalid rebase padding")
            break
        if op == 0x10:
            rebase_type = imm
        elif op == 0x20:
            segment, offset = imm, uleb()
        elif op == 0x30:
            offset += uleb()
        elif op == 0x40:
            offset += imm * 4
        elif op == 0x50:
            rebase(imm)
        elif op == 0x60:
            rebase(uleb())
        elif op == 0x70:
            skip = uleb()
            rebase(1, skip)
        elif op == 0x80:
            count, skip = uleb(), uleb()
            rebase(count, skip)
        else:
            raise InvalidImage(f"unsupported rebase opcode 0x{byte:x}")

    for location in main:
        entry = unpack("Q", location)[0]
        # LC_MAIN is a file offset within __TEXT, not a VM address.
        text = next((s for s in segments if s[4] == b"__TEXT"), None)
        require(text is not None and text[2] <= (entry & ~1) < text[2] + text[3], "invalid entry point")
        target = text[0] + entry - text[2]
        require(target & ~1 in code, "entry point has no code symbol")
        repair(location, 8, target)
    return changes


def repaired_image(data, *, allow_signed=False):
    changes = thumb_repairs(data, allow_signed=allow_signed)
    output = bytearray(data)
    for offset, (width, _, value) in changes.items():
        struct.pack_into("<Q" if width == 8 else "<I", output, offset, value)
    return output, len(changes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repair", action="store_true", help="modify an unsigned build output in place")
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    try:
        output, count = repaired_image(args.image.read_bytes(), allow_signed=not args.repair)
        if count and args.repair:
            args.image.write_bytes(output)
        print(f"{args.image}: {count} Thumb pointer(s) {'repaired' if args.repair else 'need repair'}")
        return int(count != 0 and not args.repair)
    except (OSError, ValueError) as error:
        parser.exit(1, f"arm32-thumb-fixups: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
