#!/bin/sh
# Build the game for Android (arm64) into build/ (gitignored: it contains the original game data, never share it).
#   tools/build_android.sh [--lang en|it]
# --lang: the app's default language, as in build_ios.sh (custom feature lang_en / lang_it, read by lang.gd).
# Output: build/CWaW.apk, signed with Godot's debug keystore (Editor Settings > Export > Android),
# to install with `adb install -r build/CWaW.apk` or by copying it to the phone (allow unknown sources).
# Needs: game/assets built (tools/build_assets.sh), JDK 17 and the Android SDK set in the Godot editor
# settings, the Godot 4.7 Android export template (android_debug.apk from the release's export templates).
set -e
cd "$(dirname "$0")/.."
LANG_CODE=en
if [ "$1" = "--lang" ]; then
  case "$2" in
    en|it) LANG_CODE=$2 ;;
    *) echo "--lang: en or it" >&2; exit 1 ;;
  esac
  shift 2
fi
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
VER=$("$GODOT" --version | sed 's/\.official.*//; s/\.custom.*//')
TPL="$HOME/Library/Application Support/Godot/export_templates/$VER"
[ -d game/assets/levels ] || { echo "game/assets missing: run tools/build_assets.sh first" >&2; exit 1; }
[ -f "$TPL/android_debug.apk" ] || { echo "Android export template missing in $TPL (install it from the Godot editor)" >&2; exit 1; }
# app icon from the original bundle (largest one, 114 px, scaled up)
sips -s format png -z 192 192 original/kiwi.app/IconLarge4.png --out game/assets/android_icon.png > /dev/null
cp game/export_presets.cfg build_presets.bak
trap 'mv -f build_presets.bak game/export_presets.cfg' EXIT
sed -i '' "s/^custom_features=.*/custom_features=\"lang_$LANG_CODE\"/" game/export_presets.cfg
echo "Language: $LANG_CODE (custom feature lang_$LANG_CODE)"
mkdir -p build
rm -f build/CWaW.apk
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --export-debug "Android" ../build/CWaW.apk
[ -f build/CWaW.apk ] || { echo "Godot export failed" >&2; exit 1; }
echo "Done: build/CWaW.apk (personal use only)"
