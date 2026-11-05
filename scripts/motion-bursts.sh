#!/bin/zsh
# Frame bursts for the motion review (#104): scripts/motion-bursts.sh <out-dir> [transition…]
# Each transition is captured light and dark, normally and with each display override.
# Output: <out-dir>/<transition>-<appearance>-<override>.png
set -e
cd "${0:a:h}/.."
out=${1:?out-dir}; shift
mkdir -p "$out"
typeset -A scene crop
scene=(actions next-steps glance list archive-info details-planned notices details-planned
       notice source-access-unsaved lock encrypted tray tray tray-pin tray batch batch opening browser-opening)
crop=(actions 560,-200,260,200 archive-info 772,40,334,520 notices 0,40,800,300
      notice 0,40,800,240 lock 200,4,150,52 tray-pin 24,24,300,90 batch 760,-260,346,260 opening 300,240,500,220)
transitions=($@)
(( $#transitions )) || transitions=(actions glance archive-info notices notice lock tray tray-pin batch opening)
overrides=(${=OVERRIDES:-none motion transparency contrast})
for t in $transitions; do
  for look in light dark; do
    for o in $overrides; do
      args=(-StowBurst $t)
      [[ -n ${crop[$t]} ]] && args+=(-StowBurstCrop ${crop[$t]})
      # Start from not kept open, whatever is saved (the burst puts the saved value back).
      [[ $t == tray-pin ]] && args+=(-tray.pinned '<false/>')
      case $o in
        motion) args+=(-StowReduceMotion YES) ;;
        transparency) args+=(-StowReduceTransparency YES) ;;
        contrast) args+=(-StowIncreaseContrast YES) ;;
      esac
      file=$(scripts/snapshot.sh ${scene[$t]} $look 1100x700 $args | grep burst | head -1)
      [[ -n $file ]] && mv "$file" "$out/$t-$look-$o.png" && echo "$out/$t-$look-$o.png"
    done
  done
done
