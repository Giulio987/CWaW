#!/bin/sh
# Rebuild every derived asset from original/kiwi.app. Run from the project root.
# Needs python3, ffmpeg, java (unluac) and lua.
set -e
PY=.venv/bin/python
[ -x "$PY" ] || { python3 -m venv .venv && .venv/bin/pip install -q numpy pillow texture2ddecoder scipy; }
for f in original/kiwi.app/*.dz; do n=$(basename "$f" .dz); $PY -I tools/dz_extract.py "$f" "extracted/${n#_}" > /dev/null; done
G=$(find extracted -name '*.group.bin' | sort)
A=game/assets
$PY -I tools/textures.py "$A/textures" $G
$PY -I tools/sounds.py "$A/sounds" $G
$PY -I tools/lua_extract.py "$A/lua_bytecode" $G > /dev/null
touch "$A/lua_bytecode/.gdignore"
for f in $(find "$A/lua_bytecode" -name '*.luac'); do
  o="$A/lua/${f#$A/lua_bytecode/}"; o="${o%c}"; mkdir -p "$(dirname "$o")"
  java -jar tools/bin/unluac.jar "$f" > "$o"
done
for l in nacht verruckt shinonuma derriese; do
  E=extracted/$l/levels/$l
  D=$(ls $E/dynamics/*.bin)
  $PY -I tools/entities.py "$A/levels/$l/entities.json" $E/environment/environment.group.bin $D extracted/main/ingame/dynamics/dynamics.group.bin
  $PY -I tools/wall_yaw.py "$A/levels/$l/entities.json" $E/environment/environment.group.bin
  $PY -I tools/wall_yaw.py "$A/levels/$l/entities.json" $E/environment/environment.group.bin $D
  $PY -I tools/navmesh.py "$A/levels/$l/navmesh.json" $E/environment/environment.group.bin
  lua tools/lua/dump_waves.lua "$A/lua/levels/$l/${l}_full.lua" 0 40 > "$A/levels/$l/waves.json"
  lua tools/lua/dump_level.lua "$A/lua/ingame/scripts" "$A/lua/levels/$l/$l.lua" > "$A/levels/$l/level.json"
done
$PY -I tools/resolve_names.py
$PY -I tools/export_gltf.py "$A/models" $G
$PY -I tools/export_characters.py "$A/characters" $G > /dev/null
$PY -I tools/pair_arms.py > /dev/null
$PY -I tools/sound_index.py "$A/sounds/index.json"
$PY -I tools/fonts.py extracted/main/fixed/fixed.group.bin "$A/fonts"
echo "assets rebuilt"
