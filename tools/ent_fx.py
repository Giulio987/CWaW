#!/usr/bin/env python3
"""Effect entities and ambient faders of a level -> JSON (complements tools/entities.py).

  ent_fx.py levels/<map>/ent_fx.json environment.group.bin effects.group.bin
  ent_fx.py --specs effect_specs.json effects.group.bin

Entity body (CIwEntSpec, top level or nested in another entity): u8 kind, u32 component
count, components..., transform (see entities.py), then u32 CEnt (or 0), u32, u8 flags.
kind 1 = the components are references to a CIwSpecList of the effects group (a
template, e.g. the trap arcs "<trap>Effect<n>": 01 01 00 00 00 <specList>); a nested
child entity is "u32 CIwEntSpec, u32 name hash" followed by the same layout.
Entity flags (CIwEntSpec +0x58, read at kiwi va 0x10303c-0x103118): 0x01 the entity
starts hidden (render flag 0x800: the traps' arcs until EnableRender), 0x04 billboard
facing the camera, 0x08 billboard turning about the entity's own up axis (transform
node bits 0x10 / 0x20, used by kiwi va 0x214104).

Every CIwSpecList of the effects group is listed under "spec_lists" with its
CLifeTimeSpec ([life ms, random ms, third value], serialiser kiwi va 0x14800c) and the
CIwEntSpec entities it spawns (model, transform, flags), e.g. 6be7f502, the dogs'
lightning strike (entities normal_dogSpawn / flame_dogSpawn: the spec list plus a
CDeathActionSpawnSpec that spawns the dog when it dies).

CIwAmbientFaderSpec (serialiser kiwi va 0x1a7604, update 0x162ee8): u32 near^2,
u32 far^2 (units^2), u8 invert, u8 min alpha, u8 max alpha. Each frame the squared
distance camera -> entity d2 gives alpha = min (d2 <= near^2), max (d2 >= far^2), linear
in d2 between; inverted: max - alpha. Written as metres.
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entities import transforms
from group import Group
from iwhash import iw_hash

C_ENT = iw_hash("CIwEntSpec")
C_SPECLIST = iw_hash("CIwSpecList")
C_MODEL = iw_hash("CIwModel")
C_RENDER = iw_hash("CIwRenderableModelSpec")
C_FADER = iw_hash("CIwAmbientFaderSpec")
C_LIFE = iw_hash("CLifeTimeSpec")
C_CENT = iw_hash("CEnt")
SCALE1 = struct.pack("<III", 4096, 4096, 4096)
UNITS = 400.0


def u32(b, i):
    return struct.unpack_from("<I", b, i)[0]


def ent_flags(b, scale_at):
    i = scale_at + 12
    if i + 9 <= len(b) and u32(b, i) in (0, C_CENT):
        return b[i + 8]
    return None


def first_model(b, start, models):
    for j in range(start, len(b) - 3):
        if u32(b, j) in models:
            return f"{u32(b, j):08x}"
    return ""


def spec_lists(fx_group):
    models = {r.name_hash for r in fx_group.resources if r.cls == C_MODEL}
    out = {}
    for r in fx_group.resources:
        if r.cls != C_SPECLIST:
            continue
        b = r.body
        d = {"lifetime": None, "ents": []}
        i = b.find(struct.pack("<I", C_LIFE))
        if i >= 0:
            d["lifetime"] = list(struct.unpack_from("<III", b, i + 4))
        # the entities: "u32 CIwEntSpec, u32 name, u8 kind, u32 count, components, transform"
        k = b.find(struct.pack("<I", C_ENT))
        starts = []
        while k >= 0:
            starts.append(k)
            k = b.find(struct.pack("<I", C_ENT), k + 1)
        # a spec list that is itself one entity (the trap arcs): the renderable at the top
        if not starts:
            j = b.find(struct.pack("<I", C_RENDER))
            if j >= 0:
                d["ents"].append({"model": first_model(b, j, models)})
        for n, s in enumerate(starts):
            end = starts[n + 1] if n + 1 < len(starts) else len(b)
            body = b[s:end]
            j = body.find(struct.pack("<I", C_RENDER))
            e = {"name": f"{u32(body, 4):08x}", "model": first_model(body, j, models) if j >= 0 else ""}
            xf = transforms(body)
            if xf:
                e["transform"] = xf[-1]
                e["flags"] = ent_flags(body, xf[-1]["offset"])
            d["ents"].append(e)
        if d["ents"] or d["lifetime"]:
            out[f"{r.name_hash:08x}"] = d
    return out


def main(out_path, env_path, fx_path):
    fx = Group(fx_path)
    lists = spec_lists(fx)
    env = Group(env_path)
    templates, nested, faders = {}, {}, {}
    for r in env.resources:
        if r.cls != C_ENT:
            continue
        b = r.body
        xf = transforms(b)
        name = f"{r.name_hash:08x}"
        # the entity itself an instance of a template
        if len(b) > 9 and b[0] == 1 and u32(b, 1) == 1 and f"{u32(b, 5):08x}" in lists:
            t = f"{u32(b, 5):08x}"
            ents = lists[t]["ents"]
            templates[name] = {"template": t, "model": ents[0]["model"] if ents else "",
                               "flags": ent_flags(b, xf[-1]["offset"]) if xf else None}
        # nested children
        key = struct.pack("<I", C_ENT)
        k = b.find(key)
        while k >= 0:
            if k + 17 <= len(b):
                child = f"{u32(b, k + 4):08x}"
                nxt = b.find(key, k + 1)
                own = [x for x in xf if x["offset"] > k and (nxt < 0 or x["offset"] < nxt)]
                if own:
                    c = {"parent": name, "transform": own[0], "flags": ent_flags(b, own[0]["offset"])}
                    if b[k + 8] == 1 and u32(b, k + 9) == 1:
                        t = f"{u32(b, k + 13):08x}"
                        if t in lists:
                            c["template"] = t
                            ents = lists[t]["ents"]
                            c["model"] = ents[0]["model"] if ents else ""
                    nested[child] = c
            k = b.find(key, k + 1)
        i = b.find(struct.pack("<I", C_FADER))
        if i >= 0:
            near2, far2, inv, lo, hi = struct.unpack_from("<IIBBB", b, i + 4)
            faders[name] = {"near": round(math.sqrt(near2) / UNITS, 4), "far": round(math.sqrt(far2) / UNITS, 4),
                            "invert": inv, "min": lo, "max": hi}
    used = {t["template"] for t in templates.values()} | {c["template"] for c in nested.values() if "template" in c}
    out = {"templates": templates, "nested": nested, "faders": faders,
           "spec_lists": {t: lists[t] for t in sorted(used)}}
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(out_path, len(templates), "template instances,", len(nested), "nested,", len(faders), "faders")


def main_specs(out_path, fx_path):
    with open(out_path, "w") as f:
        json.dump(spec_lists(Group(fx_path)), f, indent=1, sort_keys=True)


if __name__ == "__main__":
    if sys.argv[1] == "--specs":   # every spec list of the effects group: assets/effect_specs.json
        main_specs(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
