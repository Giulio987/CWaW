#!/usr/bin/env python3
"""Export every group's CIwModels to one .glb per group (one node per model).

Units: 400 Airplay units = 1 m (a zombie is ~724 units tall).
UVs are s16 with 4096 = 1.0. Textures are referenced as external PNGs
produced by textures.py; the lightmap (2nd material texture, UV set 2) is
stored in material extras for the Godot import script.

CIwMaterial body: u8 flags[4] (byte 3 = alpha mode, 4 = blend), ...,
  0x1d u32 texture0, 0x21 u32 texture1 (lightmap, optional).
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash
from model import Model
from textures import group_dir

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C_MODEL, C_MAT, C_TEX = iw_hash("CIwModel"), iw_hash("CIwMaterial"), iw_hash("CIwTexture")
SCALE = 1 / 400.0
ALPHA_BLEND = 4


class Index:
    """Material and texture lookup, preferring the requesting group."""

    def __init__(self, groups):
        self.mats, self.texs = {}, {}
        for g in groups:
            d = group_dir(g.path)
            for r in g.resources:
                if r.cls == C_MAT:
                    self.mats.setdefault(r.name_hash, []).append((d, r.body))
                elif r.cls == C_TEX:
                    self.texs.setdefault(r.name_hash, []).append(d)

    @staticmethod
    def _pick(entries, gdir):
        for e in entries:
            if (e[0] if isinstance(e, tuple) else e) == gdir:
                return e
        # same level beats another level
        top = gdir.split("/")[:2]
        for e in entries:
            if (e[0] if isinstance(e, tuple) else e).split("/")[:2] == top:
                return e
        return entries[0]

    def material(self, h, gdir):
        return self._pick(self.mats[h], gdir)[1] if h in self.mats else None

    def texture(self, h, gdir):
        if h not in self.texs:
            return None
        return os.path.join(ROOT, "game", "assets", "textures", self._pick(self.texs[h], gdir), f"{h:08x}.png")


class GlbWriter:
    def __init__(self, out_path):
        self.out_path = out_path
        self.bin = bytearray()
        self.j = {"asset": {"version": "2.0", "generator": "codz-remake"}, "scenes": [{"nodes": []}],
                  "nodes": [], "meshes": [], "materials": [], "textures": [], "images": [],
                  "samplers": [{"wrapS": 10497, "wrapT": 10497}], "accessors": [], "bufferViews": []}
        self.mat_cache, self.img_cache = {}, {}

    def accessor(self, arr, gl_type, kind, target=None, normalized=False):
        arr = np.ascontiguousarray(arr)
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": arr.nbytes}
        if target:
            view["target"] = target
        self.bin += arr.tobytes()
        self.j["bufferViews"].append(view)
        acc = {"bufferView": len(self.j["bufferViews"]) - 1, "componentType": gl_type,
               "count": len(arr), "type": kind}
        if normalized:
            acc["normalized"] = True
        if kind == "VEC3" and gl_type == 5126:
            acc["min"] = arr.min(0).tolist()
            acc["max"] = arr.max(0).tolist()
        self.j["accessors"].append(acc)
        return len(self.j["accessors"]) - 1

    def image(self, png):
        if png not in self.img_cache:
            uri = os.path.relpath(png, os.path.dirname(self.out_path))
            self.j["images"].append({"uri": uri})
            self.j["textures"].append({"source": len(self.j["images"]) - 1, "sampler": 0})
            self.img_cache[png] = len(self.j["textures"]) - 1
        return self.img_cache[png]

    def material(self, mat_hash, body, index, gdir):
        if mat_hash in self.mat_cache:
            return self.mat_cache[mat_hash]
        m = {"name": f"{mat_hash:08x}", "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 1}}
        if body is not None:
            alpha_mode = body[3]
            t0, t1 = struct.unpack_from("<II", body, 0x1D)
            png0 = index.texture(t0, gdir)
            if png0:
                m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": self.image(png0)}
                has_alpha = Image.open(png0).mode == "RGBA"
                if alpha_mode == ALPHA_BLEND and has_alpha:
                    m["alphaMode"] = "BLEND"
                elif has_alpha:
                    m["alphaMode"] = "MASK"
            png1 = index.texture(t1, gdir) if t1 else None
            m["extras"] = {"iw_flags": body[:5].hex(), "texture0": f"{t0:08x}"}
            if png1:
                m["extras"]["lightmap"] = os.path.relpath(png1, os.path.dirname(self.out_path))
        self.j["materials"].append(m)
        self.mat_cache[mat_hash] = len(self.j["materials"]) - 1
        return self.mat_cache[mat_hash]

    def add_model(self, name, m, index, gdir, split_parts=False, part_names=None):
        """One mesh per model, or (split_parts) one mesh+node per triangle list named after the part."""
        if m.verts is None or not m.trilists:
            return
        attrs = {"POSITION": self.accessor(m.verts.astype(np.float32) * SCALE, 5126, "VEC3", 34962)}
        n = len(m.verts)
        if m.uvs is not None and len(m.uvs) == n:
            attrs["TEXCOORD_0"] = self.accessor(m.uvs.view(np.int16).astype(np.float32) / 4096, 5126, "VEC2", 34962)
        if m.uvs2 is not None and len(m.uvs2) == n:
            attrs["TEXCOORD_1"] = self.accessor(m.uvs2.view(np.int16).astype(np.float32) / 4096, 5126, "VEC2", 34962)
        if m.cols is not None and len(m.cols) == n:
            attrs["COLOR_0"] = self.accessor(m.cols, 5121, "VEC4", 34962, normalized=True)
        groups = {}
        for part, mat_idx, idx in self._lists(m):
            mat_hash = m.materials[mat_idx] if mat_idx < len(m.materials) else 0
            prim = {"attributes": attrs, "indices": self.accessor(idx.astype(np.uint16), 5123, "SCALAR", 34963),
                    "material": self.material(mat_hash, index.material(mat_hash, gdir), index, gdir)}
            key = (part_names or {}).get(part, f"{part:08x}") + (f"_m{mat_idx}" if mat_idx else "") if split_parts else name
            groups.setdefault(key, []).append(prim)
        for key, prims in groups.items():
            self.j["meshes"].append({"name": key, "primitives": prims})
            self.j["nodes"].append({"name": key, "mesh": len(self.j["meshes"]) - 1})
            self.j["scenes"][0]["nodes"].append(len(self.j["nodes"]) - 1)

    @staticmethod
    def _lists(m):
        # trilist "flags" is the index into the model's material table
        for part, mat_idx, idx in m.trilists:
            if len(idx) >= 3:
                yield part, mat_idx, idx[: len(idx) // 3 * 3]

    def write(self):
        if not self.j["meshes"]:
            return False
        for k in [k for k, v in self.j.items() if v == []]:
            del self.j[k]
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        os.makedirs(os.path.dirname(self.out_path), exist_ok=True)
        with open(self.out_path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(self.bin)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + self.bin)
        return True


def place_entities(w, gdir):
    """Move prop models under 'ent_<name>' nodes using the level's entities.json (see entities.py)."""
    parts = gdir.split("/")
    path = os.path.join(ROOT, "game", "assets", "levels", parts[1], "entities.json") if len(parts) == 3 else ""
    if parts[0] != "levels" or parts[2] != "environment" or not os.path.exists(path):
        return
    by_name = {n["name"]: i for i, n in enumerate(w.j["nodes"])}
    scene = w.j["scenes"][0]["nodes"]
    for e in json.load(open(path)):
        refs = [h for h in [e["hash"]] + e["models"] if h in by_name]
        if not refs:
            continue
        xf = e["children"][-1] if e["children"] else e["transform"]  # model hangs off the innermost entity
        root = e["transform"]
        node = {"name": "ent_" + e["name"], "children": [],
                "translation": [c * SCALE for c in root["pos"]],
                "rotation": root["rot_wxyz"][1:] + root["rot_wxyz"][:1]}
        if xf is not root:
            node["children"].append(len(w.j["nodes"]) + 1)
            w.j["nodes"].append(node)
            w.j["nodes"].append({"name": "local", "children": [], "translation": [c * SCALE for c in xf["pos"]],
                                 "rotation": xf["rot_wxyz"][1:] + xf["rot_wxyz"][:1]})
            holder = w.j["nodes"][-1]
        else:
            w.j["nodes"].append(node)
            holder = node
        scene.append(len(w.j["nodes"]) - (2 if xf is not root else 1))
        for h in refs:
            i = by_name[h]
            if i in scene:
                scene.remove(i)
                holder["children"].append(i)


def main(out_dir, paths):
    groups = [Group(p) for p in paths]
    index = Index(groups)
    for g in groups:
        gdir = group_dir(g.path)
        w = GlbWriter(os.path.join(out_dir, gdir + ".glb"))
        for r in g.resources:
            if r.cls == C_MODEL:
                w.add_model(f"{r.name_hash:08x}", Model(r.body, r.name_hash), index, gdir)
        place_entities(w, gdir)
        if w.write():
            print(w.out_path, len(w.j["meshes"]), "models")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
