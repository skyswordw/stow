#!/bin/zsh
# Builds real archives for trying browsing and previews: scripts/make-browse-fixtures.sh [output folder]
# Default output is Stow's sandbox temporary folder, so `-StowScene open -StowOpen <path>` can read them.
#   Showcase.zip   photos, PDF, Word, Markdown, CSV, code, audio, video (if ffmpeg), a font, a nested 7z
#   Legacy GBK.zip names stored in GBK without the UTF-8 flag (garbled until decoded)
#   Big.zip        100,000 entries across 500 folders, for scrolling and search timing (pass --big)
set -e
cd "${0:a:h}/.."
out=${1:-$HOME/Library/Containers/app.stow.Stow/Data/tmp/Fixtures}
[[ $1 == --big ]] && out=$HOME/Library/Containers/app.stow.Stow/Data/tmp/Fixtures
zz=$PWD/Vendor/7zip/7zz
[[ -x $zz ]] || { echo "Run scripts/fetch-7zip.sh first."; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
src=$work/Showcase
mkdir -p "$src"/{Photos,Docs,Code,Media,Fonts,Nested/Deeper}

pictures=(/System/Library/Desktop\ Pictures/*.heic)
for index in 1 2 3 4 5 6; do
  picture=${pictures[$index]}
  [[ -f $picture ]] || continue
  name=${${picture:t:r}// /-}
  sips -Z 1600 -s format jpeg "$picture" --out "$src/Photos/$name.jpg" >/dev/null
done
sips -Z 1200 -s format png "${pictures[7]}" --out "$src/Photos/Wallpaper.png" >/dev/null

cat > "$work/notes.txt" <<'EOF'
Harbor rebrand — handoff notes

1. Use the new mark on every surface.
2. Amber is the accent; keep it rare.
3. Motion is quiet: nothing bounces.
EOF
cupsfilter "$work/notes.txt" > "$src/Docs/Handoff Notes.pdf" 2>/dev/null
textutil -convert docx "$work/notes.txt" -output "$src/Docs/Handoff Notes.docx"
cat > "$src/Docs/README.md" <<'EOF'
# Harbor Showcase

A **real** archive for trying Stow's previews: hover a file, press *Space*, or open `Nested`.

- Photos are downsized desktop pictures
- `Code/` holds a Swift file
EOF
cat > "$src/Docs/Budget.csv" <<'EOF'
Item,Owner,Q1,Q2,Q3
Photography,Ana,1200,800,950
Type licensing,Ben,400,0,0
Prototype,Chen,3100,2800,1500
Print,Dee,0,650,1200
EOF
cat > "$src/Code/Tide.swift" <<'EOF'
import Foundation

/// Predicts the next high tide from the last one.
struct Tide {
    let lastHigh: Date
    var nextHigh: Date { lastHigh.addingTimeInterval(12 * 3600 + 25 * 60) }
}

print(Tide(lastHigh: .now).nextHigh)
EOF
say -o "$src/Media/Welcome.m4a" --data-format=aac "Welcome aboard. This archive was opened by Stow." 2>/dev/null || true
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -t 4 -pix_fmt yuv420p "$src/Media/Test Pattern.mp4"
fi
cp /System/Library/Fonts/Supplemental/Georgia.ttf "$src/Fonts/" 2>/dev/null || true

# Archives inside the archive: a 7z holding a zip.
mkdir -p "$work/inner/Sketches"
cp "$src/Photos/Wallpaper.png" "$work/inner/Sketches/"
echo "Deepest level." > "$work/inner/Sketches/note.txt"
(cd "$work/inner" && "$zz" a -bso0 -bsp0 "$work/innermost.zip" Sketches)
mkdir -p "$work/middle"
cp "$work/innermost.zip" "$work/middle/Innermost.zip"
cp "$src/Docs/Budget.csv" "$work/middle/"
(cd "$work/middle" && "$zz" a -bso0 -bsp0 "$src/Nested/Earlier Rounds.7z" .)
echo "Two levels down." > "$src/Nested/Deeper/where.txt"
touch "$src/Docs/.DS_Store"

rm -f "$out/Showcase.zip"
(cd "$work" && "$zz" a -bso0 -bsp0 "$out/Showcase.zip" Showcase)
echo "$out/Showcase.zip"

python3 -I - "$out/Legacy GBK.zip" <<'EOF'
import sys, zipfile
class Legacy(zipfile.ZipInfo):
    def _encodeFilenameFlags(self):
        return self.filename.encode("gbk"), self.flag_bits & ~0x800
names = ["项目资料/设计稿/首页.txt", "项目资料/会议记录.txt", "项目资料/预算表.csv", "说明.txt", "readme.txt"]
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    for name in names:
        archive.writestr(Legacy(name), "内容 " + name)
print(sys.argv[1])
EOF

if [[ $1 == --big || $2 == --big ]]; then
  python3 -I - "$out/Big.zip" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_STORED) as archive:
    for folder in range(500):
        for item in range(200):
            archive.writestr(f"Folder {folder:03}/Item {item:03}.txt", "")
print(sys.argv[1])
EOF
fi
