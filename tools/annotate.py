#!/usr/bin/env python3
"""Hexdump a region of a file, tagging every offset whose u32 matches a known IwHash."""
import re
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from iwhash import iw_hash, load_dictionary

path, start, length = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
buf = open(path, "rb").read()
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
names = load_dictionary(os.path.join(ROOT, "analysis", "kiwi_strings.txt"))
for tok in re.findall(rb"[A-Za-z_][A-Za-z0-9_./\\-]{2,}", buf):
    t = tok.decode("latin-1")
    for v in {t, t.rsplit("/", 1)[-1], t.rsplit(".", 1)[0], t.rsplit("/", 1)[-1].rsplit(".", 1)[0]}:
        names.setdefault(iw_hash(v), v)
end = min(len(buf), start + length)
pos = start
while pos < end:
    row = buf[pos:pos + 16]
    tags = []
    for i in range(16):
        if pos + i + 4 <= len(buf):
            h = struct.unpack_from("<I", buf, pos + i)[0]
            if h in names:
                tags.append(f"+{i:x}:{names[h]}")
    asc = "".join(chr(c) if 32 <= c < 127 else "." for c in row)
    print(f"{pos:08x}  {row.hex(' '):<47}  {asc:<16}  {' '.join(tags)}")
    pos += 16
