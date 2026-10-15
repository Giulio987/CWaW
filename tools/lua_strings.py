"""Every string literal of the decompiled Lua scripts, one per line: a name dictionary for the tools
(iwhash.load_dictionary keeps the first spelling of a hash, so the order matters: case-insensitive,
lower case first, e.g. the area "startRoom" before "StartRoom").
    .venv/bin/python -I tools/lua_strings.py game/assets/lua analysis/lua_strings.txt
"""
import glob
import os
import re
import sys

lua_dir, out = sys.argv[1], sys.argv[2]
found = set()
for f in glob.glob(os.path.join(lua_dir, "**", "*.lua"), recursive=True):
    found |= set(re.findall(r'"([^"\\\n]*)"', open(f, errors="replace").read()))
found.discard("")
with open(out, "w") as fh:
    fh.write("\n".join(sorted(found, key=lambda s: (s.lower(), [-ord(c) for c in s]))) + "\n")
