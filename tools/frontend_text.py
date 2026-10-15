#!/usr/bin/env python3
"""Build game/assets/frontend_text.json: the original front-end texts (localisation/*.dat,
english_uk: italian.dat is an untranslated copy of it, only its "Boilerplate" line differs).

- maps:    CMapInfo (frontend/mapinfo/mapinfo.group.bin): u32 title, u32 description, u32 ?
           (localisation hashes); the description is the map text of the level select screen
- help:    pages of fe_help (frontend.group.bin): fe_helpgame ("Game") and fe_helpperformance
           ("Performance") as [heading, body] sections, in the order of their CGuiLabels
           (bodies are the labels starting with a bullet). Controls/Multiplayer are left out.
- credits: the CGuiLabels of fe_credits (CGuiSimpleScrollingFrame "scroller") in order
- about:   fe_about texts (copyright, LS_ABOUT_VERSION) and the bundle version (Info.plist)
- text:    other labels used by the menus (pause, options, confirmations), by name
- loc:     every localisation string by hash ("%08x"): the original English texts the
           remake shows in English (game/scripts/lang.gd: prompts, HUD messages, LS_* strings)
"""
import json
import os
import plistlib
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from achievements import localisation
from group import Group
from iwhash import iw_hash

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MAIN = os.path.join(ROOT, "extracted/main")
TEXT = {   # name -> localisation hash (found in the GUI resources named in the comment)
    "pause": 0xa19e6181,             # ig_pause title
    "resume": 0xda5c3614,            # ig_pause "resume"
    "options": 0x58a88f4f,           # ig_pause "options"
    "local_leaderboard": 0xc7f307a2,  # ig_pause "localleaderboard"
    "restart_level": 0x29ac461d,     # ig_pause "resetlevel", ig_resetlevelyesno title
    "restart_confirm": 0x6a9e7a23,   # ig_resetlevelyesno
    "return_to_menu": 0x02871d51,    # ig_pause "frontend"
    "return_confirm": 0xf0cf76cb,    # ig_returntofrontendyesno
    "default_settings": 0xb5661fc2,  # fe_options/ig_options "restoretofactory"
    "default_confirm": 0x37558a47,   # fe_restoretofactoryyesno
    "auto_pause": 0x7cbefbb9,        # fe_settings/ig_settings cl_autopausetoggle
    "detail_level": 0xbc60118d,      # (fe_helpperformance mentions it; the toggle is se_performanceleveltoggle)
    "detail_high": 0x90846ac3,       # performance_toggle values
    "detail_medium": 0xcea9ff44,
    "detail_low": 0x0c231cd5,
    "extras": 0xbd61759a,            # fe_extras
    "leaderboards": 0x44534ecb,
    "credits": 0xc085c151,
    "about": 0xa08f651e,
    "help": 0x90845a6c,              # fe_help
    "help_game": 0x762afbe5,
    "help_performance": 0xeafaa61d,
    "help_support": 0xea8ebb10,
    "single_player_leaderboards": 0xc653fc55,
    "regular_desc": 0xfa235ba4,      # fe_singleplayer, shown under si_difficultytoggle
    "recruit_desc": 0x0a25cbed,
    "headphones": 0x44ee966e,        # fe_settings / ig_settings note
}


def labels(res):
    """Localisation hashes referenced by a CIwGuiResource, in order (CIwGuiText string ids)."""
    loc = localisation()
    out, b, i = [], res.body, 0
    while i + 4 <= len(b):
        w = struct.unpack_from("<I", b, i)[0]
        if w in loc:
            out.append(loc[w])
            i += 4
        else:
            i += 1
    return out


def sections(texts):
    out = []
    for t in texts:
        if t.lstrip().startswith("•") and out:
            out[-1][1] += ("\n" if out[-1][1] else "") + t
        else:
            out.append([t, ""])
    return out


def main(out):
    loc = localisation()
    fe = {r.name_hash: r for r in Group(os.path.join(MAIN, "frontend/frontend.group.bin")).resources}
    maps = {}
    for r in Group(os.path.join(MAIN, "frontend/mapinfo/mapinfo.group.bin")).resources:
        if len(r.body) == 12:
            title, desc, _ = struct.unpack("<3I", r.body)
            if title in loc and desc in loc:
                maps["%08x" % r.name_hash] = {"title": loc[title], "desc": loc[desc]}
    for m in ["nacht", "verruckt", "shinonuma", "derriese", "tutorial", "playground"]:
        if "%08x" % iw_hash(m) in maps:
            maps[m] = maps.pop("%08x" % iw_hash(m))
    help_pages = {}
    for page, name in [("game", "fe_helpgame"), ("performance", "fe_helpperformance")]:
        texts = labels(fe[iw_hash(name)])[1:]   # [0] is the page title
        if page == "performance":
            texts = texts[1:]                     # repeated "Performance" heading
        help_pages[page] = sections(texts)
    credits = labels(fe[iw_hash("fe_credits")])
    if credits and credits[-1] == loc[TEXT["credits"]]:
        credits = credits[:-1]                    # the screen title after the scroller
    about = labels(fe[iw_hash("fe_about")])
    info = plistlib.load(open(os.path.join(ROOT, "original/kiwi.app/Info.plist"), "rb"))
    data = {
        "maps": maps,
        "help": help_pages,
        "credits": credits,
        "about": {"copyright": about[1], "version": loc[iw_hash("LS_ABOUT_VERSION")] % info.get("CFBundleVersion", "")},
        "text": {k: loc[v] for k, v in TEXT.items() if v in loc},
        "loc": {"%08x" % k: v for k, v in sorted(loc.items())},
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game/assets/frontend_text.json"))
