#!/usr/bin/env python3
"""Hit, impact and muzzle-flash effects of the effects group -> JSON (scripts/hit_fx.gd).

  hit_fx.py game/assets/effects/hit_fx.json

Decodes the effect entities (CIwEntSpec) the weapons and the zombies' CHitTemplate use:

CRenderableEffectEmitterSpec (Serialise kiwi va 0x26629c): CRenderableSpec base (volume,
u8, u8, u32, u32), the emitter parameters (va 0x1afa14, members 0x50..):
  +0x00 u32 coordinate mode (1 = particles in the entity's frame, 2 = world)
  +0x04 u32 render frame (0 = camera-facing quads, 1 = quads in the entity's XY plane)
  +0x08 i32[2] time between spawns (ms)       +0x10 i32[2] lifetime (ms)
  +0x18 i32[2] half size (units)               +0x20 i32 aspect scale (4096 = 1)
  +0x24 u8 size by life (1: shrinks to 0 over the life)
  +0x28 i32[2] size decay (4096ths per ms, x4096; negative = grows)
  +0x30 u8 alpha by life (1: fades to 0 over the life)
  +0x34 i32[2] alpha decay (same units)        +0x3c i32[2] start angle (4096 = 360 deg)
  +0x44 i32[2] spin (angle units per ms, x4096)
  +0x74 i16[2] pivot (4096 = one half size along the rotated axes)
  +0x4c range (u32 type 1 box / 2 sphere / 3 cylinder, vec3 min, vec3 max): spawn position
  +0x78 range: velocity (units per ms x4096)   +0xa0 vec3 acceleration (per ms, x4096)
  +0xb8 u8[4] cels, +0xbc i32 cel time, +0xc0 u8 (texture cels: none used here)
then +0x114 material, +0x118 emission time (ms; <= 0 = until stopped).
Update (kiwi va 0x264050): a dead slot respawns when the accumulated time passes a new
random interval; size *= (1 - decay t), alpha likewise, angle += spin t, velocity +=
acceleration t, position += velocity t. Drawn (va 0x2757dc) as quads of half size
size x (1, aspect) where aspect = texture height / width x scale, rotated by the angle,
shifted by the pivot, colour = the material's (alpha x alpha).

CRenderableEffectSplatSpec (Serialise va 0x2661d0; spawn va 0x1cda44, update va 0x2657c4,
draw va 0x22aabc): u32 count, i32[2] angle step (x 1/count turn, 4096ths), i32[2] size,
vec3 speed min, vec3 speed max, i32 turn rate, i32 stretch rate, i32 grow rate,
i32 gravity scale (world gravity x this / 4096), material, lifetime (ms). Each droplet
starts at the origin with velocity (sin a x sx, cos a x sy, sz) in the entity's XY plane
(a = running sum of the steps), turns towards its velocity, stretches (up to x11) and
grows in (sin of a quarter turn); it is drawn as a kite in the entity's XY plane.

CIwGFXEmitterSpec (Serialise va 0x182258): see scripts/iw_emitter.gd.

Child entities (u32 CIwEntSpec, name, kind 1 + CIwSpecList, transform) add their spec
list's emitters with the child's transform.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entities import transforms
from group import Group
from iwhash import iw_hash

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EFFECTS = os.path.join(ROOT, "extracted/main/ingame/effects/effects.group.bin")
PLAYER = os.path.join(ROOT, "extracted/main/ingame/player/player.group.bin")
ZOMBIES = os.path.join(ROOT, "extracted/main/ingame/zombiesbase/zombiesbase.group.bin")
DOGS = os.path.join(ROOT, "extracted/main/ingame/dogs/dog.group.bin")

H = lambda s: struct.pack("<I", iw_hash(s))
EMITTER, SPLAT, GFX = H("CRenderableEffectEmitterSpec"), H("CRenderableEffectSplatSpec"), H("CIwGFXEmitterSpec")
CYL, SPH = iw_hash("CIwVolumeCylinder"), iw_hash("CIwVolumeSphere")
ENT = H("CIwEntSpec")
GUNS = ["colt45", "magnum", "kar98", "carbine", "thompson", "mp40", "stg44", "trenchgun", "shotgun", "bar",
        "garand", "g43", "ppsh", "type100", "mg42", "raygun", "ptrs", "fg42", "sawnoff", "springfield",
        "arisaka", "browning", "flamethrower", "wunderwaffe"]


def i32(b, o):
    return struct.unpack_from("<i", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def pair(b, o):
    return [i32(b, o), i32(b, o + 4)]


def vec(b, o):
    return [i32(b, o), i32(b, o + 4), i32(b, o + 8)]


def renderable_base(b, o):
    vol = u32(b, o)
    if vol not in (CYL, SPH):
        raise ValueError("volume %08x" % vol)
    return o + 4 + (24 if vol == CYL else 20) + 10


def material(mats, h):
    m = mats.get(h)
    if m is None:
        return {"blend": 4, "color": [255, 255, 255, 255]}
    return {"blend": m[3], "color": list(m[13:17])}


def emitter(b, o, mats):
    o = renderable_base(b, o + 4)
    p = {"type": "emitter", "mode": i32(b, o), "frame": i32(b, o + 4), "every": pair(b, o + 8),
         "life": pair(b, o + 16), "size": pair(b, o + 24), "aspect": i32(b, o + 32),
         "size_by_life": b[o + 36], "size_decay": pair(b, o + 37), "alpha_by_life": b[o + 45],
         "alpha_decay": pair(b, o + 46), "angle": pair(b, o + 54), "spin": pair(b, o + 62),
         "pivot": list(struct.unpack_from("<hh", b, o + 70))}
    o += 74
    p["box_type"], p["box"] = i32(b, o), [vec(b, o + 4), vec(b, o + 16)]
    o += 28
    p["vel_type"], p["vel"] = i32(b, o), [vec(b, o + 4), vec(b, o + 16)]
    o += 28
    p["accel"] = vec(b, o)
    o += 12 + 4 + 4 + 1
    mat = u32(b, o)
    p["tex"], p["emit"] = "%08x" % mat, i32(b, o + 4)
    p.update(material(mats, mat))
    if p["size_by_life"]:
        p["size_decay"] = [0, 0]   # unused (uninitialised in the data)
    if p["alpha_by_life"]:
        p["alpha_decay"] = [0, 0]
    return p


def splat(b, o, mats):
    o = renderable_base(b, o + 4)
    p = {"type": "splat", "count": i32(b, o), "step": pair(b, o + 4), "size": pair(b, o + 12),
         "speed": [vec(b, o + 20), vec(b, o + 32)], "turn": i32(b, o + 44), "stretch": i32(b, o + 48),
         "grow": i32(b, o + 52), "gravity": i32(b, o + 56), "tex": "%08x" % u32(b, o + 60), "life": i32(b, o + 64)}
    p.update(material(mats, u32(b, o + 60)))
    return p


def gfx(b, o, mats):
    o += 4 + 4   # class, name
    mat, flags, emit = u32(b, o + 8), u32(b, o + 12), i32(b, o + 20)
    o += 24
    F = 4096.0
    p = {"type": "gfx", "tex": "%08x" % mat, "flags": flags, "emit": emit / F,
         "box": [vec(b, o), vec(b, o + 12)], "vel": [vec(b, o + 24), vec(b, o + 36)],
         "life": [v / F for v in pair(b, o + 48)], "size": [v / F for v in pair(b, o + 56)],
         "spin": [v / F for v in pair(b, o + 64)], "every": [v / F for v in pair(b, o + 80)],
         "grow": i32(b, o + 88) / F}
    p.update(material(mats, mat))
    return p


def parts(b, mats):
    out = []
    for tag, fn in ((EMITTER, emitter), (SPLAT, splat), (GFX, gfx)):
        i = b.find(tag)
        while i >= 0:
            out.append((i, fn(b, i, mats)))
            i = b.find(tag, i + 1)
    return sorted(out, key=lambda t: t[0])


def child_starts(b):
    out = []
    i = b.find(ENT)
    while i >= 0:
        if i + 13 <= len(b) and b[i + 8] in (0, 1) and 0 < u32(b, i + 9) < 16:
            out.append(i)
        i = b.find(ENT, i + 1)
    return out


def entity(h, ents, lists, mats):
    """Every emitter of the entity, its nested child entities (inline components, kind 0)
    and the spec lists its kind-1 children reference, each with the child's transform."""
    b = ents.get(h) or lists.get(h)
    if b is None:
        return None
    starts = child_starts(b)
    tfs = transforms(b)
    out = []
    for off, p in parts(b, mats):
        inside = [c for c in starts if c < off]
        tf = next((t for t in tfs if t["offset"] > off), None) if inside else None
        p["rot_wxyz"] = tf["rot_wxyz"] if tf else [1.0, 0.0, 0.0, 0.0]
        p["pos"] = list(tf["pos"]) if tf and tf["pos"] else [0, 0, 0]
        out.append(p)
    for c in starts:
        if b[c + 8] == 1 and u32(b, c + 13) in lists:
            tf = next((t for t in tfs if t["offset"] > c + 17), None)
            for _, p in parts(lists[u32(b, c + 13)], mats):
                p["rot_wxyz"] = tf["rot_wxyz"] if tf else [1.0, 0.0, 0.0, 0.0]
                p["pos"] = list(tf["pos"]) if tf and tf["pos"] else [0, 0, 0]
                out.append(p)
    if not out and b[:5] == b"\x01\x01\x00\x00\x00" and u32(b, 5) in lists:
        return entity(u32(b, 5), ents, lists, mats)
    return out


