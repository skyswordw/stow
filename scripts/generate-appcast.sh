#!/usr/bin/env bash
# Sparkle appcast for a release DMG (#34, #35): signs the DMG with Stow's EdDSA key and writes
# appcast.xml with one item, for the release workflow to attach to the draft GitHub release. The
# app's feed (SUFeedURL) is releases/latest/download/appcast.xml, so a release's appcast reaches
# people only when a person publishes that release.
#
#   scripts/generate-appcast.sh build/release/Stow-1.0.0.dmg
#
# Version, build number (CFBundleVersion, what Sparkle compares), minimum macOS and the public key
# are read from the Stow.app the DMG was built from (APP), so the feed can't disagree with the app.
# The signature is checked against that app's SUPublicEDKey before anything is written.
#
# Environment:
#   SPARKLE_ED_PRIVATE_KEY  Stow's EdDSA private key (base64 seed, Sparkle's `generate_keys -x`
#                           format); CI passes the secret of that name. Only ever piped on stdin.
#   SPARKLE_ED_KEY_FILE     or a file holding it (local releases); never commit it
#   APP                     the packaged app; default Stow.app next to the DMG (package.sh's output)
#   SPARKLE_BIN             folder with Sparkle's sign_update; default from scripts/fetch-sparkle.sh
#   RELEASE_NOTES           Markdown shown in the update window; default website/release-notes/v<version>.md
#                           when it exists (the full notes are always linked: the GitHub release page)
#   REPO                    owner/name for the URLs; default skyswordw/stow
#   OUT                     output; default appcast.xml next to the DMG (never committed)
#   REQUIRE_APPCAST=1       fail instead of skipping when no key is set
#   DRY_RUN=1               CI check on PRs: accepts Stow-<v>-unsigned.dmg and a throwaway key (the
#                           signature is checked against that key, not the app's), skips the feed check
#   SKIP_FEED_CHECK=1       don't compare with the published feed (offline)
set -euo pipefail
cd "$(dirname "$0")/.."

note() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::notice::$*"; else echo "$*"; fi; }
die()  { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else echo "error: $*" >&2; fi; exit 1; }

dmg=${1:?usage: $0 path/to/Stow-<version>.dmg}
[[ -f $dmg ]] || die "$dmg not found"
dmg=$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")
name=$(basename "$dmg")
dry=${DRY_RUN:-0}
if [[ $dry == 1 ]]; then
  base=${name%-unsigned.dmg}; base=${base%.dmg}
  [[ $base =~ ^Stow-([0-9][0-9A-Za-z.-]*)$ ]] || die "expected Stow-<version>[-unsigned].dmg, got $name"
else
  [[ $name =~ ^Stow-([0-9][0-9A-Za-z.-]*)\.dmg$ && $name != *-unsigned.dmg ]] || die "expected a signed Stow-<version>.dmg, got $name"
fi
version=${BASH_REMATCH[1]}
REPO=${REPO:-skyswordw/stow}
APP=${APP:-$(dirname "$dmg")/Stow.app}
OUT=${OUT:-$(dirname "$dmg")/appcast.xml}

