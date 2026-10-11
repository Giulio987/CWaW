#!/usr/bin/env python3
"""Extract the big HUD CIwGxFont from fixed.group.bin as a BMFont (.fnt + pages).

CIwGxFont body (as far as needed here):
  0x00..0x10  font header (flags, sizes, hash of the source)
  then N embedded CIwTexture bodies (same layout as tools/textures.py: header
  0x17 bytes, flags 0x0c 43 04 00 ...); the big font 0xda9dc767 has 4 pages of
  128x256 RGBA4444 (format 6; grey, white glyph with dark outline). The two
  small fonts are one 128x256 4 bpp page each (format 36).
  After the pages: char ranges + glyph table (8 bytes per glyph, x/y in 1/16 px,
  not fully understood) - so glyph rects are found by segmenting the ink of each
  36 px row, in the known character order (rows of ASCII as laid out in the page).

Usage: tools/fonts.py extracted/main/fixed/fixed.group.bin game/assets/fonts
"""
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash

HUD_FONT = 0xDA9DC767
ROW = 36
# characters per 36 px row of page 0 and 1 (first chars of Latin-1 order)
ROWS = [
    [' !"#$%', "&'()*+,-./", "01234567", "89:;<=>?", "@ABCDE", "FGHIJKL", "MNOPQR"],
    ["STUVWX", "YZ[\\]^_`", "abcdefgh", "ijklmnop", "qrstuvw", "xyz{|}~"],
]


def pages(body):
    out = []
    i = body.find(bytes.fromhex("0c430400"))
    while i >= 0:
        w, h, pitch = struct.unpack_from("<HHH", body, i + 13)
        if body[i + 10] == 6:  # RGBA4444 (grey: R=G=B), alpha in the top nibble
            raw = np.frombuffer(body, np.uint8, h * pitch, i + 0x17).reshape(h, w, 2)
            lum = (raw[..., 0] & 15) * 17
            alpha = (raw[..., 1] >> 4) * 17
            out.append(np.dstack([lum, lum, lum, alpha]).astype(np.uint8))
            i = body.find(bytes.fromhex("0c430400"), i + 0x17 + h * pitch)
        else:
            break
    return out


def segments(alpha_rows):
    col = (alpha_rows > 40).any(0)
    segs, s = [], None
    for x, c in enumerate(list(col) + [False]):
        if c and s is None:
            s = x
        elif not c and s is not None:
            segs.append((s, x))
            s = None
    return segs


def main(group_path, out_dir):
    g = Group(group_path)
    body = next(r.body for r in g.resources if r.cls == iw_hash("CIwGxFont") and r.name_hash == HUD_FONT)
    imgs = pages(body)
    os.makedirs(out_dir, exist_ok=True)
    chars = []
    base = None
    for p, rows in enumerate(ROWS):
        img = imgs[p]
        Image.fromarray(img, "RGBA").save(os.path.join(out_dir, f"hud_{p}.png"))
        for r, text in enumerate(rows):
            y0 = r * ROW
            segs = [s for s in segments(img[y0:y0 + ROW, :, 3]) if not (p == 0 and r == 0 and s[1] <= 15)]
            ink = [c for c in text if c != " "]
            if len(segs) < len(ink):
                print(f"page {p} row {r}: {len(segs)} segments for {len(ink)} chars", file=sys.stderr)
                continue
            for c, (x0, x1) in zip(ink, segs):
                chars.append((ord(c), x0, y0, x1 - x0, p))
                if c == "E":
                    ys = np.nonzero((img[y0:y0 + ROW, x0:x1, 0] > 128).any(1))[0]
                    base = int(ys.max()) + 1
    base = base or 28
    lines = [
        'info face="CoDHud" size=22 bold=1 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0',
        f"common lineHeight=28 base={base} scaleW=128 scaleH=256 pages={len(ROWS)} packed=0",
    ]
    lines += [f'page id={p} file="hud_{p}.png"' for p in range(len(ROWS))]
    lines.append(f"chars count={len(chars) + 1}")
    lines.append(f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=10 page=0 chnl=15")
    for cid, x, y, w, p in chars:
        lines.append(f"char id={cid} x={x} y={y} width={w} height={ROW} xoffset=0 yoffset=0 xadvance={w - 1} page={p} chnl=15")
    with open(os.path.join(out_dir, "hud.fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"hud font: {len(chars)} glyphs, base {base}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
