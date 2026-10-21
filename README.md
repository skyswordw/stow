# Stow

A native macOS archive tool: browse, preview and extract 30+ formats, and pack files that work on the
recipient's computer. *Stow* is a working name.

**Status:** prototype. Opening and extracting real archives works through a sandboxed 7-Zip engine;
"Try the Sample", the Recent list and the design-review scenes still use fictional sample data.
Finder integration (Quick Look, context menu, Services, file types) is real; packing and the other
Next Steps are simulated.

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

After each build, `scripts/register-extensions.sh` registers that build's Quick Look and Finder
extensions (ad-hoc signatures change every build, and several worktrees may hold a Stow.app).

`Stow.xcodeproj` is generated — edit `project.yml`, not the project.

## Design review screenshots

```bash
scripts/snapshot.sh <scene> [light|dark]   # → snapshots/
```

Scenes: `welcome`, `grid`, `list`, `fonts`, `search`, `activity`, `pack`, `tray`, `quicklook`
(`-StowPreview encrypted|slow`), `associations`, `integration` (`-StowRepair YES`).

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

## Finder, Quick Look and Services

- **Quick Look** (`QuickLook/`, view in `Preview/`): Space on any type Stow registers shows the file
  tree, sizes, format, encryption and a one-line Checkup, with *Open in Stow*. List only, 3 s
  timeout, fallbacks for encrypted names and slow listings. Quick Look extensions may not launch
  processes and can't reach the app's XPC services, so the extension carries its own copy of
  `StowEngine.xpc` and sends it the file as a handle, exactly like the app does.
- **Finder menu** (`FinderSync/`): Extract Here, Extract To…, Open in Stow, Compress with Stow…;
  external drives are opt-in.
- **Services**: Stow: Extract Here, Extract To…, Quick Compress, Compress…, and Send to Stow.
- **File types**: Settings › File Types sets Stow as the default per type, remembers the previous
  app and switches back. macOS confirms each change in its own dialog.
- **Login item & Dock**: `SMAppService`; the Dock icon can hide when the last window closes.

### The Finder → Stow hand-off

The Finder extension never opens files. It posts the selection (action + paths) under a random
128-bit token and opens `stow://handoff/<token>`; Stow takes the request once and refuses unknown,
reused or older-than-60-s tokens and any other URL shape. No path ever travels in a URL, so a web
page that opens `stow://…` can't make Stow do anything. The mailbox is a private named pasteboard:
an App Group container would be the textbook choice, but macOS refuses group containers to builds
without a Team ID (ad-hoc builds get `EPERM`), while named pasteboards work between any sandboxed
processes and `releaseGlobally()` makes them single-use. A Team-signed release could move the
mailbox into a group container without touching the token rules (`HandoffMailbox`).

### Sandbox and Finder actions: why Stow asks once per folder

Extract Here and Quick Compress write next to the original, which a sandboxed app can't do by
default. Options considered:

| Approach | Verdict |
| --- | --- |
| Full Disk Access / no sandbox (what ArcZip does) | Rejected: far broader than any action needs |
| Access granted through the extension | Not available: the Finder Sync extension is sandboxed too and receives paths, not file access it could hand on |
| Temporary-exception entitlements for home or `/` | Rejected: the same as no sandbox for people's files |
| **One-time folder grant** | **Chosen** |

The first time an action needs a folder Stow can't write in, Stow shows an Open panel already
pointing at that folder and says why ("Choose Allow to let Stow extract … here — and next time,
anything in this folder"). Allow grants that folder and everything inside, kept as a
security-scoped bookmark; picking a different folder uses it once and remembers nothing.
Settings › Integration lists every grant with Remove. Services and opened documents already
give Stow read access to the files themselves; the grant is only ever about writing next to them
(and reading files handed over by the Finder extension).

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
| `App/Integration` | Finder/Services actions, folder grants, File Types, login item, Dock, repair |
| `Preview`, `QuickLook` | Quick Look extension and its view (also compiled into the app for review) |
| `FinderSync`, `Handoff` | Finder context-menu extension and the one-time token hand-off |
| `App/Welcome` | Empty state / drop target |
| `website/` | Marketing site |
| `.claude/skills` | Project-level agent skills (design engineering, Apple design, Swift) — MIT, © Emil Kowalski |

## License

Stow is free software, licensed under the [GNU General Public License v3.0](LICENSE). Bundled
third-party components keep their own licenses — see `THIRD_PARTY_NOTICES.md` (7-Zip is LGPL and
ships as a separate, unmodified executable).
