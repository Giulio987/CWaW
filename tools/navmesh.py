#!/usr/bin/env python3
"""Export the level's original navigation mesh (CIwNavMesh resources) to JSON.

CIwNavMesh body (one resource per piece, 124 on Shi No Numa):
  u32 numVerts, numVerts x s32 pos[3] (400 units = 1 m),
  u32 numTris, numTris x { u16 vert[3], s16 neighbour[3] (-1 border, -2 link to
  another piece), u32 flags }, then data not decoded yet (links/portals).
Flags: 0 on most triangles, 4 on stairs and ramps, 2 under the swamp water.

Writes {"tris": [[x1,y1,z1, x2,y2,z2, x3,y3,z3, flags], ...]} in metres.
Usage: python -I tools/navmesh.py out.json environment.group.bin
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash


def navmesh(group_path):
    tris = []
    cls = iw_hash("CIwNavMesh")
    for r in Group(group_path).resources:
        if r.cls != cls:
            continue
        b = r.body
        (nv,) = struct.unpack_from("<I", b, 0)
        verts = [struct.unpack_from("<iii", b, 4 + 12 * i) for i in range(nv)]
        o = 4 + 12 * nv
        (nt,) = struct.unpack_from("<I", b, o)
        o += 4
        for _ in range(nt):
            v = struct.unpack_from("<3H3hI", b, o)
            o += 16
            t = []
            for i in v[:3]:
                t += [round(c / 400.0, 4) for c in verts[i]]
            tris.append(t + [v[6]])
    return tris


def main(out_path, group_path):
    tris = navmesh(group_path)
    with open(out_path, "w") as f:
        json.dump({"tris": tris}, f, separators=(",", ":"))
    print(out_path, len(tris), "navmesh triangles")


if __name__ == "__main__":
    main(*sys.argv[1:])
