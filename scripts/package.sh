#!/usr/bin/env bash
# Builds a Release Stow.app, signs it with Developer ID (inside-out, hardened runtime, secure
# timestamp, every target keeps its App Sandbox entitlements), wraps it in a DMG, notarizes and
# staples both, and verifies the result. Never publishes anything: the DMG lands in build/release/.
#
# The same script runs on a Mac (keychain identity + notarytool keychain profile) and in
# .github/workflows/release.yml (temporary keychain + App Store Connect API key). See RELEASING.md.
#
# Environment (all optional):
#   VERSION            marketing version; default MARKETING_VERSION from project.yml
#   BUILD_NUMBER       CFBundleVersion; default CURRENT_PROJECT_VERSION from project.yml
#   SIGN_IDENTITY      codesign identity (name or SHA-1). Unset: the first "Developer ID Application"
#                      identity in the keychain search list, else ad-hoc. "-" forces an ad-hoc dry run.
#   TEAM_ID            expected Team ID of the Developer ID identity (checked by the verify script)
#   KEYCHAIN           keychain to search for the identity (CI passes its temporary keychain)
#   Notarization (signed builds only; with none of these set, the build is signed but not notarized):
#     NOTARY_PROFILE                         `xcrun notarytool store-credentials` profile name (local), or
#     ASC_API_KEY_PATH + ASC_API_KEY_ID + ASC_API_ISSUER_ID   App Store Connect API key (CI)
#   REQUIRE_NOTARIZATION=1   fail instead of skipping when no notary credentials are set
#   PREBUILT_APP       skip xcodebuild and package this Stow.app (CI dry run reuses its Release build)
#   OUT_DIR            output folder; default build/release
set -euo pipefail
cd "$(dirname "$0")/.."

log()  { printf '==> %s\n' "$*"; }
warn() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"; else echo "warning: $*" >&2; fi; }
die()  { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else echo "error: $*" >&2; fi; exit 1; }

