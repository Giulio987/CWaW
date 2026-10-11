#!/usr/bin/env python3
"""Pair each first-person weapon animation with the arms animation played with it.

Arms animation names are unknown, so candidates with the same keyframe times are
posed together with the weapon and the one whose hands touch the weapon mesh wins.
Writes game/assets/characters/ingame/player/arms_pairs.json:
  {weapon: {"model": hex, "anims": {"idle": [weaponAnim, armsAnim], ...}}}
"""
import itertools
import json
import os
import struct
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anim import Anim, Skeleton, Skin
from export_characters import qmat
from group import Group
from iwhash import iw_hash

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARMS_MODEL = 0x7C9433B8
TAG_WEAPON = 22  # arms bone the weapon root hangs from (found by hand/grip contact)
WEAPONS = ["colt45", "kar98", "carbine", "thompson", "mp40", "stg44", "trenchgun", "shotgun", "bar", "garand", "g43",
           "ppsh", "type100", "mg42", "raygun", "ptrs", "fg42", "sawnoff", "springfield", "arisaka", "browning",
           "flamethrower", "wunderwaffe"]
# the sawed-off shares the double-barrel's skeleton and animations; its model is the
# other model family on that skeleton (50f... contains shotgun_lod1, b5c... is the sawed-off)
ANIM_ALIAS = {"sawnoff": "shotgun"}
MODEL_OVERRIDE = {"sawnoff": 0xB5C21000}
ACTIONS = ["idle", "shoot", "reload", "rechamber", "putaway", "pullout", "raise", "sprint", "melee"]


def pose(skel, anim, frame):
    """World (R, t) per bone at a keyframe, carrying forward bones missing from sparse keyframes."""
    rot = list(skel.rot)
    pos = list(skel.pos)
    for k in range(frame + 1):
        for b, q in anim.rots[k].items():
            rot[b] = q
        for b, p in anim.pos[k].items():
            pos[b] = p
        if not anim.pos[k]:
            pos[0] = anim.root_pos[k]
    world = []
    for i, par in enumerate(skel.parent_idx):
        r, t = qmat(rot[i]), pos[i]
        if par >= 0:
            pr, pt = world[par]
            world.append((pr @ r, pt + pr @ t))
        else:
            world.append((r, t))
    return world


def skinned(skin_body, skel, anim, frame):
    """Posed vertex positions from the skin's bone-local positions (stored x4)."""
    world = pose(skel, anim, frame)
    _v, _m, _s, nsets = struct.unpack_from("<IIII", skin_body, 0)
    out = []
    pos = 16
    for _ in range(nsets):
        _c, _z, nv, size = struct.unpack_from("<IIII", skin_body, pos)
        pos += 16
        start = pos
        bones = []
        while len(bones) < 4 and skin_body[pos] != 0xFF:
            bones.append(skin_body[pos])
            pos += 1
        if len(bones) < 4:
            pos += 1
        pos += (pos - start) % 2
        nb = len(bones)
        for _ in range(nv):
            pos += 2
            locs = [np.array(struct.unpack_from("<hhh", skin_body, pos + 6 * j), float) * skel.scale for j in range(nb)]
            pos += 6 * nb
            w = skin_body[pos:pos + nb]
            pos += nb + nb % 2
            v = sum(w[j] / 128.0 * (world[bones[j]][0] @ locs[j] + world[bones[j]][1]) for j in range(nb))
            out.append(v)
    return np.array(out)


