# Stow

A native macOS archive tool: browse, preview and extract 30+ formats, and pack files that work on the
recipient's computer. *Stow* is a working name.

**Status:** prototype. Opening and extracting real archives works through a sandboxed 7-Zip engine;
"Try the Sample", the Recent list and the design-review scenes still use fictional sample data.
Packing, Quick Look and the other Next Steps are simulated.

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

Scenes: `welcome`, `grid`, `list`, `fonts`, `search`, `activity`, `pack`, `tray`.

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

## Layout

| Path | What |
| --- | --- |
| `DESIGN.md` | Design language: principles, vocabulary, color, type, motion values |
| `PARITY.md` | Feature-by-feature comparison with ArcZip 1.1.1 and what is left to build |
| `App/Model` | Value types: archive listing, Checkup findings, Next Steps, packing rules |
| `App/Engine` | Engine client (XPC), staged extraction, destination picker |
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
