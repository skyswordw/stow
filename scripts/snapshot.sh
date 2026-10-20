#!/bin/zsh
# Renders a demo scene and copies its window images: scripts/snapshot.sh <scene> [light|dark]
# Output: snapshots/<scene>-<appearance>-<window|panel>.png
set -e
cd "${0:a:h}/.."
scene=${1:?scene}; look=${2:-light}
app=build/Build/Products/Debug/Stow.app/Contents/MacOS/Stow
mkdir -p snapshots
pkill -x Stow 2>/dev/null || true; sleep 0.3
style=(-StowAppearance $look)
"$app" -StowScene "$scene" -StowSnapshot YES $style 2>/dev/null | while read -r file; do
  out="snapshots/$scene-$look-${${file:t}#$scene-}"
  cp "$file" "$out" && echo "$out"
done
