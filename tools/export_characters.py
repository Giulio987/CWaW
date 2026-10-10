#!/usr/bin/env python3
"""Export skinned models (every CIwAnimSkin) with their skeleton and all
animations of that skeleton to game/assets/characters/<group>/<model>.glb."""
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anim import Anim, Skeleton, Skin
from export_gltf import SCALE, GlbWriter, Index
from group import Group
from iwhash import iw_hash
from model import Model
from textures import group_dir

# triangle list names recovered by hash guessing; others stay as hex
PART_NAMES = {iw_hash(n): n for n in (
    "body", "legs", "neck", "leftarm", "rightarm", "leftelbow", "rightelbow", "headb", "sleevel", "sleever")}
C = {n: iw_hash(n) for n in ("CIwModel", "CIwAnimSkin", "CIwAnimSkel", "CIwAnim", "CIwAnimKeyFrame")}


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def add_skeleton(w, skel):
    """Joint nodes; returns (node indices, inverse bind matrices)."""
    first = len(w.j["nodes"])
    world = []
    for i, (q, p, par) in enumerate(zip(skel.rot, skel.pos, skel.parent_idx)):
        w.j["nodes"].append({"name": f"bone{i:02d}_{skel.names[i]:08x}", "rotation": q.tolist(),
                             "translation": (p * SCALE).tolist()})
        m = np.eye(4)
        m[:3, :3] = qmat(q)
        m[:3, 3] = p * SCALE
        world.append(world[par] @ m if par >= 0 else m)
        if par >= 0:
            w.j["nodes"][first + par].setdefault("children", []).append(first + i)
    ibm = np.array([np.linalg.inv(m).T.reshape(16) for m in world], np.float32)  # column-major
    roots = [first + i for i, par in enumerate(skel.parent_idx) if par < 0]
    return list(range(first, first + len(skel.names))), ibm, roots


def add_animation(w, name, anim, joints):
    samplers, channels = [], []

    def channel(node, path, times, values, kind):
        samplers.append({"input": w.accessor(np.array(times, np.float32), 5126, "SCALAR"),
                         "output": w.accessor(np.array(values, np.float32), 5126, kind),
                         "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})

    for b, node in enumerate(joints):
        keys = [(t, r[b]) for t, r in zip(anim.times, anim.rots) if b in r]
        if not keys:
            continue
        qs = [keys[0][1]]
        for _, q in keys[1:]:
            qs.append(-q if np.dot(q, qs[-1]) < 0 else q)  # keep shortest path
        channel(node, "rotation", [k[0] for k in keys], qs, "VEC4")
    for b, node in enumerate(joints):
        if b == 0:
            continue
        keys = [(t, p[b]) for t, p in zip(anim.times, anim.pos) if b in p]
        if keys:
            channel(node, "translation", [k[0] for k in keys], [k[1] * SCALE for k in keys], "VEC3")
    channel(joints[0], "translation", anim.times, [p * SCALE for p in anim.root_pos], "VEC3")
    w.j.setdefault("animations", []).append({"name": name, "samplers": samplers, "channels": channels})


def main(out_dir, paths):
    groups = [Group(p) for p in paths]
    index = Index(groups)
    skels, anims, models = {}, {}, {}
    for g in groups:
        for r in g.resources:
            if r.cls == C["CIwAnimSkel"]:
                skels[r.name_hash] = Skeleton(r.body)
    for g in groups:
        for r in g.resources:
            if r.cls == C["CIwAnim"]:
                try:
                    skel_hash = struct.unpack_from("<I", r.body, 0)[0]
                    a = Anim(r.body, C["CIwAnimKeyFrame"], skels[skel_hash].scale if skel_hash in skels else 0.25)
                except (ValueError, AssertionError) as e:
                    print(f"skip anim {r.name_hash:08x}: {e}")
                    continue
                anims.setdefault(a.skel, []).append((r.name_hash, a))
            if r.cls == C["CIwModel"]:
                models[(group_dir(g.path), r.name_hash)] = r.body
    for g in groups:
        gdir = group_dir(g.path)
        for r in g.resources:
            if r.cls != C["CIwAnimSkin"]:
                continue
            skin = Skin(r.body)
            body = models.get((gdir, skin.model))
            if body is None or skin.skel not in skels:
                print(f"skip skin {r.name_hash:08x}: model or skeleton missing")
                continue
            m = Model(body)
            skel = skels[skin.skel]
            w = GlbWriter(os.path.join(out_dir, gdir, f"{skin.model:08x}.glb"))
            w.add_model(f"{skin.model:08x}", m, index, gdir, split_parts=True, part_names=PART_NAMES)
            if not w.j["meshes"]:
                continue
            joints, ibm, roots = add_skeleton(w, skel)
            n = len(m.verts)
            jnt = np.zeros((n, 4), np.uint16)
            wgt = np.zeros((n, 4), np.float32)
            for v in range(n):
                inf = sorted(skin.influences.get(int(m.unique_of[v]), [(0, 1.0)]), key=lambda x: -x[1])[:4]
                tot = sum(x[1] for x in inf) or 1.0
                for k, (bone, wt) in enumerate(inf):
                    jnt[v, k], wgt[v, k] = bone, wt / tot
            ja = w.accessor(jnt, 5123, "VEC4", 34962)
            wa = w.accessor(wgt, 5126, "VEC4", 34962)
            for mesh in w.j["meshes"]:
                for prim in mesh["primitives"]:
                    prim["attributes"]["JOINTS_0"] = ja
                    prim["attributes"]["WEIGHTS_0"] = wa
            w.j["skins"] = [{"joints": joints, "inverseBindMatrices": w.accessor(ibm, 5126, "MAT4"),
                             "skeleton": roots[0]}]
            for node in w.j["nodes"]:
                if "mesh" in node:
                    node["skin"] = 0
            w.j["scenes"][0]["nodes"] += roots
            for name, a in anims.get(skin.skel, []):
                add_animation(w, f"{name:08x}", a, joints)
            w.write()
            print(w.out_path, len(anims.get(skin.skel, [])), "anims")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
