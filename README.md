# CoD Zombies (iOS 2010) – remake per uso personale

Sorgente: `Call_of_Duty__Zombies_1.5.0_ios_3.0.ipa` (armv6, motore Ideaworks **Airplay SDK 4.3**, logica in **Lua 5.1**).
Obiettivo: estrarre gli asset originali e ricostruire il gioco su un motore moderno (arm64 / iPhone attuale).

## Struttura
```
original/kiwi.app     bundle originale (non modificare)
extracted/            contenuto degli archivi .dz (gruppi *.group.bin)
game/assets/textures       PNG decodificate (per gruppo, nome = hash risorsa)
game/assets/sounds         WAV PCM 16 bit
game/assets/lua            script Lua decompilati (logica di gioco, ondate, mappe)
game/assets/lua_bytecode   bytecode originale
analysis/             note, dump, anteprime
tools/                estrattori (Python)
```

## Ricostruire gli asset
Serve: Python 3, ffmpeg, Java (per unluac), Godot 4.7.
```sh
tools/build_assets.sh          # original/kiwi.app -> extracted/ -> game/assets/
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
```
Anteprima di un modello: `Godot --path game -s res://tools/preview.gd -- res://assets/models/levels/nacht/environment.glb out.png 30 -45 0.7`

## Stato
| Componente | Stato | Note |
|---|---|---|
| Archivi `.dz` (DTRZ, LZMA) | ✅ | `tools/dz_extract.py` |
| Gruppi `.group.bin` | ✅ 68/68 | `tools/group.py`; hash = djb2 lowercase (`tools/iwhash.py`) |
| Texture (PVRTC, RGB/RGBA, palette) | ✅ 384/384 | `tools/textures.py` |
| Suoni (IMA ADPCM / PCM) | ✅ 499/499 | sample rate dedotto da blockAlign |
| Script Lua | ✅ 15 script, ~10.8k righe | unluac |
| Modelli `CIwModel` | ✅ 1324/1324 | `tools/model.py`, export glTF `tools/export_gltf.py`; 4 mappe complete |
| Materiali | ✅ | texture base + lightmap (UV2, in `extras.lightmap`, non ancora applicata in Godot) |
| Scheletri / skin / animazioni tipo 3 | ✅ | zombie (72 anim), cani (29), alcuni oggetti; `tools/anim.py`, `tools/export_characters.py` |
| Animazioni tipo 2 (giocatore/armi, oggetti) | ⏳ | posizioni per osso SoA non ancora decodificate |
| Parti dei personaggi | 🔶 | mesh divise per parte; nomi noti: body, legs, neck, leftarm, rightarm, leftelbow, rightelbow, headb, sleevel, sleever |
| Entità livello (`CIwEntSpec`, trigger, barricate, box…) | ⏳ | |
| Navmesh, collisioni, GUI, font | ⏳ | |
| Gameplay in Godot | ⏳ | |

## Formati – appunti
- Risorsa nel gruppo: `u32 size, u32 nameHash, body`. Le classi polimorfiche (es. `CIwSoundData`) hanno invece `u32 subclassHash` al posto del nome, e il nome è il primo u32 del body.
- Formati dettagliati nei docstring di `tools/model.py`, `tools/anim.py`, `tools/textures.py`, `tools/sounds.py`.
- Scala: 400 unità = 1 m; UV s16 con 4096 = 1.0; tempi animazione in 1/4096 s; quaternioni "smallest three" 3×10 bit.
