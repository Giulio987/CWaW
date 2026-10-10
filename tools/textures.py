#!/usr/bin/env python3
"""Decode CIwTexture resources to PNG.

Body header (little endian, unaligned):
  0x00 u8   flags          0x0a u8  CIwImage format    0x0d u16 width
  0x0f u16  height         0x11 u16 pitch
Format 35 (PVRTC) carries a GL sub-header at 0x1f:
  u32 glFormat (0x8c00..0x8c03), u32 numMips, u32 w, u32 h, numMips x u32 size
Pixel data always ends one byte before the end of the body.
"""
import os
import struct
import sys

import numpy as np
import texture2ddecoder
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

CLS = iw_hash("CIwTexture")
FMT_RGB888, FMT_RGBA8888, FMT_PAL8, FMT_PVRTC = 10, 14, 23, 35


def decode(body):
    fmt = body[10]
    w, h, pitch = struct.unpack_from("<HHH", body, 13)
    end = len(body) - 1
    if fmt == FMT_PVRTC:
        gl, nmips = struct.unpack_from("<II", body, 0x1F)
        sizes = struct.unpack_from(f"<{nmips}I", body, 0x2F)
        start = end - sum(sizes)
        bgra = texture2ddecoder.decode_pvrtc(body[start:start + sizes[0]], w, h, gl in (0x8C01, 0x8C03))
        img = Image.frombytes("RGBA", (w, h), bgra, "raw", "BGRA")
        return img if gl in (0x8C02, 0x8C03) else img.convert("RGB")
    if fmt == FMT_RGBA8888:
        a = np.frombuffer(body, np.uint8, h * pitch, end - h * pitch).reshape(h, pitch)[:, : w * 4]
        return Image.fromarray(a.reshape(h, w, 4).copy(), "RGBA")
    if fmt == FMT_RGB888:
        a = np.frombuffer(body, np.uint8, h * pitch, end - h * pitch).reshape(h, pitch)[:, : w * 3]
        return Image.fromarray(a.reshape(h, w, 3).copy(), "RGB")
    if fmt == FMT_PAL8:
        # palette (256 x RGB888) follows the indices
        idx = np.frombuffer(body, np.uint8, h * pitch, 0x17).reshape(h, pitch)[:, :w]
        pal = np.frombuffer(body, np.uint8, 768, 0x17 + h * pitch).reshape(256, 3)
        return Image.fromarray(pal[idx], "RGB")
    raise ValueError(f"unsupported format {fmt}")


def group_dir(path):
    """extracted/<archive>/levels/nacht/environment/environment.group.bin -> levels/nacht/environment"""
    parts = os.path.normpath(path).split(os.sep)
    return os.path.join(*parts[parts.index("extracted") + 2:-1])


def main(out_dir, groups):
    ok = fail = 0
    for p in groups:
        g = Group(p)
        for r in g.resources:
            if r.cls != CLS:
                continue
            dst = os.path.join(out_dir, group_dir(p), f"{r.name_hash:08x}.png")
            try:
                img = decode(r.body)
            except Exception as e:  # keep going, report at the end
                print(f"FAIL {g.name}/{r.name_hash:08x}: {e}", file=sys.stderr)
                fail += 1
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            img.save(dst)
            ok += 1
    print(f"textures: {ok} ok, {fail} failed")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
