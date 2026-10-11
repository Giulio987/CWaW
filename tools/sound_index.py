#!/usr/bin/env python3
"""Build game/assets/sounds/index.json from the original sound resources.

- sounds:     spec hash -> {path, name} (CIwSoundSpec: first u32 is its own hash,
              last u32 the CIwSoundData it plays)
- names:      recovered name -> spec hash (names found by hash guessing, see
              analysis/sound_names.py; zombie sounds by their template in zombiesBase)
- sequences:  CSoundSequence hash -> [[delay_ms, sound]] (named after the animation
              they accompany, e.g. thompson_reload). Body: u8 0, u32 count, then
              count x {u32 command class, u32 0, u32 value}; Delay = ms, PlayAsync = spec
- guns:       weapon -> fire sound (CItemGun named iw_hash(weapon) references it)
- ambience:   CAmbienceChannel hash -> [sounds]
"""
import glob
import itertools
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash
from pair_arms import WEAPONS
from textures import group_dir

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DELAY, PLAY = iw_hash("CSoundSequenceCommandDelay"), iw_hash("CSoundSequenceCommandPlayAsync")
# zombiesBase spec list: CHitTemplate, CDeathTemplate/CPlaySoundTemplate, attack signal pipe
ZOMBIE = {"zombie_hit": [0xF889C48A, 0xF889C48B], "zombie_death": [0xC7F6B1F0, 0xC7F6B1F1, 0xC7F6B1F2],
          "zombie_attack": [0x520C63A1, 0x520C63A2]}

VOCAB_W = WEAPONS + ["colt", "knife", "grenade", "molotov", "betty", "bowie"]
VOCAB_A = ["fire", "reload", "rechamber", "mag_in", "mag_out", "clip_in", "start", "end", "open", "close",
           "charge", "slash", "stab", "explosion", "shell_01", "1", "2", "3"]
VOCAB_X = ["zombie_0%d" % i for i in range(1, 10)] + [
    "window_break1", "window_break2", "window_break3", "window_repair", "music_box_open", "music_box_close",
    "buy_success", "buy_fail", "end_wave", "maxammo", "instakill", "doublepoints", "nuke", "carpenter",
    "player_pain", "player_heartbeat", "gameover_intro", "gameover_start", "gameover_loop", "teddylaugh",
    "teddyland", "perk_random", "achievement", "dooropen", "barrel_explosion", "thunder", "thunder2",
    "ambthunder", "ambthunder2", "wind1", "wind2", "wind3", "wind_1", "wind_2", "wind_3", "Static1", "Static2",
    "radio_start1", "radio_start2", "radio_start3", "pa_level_start", "pa_power_on", "dog_spawn", "dog_attack",
    "dog_death1", "dog_death2", "dog_end_music", "dog_start_vox", "dog_fog"]


def main(out):
    sounds, seqs, guns_raw, amb = {}, {}, {}, {}
    for p in glob.glob(os.path.join(ROOT, "extracted/**/*.group.bin"), recursive=True):
        gd = group_dir(p)
        for r in Group(p).resources:
            b = r.body
            if r.cls == iw_hash("CIwSoundSpec"):
                sh = struct.unpack_from("<I", b, 0)[0]
                dh = struct.unpack_from("<I", b, len(b) - 4)[0]
                sounds[sh] = f"res://assets/sounds/{gd}/{dh:08x}.wav"
            elif r.cls == iw_hash("CSoundSequence"):
                (n,) = struct.unpack_from("<I", b, 1)
                steps, delay = [], 0
                for k in range(n):
                    cls, _z, v = struct.unpack_from("<III", b, 5 + 12 * k)
                    if cls == DELAY:
                        delay += v
                    elif cls == PLAY:
                        steps.append([delay, f"{v:08x}"])
                seqs[f"{r.name_hash:08x}"] = steps
            elif r.cls == iw_hash("CItemGun"):
                guns_raw[r.name_hash] = b
            elif r.cls == iw_hash("CAmbienceChannel"):
                amb[f"{r.name_hash:08x}"] = b
    known = set(sounds)
    names = {}
    for w, a in itertools.product(VOCAB_W, VOCAB_A):
        for s in (f"{w}_{a}",):
            if iw_hash(s) in known:
                names[s] = f"{iw_hash(s):08x}"
    for s in VOCAB_X:
        if iw_hash(s) in known:
            names[s] = f"{iw_hash(s):08x}"
    for k, hs in ZOMBIE.items():
        names[k] = [f"{h:08x}" for h in hs if h in known]
    guns = {}
    for w in WEAPONS:
        b = guns_raw.get(iw_hash(w))
        if b is None:
            continue
        for i in range(len(b) - 3):
            (h,) = struct.unpack_from("<I", b, i)
            if h in known:
                guns[w] = f"{h:08x}"
                break
    ambience = {}
    for k, b in amb.items():
        ambience[k] = sorted({f"{h:08x}" for i in range(len(b) - 3)
                              for h in [struct.unpack_from("<I", b, i)[0]] if h in known})
    index = {"sounds": {f"{h:08x}": p for h, p in sounds.items()}, "names": names, "sequences": seqs,
             "guns": guns, "ambience": ambience}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(index, open(out, "w"), indent=1)
    print(out, len(sounds), "sounds,", len(names), "names,", len(seqs), "sequences,", len(guns), "guns,",
          len(ambience), "ambience channels")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game/assets/sounds/index.json"))
