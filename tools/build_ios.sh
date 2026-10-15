#!/bin/sh
# Build the game for iPhone into build/ (gitignored: it contains the original game data, never share it).
#   tools/build_ios.sh [TEAM_ID]
# Without TEAM_ID: exports the Xcode project and compiles an UNSIGNED build/CWaW-unsigned.ipa, to sign
# and install yourself (Xcode, Sideloadly, AltStore...). With TEAM_ID (Xcode > Settings > Accounts)
# the Xcode project carries your team: open build/ios/CWaW.xcodeproj and press Run with the iPhone attached.
# Needs: game/assets built (tools/build_assets.sh), Xcode, the Godot 4.7 iOS export template
# (Godot editor > Editor > Manage Export Templates, or ios.zip from the release's export templates).
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
VER=$("$GODOT" --version | sed 's/\.official.*//; s/\.custom.*//')
TPL="$HOME/Library/Application Support/Godot/export_templates/$VER"
[ -d game/assets/levels ] || { echo "game/assets missing: run tools/build_assets.sh first" >&2; exit 1; }
[ -f "$TPL/ios.zip" ] || { echo "iOS export template missing in $TPL (install it from the Godot editor)" >&2; exit 1; }
command -v xcodebuild > /dev/null || { echo "Xcode is required" >&2; exit 1; }
# app icon from the original bundle (largest one, 114 px, scaled up)
sips -s format png -z 1024 1024 original/kiwi.app/IconLarge4.png --out game/assets/ios_icon.png > /dev/null
# Godot wants a team id even for an unsigned project: a placeholder, restored afterwards
TEAM=${1:-UNSIGNED00}
cp game/export_presets.cfg build_presets.bak
trap 'mv -f build_presets.bak game/export_presets.cfg' EXIT
sed -i '' "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$TEAM\"/" game/export_presets.cfg
rm -rf build/ios
mkdir -p build/ios
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --export-debug "iOS" ../build/ios/CWaW.xcodeproj
[ -d build/ios/CWaW.xcodeproj ] || { echo "Godot export failed" >&2; exit 1; }
if [ -n "$1" ]; then
  echo "Done: open build/ios/CWaW.xcodeproj in Xcode, connect the iPhone (Developer Mode on) and press Run."
  exit 0
fi
# unsigned device build -> Payload/CWaW.app -> build/CWaW-unsigned.ipa
xcodebuild -project build/ios/CWaW.xcodeproj -scheme CWaW -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build -quiet
APP=$(find build/ios/DerivedData/Build/Products -maxdepth 2 -name '*.app' -path '*iphoneos*' | head -1)
[ -n "$APP" ] || { echo "xcodebuild produced no .app" >&2; exit 1; }
rm -rf build/ipa build/CWaW-unsigned.ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../CWaW-unsigned.ipa Payload)
rm -rf build/ipa
echo "Done: build/CWaW-unsigned.ipa (unsigned: sign it before installing; personal use only)"
