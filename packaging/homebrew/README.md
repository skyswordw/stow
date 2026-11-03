# Homebrew cask

`stow.rb` is a template for the Stow cask. The **Homebrew cask** workflow fills version and checksum
from a published release and pushes the rendered file to
[Beastry/homebrew-tap](https://github.com/Beastry/homebrew-tap).

## Per release

1. Publish a GitHub release `v<version>` with `Stow-<version>.dmg` attached (signed and notarized:
   #32, #34). Drafts do **not** run this path — publishing is the human gate.
2. The **Homebrew cask** workflow runs on `release: published` (or by hand with *Run workflow* and
   the version). It renders the cask with the DMG's SHA-256, runs `brew style` and
   `brew audit --online` in a scratch tap, installs and uninstalls it once, uploads `stow.rb` as an
   artifact, and commits `Casks/stow.rb` to `Beastry/homebrew-tap` (needs `HOMEBREW_TAP_TOKEN`; see
   [RELEASING.md](../../RELEASING.md)).
3. Users install with:

   ```sh
   brew install --cask Beastry/tap/stow
   ```

Locally: `scripts/render-cask.sh 1.0.0` (downloads the DMG) or
`scripts/render-cask.sh 1.0.0 --dmg path/to/Stow-1.0.0.dmg`; output goes to `build/homebrew/stow.rb`.

The default repository is `Beastry/stow`. `--repo owner/name` changes both the download URL
and the rendered cask's URL and GitHub Pages homepage. The template's `@REPOSITORY@` and
`@HOMEPAGE@` placeholders are filled with the version and checksum; none may remain in the output.

## Where it is published

- **Own tap** (`Beastry/homebrew-tap`, `Casks/stow.rb`): `brew install --cask Beastry/tap/stow`.
  Updated automatically on each published Stow release.
- **homebrew/homebrew-cask** (optional later): needs a signed and notarized app, and a notable enough
  repository (self-submitted casks need roughly 75+ stars, or 30+ forks/watchers). The token `stow`
  collides with the GNU Stow formula in homebrew/core, which `brew audit --new --strict` rejects;
  the Cask Cookbook asks for a vendor prefix (`beastry-stow`) or an `-app` suffix (`stow-app`).

## Assumptions the template makes

- Release tag `v<version>` and asset `Stow-<version>.dmg` with `Stow.app` at the top level
  (`render-cask.sh` fails if the template's URL drifts from that).
- macOS 26 (Tahoe) or later (`depends_on macos: :tahoe` — Homebrew reads a bare symbol as a
  minimum); bundle ID `app.stow.Stow` and its Engine / Quick Look / Finder extension containers for
  `zap`.
- `auto_updates true` stays commented out until Sparkle ships (#35).
