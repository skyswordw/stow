#!/bin/zsh
# Builds Resources/Sample/Harbor Rebrand Handoff.zip from the real files in
# Resources/Sample/Harbor Rebrand Handoff (sources and licenses in CREDITS.md).
# Try the Sample opens this ZIP through the normal browse/preview/extract engine (#91).
#
#     zsh scripts/make-sample-zip.sh        (from the repository root)
#
# Re-run after changing sample files so the committed ZIP matches the folder.
set -euo pipefail
cd "${0:a:h}/.."

src="Resources/Sample/Harbor Rebrand Handoff"
out="Resources/Sample/Harbor Rebrand Handoff.zip"
[[ -d $src/Fonts ]] || { echo "error: run from the repository root; missing $src" >&2; exit 1; }

rm -f "$out"
# Flat archive root (README.md, Photos/, …) so the listing matches the handoff layout.
(cd "$src" && /usr/bin/zip -r -X -y "../Harbor Rebrand Handoff.zip" . -x "*.DS_Store" -x "*__MACOSX*")

# Refuse fictional / unsupported promise extensions that must not ship in the release sample.
if /usr/bin/unzip -l "$out" | /usr/bin/grep -Eiq '\.(app|pkg|mov|wav|7z)(/|$)'; then
  echo "error: sample ZIP contains an unsupported demo extension (.app/.pkg/.mov/.wav/.7z)" >&2
  exit 1
fi

echo "Wrote $out ($(du -h "$out" | awk '{print $1}'))"
