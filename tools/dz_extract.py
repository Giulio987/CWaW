#!/usr/bin/env python3
"""Extract Airplay/Marmalade DZ ("DTRZ") archives.

Layout (little endian):
  "DTRZ" u16 numFiles u16 numDirs u8 version
  numFiles  x cstring  file names
  numDirs-1 x cstring  directory names (index 0 = root)
  numFiles  x { u16 dirIndex, u16 chunkIds[] terminated by 0xFFFF }
  u16 numArchiveFiles, u16 numChunks
  numChunks x { u32 offset, u32 compLen, u32 decompLen, u16 flags, u16 archiveFile }
Chunk flags: 0x200 LZMA (lzma "alone" stream), 0x100 stored, 0x08 zlib, 0x80 zero.
"""
import lzma
import os
import struct
import sys
import zlib

FLAG_ZLIB, FLAG_ZERO, FLAG_COPY, FLAG_LZMA = 0x08, 0x80, 0x100, 0x200


def cstr(buf, pos):
    end = buf.index(b"\0", pos)
    return buf[pos:end].decode("latin-1"), end + 1


def parse(buf):
    assert buf[:4] == b"DTRZ", "not a DZ archive"
    nfiles, ndirs, _ver = struct.unpack_from("<HHB", buf, 4)
    pos = 9
    names, dirs = [], [""]  # dir 0 is the implicit root, not stored
    for _ in range(nfiles):
        s, pos = cstr(buf, pos)
        names.append(s)
    for _ in range(ndirs - 1):
        s, pos = cstr(buf, pos)
        dirs.append(s)
    files = []
    for name in names:
        (diri,) = struct.unpack_from("<H", buf, pos)
        pos += 2
        chunks = []
        while True:
            (c,) = struct.unpack_from("<H", buf, pos)
            pos += 2
            if c == 0xFFFF:
                break
            chunks.append(c)
        files.append((name, dirs[diri] if diri < len(dirs) else "", chunks))
    narch, nchunks = struct.unpack_from("<HH", buf, pos)
    pos += 4
    chunks = []
    for _ in range(nchunks):
        chunks.append(struct.unpack_from("<IIIHH", buf, pos))
        pos += 16
    return files, chunks, narch


def chunk_data(buf, chunks, i):
    off, clen, dlen, flags, _arch = chunks[i]
    if flags & FLAG_ZERO:
        return b"\0" * dlen
    if flags & FLAG_LZMA:
        # compLen is unreliable for LZMA; stream is self-terminating via size in header
        nxt = min([c[0] for c in chunks if c[0] > off] + [len(buf)])
        d = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
        return d.decompress(buf[off:nxt])[:dlen]
    if flags & FLAG_ZLIB:
        return zlib.decompress(buf[off:off + clen])
    if flags & FLAG_COPY or flags == 0:
        return buf[off:off + dlen]
    raise ValueError(f"unsupported chunk flags 0x{flags:x}")


def main(archive, outdir, list_only=False):
    buf = open(archive, "rb").read()
    files, chunks, narch = parse(buf)
    if narch != 1:
        print(f"warning: {narch} archive files referenced", file=sys.stderr)
    for name, d, ids in files:
        flags = {chunks[i][3] for i in ids}
        size = sum(chunks[i][2] for i in ids)
        print(f"{d.replace(chr(92), '/') + '/' if d else ''}{name}\t{size}\tflags={','.join(hex(f) for f in flags)}")
        if list_only:
            continue
        path = os.path.join(outdir, d.replace("\\", "/"), name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            for i in ids:
                f.write(chunk_data(buf, chunks, i))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "-l"]
    main(args[0], args[1] if len(args) > 1 else ".", "-l" in sys.argv)
