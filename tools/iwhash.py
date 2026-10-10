"""Airplay/Marmalade IwHashString: djb2 over the lowercased string."""
import re


def iw_hash(s):
    h = 5381
    for c in s.lower().encode("latin-1"):
        h = (h * 33 + c) & 0xFFFFFFFF
    return h


def load_dictionary(*paths):
    """Map hash -> name from every identifier-like token in the given text files."""
    names = {}
    for p in paths:
        for line in open(p, encoding="latin-1"):
            for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_./\\-]{2,}", line):
                names.setdefault(iw_hash(tok), tok)
    return names
