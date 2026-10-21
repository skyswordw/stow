# Homebrew cask

`stow.rb` is a template for the Stow cask. Nothing here publishes anything.

## Per release

1. Publish a GitHub release `v<version>` with `Stow-<version>.dmg` attached (signed and notarized: #32, #34).
2. The **Homebrew cask** workflow runs on `release: published` (or by hand with *Run workflow* and the
   version). It renders the cask with the DMG's SHA-256, runs `brew style` and `brew audit --online`
   in a scratch tap, installs and uninstalls it once, and uploads `stow.rb` as an artifact and in the
   run summary.
3. Commit that file to the tap.

Locally: `scripts/render-cask.sh 1.0.0` (downloads the DMG) or
`scripts/render-cask.sh 1.0.0 --dmg path/to/Stow-1.0.0.dmg`; output goes to `build/homebrew/stow.rb`.

## Where it is published (to decide)

- **Own tap** (`skyswordw/homebrew-tap`, `Casks/stow.rb`): `brew install --cask skyswordw/tap/stow`.
  Works from the first release; no review, no notability bar.
- **homebrew/homebrew-cask**: needs a signed and notarized app, and a notable enough repository
  (self-submitted casks need roughly 75+ stars, or 30+ forks/watchers). The token `stow` collides with
  the GNU Stow formula in homebrew/core, which `brew audit --new --strict` rejects; the Cask Cookbook
  asks for a vendor prefix (`skyswordw-stow`) or an `-app` suffix (`stow-app`). Stow is also still a
  working name.

## Assumptions the template makes

- Release tag `v<version>` and asset `Stow-<version>.dmg` with `Stow.app` at the top level
  (`render-cask.sh` fails if the template's URL drifts from that).
- macOS 26 (Tahoe) or later (`depends_on macos: :tahoe` — Homebrew reads a bare symbol as a minimum); bundle ID `app.stow.Stow` and its Engine / Quick Look / Finder extension
  containers for `zap`.
- `auto_updates true` stays commented out until Sparkle ships (#35).
