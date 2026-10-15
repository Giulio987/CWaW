#!/usr/bin/env python3
"""Export the level's CRouteShortcut resources (zombie jumps down / climbs up) to JSON.

CRouteShortcut body (Der Riese 11, Shi No Numa 1):
  s32 from[3], s32 to[3]           entry and exit point, one way (400 units = 1 m)
  rotation                          s32 w == 1<<30 + flags byte (identity, 5 bytes) or
                                    s32 w,x,y,z (2.30 fixed point, 16 bytes)
  u32 input                         ASM input the route requester sets on the zombie:
                                    fad7bdba..bd = jump down (states 46-49 of the zombie
                                    ASM, drops of ~2.5 / 1.8 / 3.6 / 4.8 m), 07a4bba6 =
                                    climb up (state 50), 83b8f639 = jump down (states 40-42)
  u32 value, u32 5675108b, u32 0
  s32 min[3], s32 max[3]            box around the shortcut
Writes {"shortcuts": [{"name", "from", "to", "input"}...]} in metres.
Usage: python -I tools/route_shortcuts.py out.json environment.group.bin
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

ONE = 1 << 30


def shortcuts(group_path):
    out = []
    cls = iw_hash("CRouteShortcut")
    for r in Group(group_path).resources:
        if r.cls != cls:
            continue
        b = r.body
        a = struct.unpack_from("<3i", b, 0)
        c = struct.unpack_from("<3i", b, 12)
        o = 29 if struct.unpack_from("<i", b, 24)[0] == ONE else 40
        (inp,) = struct.unpack_from("<I", b, o)
        out.append({"name": "%08x" % r.name_hash,
                    "from": [round(v / 400.0, 4) for v in a],
                    "to": [round(v / 400.0, 4) for v in c],
                    "input": "%08x" % inp})
    return out


if __name__ == "__main__":
    data = {"shortcuts": shortcuts(sys.argv[2])}
    with open(sys.argv[1], "w") as f:
        json.dump(data, f, indent=1)
    print(sys.argv[1], len(data["shortcuts"]))
