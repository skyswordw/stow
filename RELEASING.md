# Releasing Stow

How a signed, notarized `Stow-<version>.dmg` and its Sparkle `appcast.xml` are built (#32, #34,
#35). Nothing here publishes anything:
the **Release** workflow stops at a **draft** GitHub release, and a person publishes it. Publishing
is what triggers the Homebrew cask workflow (`.github/workflows/homebrew-cask.yml`).

| Piece | What it does |
| --- | --- |
| `scripts/package.sh` | Archives Release (Universal 2), re-signs every piece inside-out with Developer ID — each `7zz` (`Engine/7zz.entitlements`), Sparkle's helpers (`Installer.xpc`, `Downloader.xpc` with its own entitlements, `Autoupdate`, `Updater.app`) then `Sparkle.framework`, both `StowEngine.xpc` copies, the Quick Look and Finder extensions, then the app — with hardened runtime, a secure timestamp and the App Sandbox entitlements Xcode gave each target. Notarizes and staples the app, builds the DMG (Stow.app + /Applications link), signs, notarizes and staples the DMG, then verifies. Output: `build/release/`. |
| `scripts/verify-app-bundle.sh` | `--mode adhoc\|signed\|notarized`: layout (Sparkle's helpers included), Universal 2, sandbox on every executable we build (Sparkle's helpers run outside it by design), the Sparkle keys and mach-lookup exceptions, no `get-task-allow`, `codesign --verify --deep --strict`; signed adds Developer ID authority, Team ID, runtime and timestamp on every piece; notarized adds `stapler validate` and `spctl -a -vvv` for app and DMG. |
| `scripts/generate-appcast.sh` | Signs the notarized DMG with Stow's EdDSA key (Sparkle's `sign_update`, key on stdin only), checks the signature against the app's `SUPublicEDKey` (CryptoKit, `scripts/sparkle-ed25519.swift`), refuses a build number that isn't above the published appcast's, and writes `appcast.xml` (version, build, length, `edSignature`, `minimumSystemVersion`, release page link, optional Markdown notes from `website/release-notes/v<version>.md`). Skips without `SPARKLE_ED_PRIVATE_KEY`. |
| `scripts/fetch-sparkle.sh` | Finds Sparkle's tools for the pinned version (Xcode's resolved package, else the checksum-verified download). |
| `.github/workflows/release.yml` | Runs the above on the `xcode-27` runner with a temporary keychain. |
| `ci.yml` → `universal` | On every PR: an ad-hoc dry run of `package.sh` on the Release build, then of `generate-appcast.sh` with a throwaway key (no secrets). |

## GitHub secrets

Set on `skyswordw/stow` → Settings → Secrets and variables → Actions. Values never go in the repo,
in an issue, or in chat.

**Signing — already provisioned:**

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate + private key, exported as `.p12`, base64 |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting that `.p12` |
| `DEVELOPER_ID_IDENTITY` | `Developer ID Application: Xincao Xu (YNQ2233752)` |
| `APPLE_TEAM_ID` | `YNQ2233752` |
| `KEYCHAIN_PASSWORD` | Any random string; locks the throwaway CI keychain (a random one is used if empty) |

The `.p12` holds only the leaf certificate. The workflow imports Apple's *Developer ID Certification
Authority* (G2) intermediate from apple.com (SHA-256 pinned) when the runner doesn't have it.

> **The certificate expires on 2027-02-02.** Before then, create a new Developer ID Application
> certificate on Mac mini A (Xcode → Settings → Accounts → Manage Certificates, or
> developer.apple.com → Certificates), export it as below, and replace `DEVELOPER_ID_P12_BASE64`
> and `DEVELOPER_ID_P12_PASSWORD` (and `DEVELOPER_ID_IDENTITY` if the name changes). Apps signed
> and notarized before expiry keep launching; only new builds need the new certificate.

**Notarization — provisioned:**

