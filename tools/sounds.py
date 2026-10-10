#!/usr/bin/env python3
"""Convert CIwSoundData resources to .wav via ffmpeg.

Each record is polymorphic: what Group calls name_hash is the subclass hash, and
the body is:
  u32 nameHash, u32 dataLen, u32 sampleCount, data[dataLen], tail
ADPCM tail: u32 unknown, u16 2, u32 samplesPerBlock, u32 blockAlign (IMA ADPCM, mono).
  The sample rate is not stored; blockAlign follows the Microsoft convention
  (256 -> 11025 Hz, 512 -> 22050 Hz, 1024 -> 44100 Hz).
PCM tail:   u32 sampleRate, u16 (16-bit mono).
"""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from group import Group
from iwhash import iw_hash
from textures import group_dir

CLS = iw_hash("CIwSoundData")
SUB_ADPCM = 0x430758F0


def wav_bytes(body, subclass):
    name, n, samples = struct.unpack_from("<III", body, 0)
    data = body[12:12 + n]
    tail = body[12 + n:]
    if subclass == SUB_ADPCM:
        _, spb, align = struct.unpack_from("<HII", tail, 4)
        rate = 11025 * align // 256
        fmt = struct.pack("<HHIIHHHH", 0x11, 1, rate, rate * align // spb, align, 4, 2, spb)
        fact = b"fact" + struct.pack("<II", 4, samples)
    else:
        (rate,) = struct.unpack_from("<I", tail, 0)
        fmt = struct.pack("<HHIIHH", 1, 1, rate, rate * 2, 2, 16)
        fact = b""
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + fact + b"data" + struct.pack("<I", len(data)) + data
    return name, b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def main(out_dir, groups):
    n = 0
    for p in groups:
        for r in Group(p).resources:
            if r.cls != CLS:
                continue
            name, wav = wav_bytes(r.body, r.name_hash)
            dst = os.path.join(out_dir, group_dir(p), f"{name:08x}.wav")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "wav", "-i", "pipe:", "-c:a", "pcm_s16le", dst],
                           input=wav, check=True)
            n += 1
    print(f"sounds: {n}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
