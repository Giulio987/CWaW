#!/usr/bin/env python3
"""Dump the original weapon values (CItemGun & co.) to JSON.

    .venv/bin/python -I tools/weapon_stats.py [out.json]     (default analysis/weapon_stats.json)

CItemGun resources live in extracted/main/ingame/player/player.group.bin, one per gun
("<weapon>" and "<weapon>_upgrade"; the Pack-a-Punch version is a separate CItemGun
pointed to by the normal one). The body (after the group's u32 size, u32 nameHash) is
written by CItemGun::Serialise (kiwi, ARM, va 0x2132c0; vtable slot 5, RTTI "8CItemGun").
Field order below is that function's call order; "member" is the C++ member offset,
which is what the game code reads (e.g. GetDamage at va 0x238a40). Types:
u = u32 (IwSerialiseUInt32), i = i32 (IwSerialiseInt32), h = resource hash (u32),
b = u8/bool. iwfixed = 1/4096. Distances are world units: 400 = 1 m (the designers
typed World at War inches, x10.16: 2540 = 250 in, 10404 = 1024 in, 40640 = 4000 in).
Angles: 4096 = 360 degrees (IwGeomTan at va 0x707a4 takes this unit).

  member  type  name                 meaning
  0x48    h     anim_state_machine   CIsAnimStateMachine (fire/reload timings, see below)
  0x4c    h     anim_set             (shared by gun classes)
  0xf4    h     base_gun             normal gun (only set in *_upgrade)
  0x18..0x2c h  models/skins         view model, skins, skeletons
  0x40    h     world_model          CIwModel
  0x50    h     ?                    hash
  0x30..0x3c h  material_sets        CIsMaterialSet x4
  0x44    h     upgrade              the "_upgrade" CItemGun (0 in upgrades)
  0xe0,0xe4 h   flame_burn, flame_spec (flamethrower: CPeriodicDamage c38dd981, skel)
  0xe8..0xf0 h  ?                    hashes shared per class (sounds?)
  0x54    u     max_hits             targets a bullet passes through (penetration; 20 rifles/SMGs, 10 pistol & shotguns, 1 projectiles)
  0x88    h     projectile           CIwEntSpec fired instead of a bullet (ray gun, wunderwaffe)
  0x8c    h     projectile2          second projectile spec
  0xd9    b     ?                    projectile launched from the muzzle (0 for ray gun)
  0xd8    b     projectile_homing?   1 for ray gun (projectile tracks the aimed entity)
  0x5f    b     projectile_extra     1 for ray gun / wunderwaffe
  0x64    i     pierce_falloff       iwfixed: each target already pierced removes damage*this
  0x6c    i     falloff_per_unit     iwfixed damage lost per world unit beyond falloff_start
  0x68    i     falloff_start        world units of full damage
  0x104   i     heat_rate            iwfixed (flamethrower heat speed, 1.0)
  0x100   i     overheat_time        iwfixed s of continuous fire to overheat (flamethrower 4 / 7)
  0x74    i     lateral_falloff      iwfixed damage lost per unit off the aim axis (shotgun cone)
  0x70    i     lateral_start        units off-axis with full damage (shotgun)
  0x78    u     min_damage           damage floor after falloff
  0x58    h     fire_sound
  0x5c    b     cone                 shotgun: one hit per target inside a cone (no pellets)
  0x5d    b     flame                flamethrower
  0x5e    b     automatic            hold to fire
  0xf8    b     ?                    pistols / ray gun
  0x10c   b     ?                    flamethrower
  0x140   b     ?                    shotguns / ray gun
  0x141   b     ?
  0x143   b     ?                    always 1
  0x60    i     cone_angle           full cone angle (4096 = 360 deg), shotguns 113 = 9.9 deg
  0xfc    u     ?                    always 24
  0x7c    u     magazine
  0x80    u     reserve              spare ammo (max), as in World at War (colt 8 + 80)
  0x84    u     damage               base damage per hit
  0x90    i     ?                    always 8192
  0x94    i[6]  sway/kick?           angles
  0xb8    i[3]  ?                    vec3
  0xac    i[3]  view_offset?         vec3
  0xc4    i     ?                    ~512 (fov?)
  0xdc    i     damage_type          1 = pistol (colt45 / magnum)
  0x144   i     ?                    1 (2 for wunderwaffe_upgrade)
  0xc8    array hit_location_mult    u32 count, count x (u32 location, i32 iwfixed multiplier)
  0x108   u     ?                    hash ("rifle" for bolt actions, 92db6b0d shotguns)
  0x120   str   name                 (cstring)

Hit locations are the indices of the zombie's hit volumes (CIwSpecList c9872545 in
zombiesbase: head sphere, two arm cylinders, chest, pelvis, two legs): 0 head,
1 left arm, 2 right arm, 3 chest, 4 pelvis, 5 leg (the other leg, index 6, has no
entry and takes x1). Arm/leg sides are inferred from the volume order.

Damage of one bullet/cone hit (CItemGun::GetDamage, va 0x238a40):
    d = damage - ((damage * pierce_falloff) >> 12) * pierced
    d = d * loc_mult[loc] >> 12                    (if loc is in the table)
    if dist > falloff_start: d -= (dist - falloff_start) * falloff_per_unit >> 12
    if |lateral| > lateral_start: d -= (|lateral| - lateral_start) * lateral_falloff >> 12
    return max(d, min_damage)

Timings come from the gun's CIsAnimStateMachine: each CIsAnimState record
(tag 0x0b3d362a) holds u32 hash, u32 hash, iwfixed playback speed, i32 duration in ms,
u32 index, then the anims it plays. Index 16 = fire, 18 = fire with Double Tap,
21 = reload, 27 = reload with Speed Cola, 35 = fire while aiming, 53 = rechamber
(bolt / pump, only bolt-action rifles and the trench gun).
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER = os.path.join(ROOT, "extracted/main/ingame/player/player.group.bin")
EFFECTS = os.path.join(ROOT, "extracted/main/ingame/effects/effects.group.bin")
CONSOLE = os.path.join(ROOT, "extracted/main/console.bin")
WEAPONS = ["colt45", "magnum", "kar98", "carbine", "thompson", "mp40", "stg44", "trenchgun", "shotgun", "bar",
           "garand", "g43", "ppsh", "type100", "mg42", "raygun", "ptrs", "fg42", "sawnoff", "springfield",
           "arisaka", "browning", "flamethrower", "wunderwaffe"]
U = 400.0      # world units per metre
FX = 4096.0    # iwfixed one

# (member offset, type, name) in CItemGun::Serialise order
LAYOUT = [(0x48, "h", "anim_state_machine"), (0x4c, "h", "anim_set"), (0xf4, "h", "base_gun")] + \
    [(o, "h", "res_%x" % o) for o in (0x18, 0x1c, 0x20, 0x24, 0x28, 0x2c)] + \
    [(0x40, "h", "world_model"), (0x50, "h", "res_50")] + \
    [(o, "h", "material_set_%x" % o) for o in (0x30, 0x34, 0x38, 0x3c)] + \
    [(0x44, "h", "upgrade"), (0xe0, "h", "flame_burn"), (0xe4, "h", "flame_spec"),
     (0xe8, "h", "res_e8"), (0xec, "h", "res_ec"), (0xf0, "h", "res_f0"),
     (0x54, "u", "max_hits"), (0x88, "h", "projectile"), (0x8c, "h", "projectile2"),
     (0xd9, "b", "flag_d9"), (0xd8, "b", "flag_d8"), (0x5f, "b", "flag_5f"),
     (0x64, "i", "pierce_falloff"), (0x6c, "i", "falloff_per_unit"), (0x68, "i", "falloff_start"),
     (0x104, "i", "heat_rate"), (0x100, "i", "overheat_time"),
     (0x74, "i", "lateral_falloff"), (0x70, "i", "lateral_start"),
     (0x78, "u", "min_damage"), (0x58, "h", "fire_sound"),
     (0x5c, "b", "cone"), (0x5d, "b", "flame"), (0x5e, "b", "automatic"), (0xf8, "b", "flag_f8"),
     (0x10c, "b", "flag_10c"), (0x140, "b", "flag_140"), (0x141, "b", "flag_141"), (0x143, "b", "flag_143"),
     (0x60, "i", "cone_angle"), (0xfc, "u", "u_fc"), (0x7c, "u", "magazine"), (0x80, "u", "reserve"),
     (0x84, "u", "damage"), (0x90, "i", "i_90")] + \
    [(0x94 + 4 * k, "i", "i_%x" % (0x94 + 4 * k)) for k in range(6)] + \
    [(0xb8 + 4 * k, "i", "vec_b8_%d" % k) for k in range(3)] + \
    [(0xac + 4 * k, "i", "vec_ac_%d" % k) for k in range(3)] + \
    [(0xc4, "i", "i_c4"), (0xdc, "i", "damage_type"), (0x144, "i", "i_144")]
LOCATIONS = ["head", "left_arm", "right_arm", "chest", "pelvis", "leg"]
STATE_TAG = bytes.fromhex("2a363d0b")
STATES = {16: "fire", 18: "fire_double_tap", 21: "reload", 27: "reload_speed_cola", 35: "fire_aiming",
          53: "rechamber"}


def parse_gun(b):
    d, p = {}, 0
    for off, t, name in LAYOUT:
        if t == "b":
            d[name] = b[p]
            p += 1
        else:
            d[name] = struct.unpack_from("<i" if t == "i" else "<I", b, p)[0]
            p += 4
    (n,) = struct.unpack_from("<I", b, p)
    p += 4
    d["hit_location_mult"] = {LOCATIONS[k] if k < len(LOCATIONS) else str(k): v / FX
                              for k, v in (struct.unpack_from("<Ii", b, p + 8 * j) for j in range(n))}
    p += 8 * n
    d["u_108"] = struct.unpack_from("<I", b, p)[0]
    p += 4
    end = b.index(b"\0", p)
    d["name"] = b[p:end].decode("latin-1")
    assert end + 1 == len(b), "CItemGun layout mismatch"
    for k, v in list(d.items()):
        if isinstance(v, int) and any(n == k and t == "h" for _, t, n in LAYOUT):
            d[k] = "%08x" % v
    return d


def anim_states(body, anims):
    offs, i = [], body.find(STATE_TAG)
    while i >= 0:
        offs.append(i)
        i = body.find(STATE_TAG, i + 1)
    out = {}
    for k, o in enumerate(offs):
        e = offs[k + 1] if k + 1 < len(offs) else len(body)
        _h1, _h2, speed, dur, idx = struct.unpack_from("<IIIiI", body, o + 4)
        if idx in STATES:
            used = sorted({"%08x" % v for v in (struct.unpack_from("<I", body, q)[0] for q in range(o, e - 3)) if v in anims})
            out[STATES[idx]] = {"ms": dur, "speed": round(speed / FX, 3), "anims": used}
    return out


def derived(g):
    """The same values in game units (metres, seconds, degrees)."""
    st = g.get("states", {})
    r = {
        "damage": g["damage"], "min_damage": g["min_damage"], "magazine": g["magazine"], "reserve": g["reserve"],
        "automatic": bool(g["automatic"]), "max_hits": g["max_hits"],
        "pierce_falloff": round(g["pierce_falloff"] / FX, 4),
        "falloff_start_m": round(g["falloff_start"] / U, 3),
        "falloff_per_m": round(g["falloff_per_unit"] / FX * U, 3),
        "lateral_start_m": round(g["lateral_start"] / U, 3),
        "lateral_falloff_per_m": round(g["lateral_falloff"] / FX * U, 3),
        "cone_deg": round(g["cone_angle"] * 360.0 / 4096.0, 2) if g["cone"] else 0.0,
        "hit_location_mult": g["hit_location_mult"],
        "fire_s": st.get("fire", {}).get("ms", 0) / 1000.0,
        "fire_double_tap_s": st.get("fire_double_tap", {}).get("ms", 0) / 1000.0,
        "rechamber_s": st.get("rechamber", {}).get("ms", 0) / 1000.0,
        "reload_s": st.get("reload", {}).get("ms", 0) / 1000.0,
        "reload_speed_cola_s": st.get("reload_speed_cola", {}).get("ms", 0) / 1000.0,
    }
    if g["flame"]:
        r["overheat_s"] = g["overheat_time"] / FX
        r["heat_rate"] = g["heat_rate"] / FX
    return r


def splash_effects():
    """CSplashEffectSpec components of effect entities (grenade, ray gun, monkey, betty...).
    CSplashEffectSpec::Serialise (va 0x19237c): u32 damage, u32 target mask, u32 damage type,
    u32 hash, i32 los_free_radius, u8 x6 (0x74 instakill?, 0x30 instakill, 0x31..0x33 filters, 0x75),
    u32, u32, str stat, str weapon. Radius = the CIwVolumeSphere of the base CIwSpecList's
    collider (u32 0, u32 radius, u32 0)."""
    g = Group(EFFECTS)
    res = {r.name_hash: r.body for r in g.resources}
    sp = struct.pack("<I", iw_hash("CSplashEffectSpec"))
    cs, vs = struct.pack("<I", iw_hash("CIwColliderSpec")), struct.pack("<I", iw_hash("CIwVolumeSphere"))
    out = {}
    for h, b in res.items():
        i = b.find(sp)
        if i < 0:
            continue
        q = i + 4
        dmg, mask, dtype, _h, los = struct.unpack_from("<IIIIi", b, q)
        flags = list(b[q + 20:q + 26])
        strs = [s.decode("latin-1") for s in b[q + 34:].split(b"\0")[:2]]
        base = res.get(struct.unpack_from("<I", b, 5)[0])
        radius = None
        if base:
            j = base.find(vs, base.find(cs))
            radius = struct.unpack_from("<I", base, j + 8)[0] if j >= 0 else None
        key = strs[1] or "%08x" % h
        out[key + ("" if key not in out else "_%08x" % h)] = {
            "entity": "%08x" % h, "damage": dmg, "damage_type": dtype, "target_mask": "%08x" % mask,
            "radius_units": radius, "radius_m": radius / U if radius else None, "los_free_m": los / U,
            "flags": flags, "stat": strs[0]}
    return out


def knives(g):
    """CItemKnife::Serialise (va 0xfef00): CItem base, u32 damage (member 0x38, read by the melee
    code at va 0x20e478), u32 0x3c, i32 0x40, i32 0x44, i32 0x54, vec3 0x48, str name."""
    out = {}
    for r in g.resources:
        if r.cls == iw_hash("CItemKnife"):
            b = r.body
            s = len(b) - 1
            while s > 0 and 0x61 <= b[s - 1] <= 0x7a or 0x41 <= b[s - 1] <= 0x5a:
                s -= 1
            name = b[s:-1].decode()
            p = s - 32
            v = struct.unpack_from("<IIiii3i", b, p)
            out[name] = {"damage": v[0], "u_3c": v[1], "i_40": v[2], "i_44": v[3], "i_54": v[4]}
    return out


def periodic(g):
    """CPeriodicDamage (va 0x16b524): i32 0x1c period ms?, i32 0x20 damage type, u32 0x24 damage,
    i32 0x14 duration ms?, u8 0x18 (field names inferred)."""
    out = {}
    for r in g.resources:
        if r.cls == iw_hash("CPeriodicDamage"):
            a, t, dmg, dur, f = struct.unpack_from("<iiIiB", r.body, 0)
            out["%08x" % r.name_hash] = {"period_ms": a, "damage_type": t, "damage": dmg, "duration_ms": dur, "flag": f}
    return out


def console_vars(names):
    b = open(CONSOLE, "rb").read()
    out = {}
    for n in names:
        i = b.find(n.encode() + b"\0")
        if i >= 4:
            t = struct.unpack_from("<I", b, i - 4)[0]
            v = struct.unpack_from("<i", b, i + len(n) + 1)[0]
            out[n] = v / FX if t == 0x20C2DDA1 else v
    return out


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "analysis/weapon_stats.json")
    g = Group(PLAYER)
    sms = {r.name_hash: r.body for r in g.resources if r.cls == iw_hash("CIsAnimStateMachine")}
    anims = {r.name_hash for r in g.resources if r.cls == iw_hash("CIwAnim")}
    guns = {}
    for r in g.resources:
        if r.cls == iw_hash("CItemGun"):
            d = parse_gun(r.body)
            sm = sms.get(int(d["anim_state_machine"], 16))
            d["states"] = anim_states(sm, anims) if sm else {}
            d["game"] = derived(d)
            guns[d["name"]] = d
    order = [n for w in WEAPONS for n in (w, w + "_upgrade") if n in guns]
    data = {
        "units": "raw values; 'game' = metres / seconds / degrees",
        "guns": {n: guns[n] for n in order + sorted(set(guns) - set(order))},
        "knives": knives(g),
        "periodic_damage": periodic(g),
        "splash_effects": splash_effects(),
        "console": console_vars(["FlamethrowerDamagePeriod", "FlamethrowerMaxRange", "FlamethrowerMinSpurtTime",
                                 "FlamethrowerSpeed", "FlamethrowerGirth", "FlamethrowerNumSpheres",
                                 "MaxGrenades", "InstaKillTime", "PlayerKillPoints", "PlayerKillPointsMelee",
                                 "PlayerHeadShotPoints", "CrawlingZombieMaxHealth",
                                 "CrawlingZombieProportionalMaxHealth"]),
    }
    with open(out_path, "w") as f:
        json.dump(data, f, indent=1)
    print("%d guns -> %s" % (len(guns), out_path))
    for n in order:
        x = guns[n]["game"]
        print("%-20s dmg %4d min %4d mag %3d res %3d fire %.3f reload %.3f falloff %5.1fm -%.2f/m head x%s" % (
            n, x["damage"], x["min_damage"], x["magazine"], x["reserve"], x["fire_s"] + x["rechamber_s"], x["reload_s"],
            x["falloff_start_m"], x["falloff_per_m"], x["hit_location_mult"].get("head", 1.0)))


if __name__ == "__main__":
    main()
