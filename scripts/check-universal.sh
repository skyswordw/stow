#!/usr/bin/env bash
# Asserts that every Mach-O binary inside a built Stow.app (the app, StowEngine.xpc and its 7zz,
# the Quick Look and Finder extensions, any embedded frameworks) carries both arm64 and x86_64.
# Usage: scripts/check-universal.sh path/to/Stow.app   (macOS only: needs file(1) and lipo)
set -euo pipefail

app=${1:?usage: $0 path/to/Stow.app}
[[ -d "$app" ]] || { echo "error: $app is not a directory" >&2; exit 1; }
required=(arm64 x86_64)

checked=0 failed=0
while IFS= read -r -d '' binary; do
  file -b "$binary" | grep -q 'Mach-O' || continue
  archs=$(lipo -archs "$binary")
  missing=()
  for arch in "${required[@]}"; do
    [[ " $archs " == *" $arch "* ]] || missing+=("$arch")
  done
  relative=${binary#"$app"/}
  if (( ${#missing[@]} )); then
    echo "::error::$relative is missing ${missing[*]} (has: $archs)"
    failed=$((failed + 1))
  else
    echo "ok  $relative: $archs"
  fi
  checked=$((checked + 1))
done < <(find "$app" -type f -perm -u+x -print0)

# The binaries Stow can't run without; a bundle layout change must not silently drop them from the check.
for expected in Contents/MacOS/Stow \
                Contents/XPCServices/StowEngine.xpc/Contents/MacOS/StowEngine \
                Contents/XPCServices/StowEngine.xpc/Contents/MacOS/7zz \
                Contents/PlugIns/StowQuickLook.appex/Contents/MacOS/StowQuickLook \
                Contents/PlugIns/StowFinderSync.appex/Contents/MacOS/StowFinderSync; do
  [[ -x "$app/$expected" ]] || { echo "::error::$expected is missing from the bundle"; failed=$((failed + 1)); }
done

echo "$checked Mach-O binaries checked, $failed problems"
(( checked > 0 && failed == 0 ))
