# Stow

A native macOS archive tool: browse, preview and extract 30+ formats, and pack files that work on the
recipient's computer. *Stow* is a working name.

**Status:** prototype. Opening and extracting real archives works through a sandboxed 7-Zip engine,
and so do the install Next Steps (apps, fonts, installer packages). "Try the Sample", the Recent list
and most design-review scenes still use fictional sample data. Packing and Quick Look are simulated.

## Requirements

- macOS 26 or later (uses Liquid Glass APIs directly — no fallbacks)
- Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
scripts/fetch-7zip.sh   # pinned 7-Zip 26.04, checksum-verified, into Vendor/ (gitignored)
xcodegen generate
xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build build
open build/Build/Products/Debug/Stow.app
```

Tests (Swift Testing): `xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build test`

`Stow.xcodeproj` is generated — edit `project.yml`, not the project.

## Design review screenshots

```bash
scripts/snapshot.sh <scene> [light|dark]   # → snapshots/
```

Scenes: `welcome`, `grid`, `list`, `fonts`, `search`, `activity`, `pack`, `tray`, `batch`,
`conflict`, `conflict-folder`, `signature-warning`, `replace-app`, `extract-options`, `install-options`.
`open -StowOpen <path> -StowRun extractAll|install|fonts|installer` runs a real step
(`-StowInstallFolder`/`-StowExtractFolder` point it at scratch folders); with a locked screen,
`-StowSnapshotMode view` draws the view tree instead of the composited window.

Disk-image test fixtures (`Tests/Fixtures`) are rebuilt with `scripts/make-fixtures.sh`.

## Archive engine

All archive parsing happens in `StowEngine.xpc`, a sandboxed XPC service that runs the official
`7zz` binary (LGPL — see `THIRD_PARTY_NOTICES.md`) as a child process inheriting its sandbox.

- **Contract** (`Shared/EngineContract.swift`): versioned; requests and replies are JSON. No paths
  cross the boundary — Stow sends the archive as an open, read-only `FileHandle` (7zz reads it as
  fd 3), so the engine needs no access to people's files at all.
- **Listing:** `7zz l -slt`, parsed into `ArchiveListing`, mapped into `Archive` with names shown
  where they would actually be written, plus listing-time Checkup findings.
- **Extraction:** the engine extracts into its *own* container (the only place it can write) with
  `-bsp1` progress, removes links that point outside and device files, then streams the folder to
  Stow over a pipe as an Apple Archive. Stow unpacks it into `.itemReplacementDirectory` staging on
  the destination volume, audits it again, and moves each item into place with a no-clobber
  `rename`. Cancel or failure leaves nothing behind.
- **Containment** (`Shared/PathContainment.swift`): `../`, absolute paths and outside-pointing
  links are kept inside the destination; tests pin the rules to the bundled 7-Zip build.

## Installing from a sandbox

Stow stays sandboxed (user-selected files only) and asks for the narrowest access each install needs:

- **Where installs go.** The first install into /Applications, ~/Library/Fonts or a disk image's
  "drag here" folder opens an Open panel already showing that folder; choosing **Allow** grants that
  one folder, kept as an app-scoped security-scoped bookmark (`App/Install/FolderAccess.swift`,
  entitlement `files.bookmarks.app-scope`). Settings › Installing can forget a grant. No helper
  tool, no Full Disk Access. Accounts that can't write to /Applications are told so.
- **Why staging lives in the destination.** macOS marks files a sandboxed app writes into its own
  container as "created by a sandboxed app" (quarantine flag `0x0080`), and Gatekeeper then refuses
  to run them. Stow therefore stages each extraction in a hidden `.stow-staging-…` folder inside the
  folder you chose (entitlement `files.user-selected.executable`), audits it there and renames items
  into place. Installer packages are unpacked the same way beside the archive.
- **Gatekeeper still runs.** Before installing, Stow checks the app's code signature and
  notarization (`App/Model/CodeSignature.swift`) and asks before installing anything unsigned,
  ad-hoc signed, not notarized, broken or signed with an unknown certificate. Files written into a
  folder you chose aren't quarantined by the sandbox, so — like Archive Utility — Stow carries a
  downloaded archive's quarantine over to what it installs or extracts (through Launch Services'
  quarantine properties; a raw `setxattr` is refused, and the flag is applied after the final move,
  which would drop it). macOS then checks those apps on first launch. Not carrying it over is an
  opt-in setting ("Remove the quarantine flag").
- **Disk images are never mounted.** The engine reads HFS+, APFS and ISO images directly, so a DMG
  is browsed read-only with nothing attached to detach.

Settings keys (UserDefaults; views in `App/Options` for the Settings window):

| Key | Default | Values |
| --- | --- | --- |
| `extract.allFolder` | `automatic` | `automatic`, `always` |
| `extract.afterExtractAll` / `install.afterInstall` | `keep` | `keep`, `trash`, `ask` |
| `extract.closeWindowAfter` | `false` | |
| `extract.folderConflict` | `ask` | `ask`, `merge`, `keepBoth` |
| `extract.fileConflict` | `ask` | `ask`, `replace`, `keepBoth`, `skip` |
| `extract.skipSystemFiles` | `true` | |
| `install.removeQuarantine` | `false` | |

## Layout

| Path | What |
| --- | --- |
| `DESIGN.md` | Design language: principles, vocabulary, color, type, motion values |
| `PARITY.md` | Feature-by-feature comparison with ArcZip 1.1.1 and what is left to build |
| `App/Model` | Value types: archive listing, Checkup findings, Next Steps, packing rules |
| `App/Engine` | Engine client (XPC), staged extraction, conflict-aware placement, destination picker |
| `App/Install` | App/font/package installers, folder grants, prompts, archive aftercare |
| `App/Batch` | Batch extraction queue and its progress stack |
| `App/Options` | Extraction and install settings views |
| `Engine` | `StowEngine.xpc`: sandboxed service that drives `7zz` |
| `Shared` | Compiled into both: XPC contract, 7-Zip driver and parser, path containment |
| `App/Design` | Tokens (space, radius, motion), flow layout, thumbnails |
| `App/Browser` | Main window: sidebar + archive card, grid/list, inspector, Next Steps capsule, hover preview |
| `App/Pack` | The Pack sentence and its compatibility report |
| `App/Tray` | Floating drop shelf |
| `App/Welcome` | Empty state / drop target |
| `website/` | Marketing site |
| `.claude/skills` | Project-level agent skills (design engineering, Apple design, Swift) — MIT, © Emil Kowalski |

## License

Stow is free software, licensed under the [GNU General Public License v3.0](LICENSE). Bundled
third-party components keep their own licenses — see `THIRD_PARTY_NOTICES.md` (7-Zip is LGPL and
ships as a separate, unmodified executable).
