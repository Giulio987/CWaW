#!/usr/bin/env python3
"""CIwAnimSkel, CIwAnimSkin and CIwAnim parsers (Airplay 4.3 IwAnim).

Quaternions are packed in a u32 ("smallest three"):
  bits 30-31 index of the dropped (largest) component in x,y,z,w order,
  bits 0-9 / 10-19 / 20-29 the other three in order, each (v - 512) / 511 * sqrt(1/2).
Bone positions are s16 scaled by the bone's posScale/4096 (1024 -> 1/4 for most
skeletons, 409 -> ~1/10 for the first-person player rigs). world = parent * local.

CIwAnimSkel:  u32 numBones, then per bone (30 bytes):
  u32 class CIwAnimBone, u32 name, u32 parentName (0 = root), u32 quat,
  s16 pos[3], u16 index, u16 flags, u16 posScale (4096 = 1), u16 0
CIwAnimSkin:  u32 1, u32 modelHash, u32 skelHash, u32 numSets, then sets:
  u32 class CIwAnimSkinSet, u32 0, u32 numVerts, u32 byteSize,
  u8 boneIds[] (max 4, 0xff-terminated when fewer, padded to even),
  per vertex: u16 vertIndex, s16 localPos[numBones][3], u8 weight[numBones] (sum 128, padded to even)
CIwAnim:      u32 skelHash, u32 numBones, u32 boneMask, u32 numKeyFrames, keyframes, 12-byte trailer
  keyframe:   u32 class CIwAnimKeyFrame, u32 0, u32 time (1/4096 s),
              u8 type, s16 rootPos[3] (type 3; garbage in type 2), u8 1, u32 boneMask, u32 numBones, u8 flags,
              type 2 only: s16 x[n+1], y[n+1], z[n+1] - element 0 is a bias, bone i pos = (elem[i+1] + bias) * posScale
              u32 quat[numBones]
  Types are mixed freely within one animation. Bones missing from a keyframe keep their previous value.
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
            self.scale = struct.unpack_from("<H", body, pos + 26)[0] / 4096.0
            self.names.append(name)
            self.parents.append(parent)
            self.rot.append(unpack_quat(q))
            self.pos.append(np.array(p, float) * self.scale)
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
    def __init__(self, body, kf_class, scale=0.25):
        """scale: the skeleton's position scale (Skeleton.scale)."""
        self.skel, self.num_bones, _mask, nk = struct.unpack_from("<IIII", body, 0)
        self.times, self.root_pos, self.rots = [], [], []  # rots: list of {bone: quat}
        self.pos = []  # list of {bone: local position} (type 2 keyframes only)
        pos = 16
        for _ in range(nk):
            cls, _z, t, kind = struct.unpack_from("<IIIB", body, pos)
            if cls != kf_class or kind not in (2, 3):
                raise ValueError("bad keyframe at %d" % pos)
            mask, cnt = struct.unpack_from("<II", body, pos + 20)
            bones = [i for i in range(32) if mask >> i & 1]
            assert len(bones) == cnt
            pos += 29
            bone_pos = {}
            if kind == 3:
                rp = np.array(struct.unpack_from("<hhh", body, pos - 16), float) * scale
            else:
                # SoA x[n+1] y[n+1] z[n+1]; element 0 is a bias added to the others
                v = np.frombuffer(body, "<i2", 3 * (cnt + 1), pos).reshape(3, cnt + 1).T.astype(float)
                pos += 6 * (cnt + 1)
                p = (v[1:] + v[0]) * scale
                bone_pos = dict(zip(bones, p))
                rp = bone_pos.get(0, self.root_pos[-1] if self.root_pos else np.zeros(3))
            qs = struct.unpack_from(f"<{cnt}I", body, pos)
            pos += 4 * cnt
            self.times.append(t / 4096.0)
            self.root_pos.append(rp)
            self.pos.append(bone_pos)
            self.rots.append({b: unpack_quat(q) for b, q in zip(bones, qs)})
        self.trailer = body[pos:]
