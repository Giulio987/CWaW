"""Recover entity names that entities.json only knows by hash.

Entity names are djb2 hashes of the lower-cased name (tools/iwhash.py); the
names that were not in the dictionary stay as 8 hex digits. Candidates come
from every string in the level/ingame Lua bytecode and from the naming schemes
the scripts build at run time (<Area>ZombieWindow<n>, <Area>ZombieCYWindow<n>,
<Area>ZombieSwampSpawn<n>, <Trap>Effect<n>, ...).

Writes game/assets/levels/<map>/names.json: {hash: name}.
Usage: python -I tools/resolve_names.py
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LEVELS = os.path.join(ROOT, "game", "assets", "levels")
BYTECODE = os.path.join(ROOT, "game", "assets", "lua_bytecode")

SUFFIXES = ["ZombieWindow", "ZombieCYWindow", "ZombieSpawn", "ZombieSwampSpawn", "DogSpawn",
            "Effect", "Laser", "Damager", "Sound", "Object", "Trigger", "_fxSpawn"]


def iw_hash(s: str) -> str:
    h = 5381
    for c in s.lower().encode():
        h = (h * 33 + c) & 0xFFFFFFFF
    return "%08x" % h


def lua_strings() -> set:
    out = set()
    for dirpath, _, files in os.walk(BYTECODE):
        for f in files:
            data = open(os.path.join(dirpath, f), "rb").read()
            for m in re.finditer(rb"[A-Za-z_][A-Za-z0-9_]{2,63}", data):
                out.add(m.group().decode())
    return out


def main() -> None:
    base = lua_strings()
    for level in sorted(os.listdir(LEVELS)):
        ents = json.load(open(os.path.join(LEVELS, level, "entities.json")))
        cfg = json.load(open(os.path.join(LEVELS, level, "level.json")))
        stems = set(base) | {a["Name"] for a in cfg["areas"]} | {"Courtyard"}
        stems |= {e["name"] for e in ents if not re.fullmatch(r"[0-9a-f]{8}", e["name"])}
        cand = {}
        for s in stems:
            cand[iw_hash(s)] = s
            for n in range(0, 31):
                cand.setdefault(iw_hash(s + str(n)), s + str(n))
            for suf in SUFFIXES:
                for n in range(1, 31):
                    cand.setdefault(iw_hash(s + suf + str(n)), s + suf + str(n))
        found = {}
        for e in ents:
            n = e["name"]
            if re.fullmatch(r"[0-9a-f]{8}", n) and n in cand:
                found[n] = cand[n]
        with open(os.path.join(LEVELS, level, "names.json"), "w") as fh:
            json.dump(found, fh, indent=1, sort_keys=True)
        print(level, len(found), "names recovered", file=sys.stderr)


if __name__ == "__main__":
    main()
