#!/usr/bin/env python3
"""Build a Godot 4.x .pck file from the Pixelorama MCP extension source."""

import hashlib
import os
import struct
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(SCRIPT_DIR, "PixeloramaMCP")
OUT_DIR = os.path.join(SCRIPT_DIR, "dist")
OUT_PATH = os.path.join(OUT_DIR, "PixeloramaMCP.pck")

# Godot 4.x PCK header constants
MAGIC = b"GDPC"
PACK_FORMAT = 2
ENGINE_MAJOR = 4
ENGINE_MINOR = 3
ENGINE_PATCH = 0
PACK_FLAGS = 0
FILE_BASE_OFFSET = 0
# Godot reads 16 reserved int32 values = 64 bytes
# Total header: magic(4) + format(4) + major(4) + minor(4) + patch(4)
#             + flags(4) + base_offset(8) + reserved(64) = 96 bytes
HEADER_RESERVED = b"\x00" * 64
HEADER_SIZE = 96


def collect_files(src_dir):
    """Walk src_dir and return list of (res_path, abs_path) sorted by res_path."""
    entries = []
    for root, _dirs, files in os.walk(src_dir):
        for name in files:
            abs_path = os.path.join(root, name)
            rel = os.path.relpath(abs_path, src_dir)
            res_path = "res://" + rel.replace(os.sep, "/")
            entries.append((res_path, abs_path))
    entries.sort(key=lambda e: e[0])
    return entries


def pad_to_4(length):
    """Return number of zero-padding bytes needed to align length to 4."""
    remainder = length % 4
    return (4 - remainder) % 4


def build_pck(entries, out_path):
    """Build .pck binary and write to out_path."""
    # Read all file contents and compute MD5 hashes
    file_data_list = []
    for res_path, abs_path in entries:
        with open(abs_path, "rb") as f:
            data = f.read()
        md5 = hashlib.md5(data).digest()
        file_data_list.append((res_path, data, md5))

    # Compute file offsets relative to data section start
    # First pass: assign offsets
    offset = 0
    file_records = []  # (res_path, offset, size, md5)
    for res_path, data, md5 in file_data_list:
        size = len(data)
        file_records.append((res_path, offset, size, md5))
        offset += size

    # Build the file table binary
    file_table = struct.pack("<I", len(file_records))
    for res_path, file_offset, file_size, md5 in file_records:
        path_bytes = res_path.encode("utf-8")
        path_len = len(path_bytes)
        padding = pad_to_4(path_len)
        file_table += struct.pack("<I", path_len)
        file_table += path_bytes + b"\x00" * padding
        file_table += struct.pack("<q", file_offset)  # int64 LE
        file_table += struct.pack("<q", file_size)  # int64 LE
        file_table += md5  # 16 bytes
        file_table += struct.pack("<I", 0)  # flags

    # Build header
    header = MAGIC
    header += struct.pack("<I", PACK_FORMAT)
    header += struct.pack("<I", ENGINE_MAJOR)
    header += struct.pack("<I", ENGINE_MINOR)
    header += struct.pack("<I", ENGINE_PATCH)
    header += struct.pack("<I", PACK_FLAGS)
    header += struct.pack("<q", FILE_BASE_OFFSET)
    header += HEADER_RESERVED
    assert len(header) == HEADER_SIZE, f"Header is {len(header)} bytes, expected {HEADER_SIZE}"

    # Write the .pck file: header + file table + file data
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(file_table)
        for _res_path, data, _md5 in file_data_list:
            f.write(data)

    return len(file_records)


def main():
    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: source directory not found: {SRC_DIR}", file=sys.stderr)
        sys.exit(1)

    entries = collect_files(SRC_DIR)
    if not entries:
        print(f"ERROR: no files found in {SRC_DIR}", file=sys.stderr)
        sys.exit(1)

    count = build_pck(entries, OUT_PATH)
    print(f"Packed {count} files -> {OUT_PATH}")


if __name__ == "__main__":
    main()
