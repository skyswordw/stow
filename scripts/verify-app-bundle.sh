#!/usr/bin/env bash
# Checks a packaged Stow.app (and optionally its DMG) before anything is uploaded.
#
#   scripts/verify-app-bundle.sh [--mode adhoc|signed|notarized] path/to/Stow.app [path/to/Stow.dmg]
#
# Every mode: the bundle layout (app, StowEngine.xpc + 7zz, Quick Look and Finder extensions),
# Universal 2 binaries, App Sandbox on every executable we ship, no get-task-allow, and
# `codesign --verify --deep --strict`. The DMG, when given, must hold Stow.app and an
# /Applications link.
# signed:    also Developer ID authority, the expected Team ID (TEAM_ID env, if set), hardened
#            runtime and a secure timestamp on every piece; the DMG itself is signed.
# notarized: also stapled tickets on app and DMG, and Gatekeeper (`spctl`) accepts both.
set -euo pipefail

mode=adhoc
if [[ ${1:-} == --mode ]]; then mode=${2:?}; shift 2; fi
case $mode in adhoc|signed|notarized) ;; *) echo "error: unknown mode $mode" >&2; exit 2 ;; esac
app=${1:?usage: $0 [--mode adhoc|signed|notarized] Stow.app [Stow.dmg]}
dmg=${2:-}
TEAM_ID=${TEAM_ID:-}
cd "$(dirname "$0")/.."

problems=0
ok()   { echo "ok    $*"; }
fail() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else echo "FAIL  $*"; fi; problems=$((problems + 1)); }

[[ -d $app ]] || { fail "$app is not a directory"; exit 1; }

# --- Layout + Universal 2 ---------------------------------------------------------------------
if scripts/check-universal.sh "$app" > /tmp/stow-universal.$$ 2>&1; then
  ok "every binary is arm64 + x86_64 ($(tail -1 /tmp/stow-universal.$$))"
else
  cat /tmp/stow-universal.$$; fail "Universal 2 / layout check failed"
fi
rm -f /tmp/stow-universal.$$

# Everything we sign: the app, its bundles and each 7zz.
code=("$app")
while IFS= read -r p; do code+=("$p"); done < <(find "$app/Contents" \( -type d \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' \) \) -o \( -type f -name 7zz \) | sort)
for p in "$app/Contents/XPCServices/StowEngine.xpc" \
         "$app/Contents/XPCServices/StowEngine.xpc/Contents/MacOS/7zz" \
         "$app/Contents/PlugIns/StowQuickLook.appex" \
         "$app/Contents/PlugIns/StowFinderSync.appex"; do
  [[ -e $p ]] || fail "missing ${p#"$app"/}"
done

# --- Signatures --------------------------------------------------------------------------------
if codesign --verify --deep --strict --verbose=2 "$app" 2>/tmp/stow-cs.$$; then
  ok "codesign --verify --deep --strict"
else
  cat /tmp/stow-cs.$$; fail "codesign --verify --deep --strict failed"
fi
rm -f /tmp/stow-cs.$$

for p in "${code[@]}"; do
  rel=${p#"$(dirname "$app")"/}
  info=$(codesign -dvvv "$p" 2>&1 || true)
  ents=$(codesign -d --entitlements - --xml "$p" 2>/dev/null || true)
  entfile=$(mktemp); printf '%s' "$ents" > "$entfile"
  if [[ $p != *.framework ]]; then
    sandbox=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entfile" 2>/dev/null || true)
    [[ $sandbox == true ]] || fail "$rel: App Sandbox entitlement missing"
  fi
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entfile" >/dev/null 2>&1; then
    fail "$rel: has get-task-allow (notarization rejects it)"
  fi
  rm -f "$entfile"
  grep -q 'flags=.*runtime' <<<"$info" || fail "$rel: hardened runtime is off"
  if [[ $mode != adhoc ]]; then
    grep -q '^Authority=Developer ID Application:' <<<"$info" || fail "$rel: not signed with a Developer ID Application certificate"
    grep -q '^Timestamp=' <<<"$info" || fail "$rel: no secure timestamp"
    if [[ -n $TEAM_ID ]]; then
      grep -q "^TeamIdentifier=$TEAM_ID\$" <<<"$info" || fail "$rel: Team ID is not $TEAM_ID ($(sed -n 's/^TeamIdentifier=//p' <<<"$info"))"
    fi
  fi
  who=$(sed -n 's/^Authority=//p' <<<"$info" | head -1); echo "      $rel: ${who:-ad-hoc}"
done

if [[ $mode == notarized ]]; then
  if xcrun stapler validate "$app" >/dev/null 2>&1; then ok "app ticket stapled"; else fail "app has no stapled ticket"; fi
  if spctl --assess --type execute -vvv "$app" 2>&1; then ok "Gatekeeper accepts the app"; else fail "spctl rejects the app"; fi
fi

# --- DMG ---------------------------------------------------------------------------------------
if [[ -n $dmg ]]; then
  [[ -f $dmg ]] || { fail "$dmg does not exist"; dmg=""; }
fi
if [[ -n $dmg ]]; then
  hdiutil verify -quiet "$dmg" && ok "hdiutil verify $(basename "$dmg")" || fail "hdiutil verify failed"
  mnt=$(mktemp -d)
  if hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg"; then
    [[ -d "$mnt/Stow.app" ]] && ok "DMG holds Stow.app" || fail "DMG has no Stow.app at its top level"
    [[ -L "$mnt/Applications" && $(readlink "$mnt/Applications") == /Applications ]] \
      && ok "DMG has an /Applications link" || fail "DMG has no /Applications link"
    if [[ -d "$mnt/Stow.app" ]] && ! codesign --verify --deep --strict "$mnt/Stow.app" 2>/dev/null; then
      fail "Stow.app inside the DMG fails codesign --verify"
    fi
    hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt" || true
  else
    fail "could not mount $dmg"
  fi
  rmdir "$mnt" 2>/dev/null || true
  if [[ $mode != adhoc ]]; then
    dinfo=$(codesign -dvvv "$dmg" 2>&1 || true)
    if codesign --verify --strict "$dmg" 2>/dev/null && grep -q '^Authority=Developer ID Application:' <<<"$dinfo"; then
      ok "DMG is Developer ID signed"
    else
      fail "DMG is not Developer ID signed"
    fi
  fi
  if [[ $mode == notarized ]]; then
    if xcrun stapler validate "$dmg" >/dev/null 2>&1; then ok "DMG ticket stapled"; else fail "DMG has no stapled ticket"; fi
    if spctl --assess --type open --context context:primary-signature -vvv "$dmg" 2>&1; then
      ok "Gatekeeper accepts the DMG"
    else
      fail "spctl rejects the DMG"
    fi
  fi
fi

echo "verify ($mode): $problems problem(s)"
(( problems == 0 ))
