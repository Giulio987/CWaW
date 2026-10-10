#!/usr/bin/env python3
"""Dump CIwLuaScriptRes bodies (cstring path, u32 len, Lua 5.1 bytecode) to .luac files."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

CLS = iw_hash("CIwLuaScriptRes")

out_dir = sys.argv[1]
for p in sys.argv[2:]:
    for r in Group(p).resources:
        if r.cls != CLS:
            continue
        nul = r.body.index(b"\0")
        path = r.body[:nul].decode("latin-1").replace("//", "/")
        (n,) = struct.unpack_from("<I", r.body, nul + 1)
        dst = os.path.join(out_dir, path + "c")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(r.body[nul + 5: nul + 5 + n])
        print(dst, n)
