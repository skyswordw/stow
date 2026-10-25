#!/bin/zsh
# Renders a demo scene and copies its window images: scripts/snapshot.sh <scene> [light|dark] [WxH] [-StowKey value …]
# Output: snapshots/<scene>-<appearance>-<window|panel>.png
#
# Only the Stow this script starts is ever stopped (it quits by itself after the capture; a hung
# one is killed by PID after 60 s). Other Stows — test hosts, other worktrees — are left alone.
set -e
cd "${0:a:h}/.."
scene=${1:?scene}; look=${2:-light}; size=${3:-}
app=build/Build/Products/Debug/Stow.app/Contents/MacOS/Stow
mkdir -p snapshots
# Ignore saved window state: a Stow that quit with no windows open would otherwise start without the
# main window, and scenes start from it.
style=(-StowAppearance $look -ApplePersistenceIgnoreState YES); [[ -n $size ]] && style+=(-StowWindowSize $size); style+=("${@:4}")
list=$(mktemp)
"$app" -StowScene "$scene" -StowSnapshot YES $style > "$list" 2>/dev/null &
pid=$!
for _ in {1..600}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
kill -0 $pid 2>/dev/null && { kill $pid; echo "snapshot: $scene timed out" >&2; }
while read -r file; do
  [[ -f $file ]] || continue
  out="snapshots/$scene-$look-${${file:t}#$scene-}"
  cp "$file" "$out" && echo "$out"
done < "$list"
rm -f "$list"
