#!/usr/bin/env python3
"""Flight paths of the level entities with a CIwAnimatorSpec (Shi No Numa's dragonflies).

    .venv/bin/python -I tools/animators.py out.json environment.group.bin

The animator plays a CIwAnim of the main effects group on a one-bone skeleton: the
root keyframes move and turn the entity's model around its placed transform, looping
(dragonfly1..9 use 6a83866c, 9.3 s; "dragonfly" and 6a83804c use 6a83866b). The spec
names the animation by hash; any CIwAnim hash of the effects group found in the spec
body is taken. Output: {entity: {"times": [s], "pos": [[x, y, z] m], "rot": [[x, y, z, w]]}}.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anim import Anim
from group import Group
from iwhash import iw_hash

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EFFECTS = os.path.join(ROOT, "extracted/main/ingame/effects/effects.group.bin")
UNITS = 1 / 400.0


def main(out_path, group_path):
    kf = iw_hash("CIwAnimKeyFrame")
    anims = {r.name_hash: r.body for r in Group(EFFECTS).resources if r.cls == iw_hash("CIwAnim")}
    out = {}
    for r in Group(group_path).resources:
        if r.cls != iw_hash("CIwEntSpec"):
            continue
        b = r.body
        h = next((v for v in (struct.unpack_from("<I", b, o)[0] for o in range(len(b) - 3)) if v in anims), None)
        if h is None:
            continue
        a = Anim(anims[h], kf, 0.25)   # one-bone skeleton 4db7c78b, posScale 1024
        rots, last = [], [0.0, 0.0, 0.0, 1.0]
        for k in range(len(a.times)):
            last = [float(x) for x in a.rots[k].get(0, last)]
            rots.append(last)
        out["%08x" % r.name_hash] = {"anim": "%08x" % h, "times": [round(t, 4) for t in a.times],
                                    "pos": [[round(float(c) * UNITS, 4) for c in p] for p in a.root_pos], "rot": rots}
    with open(out_path, "w") as f:
        json.dump(out, f)
    print("%s: %d animated entities" % (out_path, len(out)))


if __name__ == "__main__":
    main(*sys.argv[1:3])