| Secret | Content |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API key ID (10 characters) |
| `ASC_API_ISSUER_ID` | Issuer ID (UUID shown above the keys list) |
| `ASC_API_KEY_P8_BASE64` | The downloaded `AuthKey_<KEYID>.p8`, base64 |

**Updates (#35, Sparkle) — provisioned:**

| Secret | Content |
| --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | Stow's **own** Ed25519 private key in Sparkle's exported format (base64 of the 32-byte seed, what `generate_keys -x` writes) |

Its public half is `SUPublicEDKey` in `project.yml` (and the committed `App/Info.plist`):
`w/8KK7rFz8EqDr/3GTf/oncwRrzfnsh1Jucno8bdKMo=`. The key was generated for Stow alone (never reuse
another app's, e.g. MijiaBar's) and piped straight into the secret; **no other copy exists**. A
GitHub secret can't be read back, so it can't be exported later either. Without the secret no
appcast is made; the release workflow fails if the secret doesn't match `SUPublicEDKey`.

Every installed copy trusts only that public key. Until the first public release ships, replacing
the pair costs nothing: generate a new one (`generate_keys` on a Mac, then `generate_keys -x` to
export it, or any Ed25519 tool producing the same format), `gh secret set SPARKLE_ED_PRIVATE_KEY`
from stdin, and change `SUPublicEDKey`. **After** a release is public, installed copies keep
trusting this key, so losing it makes updating them hard (they reject updates signed with any other
key); if you rotate it before then, keep an offline backup of the new one.

### Exporting the `.p12` (Mac mini A)

1. Keychain Access → *login* keychain → *My Certificates* → expand
   **Developer ID Application: Xincao Xu (YNQ2233752)** and check the private key is under it.
2. Select the certificate (not the key alone) → File → Export Items… → format *Personal Information
   Exchange (.p12)* → save to a temporary folder outside any repository → set a **new** password.
3. Upload, then delete the file:

   ```sh
   base64 -i /tmp/stow-devid.p12 | gh secret set DEVELOPER_ID_P12_BASE64 -R skyswordw/stow
   gh secret set DEVELOPER_ID_P12_PASSWORD -R skyswordw/stow        # prompts; paste the password
   gh secret set DEVELOPER_ID_IDENTITY -R skyswordw/stow -b 'Developer ID Application: Xincao Xu (YNQ2233752)'
   gh secret set APPLE_TEAM_ID -R skyswordw/stow -b YNQ2233752
   openssl rand -hex 24 | gh secret set KEYCHAIN_PASSWORD -R skyswordw/stow
   rm -P /tmp/stow-devid.p12
   ```

### Creating the App Store Connect API key

1. [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   (Account Holder or Admin; request access once if the tab asks).
2. *Team Keys* → **+** → name it `Stow notarization` → access **Developer** (enough for
   `notarytool`) → Generate.
3. Note the **Key ID** and the **Issuer ID**, then **Download API Key** — `AuthKey_<KEYID>.p8` can
   only be downloaded once.
4. Upload, then delete the file:

   ```sh
   gh secret set ASC_API_KEY_ID -R skyswordw/stow -b '<KEYID>'
   gh secret set ASC_API_ISSUER_ID -R skyswordw/stow -b '<issuer uuid>'
   base64 -i ~/Downloads/AuthKey_<KEYID>.p8 | gh secret set ASC_API_KEY_P8_BASE64 -R skyswordw/stow
   rm -P ~/Downloads/AuthKey_<KEYID>.p8
   ```

Check with `gh secret list -R skyswordw/stow` (names only; values can't be read back).

## Making a release build

1. Bump `MARKETING_VERSION` in `project.yml` in a PR (or pass the version to the workflow).
   Optionally add Markdown release notes as `website/release-notes/v<version>.md`; Sparkle's update
   window shows them (the GitHub release page is always linked as the full notes).
2. Actions → **Release** → *Run workflow* on `main`: version (empty = `project.yml`), build number
   (empty = the commit count of `main`), *draft-release* on. Pushing a tag `v<version>` does the same.
3. The run uploads the DMG, its `.sha256`, `appcast.xml`, dSYMs and notary logs as an artifact. If it
   is notarized (and *draft-release* is on, or a tag was pushed) it also creates or updates the
   **draft** release `v<version>` with the DMG, `.sha256` and `appcast.xml`. A draft doesn't create
   the tag; publishing it does. The workflow refuses to touch a release that is already published.
4. Download the DMG on a clean Mac, open it, drag Stow to Applications and launch: Gatekeeper must
   not warn (ROADMAP tests #17). Then publish the draft by hand.

### Sparkle updates

- **Feed:** `SUFeedURL` = `https://github.com/skyswordw/stow/releases/latest/download/appcast.xml`.
  GitHub resolves `latest` to the newest *published*, non-pre-release release, so a draft (or a
  pre-release) is never offered to anyone, and publishing the draft is the one switch that ships
  both the download and the update. No Pages deploy or commit per release; each release carries a
  one-item appcast, which is all Sparkle needs (no delta updates). Don't mark a release as
  pre-release if it should update people, and don't delete `appcast.xml` from the latest release.
- **Build numbers:** Sparkle compares `CFBundleVersion`. The workflow and `package.sh` default it to
  the commit count, which only grows on `main`; `generate-appcast.sh` fails if it isn't above the
  published appcast's. Re-running a release for the same commit gives the same number: fine for
  re-building a draft, but a new release needs a new commit (or a higher *build-number*).
- **In the app:** Sparkle 2.10 via Swift Package Manager. Sandboxed setup per Sparkle's guide:
  `SUEnableInstallerLauncherService` + the `-spks`/`-spki` mach-lookup exceptions in
  `App/Stow.entitlements`; `SUEnableDownloaderService` so Stow itself has no network entitlement.
  Only Developer ID release builds start the updater (`App/Updates/UpdatePolicy.swift`); Debug,
  ad-hoc, tests and `-Stow…` demo scenes never do. Checks run daily (`SUEnableAutomaticChecks`), and
  installs ask first unless people turn on automatic installs in Settings › General › Updates.
- **The first release with Sparkle** is the first one that can update itself; whatever people
  install before it has to be replaced by hand once.

What each credential state produces:

| Secrets present | Result |
| --- | --- |
| none, or a pull request | ad-hoc `Stow-<v>-unsigned.dmg` (dry run) |
| signing only | Developer ID signed `Stow-<v>.dmg`, **not notarized**, no draft release |
| signing + notarization | signed, notarized, stapled `Stow-<v>.dmg` + draft release |

## Locally (Mac mini A)

```sh
zsh scripts/fetch-7zip.sh
# Once: a notarytool profile for Stow (Apple ID + app-specific password, or the API key above)
xcrun notarytool store-credentials Stow-notary --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <issuer>
VERSION=0.1.0 TEAM_ID=YNQ2233752 NOTARY_PROFILE=Stow-notary scripts/package.sh
# Appcast, with the key in a file outside any repository (never commit it):
SPARKLE_ED_KEY_FILE=~/stow-private/sparkle_ed25519.key scripts/generate-appcast.sh build/release/Stow-0.1.0.dmg
```

`SIGN_IDENTITY` defaults to the first *Developer ID Application* identity in the keychain;
`SIGN_IDENTITY=-` makes an ad-hoc dry run. Without `NOTARY_PROFILE` (or `ASC_API_KEY_*`) the build
is signed but not notarized; `REQUIRE_NOTARIZATION=1` turns that into an error.

## If notarization fails

`build/release/notary-<app|dmg>-log.json` (also in the workflow artifact) lists every rejected
file. Typical causes: a binary without hardened runtime or timestamp, `get-task-allow`, or an
unsigned nested executable — `verify-app-bundle.sh --mode signed` catches these before upload.
