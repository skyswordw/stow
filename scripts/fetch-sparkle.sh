#!/usr/bin/env bash
# Prints the folder holding Sparkle's command-line tools (sign_update, generate_keys…) for the
# Sparkle version project.yml pins. Reuses the copy Xcode resolved for the build (DerivedData's
# SourcePackages/artifacts), else downloads the same Swift package archive Xcode uses and checks
# its SHA-256 (the checksum in Sparkle's Package.swift). Output: build/sparkle/<version>/bin.
set -euo pipefail
cd "$(dirname "$0")/.."

version=2.10.0
sha256=17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959

pinned=$(awk '/^  Sparkle:/{s=1} s&&/exactVersion:/{print $2; exit}' project.yml | tr -d '"')
[[ $pinned == "$version" ]] || { echo "error: project.yml pins Sparkle '$pinned' but $0 has $version; update both" >&2; exit 1; }

if [[ -n "${SPARKLE_BIN:-}" ]]; then
  [[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "error: SPARKLE_BIN=$SPARKLE_BIN has no sign_update" >&2; exit 1; }
  echo "$SPARKLE_BIN"; exit 0
fi

# Xcode's copy, when it is the pinned version.
while IFS= read -r tool; do
  bin=$(dirname "$tool")
  if grep -q "<string>$version</string>" "$bin/../Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist" 2>/dev/null; then
    echo "$bin"; exit 0
  fi
done < <(find build -path '*SourcePackages/artifacts/*' -name sign_update -type f -perm -u+x 2>/dev/null)

dest=build/sparkle/$version
if [[ ! -x "$dest/bin/sign_update" ]]; then
  mkdir -p "$dest"
  zip="$dest/Sparkle-for-Swift-Package-Manager.zip"
  curl --fail --silent --show-error --location -o "$zip" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip" >&2
  echo "$sha256  $zip" | shasum -a 256 --check --status || { rm -f "$zip"; echo "error: Sparkle $version checksum mismatch" >&2; exit 1; }
  unzip -q -o "$zip" 'bin/*' -d "$dest" >&2
  rm -f "$zip"
fi
echo "$dest/bin"
