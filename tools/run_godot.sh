#!/bin/sh
# Run the game with a hard time limit so a stuck test never hangs:
#   tools/run_godot.sh <seconds> [-- game args...]
LIMIT=$1; shift
/Applications/Godot.app/Contents/MacOS/Godot --path "$(dirname "$0")/../game" "$@" &
PID=$!
i=0
while kill -0 $PID 2>/dev/null; do
  sleep 1; i=$((i + 1))
  if [ $i -ge "$LIMIT" ]; then echo "run_godot: timeout after ${LIMIT}s, killing" >&2; kill $PID; break; fi
done
wait $PID 2>/dev/null
