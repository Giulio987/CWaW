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


def debris_yaw(entities_path, group_path, dynamics_path):
    """Debris rotation: of the four wall-aligned yaws, the one whose closed-pose model
    best fills the entity's own collider box (CIwColliderSpec, world aligned)."""
    import struct
    from anim import Anim, Skeleton, Skin
    from pair_arms import skinned

    ents = json.load(open(entities_path))
    dyn = Group(dynamics_path)
    res = {(r.cls, r.name_hash): r.body for r in dyn.resources}
    skels = {r.name_hash: Skeleton(r.body) for r in dyn.resources if r.cls == iw_hash("CIwAnimSkel")}
    for e in ents:
        if "CActionBuySpec" not in e["components"] or not e["models"] or not e.get("colliders"):
            continue
        h = int(e["models"][0], 16)
        skin_body = res.get((iw_hash("CIwAnimSkin"), h))
        if skin_body is None:
            continue
        skel = skels[Skin(skin_body).skel]
        poses = [Anim(b, iw_hash("CIwAnimKeyFrame"), skel.scale) for (c, _n), b in res.items()
                 if c == iw_hash("CIwAnim") and struct.unpack_from("<I", b, 0)[0] == Skin(skin_body).skel]
        poses = [a for a in poses if len(a.times) == 1]
        if not poses:
            continue
        verts = skinned(skin_body, skel, poses[0], 0)
        child = np.array(e["children"][-1]["pos"], float) if e["children"] else np.zeros(3)
        box = e["colliders"][0]
        lo, hi = np.array(box["min"], float), np.array(box["max"], float)
        base = e.get("wall_yaw", 0.0)
        best = None
        for k in range(4):
            yaw = base + k * math.pi / 2
            c, s_ = math.cos(yaw), math.sin(yaw)
            # Godot Basis(UP, yaw): x' = x cos + z sin, z' = -x sin + z cos
            v = verts + child
            rx = v[:, 0] * c + v[:, 2] * s_
            rz = -v[:, 0] * s_ + v[:, 2] * c
            inside = ((rx >= lo[0]) & (rx <= hi[0]) & (rz >= lo[2]) & (rz <= hi[2])).mean()
            if best is None or inside > best[0]:
                best = (inside, yaw)
        e["debris_yaw"] = float(best[1])
        print(e["name"], "debris_yaw", round(math.degrees(best[1])), "fit", round(best[0], 2))
    json.dump(ents, open(entities_path, "w"), indent=1)


if __name__ == "__main__" and len(sys.argv) > 3:
    debris_yaw(sys.argv[1], sys.argv[2], sys.argv[3])