def hit_template(path, list_hash):
    """CHitTemplate "Hit" (Serialise kiwi va 0x12a03c; used by CHitHandler va 0x110e58):
    u32 0, u32 effect for explosive hits (hit type 2), u8, u32 sound, u32 sound (other
    hit), u32 n, n x (u32 effect, u32 damage limit): a hit spawns the first effect whose
    limit is above the damage (the last one above them all)."""
    g = Group(path)
    for r in g.resources:
        if r.name_hash == list_hash and r.cls == iw_hash("CIwSpecList"):
            b = r.body
            i = b.find(H("CHitTemplate") + H("Hit"))
            o = i + 12
            explosive, snd1, snd2, n = u32(b, o), u32(b, o + 5), u32(b, o + 9), u32(b, o + 13)
            steps = [["%08x" % u32(b, o + 17 + 8 * k), u32(b, o + 21 + 8 * k)] for k in range(n)]
            return {"explosive": "%08x" % explosive, "sounds": ["%08x" % snd1, "%08x" % snd2], "steps": steps}
    return None


def main(out_path):
    g = Group(EFFECTS)
    ents, lists, mats = {}, {}, {}
    for r in g.resources:
        if r.cls == iw_hash("CIwEntSpec"):
            ents[r.name_hash] = r.body
        elif r.cls == iw_hash("CIwSpecList"):
            lists[r.name_hash] = r.body
        elif r.cls == iw_hash("CIwMaterial"):
            mats[r.name_hash] = r.body
    guns = {}
    for r in Group(PLAYER).resources:
        if r.cls != iw_hash("CItemGun"):
            continue
        name = next((n + s for n in GUNS for s in ("", "_upgrade") if iw_hash(n + s) == r.name_hash), None)
        if name is None:
            continue
        b = r.body
        # CItemGun::Serialise order (tools/weapon_stats.py): 0xe8, 0xec, 0xf0 at body 72..80,
        # the muzzle flash effect at body 131
        guns[name] = {"impact": "%08x" % u32(b, 72), "impact_other": "%08x" % u32(b, 76),
                      "impact_other2": "%08x" % u32(b, 80), "flash": "%08x" % u32(b, 131)}
    zombie = hit_template(ZOMBIES, 0xc9872545)
    dog = hit_template(DOGS, 0x1d1ca339)
    want = set()
    for t in (zombie, dog):
        want.add(t["explosive"])
        want.update(s[0] for s in t["steps"])
    for gdat in guns.values():
        want.update(v for v in gdat.values() if v != "00000000")
    want.add("ee72b935")   # betty / Mustang & Sally explosion (spec list of splash ab7c47a0)
    out = {"hit_zombie": zombie, "hit_dog": dog, "guns": guns, "entities": {}}
    for h in sorted(want):
        e = entity(int(h, 16), ents, lists, mats)
        if e:
            out["entities"][h] = e
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1)
    print("hit_fx: %d entities, %d guns" % (len(out["entities"]), len(guns)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game/assets/effects/hit_fx.json"))
