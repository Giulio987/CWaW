#!/usr/bin/env python3
"""Extract CIwEntSpec level entities to JSON.

Component specs are not fully decoded yet; we recover:
  - transforms: s32 pos[3], then a 2.30 fixed-point quaternion stored as
    s32 w (== 1<<30 means identity, followed by a flags byte) or s32 w,x,y,z,
    then u32 scale[3] (4096 = 1.0). Nested child entities carry their own
    transform; the entity's own transform is the last one in the body.
  - component class names (any known *Spec class hash in the body),
  - referenced models (u32 values matching a CIwModel name in the given groups).
Positions are in Airplay units (400 = 1 m).
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash, load_dictionary

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONE = 1 << 30
SCALE1 = struct.pack("<III", 4096, 4096, 4096)


def names_dictionary():
    lua = os.path.join(ROOT, "analysis", "lua_strings.txt")
    d = load_dictionary(os.path.join(ROOT, "analysis", "kiwi_strings.txt"), lua)
    bases = set()
    for line in open(lua):
        base = re.sub(r"\d+$", "", line.strip())
        bases.add(base)
        # area names ("StartRoom") also prefix their spawns and windows ("startroomZombieSpawn3")
        for suffix in ("ZombieSpawn", "ZombieWindow", "DogSpawn", "Spawn", "Window"):
            bases.add("sector_" + base.lower())
            bases.add(base.lower() + suffix)
            bases.add(base + suffix)
    for base in bases:
        d.setdefault(iw_hash(base), base)
        for i in range(40):
            for v in (f"{base}{i}", f"{base}{i:02d}"):
                d.setdefault(iw_hash(v), v)
    return d


def transforms(b):
    out = []
    i = b.find(SCALE1)
    while i >= 0:
        if i >= 22 and struct.unpack_from("<i", b, i - 5)[0] == ONE:
            pos = struct.unpack_from("<iii", b, i - 17)
            rot = (1.0, 0.0, 0.0, 0.0)
            flags = b[i - 1]
        elif i >= 28:
            pos = struct.unpack_from("<iii", b, i - 28)
            rot = tuple(v / ONE for v in struct.unpack_from("<iiii", b, i - 16))
            flags = None
        else:
            pos = None
        if pos is not None and abs(sum(c * c for c in rot) - 1) < 0.01:
            out.append({"pos": list(pos), "rot_wxyz": [round(c, 6) for c in rot], "offset": i, "flags": flags})
        i = b.find(SCALE1, i + 1)
    return out


WEAPONS = ["colt45", "kar98", "carbine", "thompson", "mp40", "stg44", "trenchgun", "shotgun", "bar", "garand", "g43",
           "ppsh", "type100", "mg42", "raygun", "ptrs", "fg42", "sawnoff", "springfield", "arisaka", "browning",
           "flamethrower", "wunderwaffe", "grenade", "molotov", "betty", "knife"]


def lod_controller(b, models):
    """CIwLODControllerCameraVolumeSpec: u32 0, u32 n, n x (u32 sectorHash, u32 lod);
    the renderable then lists its models from LOD 0 (most detailed) down."""
    i = b.find(struct.pack("<I", iw_hash("CIwLODControllerCameraVolumeSpec")))
    if i < 0:
        return None
    (n,) = struct.unpack_from("<I", b, i + 8)
    pairs = {}
    for k in range(n):
        h, lod = struct.unpack_from("<II", b, i + 12 + 8 * k)
        pairs[f"{h:08x}"] = lod
    order = []
    for j in range(i + 12 + 8 * n, len(b) - 3):
        (h,) = struct.unpack_from("<I", b, j)
        if h in models and f"{h:08x}" not in order:
            order.append(f"{h:08x}")
    return {"sectors": pairs, "lods": order}


def colliders(b):
    """CIwColliderSpec + CIwVolumeAABox: 4 zero bytes, then s32 min[3], max[3] in entity units."""
    out = []
    key = struct.pack("<II", iw_hash("CIwColliderSpec"), iw_hash("CIwVolumeAABox"))
    i = b.find(key)
    while i >= 0:
        lo = struct.unpack_from("<iii", b, i + 12)
        hi = struct.unpack_from("<iii", b, i + 24)
        if all(h >= l for l, h in zip(lo, hi)):
            out.append({"min": list(lo), "max": list(hi), "offset": i})
        i = b.find(key, i + 1)
    return out


def action_params(b, comps_hashes):
    """Cost fields of the buy actions: class hash, u32 cost, u32 0, u32 weapon, u32 ammoCost."""
    out = {}
    names = {iw_hash(w): w for w in WEAPONS}
    names.update({iw_hash(w + "_upgrade"): w + "_upgrade" for w in WEAPONS})
    for cls in ("CActionBuySpec", "CActionBuyWeaponSpec", "CActionBuyGrenadeSpec", "CActionBuyPerkSpec",
                "CActionBuyTrapSpec", "CActionBuyBettySpec"):
        i = b.find(struct.pack("<I", iw_hash(cls)))
        if i < 0:
            continue
        out["cost"] = struct.unpack_from("<I", b, i + 4)[0]
        if cls == "CActionBuyWeaponSpec":
            w, ammo = struct.unpack_from("<II", b, i + 12)
            out["weapon"] = names.get(w, f"{w:08x}")
            out["ammo_cost"] = ammo
    return out


def main(out_path, group_path, *model_groups):
    d = names_dictionary()
    g = Group(group_path)
    c_ent, c_model = iw_hash("CIwEntSpec"), iw_hash("CIwModel")
    models = {r.name_hash for gg in [g] + [Group(p) for p in model_groups] for r in gg.resources if r.cls == c_model}
    ents = []
    for r in g.resources:
        if r.cls != c_ent:
            continue
        b = r.body
        comps, refs = [], []
        for i in range(len(b) - 3):
            (h,) = struct.unpack_from("<I", b, i)
            n = d.get(h, "")
            if n.startswith("C") and n.endswith("Spec") and n not in comps:
                comps.append(n)
            if h in models and h not in refs:
                refs.append(h)
        xf = transforms(b)
        ents.append({"name": d.get(r.name_hash, f"{r.name_hash:08x}"), "hash": f"{r.name_hash:08x}",
                     "components": comps, "models": [f"{h:08x}" for h in refs],
                     "transform": xf[-1] if xf else None, "children": xf[:-1], "size": len(b),
                     "params": action_params(b, comps), "colliders": colliders(b),
                     "lod": lod_controller(b, models)})
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(ents, f, indent=1)
    # scene sectors (CIwSGSectorBuilder): u32 index, u8 0, s32 min[3], s32 max[3]
    sectors = []
    for r in g.resources:
        if r.cls == iw_hash("CIwSGSectorBuilder"):
            lo = struct.unpack_from("<iii", r.body, 5)
            hi = struct.unpack_from("<iii", r.body, 17)
            sectors.append({"hash": f"{r.name_hash:08x}", "name": d.get(r.name_hash, ""), "min": list(lo), "max": list(hi)})
    with open(os.path.join(os.path.dirname(out_path), "sectors.json"), "w") as f:
        json.dump(sectors, f, indent=1)
    print(out_path, len(ents), "entities,", sum(1 for e in ents if e["transform"]), "with transform")


if __name__ == "__main__":
    main(*sys.argv[1:])  # out.json environment.group.bin [other groups whose models entities may use...]
