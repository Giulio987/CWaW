#!/usr/bin/env python3
"""Texture cel animation of the CIwMaterials -> JSON {materialHash: [num, numU, w, h, period]}.

The 57-byte CIwMaterial bodies (51 bytes otherwise) end with an IwGx cel block:
  0x2d u8 1, u8 0, u8 celNum, u8 celNumU (cels per row), u8 celW, u8 celH (texels),
  u8 celPeriod (ticks per cel), then 5 zero bytes.
The cel offset (cel % numU * celW, cel / numU * celH) is added to the model's UVs:
0f74ae25 flames (256x256): 32 cels, 8 per row, 32x64; 7d038846 window shafts (128x128):
128 cels of 1 texel, i.e. the texture scrolls sideways; 9ac50779 smoke: 4 texels up per cel.
Material hashes are unique across the groups (same hash = same body).
"""
import json
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

C_MAT = iw_hash("CIwMaterial")


def main(out_path, *groups):
    out = {}
    for p in groups:
        for r in Group(p).resources:
            b = r.body
            if r.cls == C_MAT and len(b) >= 0x34 and b[0x2d] == 1:
                num, num_u, w, h, period = struct.unpack_from("<5B", b, 0x2f)
                if num > 1:
                    out[f"{r.name_hash:08x}"] = [num, num_u, w, h, period]
    with open(out_path, "w") as f:
        f.write("{\n" + ",\n".join(f'"{k}": {json.dumps(v)}' for k, v in sorted(out.items())) + "\n}\n")
    print(out_path, len(out), "animated materials")


if __name__ == "__main__":
    main(*sys.argv[1:])
