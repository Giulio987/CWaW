#!/usr/bin/env python3
"""Parse CIwModel resources (Airplay 4.3 IwGraphics).

Model header (28 bytes):
  u16 0, u16 type, u16 numVerts, u16 numUniqueVerts,
  s32 centre[3], u32 radius, u32 numBlocks
Then blocks, each starting with u32 classHash. Most blocks continue with
u32 nameHash, u16 memSize, u16 count, u16 0 (see parse_block).
"""
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iwhash import iw_hash

B = {n: iw_hash(n) for n in (
    "CIwModelBlockVerts", "CIwModelBlockNorms", "CIwModelBlockGLUVs", "CIwModelBlockGLUVs2",
    "CIwModelBlockCols", "CIwModelBlockGLTriList", "CIwModelBlockChunkTree", "CIwModelBlockChunk",
    "CIwModelBlockChunkVerts", "CIwModelExtSectorChunkData", "CIwModelExtSelSetFace", "CIwModelExtPos")}
NAMES = {v: k for k, v in B.items()}


class Model:
    def __init__(self, body, name_hash=0):
        self.name_hash = name_hash
        self.body = body
        (_, self.type, self.num_verts, self.num_unique, cx, cy, cz, self.radius,
         self.num_blocks) = struct.unpack_from("<HHHHiiiII", body, 0)
        self.centre = (cx, cy, cz)
        self.verts = self.norms = self.uvs = self.uvs2 = self.cols = None
        self.trilists = []   # (materialHash, flags, indices ndarray)
        self.chunks = []     # (header bytes, vertex index ndarray)
        self.sector_names = []
        self.sel_sets = []   # (nameHash, face indices)
        self.unparsed = None
        self._parse()

    def _parse(self):
        b = self.body
        pos = 28
        self.materials = []
        while pos + 4 <= len(b):
            (cls,) = struct.unpack_from("<I", b, pos)
            if cls not in NAMES or NAMES[cls].startswith("CIwModelExt"):
                break
            pos = getattr(self, "_b_" + NAMES[cls][8:])(b, pos + 4)
        # extensions: u32 count, then {u32 classHash, ...}
        (n_ext,) = struct.unpack_from("<I", b, pos)
        pos += 4
        try:
            for _ in range(n_ext):
                (cls,) = struct.unpack_from("<I", b, pos)
                pos = getattr(self, "_b_" + NAMES[cls][8:])(b, pos + 4)
        except (KeyError, NotImplementedError, ValueError, struct.error):
            pos = self._find_material_table()
            if pos is None:
                self.unparsed = len(b)
                return
        # material table: u32 n, n x u32 materialHash
        (n,) = struct.unpack_from("<I", b, pos)
        self.materials = list(struct.unpack_from(f"<{n}I", b, pos + 4))
        if pos + 4 + 4 * n != len(b):
            self.unparsed = pos

    def _find_material_table(self):
        """The material table ends the body; locate it from the end when an extension is opaque."""
        b = self.body
        for n in range(1, 64):
            pos = len(b) - 4 - 4 * n
            if pos > 28 and struct.unpack_from("<I", b, pos)[0] == n:
                return pos
        return None

    # ---- blocks; each takes the offset after the class hash and returns the next offset

    def _common(self, b, pos):
        name, _mem, count, _z = struct.unpack_from("<IHHH", b, pos)
        return name, count, pos + 10

    def _b_BlockVerts(self, b, pos):
        _, n, pos = self._common(b, pos)
        unique, bias = struct.unpack_from("<Hh", b, pos)
        pos += 4
        # every coordinate carries the same bias; removing it centres the model on header.centre
        soa = np.frombuffer(b, "<i2", unique * 3, pos).reshape(3, unique).T.astype(np.int32) + bias
        pos += unique * 6
        remap = np.frombuffer(b, "<u2", n - unique, pos)
        pos += (n - unique) * 2
        self.verts = np.concatenate([soa, soa[remap]]) if len(remap) else soa.copy()
        # unique source vertex of every expanded vertex (skins address unique vertices)
        self.unique_of = np.concatenate([np.arange(unique), remap]).astype(np.int64)
        return pos

    def _b_BlockNorms(self, b, pos):
        _, n, pos = self._common(b, pos)
        pos += 2
        self.norms = np.frombuffer(b, "<i2", n * 3, pos).reshape(n, 3)
        return pos + n * 6

    def _uvs(self, b, pos):
        _, n, pos = self._common(b, pos)
        return np.frombuffer(b, "<u2", n * 2, pos).reshape(n, 2), pos + n * 4

    def _b_BlockGLUVs(self, b, pos):
        self.uvs, pos = self._uvs(b, pos)
        return pos

    def _b_BlockGLUVs2(self, b, pos):
        self.uvs2, pos = self._uvs(b, pos)
        return pos

    def _b_BlockCols(self, b, pos):
        _, n, pos = self._common(b, pos)
        mode = b[pos]  # 1: one luminance byte per vertex, otherwise planar R[n] G[n] B[n] A[n]
        pos += 1
        if mode == 1:
            lum = np.frombuffer(b, np.uint8, n, pos)
            self.cols = np.stack([lum, lum, lum, np.full(n, 255, np.uint8)], 1)
            return pos + n
        self.cols = np.frombuffer(b, np.uint8, n * 4, pos).reshape(4, n).T.copy()
        return pos + n * 4

    def _b_BlockGLTriList(self, b, pos):
        mat, n, pos = self._common(b, pos)
        (flags,) = struct.unpack_from("<I", b, pos)
        pos += 4
        idx = np.frombuffer(b, "<u2", n, pos)
        self.trilists.append((mat, flags, idx))
        return pos + n * 2 + 4  # + u16 minIndex, u16 maxIndex

    def _b_BlockChunkTree(self, b, pos):
        # u32 name, 6 x u8 0, u16 numNodes, u16 numLeaves, then nodes depth-first:
        #   s32 centre[3], s32 radius, s16 child[2], u8 isLeaf
        # a leaf is followed inline by its Chunk, ChunkVerts and GLTriList blocks
        num_nodes, _leaves = struct.unpack_from("<HH", b, pos + 10)
        pos += 14
        for _ in range(num_nodes):
            leaf = b[pos + 20]
            pos += 21
            if not leaf:
                continue
            while pos + 4 <= len(b):
                (cls,) = struct.unpack_from("<I", b, pos)
                if cls not in (B["CIwModelBlockChunk"], B["CIwModelBlockChunkVerts"], B["CIwModelBlockGLTriList"]):
                    break
                pos = getattr(self, "_b_" + NAMES[cls][8:])(b, pos + 4)
        return pos

    def _b_BlockChunk(self, b, pos):
        self._chunk_hdr = b[pos:pos + 14]
        return pos + 14

    def _b_BlockChunkVerts(self, b, pos):
        _, n, pos = self._common(b, pos)
        self.chunks.append((self._chunk_hdr, np.frombuffer(b, "<u2", n, pos)))
        return pos + n * 2

    def _b_ExtSectorChunkData(self, b, pos):
        pos += 4
        end = b.index(b"\0", pos)
        self.sector_names.append(b[pos:end].decode("latin-1"))
        raise NotImplementedError  # rest of the sector data is not decoded yet

    def _b_ExtSelSetFace(self, b, pos):
        name, _a, _b, n = struct.unpack_from("<IIII", b, pos)
        pos += 16
        self.sel_sets.append((name, np.frombuffer(b, "<u2", n, pos)))
        return pos + n * 2

    def _b_ExtPos(self, b, pos):
        raise NotImplementedError


if __name__ == "__main__":
    import glob
    import collections
    from group import Group

    M = iw_hash("CIwModel")
    stats = collections.Counter()
    for p in sorted(glob.glob(os.path.join(sys.argv[1], "**/*.group.bin"), recursive=True)):
        for r in Group(p).resources:
            if r.cls != M:
                continue
            try:
                m = Model(r.body, r.name_hash)
            except Exception as e:
                stats[f"error {type(e).__name__}"] += 1
                continue
            if m.unparsed is None:
                stats["complete"] += 1
            else:
                rest = len(r.body) - m.unparsed
                stats[f"stopped, {rest} bytes left"] += 1
    for k, v in stats.most_common():
        print(v, k)
