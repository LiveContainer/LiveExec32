#!/usr/bin/env python3

import os
import struct
import sys
import tempfile


def fail(message):
    raise SystemExit(f"extract-img3: {message}")


if len(sys.argv) != 3:
    fail(f"usage: {sys.argv[0]} INPUT OUTPUT")

input_path, output_path = sys.argv[1:]
if os.path.abspath(input_path) == os.path.abspath(output_path):
    fail("input and output paths must differ")

with open(input_path, "rb") as source:
    header = source.read(20)
    if len(header) != 20:
        fail("input is shorter than the Img3 header")

    magic, container_size, data_size, _, _ = struct.unpack(
        "<4sIIII", header)
    if magic != b"3gmI":
        fail("input is not an Img3 container")

    file_size = os.fstat(source.fileno()).st_size
    if container_size != file_size:
        fail("invalid Img3 container size")
    if data_size != container_size - len(header):
        fail("invalid Img3 data size")

    data_tag = None
    encrypted = False
    offset = len(header)
    while offset < container_size:
        if container_size - offset < 12:
            fail("truncated Img3 tag header")
        source.seek(offset)
        tag_header = source.read(12)
        tag_magic, tag_size, payload_size = struct.unpack(
            "<4sII", tag_header)
        if tag_size < len(tag_header) or payload_size > tag_size - 12:
            fail("invalid Img3 tag size")
        if tag_size % 4 != 0:
            fail("unaligned Img3 tag size")
        if offset + tag_size > container_size:
            fail("Img3 tag extends beyond the container")

        if tag_magic == b"GABK":
            encrypted = True
        elif tag_magic == b"ATAD":
            if data_tag is not None:
                fail("multiple DATA tags are unsupported")
            data_tag = (offset + len(tag_header), payload_size)
        offset += tag_size

    if offset != container_size:
        fail("Img3 tags do not fill the container")
    if encrypted:
        fail("encrypted Img3 DATA requires an external decryptor")
    if data_tag is None:
        fail("Img3 container has no DATA tag")

    output_dir = os.path.dirname(os.path.abspath(output_path))
    os.makedirs(output_dir, exist_ok=True)
    temporary = tempfile.NamedTemporaryFile(
        prefix=".img3-data.", dir=output_dir, delete=False)
    temporary_path = temporary.name
    try:
        source.seek(data_tag[0])
        remaining = data_tag[1]
        with temporary:
            while remaining:
                chunk = source.read(min(remaining, 1024 * 1024))
                if not chunk:
                    fail("truncated Img3 DATA payload")
                temporary.write(chunk)
                remaining -= len(chunk)
        os.chmod(temporary_path, 0o644)
        os.replace(temporary_path, output_path)
    except BaseException:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
        raise
