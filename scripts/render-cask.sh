#!/usr/bin/env bash
# Renders packaging/homebrew/stow.rb for one release: fills in the version and the SHA-256 of the
# release DMG. Never publishes anything — it writes a cask file for a person (or the tap workflow)
# to commit.
#
#   scripts/render-cask.sh 1.0.0                     # downloads Stow-1.0.0.dmg from the v1.0.0 release
#   scripts/render-cask.sh 1.0.0 --dmg build/Stow-1.0.0.dmg
#   scripts/render-cask.sh 1.0.0 --output Casks/stow.rb
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "usage: $0 <version> [--dmg <path>] [--output <path>] [--repo owner/name]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
version=${1#v}; shift
dmg="" output="build/homebrew/stow.rb" repo="skyswordw/stow"
while [[ $# -gt 0 ]]; do
  case $1 in
    --dmg) dmg=${2:?}; shift 2 ;;
    --output) output=${2:?}; shift 2 ;;
    --repo) repo=${2:?}; shift 2 ;;
    *) usage ;;
  esac
done
[[ $version =~ ^[0-9]+(\.[0-9]+){1,3}([-.][0-9A-Za-z.]+)?$ ]] || { echo "error: bad version '$version'" >&2; exit 2; }

template=packaging/homebrew/stow.rb
asset="Stow-$version.dmg"
url="https://github.com/$repo/releases/download/v$version/$asset"
# The template's url must keep matching the asset name and tag this script uses.
grep -q 'releases/download/v#{version}/Stow-#{version}.dmg' "$template" \
  || { echo "error: $template url no longer matches v<version>/$asset" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
if [[ -z $dmg ]]; then
  dmg="$work/$asset"
  echo "Downloading $url" >&2
  curl --fail --location --silent --show-error --output "$dmg" "$url"
fi
[[ -s $dmg ]] || { echo "error: $dmg is missing or empty" >&2; exit 1; }
# A DMG starts with a zlib/bzip2/raw image and ends with the 512-byte "koly" trailer.
[[ "$(tail -c 512 "$dmg" | head -c 4)" == koly ]] || { echo "error: $dmg is not a UDIF disk image" >&2; exit 1; }

if command -v shasum >/dev/null; then
  sha256=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
else
  sha256=$(sha256sum "$dmg" | cut -d' ' -f1)
fi

mkdir -p "$(dirname "$output")"
# Drop the template's own header comment (everything before the `cask` line).
sed -e '1,/^cask /{/^#/d;}' -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha256/" "$template" > "$output"
if grep -q '@[A-Z0-9]*@' "$output"; then
  echo "error: unfilled placeholder in $output" >&2; exit 1
fi
echo "Rendered $output (version $version, sha256 $sha256)" >&2
