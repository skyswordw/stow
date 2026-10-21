#!/bin/zsh
# Exports Stow's localizable strings for a language with xcodebuild and fails if any string has no
# translation. Usage: scripts/check-localizations.sh [language] (default zh-Hans). Run after
# `xcodegen generate` and scripts/fetch-7zip.sh. Writes build/loc/missing-<language>.txt.
set -euo pipefail
cd "${0:a:h}/.."
lang=${1:-zh-Hans}
rm -rf build/loc && mkdir -p build/loc
xcodebuild -exportLocalizations -project Stow.xcodeproj -localizationPath build/loc -exportLanguage "$lang" \
  -derivedDataPath build/LocDerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  > build/loc/export.log 2>&1 || { tail -40 build/loc/export.log; exit 1; }
xliff=$(find build/loc -name "$lang.xliff" | head -1)
[[ -n $xliff ]] || { echo "error: no $lang.xliff exported" >&2; exit 1; }
python3 - "$xliff" "build/loc/missing-$lang.txt" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
root = ET.parse(sys.argv[1]).getroot()
total, missing = 0, []
for file in root.findall("x:file", ns):
    origin = file.get("original", "")
    for unit in file.iter("{urn:oasis:names:tc:xliff:document:1.2}trans-unit"):
        if unit.get("translate") == "no":
            continue
        total += 1
        target = unit.find("x:target", ns)
        state = target.get("state") if target is not None else None
        if target is None or not (target.text or "").strip() or state in ("new", "needs-translation"):
            source = unit.find("x:source", ns)
            missing.append(f"{origin}\t{unit.get('id')}\t{source.text if source is not None else ''}")
with open(sys.argv[2], "w", encoding="utf-8") as out:
    out.write("\n".join(missing) + ("\n" if missing else ""))
print(f"{len(missing)} of {total} strings have no translation ({sys.argv[1]})")
for line in missing[:60]:
    print("  " + line)
sys.exit(1 if missing else 0)
PY