def main():
    g = Group(os.path.join(ROOT, "extracted/main/ingame/player/player.group.bin"))
    kf = iw_hash("CIwAnimKeyFrame")
    res = {(r.cls, r.name_hash): r.body for r in g.resources}
    skels = {r.name_hash: Skeleton(r.body) for r in g.resources if r.cls == iw_hash("CIwAnimSkel")}
    anims = {}
    for r in g.resources:
        if r.cls == iw_hash("CIwAnim"):
            sh = struct.unpack_from("<I", r.body, 0)[0]
            a = Anim(r.body, kf, skels[sh].scale if sh in skels else 0.25)
            anims.setdefault(a.skel, {})[r.name_hash] = a
    arms_skin = res[(iw_hash("CIwAnimSkin"), ARMS_MODEL)]
    arms_skel = skels[Skin(arms_skin).skel]
    arms_anims = anims[Skin(arms_skin).skel]
    out = {}
    skins_by_skel = {}
    for (cls, h), body in res.items():
        if cls == iw_hash("CIwAnimSkin"):
            skins_by_skel.setdefault(Skin(body).skel, []).append(h)
    verts = {h: struct.unpack_from("<H", body, 4)[0] for (cls, h), body in res.items() if cls == iw_hash("CIwModel")}
    for w in WEAPONS:
        anim_name = ANIM_ALIAS.get(w, w)
        idle = res.get((iw_hash("CIwAnim"), iw_hash(f"{anim_name}_idle")))
        if idle is None:
            continue
        # the first-person model is the most detailed skin on the weapon's own skeleton
        cands = skins_by_skel.get(struct.unpack_from("<I", idle, 0)[0], [])
        if w in MODEL_OVERRIDE:
            model = MODEL_OVERRIDE[w]
        elif cands:
            model = max(cands, key=lambda h: verts.get(h, 0))
        else:
            continue
        wskin = res[(iw_hash("CIwAnimSkin"), model)]
        wskel = skels[Skin(wskin).skel]
        entry = {"model": f"{model:08x}", "anims": {}}
        for act in ACTIONS:
            h = iw_hash(f"{anim_name}_{act}")
            a = anims.get(Skin(wskin).skel, {}).get(h)
            if a is None:
                continue
            cands = [(ah, aa) for ah, aa in arms_anims.items()
                     if len(aa.times) == len(a.times) and np.allclose(aa.times, a.times, atol=1e-3)]
            best, best_score = None, -1
            gun = skinned(wskin, wskel, a, 0)
            for ah, aa in cands:
                hands = skinned(arms_skin, arms_skel, aa, 0)
                r, t = pose(arms_skel, aa, 0)[TAG_WEAPON]
                score = (cKDTree(hands).query((r @ gun.T).T + t)[0] < 15).sum()
                if score > best_score:
                    best, best_score = ah, score
            if best is not None:
                entry["anims"][act] = [f"{h:08x}", f"{best:08x}"]
                print(f"{w}_{act}: arms {best:08x} ({len(cands)} candidates, contact {best_score})")
        # idle poses are ambiguous by timing (dozens of 1-key candidates): take the one
        # closest to where the shoot/reload animation starts
        ref = next((entry["anims"][k][1] for k in ("shoot", "reload") if k in entry["anims"]), None)
        h = iw_hash(f"{anim_name}_idle")
        if ref is not None and h in anims.get(Skin(wskin).skel, {}):
            ref_pose = np.array([t for _, t in pose(arms_skel, arms_anims[int(ref, 16)], 0)])
            idle = anims[Skin(wskin).skel][h]
            cands = [ah for ah, aa in arms_anims.items() if len(aa.times) == len(idle.times)]
            best = min(cands, key=lambda ah: np.abs(np.array([t for _, t in pose(arms_skel, arms_anims[ah], 0)]) - ref_pose).sum())
            entry["anims"]["idle"] = [f"{h:08x}", f"{best:08x}"]
            print(f"{w}_idle -> arms {best:08x} (closest to {ref})")
        out[w] = entry
    dst = os.path.join(ROOT, "game/assets/characters/ingame/player/arms_pairs.json")
    with open(dst, "w") as f:
        json.dump({"arms_model": f"{ARMS_MODEL:08x}", "tag_weapon": TAG_WEAPON, "weapons": out}, f, indent=1)
    print(dst)


if __name__ == "__main__":
    main()
