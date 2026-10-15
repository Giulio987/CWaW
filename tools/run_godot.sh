#!/bin/sh
[ -e "$(dirname "$0")/../.tests_paused" ] && [ "$GODOT_NOLOCK" != 1 ] && { echo "run_godot.sh: test in pausa (.tests_paused)" >&2; exit 1; }
# Run the game with a hard time limit so a stuck test never hangs:
#   tools/run_godot.sh <seconds> [-- game args...]
# One instance at a time: concurrent callers wait for a lock (GODOT_NOLOCK=1 skips it). With PREVIEW_TO=<dir>,
# the screenshots this run wrote to analysis/preview are copied there before the lock
# is released (parallel callers would overwrite each other's view_0.png...).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.godot_run.lock"
if [ "$GODOT_NOLOCK" = 1 ]; then
  # GODOT_NOLOCK=1: run alongside the others (screenshots go to the same analysis/preview: use distinct names)
  LOCK=$(mktemp -d)
  trap 'rm -rf "$LOCK"' EXIT INT TERM
else
while ! mkdir "$LOCK" 2>/dev/null; do
  # stale lock: its owner is gone
  if [ -f "$LOCK/pid" ] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then
    rm -rf "$LOCK"; continue
  fi
  sleep 1
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM
fi
MARK="$LOCK/start"
touch "$MARK"
LIMIT=$1; shift
# silent by default (Master bus muted in settings.gd); CODZ_MUTE=0 to hear it
CODZ_MUTE=${CODZ_MUTE:-1} /Applications/Godot.app/Contents/MacOS/Godot --path "$ROOT/game" "$@" &
PID=$!
i=0
while kill -0 $PID 2>/dev/null; do
  sleep 1; i=$((i + 1))
  if [ $i -ge "$LIMIT" ]; then echo "run_godot: timeout after ${LIMIT}s, killing" >&2; kill $PID; break; fi
done
wait $PID 2>/dev/null
if [ -n "$PREVIEW_TO" ]; then
  mkdir -p "$PREVIEW_TO"
  find "$ROOT/analysis/preview" -type f -newer "$MARK" -exec cp {} "$PREVIEW_TO/" \;
fi