# --- Key (never echoed, never written) ----------------------------------------------------------
key=${SPARKLE_ED_PRIVATE_KEY:-}
if [[ -z $key && -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  [[ -f $SPARKLE_ED_KEY_FILE ]] || die "SPARKLE_ED_KEY_FILE $SPARKLE_ED_KEY_FILE does not exist"
  key=$(tr -d '[:space:]' < "$SPARKLE_ED_KEY_FILE")
fi
if [[ -z $key ]]; then
  [[ "${REQUIRE_APPCAST:-0}" == 1 ]] && die "no SPARKLE_ED_PRIVATE_KEY or SPARKLE_ED_KEY_FILE"
  note "Appcast skipped: no SPARKLE_ED_PRIVATE_KEY (see RELEASING.md)."
  exit 0
fi
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$key"

# --- What the app says ----------------------------------------------------------------------------
plist="$APP/Contents/Info.plist"
[[ -f $plist ]] || die "$plist not found (set APP to the Stow.app inside $name)"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
short=$(read_key CFBundleShortVersionString)
build=$(read_key CFBundleVersion)
minimum=$(read_key LSMinimumSystemVersion)
app_key=$(read_key SUPublicEDKey)
feed=$(read_key SUFeedURL)
[[ $short == "$version" ]] || die "$name is $version but the app says CFBundleShortVersionString=$short"
[[ $build =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "CFBundleVersion '$build' is not numeric; Sparkle compares it"
[[ -n $minimum ]] || die "the app has no LSMinimumSystemVersion"
[[ -n $app_key ]] || die "the app has no SUPublicEDKey"
[[ $feed == "https://github.com/$REPO/releases/latest/download/appcast.xml" ]] || die "unexpected SUFeedURL '$feed'"

# --- Sign and check -------------------------------------------------------------------------------
bin=$(scripts/fetch-sparkle.sh)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
xcrun swiftc -O -o "$work/sparkle-ed25519" scripts/sparkle-ed25519.swift
key_public=$(printf '%s' "$key" | "$work/sparkle-ed25519" public-key) || die "SPARKLE_ED_PRIVATE_KEY is not a Sparkle EdDSA key"
if [[ $dry == 1 ]]; then
  check_key=$key_public
  [[ $(printf '%s' "$app_key" | base64 --decode | wc -c | tr -d ' ') == 32 ]] || die "the app's SUPublicEDKey is not 32 bytes"
else
  [[ $key_public == "$app_key" ]] || die "SPARKLE_ED_PRIVATE_KEY does not belong to the app's SUPublicEDKey ($app_key); updates would be rejected"
  check_key=$app_key
fi
signature=$(printf '%s' "$key" | "$bin/sign_update" --ed-key-file - -p "$dmg") || die "sign_update failed"
unset key
[[ $signature =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "sign_update returned no signature"
"$work/sparkle-ed25519" verify "$check_key" "$signature" "$dmg"
length=$(stat -f %z "$dmg")

# --- Build numbers only go up -------------------------------------------------------------------
if [[ $dry != 1 && "${SKIP_FEED_CHECK:-0}" != 1 ]]; then
  if curl --fail --silent --location --max-time 30 -o "$work/published.xml" "$feed"; then
    published=$(python3 -c 'import sys,xml.etree.ElementTree as E
ns="{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items=E.parse(sys.argv[1]).getroot().iter("item")
print(max((i.findtext(ns+"version") or "0" for i in items), key=lambda v: [int(p) for p in v.split(".")], default="0"))' "$work/published.xml")
    newest=$(printf '%s\n%s\n' "$published" "$build" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    if [[ $build == "$published" || $newest != "$build" ]]; then
      die "build $build is not newer than the published appcast's $published; Sparkle would never offer it (pass a higher build number)"
    fi
    note "Published appcast has build $published; this one is $build."
  else
    note "No published appcast yet ($feed); this is the first."
  fi
fi

# --- Notes and XML --------------------------------------------------------------------------------
notes=${RELEASE_NOTES:-website/release-notes/v$version.md}
[[ -f $notes ]] || notes=""
python3 - "$OUT" "$version" "$build" "$minimum" "$length" "$signature" "$REPO" "$notes" "$(basename "$dmg")" <<'PY'
import sys, email.utils, xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr
out, version, build, minimum, length, signature, repo, notes, dmg = sys.argv[1:]
page = f"https://github.com/{repo}/releases/tag/v{version}"
url = f"https://github.com/{repo}/releases/download/v{version}/{dmg}"
description = ""
if notes:
    text = open(notes, encoding="utf-8").read().strip().replace("]]>", "]]]]><![CDATA[>")
    description = f'      <description sparkle:format="markdown"><![CDATA[{text}]]></description>\n'
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Stow</title>
    <link>https://github.com/{escape(repo)}</link>
    <description>Stow updates</description>
    <language>en</language>
    <item>
      <title>Stow {escape(version)}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <link>{escape(page)}</link>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(minimum)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{escape(page)}</sparkle:fullReleaseNotesLink>
{description}      <enclosure url={quoteattr(url)} length="{int(length)}" type="application/octet-stream" sparkle:edSignature={quoteattr(signature)}/>
    </item>
  </channel>
</rss>
'''
ET.fromstring(xml.encode())  # well-formed or fail
with open(out, "w", encoding="utf-8") as f:
    f.write(xml)
PY
note "Wrote $OUT: Stow $version (build $build), $length bytes, EdDSA-signed, macOS $minimum+"
