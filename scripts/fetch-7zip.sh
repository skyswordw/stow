#!/bin/zsh
# Downloads the pinned official 7-Zip console build for macOS, verifies its SHA-256 and unpacks
# `7zz` + license files into Vendor/7zip/. The Xcode build copies them into StowEngine.xpc.
#
# 7-Zip is © Igor Pavlov, GNU LGPL (+ unRAR restriction). It stays a separate, unmodified
# executable that the engine runs as a child process — see Vendor/7zip/License.txt.
set -euo pipefail
cd "${0:a:h}/.."

version=26.04
archive=7z2604-mac.tar.xz
sha256=bee04358cbcbc7106273cee0e8d72916db2696c48067a3538c34d8cd6fd16578
url=https://github.com/ip7z/7zip/releases/download/$version/$archive

dest=Vendor/7zip
if [[ -x $dest/7zz && "$(cat $dest/VERSION 2>/dev/null)" == $version ]]; then
  echo "7-Zip $version already in $dest"; exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl --fail --location --silent --show-error --output "$work/$archive" "$url"
echo "$sha256  $work/$archive" | shasum -a 256 --check --status \
  || { echo "error: checksum mismatch for $archive" >&2; exit 1; }

mkdir -p "$work/x" && tar -xJf "$work/$archive" -C "$work/x"
rm -rf $dest && mkdir -p $dest
# Stow ships Universal 2 (#33): the official macOS build has arm64 and x86_64 slices; refuse one that doesn't.
if command -v lipo >/dev/null; then
  archs=$(lipo -archs "$work/x/7zz")
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] \
    || { echo "error: 7zz is not universal (has: $archs)" >&2; exit 1; }
fi
cp "$work/x/7zz" $dest/7zz && chmod 755 $dest/7zz
for f in License.txt readme.txt History.txt; do [[ -f "$work/x/$f" ]] && cp "$work/x/$f" $dest/; done
echo $version > $dest/VERSION
echo "7-Zip $version → $dest/7zz"
