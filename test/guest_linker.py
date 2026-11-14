#!/usr/bin/env python3
"""Host-only parser checks; no SDK, guest launcher, or signing is required."""
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from arm32_thumb_fixups import InvalidImage, repaired_image, thumb_repairs


def fixture(opcodes=b"\x11\x21\0\x53\x30\4\x51\0", extra=b""):
    def section(name, segment, address, size, offset, flags):
        return struct.pack("<16s16s9I", name, segment, address, size, offset, 2, 0, 0, flags, 0, 0)
    def segment(name, address, offset, size, sections=b""):
        return struct.pack("<2I16s8I", 1, 56 + len(sections), name, address,
                           size, offset, size, 7, 7, len(sections) // 68, 0) + sections
    commands = segment(b"__TEXT", 0x1000, 0, 0x600,
                       section(b"__text", b"__TEXT", 0x1400, 8, 0x400, 0x80000400))
    commands += segment(b"__DATA", 0x2000, 0x600, 0x40,
                        section(b"__data", b"__DATA", 0x2000, 0x40, 0x600, 0))
    commands += segment(b"__LINKEDIT", 0x3000, 0x640, 0x2c0)
    commands += struct.pack("<6I", 2, 24, 0x700, 3, 0x740, 19)
    commands += struct.pack("<12I", 0x80000022, 48, 0x780, len(opcodes), *([0] * 8))
    commands += struct.pack("<2I2Q", 0x80000028, 24, 0x400, 0)
    commands += extra
    data = bytearray(0x900)
    struct.pack_into("<7I", data, 0, 0xfeedface, 12, 11, 2,
                     6 + bool(extra), len(commands), 0x200004)
    data[28:28 + len(commands)] = commands
    struct.pack_into("<5I", data, 0x600, 0x1400, 0x1404, 0x2000, 0x1400, 0x1401)
    for index, (name, sect, desc, value) in enumerate(((1, 1, 8, 0x1400), (8, 1, 0, 0x1404), (13, 2, 0, 0x2000))):
        struct.pack_into("<IBBHI", data, 0x700 + 12 * index, name, 0xe, sect, desc, value)
    data[0x740:0x753] = b"\0_thumb\0_arm\0_data\0"
    data[0x780:0x780 + len(opcodes)] = opcodes
    return data


class ThumbFixups(unittest.TestCase):
    def test_only_recorded_thumb_pointers_and_entry_change(self):
        data = fixture()
        output, count = repaired_image(data)
        self.assertEqual(count, 2)
        self.assertEqual(struct.unpack_from("<5I", output, 0x600),
                         (0x1401, 0x1404, 0x2000, 0x1400, 0x1401))
        self.assertEqual(thumb_repairs(output), {})
        self.assertEqual(data[0x400:0x600], output[0x400:0x600])

    def test_rebase_opcode_variants(self):
        for opcodes in (b"\x11\x21\0\x60\1\0",  # count ULEB
                        b"\x11\x21\0\x70\x0c\x51\0",  # rebase + skip
                        b"\x11\x21\0\x80\2\x0c\0",  # count + skip
                        b"\x11\x21\0\x40\x51\0",  # scaled add
                        b"\x12\x21\0\x51\0"):  # absolute32
            with self.subTest(opcodes=opcodes):
                self.assertEqual(len(thumb_repairs(fixture(opcodes))), 2)

    def test_arm_entry_is_not_tagged(self):
        data = fixture()
        changes = thumb_repairs(data)
        entry = next(offset for offset, (width, _, _) in changes.items() if width == 8)
        struct.pack_into("<Q", data, entry, 0x404)
        self.assertEqual(len(thumb_repairs(data)), 1)

    def test_signed_images_can_only_be_audited(self):
        data = fixture(extra=struct.pack("<4I", 0x1d, 16, 0, 0))
        with self.assertRaises(InvalidImage):
            repaired_image(data)
        self.assertEqual(len(thumb_repairs(data, allow_signed=True)), 2)

    def test_ambiguous_code_symbols_are_rejected(self):
        data = fixture()
        # An ARM symbol aliases the Thumb function's address.
        struct.pack_into("<I", data, 0x714, 0x1400)
        with self.assertRaises(InvalidImage):
            repaired_image(data)

    def test_unwind_code_addresses_are_not_function_pointers(self):
        data = fixture()
        # Rename the data section without changing its recorded rebases.
        data[28 + 124 + 56:28 + 124 + 72] = b"__eh_frame".ljust(16, b"\0")
        output, count = repaired_image(data)
        self.assertEqual(count, 1)  # LC_MAIN only
        self.assertEqual(data[0x600:0x640], output[0x600:0x640])

    def test_unknown_formats_and_bad_metadata_fail_without_mutation(self):
        invalid = [fixture(extra=struct.pack("<4I", command, 16, 0, 0))
                   for command in (0x1d, 0x80000034)]
        for field, value in ((0, 0xfeedfacf), (4, 0x100000c), (12, 1),
                             (16, 999), (20, 0xfffffff0), (24, 4), (0x708, 0x1401)):
            data = fixture()
            struct.pack_into("<I", data, field, value)
            # Odd symbol values are legal; use an invalid section for this case.
            if field == 0x708:
                data[0x705] = 99
            invalid.append(data)
        invalid += [fixture(opcodes) for opcodes in (
            b"\x21\x80", b"\x21" + b"\xff" * 10,
            b"\x11\x2f\0\x51", b"\x13\x21\0\x51",
            b"\x11\x21\x40\x51", b"\x11\x21\0\x90",
            b"\x11\x21\0\x60\xff\xff\xff\xff\x0f",
            b"\x11\x21\0\x51\x21\0\x51", b"\0\x51")]
        for data in invalid:
            with self.subTest(data=bytes(data[0x780:0x790])):
                original = bytes(data)
                with self.assertRaises(InvalidImage):
                    repaired_image(data)
                self.assertEqual(data, original)

    def test_truncations(self):
        data = fixture()
        for size in (0, 4, 27, 70, 300, 0x603, 0x710, 0x750, 0x780):
            with self.subTest(size=size), self.assertRaises(InvalidImage):
                repaired_image(data[:size])


if __name__ == "__main__":
    unittest.main()
