#!/bin/zsh
# Retakes every website screenshot and walkthrough frame in light and dark (#69):
#   scripts/website-shots.sh [name]      # e.g. grid, checkup-3; no name retakes all of them
# Builds nothing: run after `xcodebuild … build`. PNGs land in snapshots/website/, WebPs in
# website/assets/ (needs `cwebp`: brew install webp). Brings Stow to the front for each capture, so
# windows look active; leave the Mac alone while it runs. A locked screen captures blank windows.
#
# The browsing shots open Try the Sample's own ZIP through the engine, so they show exactly what it
# shows. The Checkup walkthrough uses "Harbor Prototype 1.3.zip" (an app build; the sample holds no
# app), and Pack packs a real "Harbor Handoff" folder made here from the sample's files.
set -e; setopt null_glob
cd "${0:a:h}/.."
only=${1:-}
png=snapshots/website; mkdir -p $png
zip="$PWD/build/Build/Products/Debug/Stow.app/Contents/Resources/Sample/Harbor Rebrand Handoff.zip"
[[ -f $zip ]] || { echo "Build Stow first: $zip is missing" >&2; exit 1; }

# The Pack frames' folder, inside Stow's sandbox: the sample's files, plus the Finder files and
# names Windows rejects that a real handoff folder picks up.
handoff=~/Library/Containers/app.stow.Stow/Data/tmp/Harbor\ Handoff
rm -rf $handoff; mkdir -p $handoff
sample="$PWD/Resources/Sample/Harbor Rebrand Handoff"
cp -R "$sample/Photos" "$sample/Specs" "$sample/Logo" "$sample/Screens" "$sample/README.md" $handoff/
printf 'x' > $handoff/.DS_Store; printf 'x' > $handoff/Photos/.DS_Store; printf 'x' > "$handoff/Photos/._Lighthouse.jpg"
printf 'Copy for the App Store page, round 2.\n' > "$handoff/Specs/Store Copy: Round 2.txt"
printf 'Which photo leads the launch post?\n' > "$handoff/Specs/Open Questions?.txt"
printf 'Book the photographer for the Oamaru reshoot.\n' > "$handoff/Specs/To do."

# shoot <name> <scene> <window size> [-StowKey value …]; $pick picks the capture (window, panel,
# combined = a window with its sheet, window1 / panel1 = the second window).
shoot() {
  local name=$1 scene=$2 size=$3; shift 3
  [[ -n $only && $only != $name ]] && return
  for look in light dark; do
    rm -f snapshots/$scene-$look-*
    scripts/snapshot.sh $scene $look "$size" -StowActivate '<true/>' "$@" >/dev/null
    local file=(snapshots/$scene-$look-${pick:-window}.png)
    [[ -f $file ]] || { echo "missing: $name $look" >&2; continue; }
    cp $file $png/$name-$look.png
    local dest=website/assets/$name-$look.webp
    [[ $name == (checkup|pack)-* ]] && dest=website/assets/tour/$name-$look.webp
    cwebp -quiet -q 86 -alpha_q 100 -m 6 $file -o $dest && echo $dest
  done
}

photos=(-StowFolder Photos -StowSelect "Lighthouse.jpg|Pier at Dawn.jpg")
fonts="Atkinson Hyperlegible Bold.ttf|Atkinson Hyperlegible Regular.ttf|Instrument Serif Italic.ttf"
shoot grid open 1000x607 -StowOpen $zip $photos -StowView grid -StowSnapshotDelay 6
shoot steps open 900x547 -StowOpen $zip -StowFolder Fonts -StowView grid -StowSelect $fonts -StowSnapshotDelay 6
shoot editing open 900x547 -StowOpen $zip -StowView grid -StowEdits '<true/>' -StowSnapshotDelay 6
# Grid first, so the photos' thumbnails are loaded when Glance lists them.
shoot glance open 1000x607 -StowOpen $zip $photos -StowView grid -StowGlance '<true/>' -StowSnapshotDelay 12
pick=panel1 shoot tray tray ""
shoot recents recents 600x436
pick=window1 shoot quicklook quicklook 550x450 -StowOpen $zip -StowSnapshotDelay 4

shoot checkup-1 checkup 800x573
shoot checkup-2 checkup 800x573 -StowSelect "Harbor Prototype.app"
pick=combined shoot checkup-3 signature-warning 800x573 -StowSnapshotDelay 2
pick=combined shoot checkup-4 replace-app 800x573 -StowSnapshotDelay 2
shoot checkup-5 install-done 800x573

pick=combined shoot pack-1 pack 800x582 -StowPack $handoff -PackAudience windows -StowSnapshotDelay 3
pick=combined shoot pack-2 pack 800x582 -StowPack $handoff -PackAudience mac -StowSnapshotDelay 3
pick=combined shoot pack-3 pack 800x582 -StowPack $handoff -PackAudience linux -StowSnapshotDelay 3
shoot pack-4 packing 800x582
shoot pack-5 packed 800x582