setting() { sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" project.yml | head -1; }
VERSION=${VERSION:-$(setting MARKETING_VERSION)}
VERSION=${VERSION#v}
BUILD_NUMBER=${BUILD_NUMBER:-$(setting CURRENT_PROJECT_VERSION)}
[[ $VERSION =~ ^[0-9]+(\.[0-9]+){1,3}([-.][0-9A-Za-z.]+)?$ ]] || die "bad VERSION '$VERSION'"
[[ $BUILD_NUMBER =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "bad BUILD_NUMBER '$BUILD_NUMBER'"
OUT_DIR=${OUT_DIR:-build/release}
TEAM_ID=${TEAM_ID:-}
keychain_args=(); [[ -n "${KEYCHAIN:-}" ]] && keychain_args=(--keychain "$KEYCHAIN")

# --- Identity ---------------------------------------------------------------------------------
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning ${KEYCHAIN:+"$KEYCHAIN"} 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1 || true)
  [[ -n $SIGN_IDENTITY ]] || { warn "no Developer ID Application identity found; building an ad-hoc dry run"; SIGN_IDENTITY=-; }
fi
if [[ $SIGN_IDENTITY == - ]]; then
  signed=0; DMG="$OUT_DIR/Stow-$VERSION-unsigned.dmg"
  log "Ad-hoc dry run (not for distribution)"
else
  signed=1; DMG="$OUT_DIR/Stow-$VERSION.dmg"
  log "Signing identity: $SIGN_IDENTITY"
fi

# --- Notarization credentials -------------------------------------------------------------------
notary_args=(); notarize=0
if (( signed )); then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE"); notarize=1; log "Notarizing with keychain profile $NOTARY_PROFILE"
  elif [[ -n "${ASC_API_KEY_PATH:-}" && -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_ISSUER_ID:-}" ]]; then
    [[ -f $ASC_API_KEY_PATH ]] || die "ASC_API_KEY_PATH $ASC_API_KEY_PATH does not exist"
    notary_args=(--key "$ASC_API_KEY_PATH" --key-id "$ASC_API_KEY_ID" --issuer "$ASC_API_ISSUER_ID"); notarize=1
    log "Notarizing with App Store Connect API key $ASC_API_KEY_ID"
  elif [[ "${REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
    die "REQUIRE_NOTARIZATION=1 but no NOTARY_PROFILE or ASC_API_KEY_* is set"
  else
    warn "no notarization credentials (NOTARY_PROFILE or ASC_API_KEY_*): the DMG will be signed but NOT notarized"
  fi
fi

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
DMG="$OUT_DIR/$(basename "$DMG")"
APP="$OUT_DIR/Stow.app"

# --- Build ------------------------------------------------------------------------------------
if [[ -n "${PREBUILT_APP:-}" ]]; then
  [[ -d $PREBUILT_APP ]] || die "PREBUILT_APP $PREBUILT_APP is not a directory"
  log "Packaging prebuilt $PREBUILT_APP"
  ditto "$PREBUILT_APP" "$APP"
else
  [[ -x Vendor/7zip/7zz ]] || zsh scripts/fetch-7zip.sh
  command -v xcodegen >/dev/null || die "xcodegen is missing (brew install xcodegen)"
  xcodegen generate --quiet
  archive="$OUT_DIR/Stow.xcarchive"
  log "Archiving Release $VERSION ($BUILD_NUMBER), all architectures"
  # Built ad-hoc on purpose: Xcode applies each target's sandbox entitlements, and the signing pass
  # below re-signs every piece with the real identity, keeping those entitlements.
  if ! xcodebuild archive \
    -project Stow.xcodeproj -scheme Stow -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    -derivedDataPath build/DerivedData-release \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    > "$OUT_DIR/xcodebuild-archive.log" 2>&1; then
    grep -E 'error:' "$OUT_DIR/xcodebuild-archive.log" | head -40 >&2 || true
    tail -30 "$OUT_DIR/xcodebuild-archive.log" >&2
    die "xcodebuild archive failed (see $OUT_DIR/xcodebuild-archive.log)"
  fi
  grep -E '^\*\* ' "$OUT_DIR/xcodebuild-archive.log" || true
  [[ -d "$archive/Products/Applications/Stow.app" ]] || die "archive has no Stow.app"
  ditto "$archive/Products/Applications/Stow.app" "$APP"
  [[ -d "$archive/dSYMs" ]] && ditto -c -k --keepParent "$archive/dSYMs" "$OUT_DIR/Stow-$VERSION-dSYMs.zip"
fi

# --- Sign, inside out ---------------------------------------------------------------------------
sign() { # <path> [extra codesign args…]
  local path=$1; shift
  if (( signed )); then
    codesign --force --sign "$SIGN_IDENTITY" ${keychain_args[@]+"${keychain_args[@]}"} --options runtime --timestamp "$@" "$path"
  else
    codesign --force --sign - --options runtime --timestamp=none "$@" "$path"
  fi
}
# Entitlements Xcode gave a bundle (ENABLE_APP_SANDBOX and friends), minus debug-only keys.
entitlements_of() { # <bundle> <out.plist>
  codesign -d --entitlements - --xml "$1" 2>/dev/null > "$2" || true
  [[ -s $2 ]] || die "$1 has no entitlements; refusing to sign it without its sandbox"
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$2" >/dev/null 2>&1 || true
}

log "Signing nested code"
ent_dir=$(mktemp -d); trap 'rm -rf "$ent_dir"' EXIT
# 1. 7zz, a helper executable in each StowEngine.xpc copy: sandboxed, inherits the engine's sandbox.
while IFS= read -r -d '' sz; do
  sign "$sz" --identifier org.7-zip.7zz --entitlements Engine/7zz.entitlements
done < <(find "$APP" -type f -name 7zz -print0)
# 2. Loose dylibs and frameworks, if any package ever embeds one.
while IFS= read -r -d '' lib; do sign "$lib"; done < <(find "$APP" -type f -name '*.dylib' -print0)
# 3. Bundles, deepest first (QuickLook's private StowEngine.xpc before the appex, the app last).
i=0
while IFS= read -r bundle; do
  i=$((i + 1))
  case $bundle in
    *.framework) sign "$bundle" ;;
    *) entitlements_of "$bundle" "$ent_dir/$i.plist"; sign "$bundle" --entitlements "$ent_dir/$i.plist" ;;
  esac
  echo "    signed ${bundle#"$OUT_DIR"/}"
done < <(find "$APP/Contents" -type d \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' -o -name '*.app' \) \
           | awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-)
entitlements_of "$APP" "$ent_dir/app.plist"
sign "$APP" --entitlements "$ent_dir/app.plist"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Notarize --------------------------------------------------------------------------------
notarize_file() { # <file> <label>
  local file=$1 label=$2 json="$OUT_DIR/notary-$2.json" id status
  log "Notarizing $label (waits for Apple)"
  xcrun notarytool submit "$file" "${notary_args[@]}" --wait --timeout 2h --output-format json > "$json" \
    || { cat "$json" >&2 || true; }
  id=$(plutil -extract id raw -o - "$json" 2>/dev/null || true)
  status=$(plutil -extract status raw -o - "$json" 2>/dev/null || true)
  if [[ -n $id ]]; then
    xcrun notarytool log "$id" "${notary_args[@]}" "$OUT_DIR/notary-$label-log.json" >/dev/null 2>&1 || true
  fi
  [[ $status == Accepted ]] || die "notarization of $label: status '${status:-unknown}' (id ${id:-none}); see notary-$label-log.json"
  log "$label: Accepted ($id)"
}

if (( notarize )); then
  # The app first, so its ticket can be stapled inside the DMG and Stow opens offline after a copy
  # (and from the Homebrew cask, which copies the app out of the DMG).
  ditto -c -k --keepParent "$APP" "$OUT_DIR/Stow-notarize.zip"
  notarize_file "$OUT_DIR/Stow-notarize.zip" app
  rm -f "$OUT_DIR/Stow-notarize.zip"
  xcrun stapler staple "$APP"
fi

# --- DMG ---------------------------------------------------------------------------------------
log "Building $(basename "$DMG")"
stage=$(mktemp -d)
ditto "$APP" "$stage/Stow.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Stow" -srcfolder "$stage" -fs APFS -format UDZO -ov "$DMG"
rm -rf "$stage"
if (( signed )); then
  codesign --force --sign "$SIGN_IDENTITY" ${keychain_args[@]+"${keychain_args[@]}"} --timestamp "$DMG"
fi
if (( notarize )); then
  notarize_file "$DMG" dmg
  xcrun stapler staple "$DMG"
fi

# --- Verify ------------------------------------------------------------------------------------
mode=adhoc; (( signed )) && mode=signed; (( notarize )) && mode=notarized
TEAM_ID="$TEAM_ID" scripts/verify-app-bundle.sh --mode "$mode" "$APP" "$DMG"

(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
{
  echo "version=$VERSION"
  echo "build=$BUILD_NUMBER"
  echo "mode=$mode"
  echo "dmg=$DMG"
} > "$OUT_DIR/package.env"
log "Done: $DMG ($mode)"
