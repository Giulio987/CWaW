#!/usr/bin/env python3
"""Camera fly-through paths of a level (CCameraPath resources, "EndCamera1..5").

    .venv/bin/python -I tools/camera_paths.py out.json environment.group.bin

Game over (kiwi va 0x1b318c): 3 s after ig_gameover_dead the camera manager switches to
mode 5 = "cam_flythrough" (va 0x2010e4), a CCameraControllerFlythrough (update va 0x1e4fe4):
it takes every CCameraPath of the level in resource order (va 0x1e4eec), starting with the
first and moving to the next (wrapping) when one ends. CCameraPath::Serialise (va 0x10f21c):
  0x1c speed (fixed: distance += speed * frame ms >> 12, i.e. speed * 1000/4096 units/s)
  0x14 the camera's CIwPathLine
  0x18 an optional nested CCameraPath (class hash + name hash, then its own speed, line and
       null child): the look-at line, sampled at distance * its length / the camera's length
CIwPathLine: two zero words, total length, point count, segment count, points (x, y, z),
then per segment (length, start distance). The camera is placed at the point at the
travelled distance and looks at the target point (or straight ahead without a target).
Output: [{"name", "speed" (m/s), "pos": [[x, y, z] m], "target": [[x, y, z] m] or []}].
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

UNITS = 1 / 400.0
PATH_LINE = iw_hash("CIwPathLine")
CAMERA_PATH = iw_hash("CCameraPath")
NAMES = {iw_hash("EndCamera%d" % i): "EndCamera%d" % i for i in range(1, 10)}


def read_line(b, o):
    cls, _, _, length, n, segs = struct.unpack_from("<6I", b, o)
    assert cls == PATH_LINE, hex(cls)
    o += 24
    pts = [list(struct.unpack_from("<3i", b, o + 12 * i)) for i in range(n)]
    o += 12 * n + 8 * segs
    return pts, length, o


def read_path(b, o):
    speed = struct.unpack_from("<i", b, o)[0]
    pts, length, o = read_line(b, o + 4)
    target = []
    nxt = struct.unpack_from("<I", b, o)[0]
    if nxt == CAMERA_PATH:
        target, _, _, o = read_path(b, o + 8)   # class hash + name hash of the nested path
    else:
        o += 4   # null pointer
    return pts, speed, target, o


def main(out_path, group_path):
    out = []
    for r in Group(group_path).resources:
        if r.cls != CAMERA_PATH:
            continue
        pts, speed, target, _ = read_path(r.body, 0)
        out.append({
            "name": NAMES.get(r.name_hash, "%08x" % r.name_hash),
            "speed": speed * 1000.0 / 4096.0 * UNITS,
            "pos": [[round(c * UNITS, 4) for c in p] for p in pts],
            "target": [[round(c * UNITS, 4) for c in p] for p in target],
        })
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1)
    print(out_path, len(out), "paths")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
