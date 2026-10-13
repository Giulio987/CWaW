#!/usr/bin/env python3
"""Pair each first-person weapon animation with the arms animation played with it.

The pairs come from the gun's CIsAnimStateMachine (CItemGun anim_state_machine):
every state names the arms and weapon animations it plays, in a fixed state order
shared by all guns (STATE_ACTIONS). Actions missing there fall back to a guess:
arms candidates with the same keyframe times are posed together with the weapon and
the one whose hands touch the weapon mesh wins.
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
from weapon_stats import STATE_TAG, parse_gun

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
# state index -> action (11 raise, 12 idle loop, 16 fire, 21 reload, 53 rechamber; 50 is
# the Perk-a-Cola drink, see viewmodel.gd). Aiming down the sights (transitions of the
# state machine: idle --toggleAim--> 32 --> 34 "aiming" --toggleAim--> 33 --> idle):
# 32 raise to the sights (outputs aim, aimfov and the "lockon" pulse; arms only, the
# weapon keeps <gun>_idle; was labelled "putaway" before), 33 lower the sights (outputs
# walk, reticle), 34 "aiming" (iw_hash; weapon <gun>_aimidle, output adsRender), 35 fire
# while aiming (36 the same, 37/38 Double Tap at double speed; weapon <gun>_aimshoot)
STATE_ACTIONS = {12: "idle", 16: "shoot", 21: "reload", 53: "rechamber", 11: "pullout",
                 32: "aim_in", 33: "aim_out", 34: "aim", 35: "aim_shoot"}
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


def state_pairs(body, arms, weapon):
    """{action: (weapon anim, arms anim)} from a CIsAnimStateMachine body."""
    offs, i = [], body.find(STATE_TAG)
    while i >= 0:
        offs.append(i)
        i = body.find(STATE_TAG, i + 1)
    out = {}
    for k, o in enumerate(offs):
        idx = struct.unpack_from("<I", body, o + 20)[0]
        if idx not in STATE_ACTIONS:
            continue
        e = offs[k + 1] if k + 1 < len(offs) else len(body)
        hs = [struct.unpack_from("<I", body, q)[0] for q in range(o, e - 3)]
        a = next((h for h in hs if h in arms), None)
        w = next((h for h in hs if h in weapon), None)
        if a is not None and w is not None:
            out[STATE_ACTIONS[idx]] = (w, a)
    return out


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
    machines = {}
    for r in g.resources:
        if r.cls == iw_hash("CItemGun"):
            gun = parse_gun(r.body)
            machines.setdefault(gun["name"], res.get((iw_hash("CIsAnimStateMachine"), int(gun["anim_state_machine"], 16))))
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
        machine = machines.get(w) or machines.get(anim_name)
        known = state_pairs(machine, arms_anims, anims.get(Skin(wskin).skel, {})) if machine else {}
        for act, (wa, aa) in known.items():
            entry["anims"][act] = [f"{wa:08x}", f"{aa:08x}"]
            print(f"{w}_{act}: arms {aa:08x} (state machine)")
        for act in ACTIONS:
            if act in known:
                continue
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
        if "idle" not in known and ref is not None and h in anims.get(Skin(wskin).skel, {}):
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
