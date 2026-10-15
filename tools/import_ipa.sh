#!/bin/sh
# Unpack your own copy of the original game into original/kiwi.app (gitignored).
#   tools/import_ipa.sh path/to/Call_of_Duty_Zombies.ipa
# Only the data archives (*.dz) and Info.plist are used; nothing from the IPA is ever committed.
set -e
[ -f "$1" ] || { echo "usage: tools/import_ipa.sh <file.ipa>" >&2; exit 1; }
cd "$(dirname "$0")/.."
T=$(mktemp -d)
unzip -q "$1" 'Payload/*' -d "$T"
APP=$(find "$T/Payload" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] && ls "$APP"/*.dz > /dev/null 2>&1 || { echo "no .dz archives in the IPA: not the expected game" >&2; rm -rf "$T"; exit 1; }
rm -rf original/kiwi.app
mkdir -p original
mv "$APP" original/kiwi.app
rm -rf "$T"
echo "original/kiwi.app ready: now run tools/build_assets.sh"
