#!/usr/bin/env python3
"""Parse Airplay 4.3 binary resource groups (*.group.bin).

Top level is a sequence of tagged sections: u32 tagHash, u32 size (size counts
itself, so payload = size - 4). Known tags:
  ResGroupMembers     cstring name, u32 flags
  ResGroupChildPaths  child .group paths
  ResGroupResources   u32 numLists, then per list:
                        u32 classHash, u32 count, u8, u8,
                        count x { u32 size (incl. itself), u32 nameHash, body }
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iwhash import iw_hash, load_dictionary

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T_MEMBERS = iw_hash("ResGroupMembers")
T_CHILDREN = iw_hash("ResGroupChildPaths")
T_RESOURCES = iw_hash("ResGroupResources")


class Resource:
    def __init__(self, cls, name_hash, flags, body, offset):
        self.cls, self.name_hash, self.flags, self.body, self.offset = cls, name_hash, flags, body, offset


class Group:
    def __init__(self, path):
        self.path = path
        self.buf = open(path, "rb").read()
        self.name = None
        self.children = []
        self.resources = []
        self.unknown_tags = []
        self._parse()

    def _parse(self):
        b = self.buf
        pos = 6  # u32 version 0x0406033d + u16 0
        while pos + 8 <= len(b):
            tag, size = struct.unpack_from("<II", b, pos)
            body = b[pos + 8: pos + 4 + size]
            if tag == T_MEMBERS:
                self.name = body[: body.index(b"\0")].decode("latin-1")
            elif tag == T_CHILDREN:
                self.children = [s.decode("latin-1") for s in body.split(b"\0") if s.endswith(b".group")]
                self.children = [c[c.index("levels") if "levels" in c else 0:] for c in self.children]
            elif tag == T_RESOURCES:
                self._parse_resources(body, pos + 8)
            else:
                self.unknown_tags.append((tag, pos, size))
            pos += 4 + size

    def _parse_resources(self, b, base):
        (nlists,) = struct.unpack_from("<I", b, 0)
        pos = 4
        for _ in range(nlists):
            cls, count, f0, f1 = struct.unpack_from("<IIBB", b, pos)
            pos += 10
            for _ in range(count):
                size, nh = struct.unpack_from("<II", b, pos)
                self.resources.append(Resource(cls, nh, (f0, f1), b[pos + 8: pos + size], base + pos))
                pos += size
        if pos != len(b):
            raise ValueError(f"{self.path}: resource section parsed to {pos}, expected {len(b)}")


def dictionary():
    return load_dictionary(os.path.join(ROOT, "analysis", "kiwi_strings.txt"))


if __name__ == "__main__":
    names = dictionary()
    for p in sys.argv[1:]:
        g = Group(p)
        print(f"== {p}  name={g.name}  children={g.children}  unknown={len(g.unknown_tags)}")
        counts = {}
        for r in g.resources:
            counts[r.cls] = counts.get(r.cls, 0) + 1
        for c, n in counts.items():
            print(f"   {names.get(c, hex(c))}: {n}")
