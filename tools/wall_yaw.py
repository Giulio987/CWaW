#!/usr/bin/env python3
"""Add "wall_yaw" (radians, direction of the wall normal) to barricade and debris
entities in entities.json. The original entities carry no rotation for these, so
the wall is measured from the level geometry: vertical triangles near the entity
whose plane passes close to it vote (area-weighted) for a normal direction."""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash
from model import Model


def main(entities_path, group_path):
    ents = json.load(open(entities_path))
    g = Group(group_path)
    offset = {}
    for e in ents:
        for h in [e["hash"]] + e["models"]:
            offset.setdefault(h, np.array(e["transform"]["pos"], float))
    tris = []
    for r in g.resources:
        if r.cls != iw_hash("CIwModel"):
            continue
        m = Model(r.body)
        if m.verts is None:
            continue
        off = offset.get(f"{r.name_hash:08x}", 0)
        for _, _, idx in m.trilists:
            idx = idx[: len(idx) // 3 * 3].reshape(-1, 3)
            tris.append(m.verts[idx].astype(float) + off)
    t = np.concatenate(tris)
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    area = np.linalg.norm(n, axis=1)
    n = n / np.maximum(area, 1e-9)[:, None]
    c = t.mean(1)
    vertical = np.abs(n[:, 1]) < 0.2
    count = 0
    for e in ents:
        comps = e["components"]
        if "CBarricadeSpec" not in comps and "CActionBuySpec" not in comps:
            continue
        p = np.array(e["transform"]["pos"], float) + [0, 500, 0]
        near = vertical & (np.linalg.norm((c - p)[:, [0, 2]], axis=1) < 600) & (np.abs(c[:, 1] - p[1]) < 600)
        plane = np.abs(((p - t[:, 0]) * n).sum(1)) < 120
        sel = near & plane
        if sel.sum() == 0:
            continue
        ang = np.arctan2(n[sel, 0], n[sel, 2]) % math.pi
        hist, edges = np.histogram(ang, bins=72, range=(0, math.pi), weights=area[sel])
        hist = hist + np.roll(hist, 1) + np.roll(hist, -1)  # smooth, wraps at 180 deg
        e["wall_yaw"] = float(edges[hist.argmax()] + math.pi / 144)
        count += 1
    json.dump(ents, open(entities_path, "w"), indent=1)
    print(entities_path, count, "wall directions")


if __name__ == "__main__" and len(sys.argv) == 3:
    main(sys.argv[1], sys.argv[2])


def uphill(points):
    """Horizontal direction in which a point cloud rises (least squares plane y = ax + bz + c)."""
    a = np.c_[points[:, 0], points[:, 2], np.ones(len(points))]
    (gx, gz, _), *_ = np.linalg.lstsq(a, points[:, 1], rcond=None)
    v = np.array([gx, gz])
    return v / (np.linalg.norm(v) + 1e-9), np.linalg.norm([gx, gz])


def flag_matrix(xf):
    """Rotation of an entity transform as Godot's Level.flag_transform builds it: the
    quaternion, or for the identity one the quarter turns in the flags byte
    (0x10 = -90 deg, 0x04 = 180 deg about Y)."""
    from export_characters import qmat
    w, x, y, z = xf["rot_wxyz"]
    m = qmat([x, y, z, w])
    yaw = 0.0
    if xf.get("flags") is not None:
        yaw = (-math.pi / 2 if xf["flags"] & 0x10 else 0.0) + (math.pi if xf["flags"] & 0x04 else 0.0)
    c, s_ = math.cos(yaw), math.sin(yaw)
    return np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]]) @ m


def closed_box(entities_path, group_path, dynamics_path):
    """Debris without a collider box (the Shi No Numa gates stored with a real rotation
    only have a use cylinder): add "closed_box", the bounds of the model in its closed
    pose (first frame of the opening animation) in the entity frame, as the blocker."""
    import struct
    from anim import Anim, Skeleton, Skin
    from pair_arms import skinned

    ents = json.load(open(entities_path))
    dyn = Group(dynamics_path)
    res = {(r.cls, r.name_hash): r.body for r in dyn.resources}
    skels = {r.name_hash: Skeleton(r.body) for r in dyn.resources if r.cls == iw_hash("CIwAnimSkel")}
    for e in ents:
        e.pop("debris_yaw", None)  # older builds fitted a yaw to the collider box
        if "CActionBuySpec" not in e["components"] or not e["models"] or e.get("colliders"):
            continue
        skin_body = res.get((iw_hash("CIwAnimSkin"), int(e["models"][0], 16)))
        if skin_body is None:
            continue
        skel_hash = Skin(skin_body).skel
        skel = skels[skel_hash]
        anims = [Anim(b, iw_hash("CIwAnimKeyFrame"), skel.scale) for (c, _n), b in res.items()
                 if c == iw_hash("CIwAnim") and struct.unpack_from("<I", b, 0)[0] == skel_hash]
        opening = max((a for a in anims if len(a.times) > 1), key=lambda a: a.times[-1], default=None)
        if opening is None:
            continue
        v = skinned(skin_body, skel, opening, 0)
        if e["children"]:
            ch = e["children"][-1]
            v = v @ flag_matrix(ch).T + np.array(ch["pos"], float)
        e["closed_box"] = {"min": [round(float(c)) for c in v.min(0)], "max": [round(float(c)) for c in v.max(0)]}
        print(e["name"], "closed_box", e["closed_box"])
    json.dump(ents, open(entities_path, "w"), indent=1)


if __name__ == "__main__" and len(sys.argv) > 3:
    closed_box(sys.argv[1], sys.argv[2], sys.argv[3])
