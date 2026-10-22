# Releasing Stow

How a signed, notarized `Stow-<version>.dmg` is built (#32, #34). Nothing here publishes anything:
the **Release** workflow stops at a **draft** GitHub release, and a person publishes it. Publishing
is what triggers the Homebrew cask workflow (`.github/workflows/homebrew-cask.yml`).

| Piece | What it does |
| --- | --- |
| `scripts/package.sh` | Archives Release (Universal 2), re-signs every piece inside-out with Developer ID — each `7zz` (`Engine/7zz.entitlements`), both `StowEngine.xpc` copies, the Quick Look and Finder extensions, then the app — with hardened runtime, a secure timestamp and the App Sandbox entitlements Xcode gave each target. Notarizes and staples the app, builds the DMG (Stow.app + /Applications link), signs, notarizes and staples the DMG, then verifies. Output: `build/release/`. |
| `scripts/verify-app-bundle.sh` | `--mode adhoc\|signed\|notarized`: layout, Universal 2, sandbox on every executable, no `get-task-allow`, `codesign --verify --deep --strict`; signed adds Developer ID authority, Team ID, runtime and timestamp on every piece; notarized adds `stapler validate` and `spctl -a -vvv` for app and DMG. |
| `scripts/generate-appcast.sh` | Sparkle appcast hook. Skips (exit 0) until Sparkle lands (#35). |
| `.github/workflows/release.yml` | Runs the above on the `xcode-27` runner with a temporary keychain. |
| `ci.yml` → `universal` | On every PR: an ad-hoc dry run of `package.sh` on the Release build (no secrets). |

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

**Notarization — not created yet** (until they exist, CI builds are signed but not notarized, and
no draft release is made):

| Secret | Content |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API key ID (10 characters) |
| `ASC_API_ISSUER_ID` | Issuer ID (UUID shown above the keys list) |
| `ASC_API_KEY_P8_BASE64` | The downloaded `AuthKey_<KEYID>.p8`, base64 |

**Later (#35, Sparkle):** `SPARKLE_ED_PRIVATE_KEY` — Stow's **own** EdDSA key, generated with
Sparkle's `generate_keys` for Stow. Never reuse another app's (e.g. MijiaBar's) Sparkle key.

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
2. Actions → **Release** → *Run workflow* on `main`: version (empty = `project.yml`), build number
   (empty = run number), *draft-release* on. Pushing a tag `v<version>` does the same.
3. The run uploads the DMG, its `.sha256`, dSYMs and notary logs as an artifact. If it is notarized
   (and *draft-release* is on, or a tag was pushed) it also creates or updates the **draft** release
   `v<version>`. A draft doesn't create the tag; publishing it does. The workflow refuses to touch
   a release that is already published.
4. Download the DMG on a clean Mac, open it, drag Stow to Applications and launch: Gatekeeper must
   not warn (ROADMAP tests #17). Then publish the draft by hand.

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
```

`SIGN_IDENTITY` defaults to the first *Developer ID Application* identity in the keychain;
`SIGN_IDENTITY=-` makes an ad-hoc dry run. Without `NOTARY_PROFILE` (or `ASC_API_KEY_*`) the build
is signed but not notarized; `REQUIRE_NOTARIZATION=1` turns that into an error.

## If notarization fails

`build/release/notary-<app|dmg>-log.json` (also in the workflow artifact) lists every rejected
file. Typical causes: a binary without hardened runtime or timestamp, `get-task-allow`, or an
unsigned nested executable — `verify-app-bundle.sh --mode signed` catches these before upload.
