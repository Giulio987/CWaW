#!/bin/sh
# Intro video (kiwi.app/videos/intro.mp4, console.bin IntroVideoPath, 480x320 MPEG-4 at
# 20 fps + AAC) -> game/assets/videos/intro.ogv (Ogg Theora/Vorbis, the format Godot plays).
# Homebrew's ffmpeg has no Theora encoder: ffmpeg decodes to PNG frames + WAV and Godot's
# own OGV movie writer (MovieWriterOGV) encodes them (game/tools/encode_movie.gd) at the
# project's 1280x720. The 480x320 frames are a 16:9 picture (480x270 at y 24, ffmpeg
# cropdetect) between black bars: the bars are cropped so the picture fills the 16:9 movie.
# Run from the project root; needs ffmpeg and Godot (through tools/run_godot.sh).
set -e
SRC=original/kiwi.app/videos/intro.mp4
OUT="$(pwd)/game/assets/videos/intro.ogv"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$SRC")
mkdir -p "$TMP/frames" "$(dirname "$OUT")"
ffmpeg -v error -y -i "$SRC" -vf crop=480:270:0:24 "$TMP/frames/%05d.png"
ffmpeg -v error -y -i "$SRC" -vn -ac 2 -ar 48000 -c:a pcm_s16le "$TMP/audio.wav"
# written outside the project (a file growing under res:// while Godot runs is not safe)
tools/run_godot.sh 300 --write-movie "$TMP/intro.ogv" --fixed-fps "${FPS%/*}" \
  -s res://tools/encode_movie.gd -- "$TMP/frames" "$TMP/audio.wav" "${FPS%/*}" > "$TMP/godot.log" 2>&1 &
PID=$!
# guard against the writer running away (see encode_movie.gd): the result is a few MB
while kill -0 $PID 2>/dev/null; do
  if [ "$(stat -f %z "$TMP/intro.ogv" 2>/dev/null || echo 0)" -gt 200000000 ]; then
    pkill -f encode_movie.gd; echo "intro_video: runaway output, stopped" >&2
  fi
  sleep 1
done
wait $PID || true
grep -q "Done recording" "$TMP/godot.log" && [ -s "$TMP/intro.ogv" ] || { cat "$TMP/godot.log"; echo "intro_video: encoding failed" >&2; exit 1; }
mv "$TMP/intro.ogv" "$OUT"
echo "intro video: $OUT"
