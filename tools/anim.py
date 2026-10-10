#!/usr/bin/env python3
"""CIwAnimSkel, CIwAnimSkin and CIwAnim parsers (Airplay 4.3 IwAnim).

Quaternions are packed in a u32 ("smallest three"):
  bits 30-31 index of the dropped (largest) component in x,y,z,w order,
  bits 0-9 / 10-19 / 20-29 the other three in order, each (v - 512) / 511 * sqrt(1/2).
Bone positions are s16 in 1/4 model units. world = parent * local.

CIwAnimSkel:  u32 numBones, then per bone (30 bytes):
  u32 class CIwAnimBone, u32 name, u32 parentName (0 = root), u32 quat,
  s16 pos[3], u16 index, u16 flags, u16 0x400, u16 0
CIwAnimSkin:  u32 1, u32 modelHash, u32 skelHash, u32 numSets, then sets:
  u32 class CIwAnimSkinSet, u32 0, u32 numVerts, u32 byteSize,
  u8 boneIds[] (max 4, 0xff-terminated when fewer, padded to even),
  per vertex: u16 vertIndex, s16 localPos[numBones][3], u8 weight[numBones] (sum 128, padded to even)
CIwAnim:      u32 skelHash, u32 numBones, u32 boneMask, u32 numKeyFrames, keyframes, 12-byte trailer
  keyframe:   u32 class CIwAnimKeyFrame, u32 0, u32 time (1/4096 s),
              u8 3, s16 rootPos[3], u8 1, u32 boneMask, u32 numQuats, u8 flags, u32 quat[numQuats]
"""
import struct

import numpy as np

SQRT_HALF = 0.70710678


def unpack_quat(u):
    big = u >> 30
    v = [((u >> s) & 0x3FF) - 512 for s in (0, 10, 20)]
    v = [x / 511 * SQRT_HALF for x in v]
    w = max(0.0, 1.0 - sum(x * x for x in v)) ** 0.5
    q = v[:big] + [w] + v[big:]
    return np.array(q)  # x, y, z, w


class Skeleton:
    def __init__(self, body):
        (n,) = struct.unpack_from("<I", body, 0)
        self.names, self.parents, self.rot, self.pos = [], [], [], []
        pos = 4
        for _ in range(n):
            _cls, name, parent, q = struct.unpack_from("<IIII", body, pos)
            p = struct.unpack_from("<hhh", body, pos + 16)
            self.names.append(name)
            self.parents.append(parent)
            self.rot.append(unpack_quat(q))
            self.pos.append(np.array(p, float) * 0.25)
            pos += 30
        index = {h: i for i, h in enumerate(self.names)}
        self.parent_idx = [index.get(p, -1) for p in self.parents]


class Skin:
    def __init__(self, body):
        _v, self.model, self.skel, nsets = struct.unpack_from("<IIII", body, 0)
        self.influences = {}  # unique vertex -> [(bone, weight)]
        pos = 16
        for _ in range(nsets):
            _cls, _z, nv, size = struct.unpack_from("<IIII", body, pos)
            pos += 16
            start = pos
            bones = []
            while len(bones) < 4 and body[pos] != 0xFF:
                bones.append(body[pos])
                pos += 1
            if len(bones) < 4:
                pos += 1  # 0xff terminator
            pos += (pos - start) % 2
            nb = len(bones)
            for _ in range(nv):
                (vi,) = struct.unpack_from("<H", body, pos)
                pos += 2 + 6 * nb
                w = body[pos:pos + nb]
                pos += nb + nb % 2
                self.influences[vi] = [(bones[j], w[j] / 128.0) for j in range(nb)]
            assert pos == start + size


class Anim:
    def __init__(self, body, kf_class):
        self.skel, self.num_bones, _mask, nk = struct.unpack_from("<IIII", body, 0)
        self.times, self.root_pos, self.rots = [], [], []  # rots: list of {bone: quat}
        pos = 16
        for _ in range(nk):
            cls, _z, t = struct.unpack_from("<III", body, pos)
            if cls != kf_class or body[pos + 12] != 3:
                # TODO: type 2 keyframes (per-bone positions, player/props) are not decoded yet
                raise NotImplementedError("keyframe type %d" % body[pos + 12])
            rp = struct.unpack_from("<hhh", body, pos + 13)
            mask, cnt = struct.unpack_from("<II", body, pos + 20)
            pos += 29
            bones = [i for i in range(32) if mask >> i & 1]
            assert len(bones) == cnt
            qs = struct.unpack_from(f"<{cnt}I", body, pos)
            pos += 4 * cnt
            self.times.append(t / 4096.0)
            self.root_pos.append(np.array(rp, float) * 0.25)
            self.rots.append({b: unpack_quat(q) for b, q in zip(bones, qs)})
        self.trailer = body[pos:]
