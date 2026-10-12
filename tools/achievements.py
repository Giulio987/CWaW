#!/usr/bin/env python3
"""Dump the original achievements (fixed/achievements/*.group.bin) to
game/assets/achievements.json, with names/descriptions from the localisation.

CAchievementResource is polymorphic: u32 subclass hash (CAchievementDirect,
CAchievementGreaterEqu, ...), then the body:
  u32 name hash (the id used by Lua Game.SetAchievement), u32 id (1..108, order
  of the list), u32 points, u32 name string hash, u32 description string hash,
  condition 0: i32 value, u32 category hash (global / weapon / map), u32 stat hash,
  u8 a, u8 b, u8 c, u32 n, n x u32 map hash (maps the achievement can be earned on,
  empty = the category map or any), then per subclass:
    *Exact / *GreaterEqu / *LessEqu ... with two or three comparisons: more
    {i32 value, u32 category, u32 stat} conditions (one per extra comparison);
    Weapon*: u32 n weapons, n x u32 weapon hash, u32 stat... (kept raw)
    Wunder: raw.
Comparison names follow the class name: LessEquGreaterEqu = cond0 <= value0 and
cond1 >= value1, etc.

Localisation (localisation/*.dat, LOC0): u32 ?, u32 data size, u32 count, u32 0?,
count x u32 offset, 6 bytes ("utf-8\\0"), strings. LocaliseHashes.dat: "LOC0",
u16 count, count x u32 key hash, count x u16 string index.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash, load_dictionary

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "extracted/main")
GROUPS = ["achievements", "nacht_achievements", "verruckt_achievements", "shinonuma_achievements",
          "derriese_achievements"]   # console.bin AllAchievementsGroupName order
CLASSES = ["CAchievementDirect", "CAchievementExact", "CAchievementLessEqu", "CAchievementGreaterEqu",
           "CAchievementLessEquGreaterEqu", "CAchievementGreaterEquInput", "CAchievementLessEquExact",
           "CAchievementGreaterEquExact", "CAchievementGreaterEquGreaterEqu", "CAchievementWeaponExact",
           "CAchievementWeaponGreaterEqu", "CAchievementGreaterEquGreaterEquExact",
           "CAchievementTwoAddGreaterEqu", "CAchievementWeaponKillInARow", "CAchievementInventoryWeapon",
           "CAchievementWunder"]
# names not in the binary's strings (stat names guessed and verified by hash)
EXTRA = ["nacht", "verruckt", "shinonuma", "derriese", "global", "grenade", "betty", "knife", "magnum",
         "colt", "raygun", "wunderwaffe", "monkeybomb", "flamethrower", "bowieKnife", "shotgun", "nuke",
         "player", "currenthour", "timeperwave", "doublePoints", "instakill", "carpenter", "gibs",
         "headlesszombie", "armlesszombie", "leglesszombie", "distancecovered", "maxkilldistance"]


def localisation(lang="english_uk"):
    h = open(os.path.join(MAIN, "localisation/LocaliseHashes.dat"), "rb").read()
    (n,) = struct.unpack_from("<H", h, 4)
    keys = struct.unpack_from("<%dI" % n, h, 6)
    idx = struct.unpack_from("<%dH" % n, h, 6 + 4 * n)
    d = open(os.path.join(MAIN, f"localisation/{lang}.dat"), "rb").read()
    (count,) = struct.unpack_from("<I", d, 12)
    offs = struct.unpack_from("<%dI" % count, d, 16)
    base = 16 + 4 * count + 6
    out = {}
    for k, i in zip(keys, idx):
        o = base + offs[i]
        out[k] = d[o:d.index(b"\0", o)].decode("utf-8", "replace")
    return out


def main(out):
    names = load_dictionary(os.path.join(ROOT, "analysis/kiwi_strings.txt"),
                            os.path.join(ROOT, "analysis/lua_strings.txt"))
    for s in EXTRA + CLASSES:
        names[iw_hash(s)] = s
    loc = localisation()

    def nm(h):
        return names.get(h, "%08x" % h)

    result = []
    for g in GROUPS:
        grp = Group(os.path.join(MAIN, f"fixed/achievements/{g}.group.bin"))
        for r in grp.resources:
            b = r.body
            name, aid, points, sname, sdesc, value, cat, stat = struct.unpack_from("<IIIIIiII", b, 0)
            a, bb, c, nmaps = struct.unpack_from("<BBBI", b, 32)
            maps = [nm(m) for m in struct.unpack_from("<%dI" % nmaps, b, 39)]
            rest = b[39 + 4 * nmaps:]
            cls = nm(r.name_hash)
            conds = [[value, nm(cat), nm(stat)]]
            extra = None
            if cls in ("CAchievementLessEquGreaterEqu", "CAchievementGreaterEquExact", "CAchievementLessEquExact",
                       "CAchievementGreaterEquGreaterEqu", "CAchievementGreaterEquGreaterEquExact",
                       "CAchievementTwoAddGreaterEqu"):
                for k in range(len(rest) // 12):
                    v, ct, st = struct.unpack_from("<iII", rest, 12 * k)
                    conds.append([v, nm(ct), nm(st)])
                rest = rest[12 * (len(rest) // 12):]
            if rest:
                extra = [nm(w) if w > 0xFFFF else w for w in struct.unpack_from("<%dI" % (len(rest) // 4), rest)]
            result.append({"id": nm(name), "num": aid, "points": points, "group": g, "type": cls[len("CAchievement"):],
                           "name": loc.get(sname, "%08x" % sname), "desc": loc.get(sdesc, "%08x" % sdesc),
                           "conds": conds, "flags": [a, bb, c], "maps": maps, "extra": extra})
    result.sort(key=lambda e: e["num"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(result, open(out, "w"), indent=1, ensure_ascii=False)
    print(out, len(result), "achievements")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game/assets/achievements.json"))
