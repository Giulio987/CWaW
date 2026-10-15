#!/usr/bin/env python3
"""First-person gun states: sounds, animations and timings of each gun's CIsAnimStateMachine.

CIsAnimStateMachine body (player group, one per CItemGun):
  per state: tag 0x0b3d362a, u32 name hash, u32 arms anim, iwfixed speed, i32 ms, u32 index,
    u8[4] flags (byte 2 = 1: the state loops),
    u32 n + n x (u16 output, u32 param, u16 ms)       timed outputs (ms into the state)
    u32 n + n x (u16 output, u32 param, u8[3] when)   outputs on entry (when[0] = 0) / exit (1)
    u32 n + n x (u16 target, u16 blend, u16 input, u16 condition, u16, u8, u8)   transitions
  then u32 n + inputs, u32 n + outputs (hashes; the u16 ids count from the END of each list).
The animations play at `speed`, so a state lasts len(anim) / speed = ms.
Outputs used here: playsound (a CIwSoundSpec), playSoundSequence (CSoundSequence),
playGunAnim (weapon animation), reload (n: the bullets added; 0 = fill the magazine),
playSoundUpgrade (kiwi va 0x2070d8: plays only when the held gun has byte 0x142 set, i.e.
it is a "_upgrade" gun: the resolver at va 0x213240 sets it on the base gun's upgrade, and
the CItemGun byte 0x143; the Pack-a-Punch layer 19571fe7 on every shot), playSound3
(va 0x20706c: the hash continued with "1", "2" or "3" at random, iw_hash(name + digit)).
State indices (same in every gun): 13/14/15 run in / running (loop) / run out, 16 fire,
17 fire with the last round (transition condition 2 out of idle; the Garand's clip "ping"),
18/19 the same with Double Tap, 20/21/22 reload start / reload / end with rounds left,
23/24/25 the same with an empty magazine, 26-28 and 29-31 the same with Speed Cola,
35/36 fire while aiming (last round), 46 Throwingmonkeybomb, 53 rechamber after 16/17
(bolt or pump), 54 rechamber after 35/36 (back to the sights).
Writes game/assets/characters/ingame/player/weapon_states.json:
  {gun: {"fire": st, "fire_last": st, "aim_fire": st, "aim_fire_last": st, "rechamber": st,
         "aim_rechamber": st, "run": [st, st, st], "reload": [st...], "reload_empty": [...],
         "reload_speed": [...], "reload_speed_empty": [...], "upgrade_sound": hash},
   "monkey_throw": st, "monkey_loop": st}
  st = {"ms", "speed", "loop", "arms", "weapon", "events": [[ms, output, param], ...]}
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash
from weapon_stats import parse_gun

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER = os.path.join(ROOT, "extracted/main/ingame/player/player.group.bin")
OUT = os.path.join(ROOT, "game/assets/characters/ingame/player/weapon_states.json")
TAG = bytes.fromhex("2a363d0b")
OUTPUTS = ["playsound", "playSoundSequence", "playGunAnim", "reload", "playSoundUpgrade", "playSound3",
           "monkeyBombThrowStart", "monkeyBombThrowEnd", "monkeyJumpStart", "monkeyJumpEnd"]
NAMES = {iw_hash(n): n for n in OUTPUTS}
MONKEY_GROUND = 0x93125439   # ASM of the thrown monkey bomb (single looping state)


def parse(b):
    """[state dict], following the layout above."""
    o = b.find(TAG)
    states = []
    while o >= 0 and b[o:o + 4] == TAG:
        _name, arms, speed, ms, idx = struct.unpack_from("<IIIiI", b, o + 4)
        flags = b[o + 24:o + 28]
        o += 28
        n = struct.unpack_from("<I", b, o)[0]
        o += 4
        timed = [struct.unpack_from("<HIH", b, o + 8 * j) for j in range(n)]
        o += 8 * n
        n = struct.unpack_from("<I", b, o)[0]
        o += 4
        entry = [struct.unpack_from("<HI", b, o + 9 * j) + (b[o + 9 * j + 6],) for j in range(n)]
        o += 9 * n
        n = struct.unpack_from("<I", b, o)[0]
        o += 4 + 12 * n
        states.append({"idx": idx, "arms": arms, "speed": speed / 4096.0, "ms": ms, "loop": flags[2] == 1,
                       "timed": timed, "entry": entry})
    ni = struct.unpack_from("<I", b, o)[0]
    o += 4 + 4 * ni
    no = struct.unpack_from("<I", b, o)[0]
    outs = [struct.unpack_from("<I", b, o + 4 + 4 * k)[0] for k in range(no)]
    return states, outs


def state_out(st, outs):
    ev = []
    for t, p, ms in st["timed"]:
        ev.append((ms, outs[len(outs) - 1 - t], p))
    for t, p, when in st["entry"]:
        if when == 0:
            ev.append((0, outs[len(outs) - 1 - t], p))
    weapon = next((p for _ms, o, p in ev if o == iw_hash("playGunAnim")), 0)
    events = sorted([ms, NAMES[o], f"{p:08x}" if p > 0xFFFF else p] for ms, o, p in ev
                    if o in NAMES and o != iw_hash("playGunAnim"))
    return {"ms": st["ms"], "speed": round(st["speed"], 4), "loop": st["loop"],
            "arms": f"{st['arms']:08x}" if st["arms"] else "", "weapon": f"{weapon:08x}" if weapon else "",
            "events": events}


def main():
    g = Group(PLAYER)
    sms = {r.name_hash: r.body for r in g.resources if r.cls == iw_hash("CIsAnimStateMachine")}
    out = {}
    for r in g.resources:
        if r.cls != iw_hash("CItemGun"):
            continue
        gun = parse_gun(r.body)
        body = sms.get(int(gun["anim_state_machine"], 16))
        if body is None:
            continue
        states, outs = parse(body)
        by = {s["idx"]: state_out(s, outs) for s in states}
        e = {"fire": by.get(16), "fire_last": by.get(17), "aim_fire": by.get(35), "aim_fire_last": by.get(36),
             "run": [by[k] for k in (13, 14, 15) if k in by]}
        if by.get(53) and by[53]["arms"]:
            e["rechamber"] = by[53]
            e["aim_rechamber"] = by.get(54)
        for key, idxs in (("reload", (20, 21, 22)), ("reload_empty", (23, 24, 25)),
                          ("reload_speed", (26, 27, 28)), ("reload_speed_empty", (29, 30, 31))):
            # the start / end states are pass-through (no animation) except for the trench gun
            e[key] = [by[k] for k in idxs if k in by and (by[k]["arms"] or by[k]["events"])]
        up = [p for _ms, o, p in by.get(16, {}).get("events", []) if o == "playSoundUpgrade"]
        e["upgrade_sound"] = up[0] if up and gun["flag_143"] else ""
        out[gun["name"]] = e
        if 46 in by and "monkey_throw" not in out:
            out["monkey_throw"] = by[46]
    if MONKEY_GROUND in sms:
        states, outs = parse(sms[MONKEY_GROUND])
        out["monkey_loop"] = state_out(states[0], outs)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(OUT, len(out), "entries")


if __name__ == "__main__":
    main()
