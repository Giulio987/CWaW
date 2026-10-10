#!/bin/sh
# Rebuild every derived asset from original/kiwi.app. Run from the project root.
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
$PY -I tools/export_gltf.py "$A/models" $G
$PY -I tools/export_characters.py "$A/characters" $G > /dev/null
echo "assets rebuilt"
