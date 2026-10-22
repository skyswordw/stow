#!/usr/bin/env bash
# Sparkle appcast for a notarized release DMG (#34). A HOOK until Sparkle ships in the app (#35):
# with no Sparkle tools or key it prints what is missing and exits 0, so release.yml can call it
# unconditionally.
#
#   scripts/generate-appcast.sh build/release/Stow-1.0.0.dmg
#
# Environment:
#   SPARKLE_BIN          folder with Sparkle's `generate_appcast` (from the Sparkle release that #35 pins)
#   SPARKLE_ED_KEY_FILE  Stow's own EdDSA private key file. Generate a NEW pair with Sparkle's
#                        `generate_keys` for Stow; never reuse another app's (e.g. MijiaBar's) key.
#                        In CI it comes from the SPARKLE_ED_PRIVATE_KEY secret (not created yet).
#   REPO                 owner/name for the download URL; default skyswordw/stow
#   OUT                  output appcast; default build/release/appcast.xml (published as a release
#                        asset, never committed by this script)
#   REQUIRE_APPCAST=1    fail instead of skipping when the tools or key are missing
set -euo pipefail
cd "$(dirname "$0")/.."

dmg=${1:?usage: $0 path/to/Stow-<version>.dmg}
[[ -f $dmg ]] || { echo "error: $dmg not found" >&2; exit 1; }
name=$(basename "$dmg")
[[ $name =~ ^Stow-([0-9][0-9A-Za-z.-]*)\.dmg$ && $name != *-unsigned.dmg ]] \
  || { echo "error: expected a signed Stow-<version>.dmg, got $name" >&2; exit 1; }
version=${BASH_REMATCH[1]}
REPO=${REPO:-skyswordw/stow}
OUT=${OUT:-build/release/appcast.xml}

skip() {
  if [[ "${REQUIRE_APPCAST:-0}" == 1 ]]; then echo "error: $*" >&2; exit 1; fi
  echo "Appcast skipped: $* (Sparkle lands in #35)."; exit 0
}
gen=${SPARKLE_BIN:+$SPARKLE_BIN/generate_appcast}
[[ -n $gen && -x $gen ]] || skip "SPARKLE_BIN/generate_appcast not found"
[[ -n "${SPARKLE_ED_KEY_FILE:-}" && -f $SPARKLE_ED_KEY_FILE ]] || skip "SPARKLE_ED_KEY_FILE not set"

stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
cp "$dmg" "$stage/"
[[ -f "website/release-notes/v$version.md" ]] && cp "website/release-notes/v$version.md" "$stage/Stow-$version.md"
"$gen" \
  --ed-key-file "$SPARKLE_ED_KEY_FILE" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$version/" \
  --link "https://skyswordw.github.io/stow/" \
  --embed-release-notes \
  -o "$stage/appcast.xml" \
  "$stage"
mkdir -p "$(dirname "$OUT")"
cp "$stage/appcast.xml" "$OUT"
echo "Wrote $OUT for $version"
