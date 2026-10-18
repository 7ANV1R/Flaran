#!/bin/sh
# Regenerates the README screenshots in assets/screenshots.
# Runs the debug build in showcase mode (clean backdrop, demo projects and devices) and
# captures only that window, so nothing from your own desktop ends up in the images, then
# places each capture in the top-right corner of a laptop mockup.
# Optional: FLARAN_SHOWCASE_WALLPAPER=/path/to/image to use a wallpaper instead of the default blues.
set -e
cd "$(dirname "$0")/.."
swift build
mkdir -p assets/screenshots
for scene in home devices; do
  rect=$(mktemp -u)
  FLARAN_SHOWCASE=$scene FLARAN_SHOWCASE_RECT=$rect .build/debug/Flaran &
  pid=$!
  i=0
  while [ ! -s "$rect" ] && [ $i -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
  raw=$(mktemp -u).png
  screencapture -x -o -R "$(cat "$rect")" "$raw"
  swift scripts/frame-screenshot.swift "$raw" "assets/screenshots/$scene.png"
  rm -f "$raw"
  kill $pid; wait $pid 2>/dev/null || true
  rm -f "$rect"
  echo "assets/screenshots/$scene.png"
done
