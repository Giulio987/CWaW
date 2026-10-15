#!/bin/sh
# Export the game as an Xcode project in build/ios/ (gitignored), to open in Xcode and run on an iPhone.
#   tools/build_ios.sh [TEAM_ID]
# Needs: game/assets built (tools/build_assets.sh), Xcode, the Godot 4.7 iOS export templates
# (Godot editor > Editor > Manage Export Templates > Download and Install).
# TEAM_ID: your Apple Developer team (Xcode > Settings > Accounts; a free Apple ID works too).
# Without it the project is exported unsigned and the team is chosen later in Xcode.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
VER=$("$GODOT" --version | sed 's/\.official.*//; s/\.custom.*//')
TPL="$HOME/Library/Application Support/Godot/export_templates/$VER"
[ -d game/assets/levels ] || { echo "game/assets missing: run tools/build_assets.sh first" >&2; exit 1; }
[ -f "$TPL/ios.zip" ] || { echo "iOS export template missing in $TPL (install it from the Godot editor)" >&2; exit 1; }
command -v xcodebuild > /dev/null || { echo "Xcode is required" >&2; exit 1; }
if [ -n "$1" ]; then
  sed -i '' "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$1\"/" game/export_presets.cfg
fi
mkdir -p build/ios
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --export-debug "iOS" ../build/ios/CoDZombiesRemake.xcodeproj
if [ -n "$1" ]; then
  git checkout -- game/export_presets.cfg 2>/dev/null || true
fi
echo "Done: open build/ios/CoDZombiesRemake.xcodeproj in Xcode, pick your team under Signing & Capabilities,"
echo "connect the iPhone (Developer Mode on) and press Run."
