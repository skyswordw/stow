# Stow

A native macOS archive tool: browse, preview and extract 30+ formats, and pack files that work on the
recipient's computer. *Stow* is a working name.

**Website:** https://skyswordw.github.io/stow/ · **Roadmap:** [ROADMAP.md](ROADMAP.md) · **Feature parity:** [PARITY.md](PARITY.md)

**Status:** prototype. Real archives open, browse, preview and extract through a sandboxed 7-Zip
engine; packing creates real archives; the install Next Steps (apps, fonts, installer packages) and
Finder integration (Quick Look, context menu, Services, file types) are real. "Try the Sample", the
Recent list and most design-review scenes still use fictional sample data.

- 🧪 Staged ZIP / 7Z / TAR editing: add, delete, rename, replace, undo/redo, and atomic Save (pending macOS verification).
- 🧪 Read-only archives explain the limitation and offer Extract and Repack as ZIP or 7Z (pending macOS verification).

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

Scenes: `editing`, `readonly`, `welcome`, `grid`, `list`, `fonts`, `search`, `activity`, `pack`, `tray`, `quicklook`
(`-StowPreview encrypted|slow`), `associations`, `integration` (`-StowRepair YES`), `batch`,
`conflict`, `conflict-folder`, `signature-warning`, `replace-app`, `extract-options`, `install-options`,
`packing`, `packed`, `packrun`. Browsing scenes take `-StowOpen <path>` plus the flags listed in
`App/Browser/BrowseDemo.swift`.
`open -StowOpen <path> -StowRun extractAll|install|fonts|installer` runs a real step
(`-StowInstallFolder`/`-StowExtractFolder` point it at scratch folders); with a locked screen,
`-StowSnapshotMode view` draws the view tree instead of the composited window.

Test fixtures are rebuilt with `scripts/make-fixtures.sh` (disk images) and
`scripts/make-browse-fixtures.sh [--big]` (browsing, 100k entries).

## Archive engine

All archive parsing happens in `StowEngine.xpc`, a sandboxed XPC service that runs the official
`7zz` binary (LGPL — see `THIRD_PARTY_NOTICES.md`) as a child process inheriting its sandbox.

- **Contract** (`Shared/EngineContract.swift`): versioned; requests and replies are JSON. No paths
  cross the boundary — Stow sends the archive as an open, read-only `FileHandle` (7zz reads it as
  fd 3), so the engine needs no access to people's files at all.
- **Listing:** `7zz l -slt`, parsed into `ArchiveListing`, mapped into `Archive` with names shown
  where they would actually be written, plus listing-time Checkup findings.
- **Embedded ZIP compatibility:** after an unrecognized-input failure, listing, extraction and
  verification retry with explicit ZIP scanning bounded by the prepared file size (`-tzip:s<size>b`).
  Recognized damaged archives and password errors are not retried. Checkup retains prefix/tail
  warnings; ZIPs with surrounding data are read-only so Save cannot discard unrelated bytes (#207).
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

**First run:** A skippable Welcome to Stow checklist introduces archives, file types, the Finder
extension and Tray (⌥⌘T). Skip or Get Started finishes it; Help › Welcome to Stow reopens it.
Resetting preferences keeps first-run completion remembered.

Stow has a Settings window (⌘,) with General, Extraction, Installing, Packing, Next Steps, Previews,
Passwords, File Types, Integration, Advanced and Licenses panes. Glance and Tray controls live
in General. The host lives in `App/Settings` and reuses the extraction and
installing forms in `App/Options`. Advanced can clean preview caches and reset preferences.

Settings keys (UserDefaults; the resettable list and defaults are in `SettingsKeys`):

| Key | Default | Values |
| --- | --- | --- |
| `extract.allFolder` | `automatic` | `automatic`, `always` |
| `extract.afterExtractAll` / `install.afterInstall` | `keep` | `keep`, `trash`, `ask` |
| `extract.closeWindowAfter` | `false` | |
| `extract.folderConflict` | `ask` | `ask`, `merge`, `keepBoth` |
| `extract.fileConflict` | `ask` | `ask`, `replace`, `keepBoth`, `skip` |
| `extract.skipSystemFiles` | `true` | |
| `install.removeQuarantine` | `false` | |
| `general.appearance` | `system` | `system`, `light`, `dark` |
| `browse.defaultView` | `grid` | `grid`, `list`, `columns` |
| `browse.hoverPreviews` | `true` | |
| `password.showByDefault` | `false` | |
| `glance.colourfulControls` | `false` | Red Close, yellow Pin and green Open in Full Window controls |
| `PackAudience` | `windows` | `windows`, `mac`, `linux`, `web` |
| `PackLevel.<audience>` | `5` (Balanced) | One compression level per audience |
| `PackVolumeSize` | `0` | `0`, `100000000`, `700000000`, `4000000000` bytes |
| `PackVerify` / `PackCPUCores` | `false` / `0` | 0 cores means all |
| `FinderMenuOnExternalDrives` / `HideDockIconWithoutWindows` | `false` | |
| `SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` | `true` / `false` | Sparkle's own keys (General › Updates); reset falls back to Info.plist |

**Updates:** Stow updates itself with [Sparkle](https://sparkle-project.org) 2 (Stow › Check for
Updates…, and General › Updates in Settings). The feed is the `appcast.xml` on the latest
*published* GitHub release, and each update DMG is EdDSA-signed with Stow's own key (public half
`SUPublicEDKey` in `project.yml`) as well as Developer ID–signed and notarized. Stow stays
sandboxed and without network access: Sparkle's downloader service fetches the feed and the update,
and its installer service replaces the app; a restart into an update waits until extracting,
packing or opening finishes (`App/Updates`). Debug, ad-hoc, test and `-Stow…` demo runs never
start Sparkle, so they never touch the network or show an update prompt.

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
| `App/Updates` | Sparkle updater, when it may run (`UpdatePolicy`), installs that wait for running tasks |
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
| `website/` | Marketing site, deployed with the rendered docs to GitHub Pages (`scripts/build-site.py`, `.github/workflows/pages.yml`) |
| `ROADMAP.md` | Follow-up plan: remaining features, design polish, release work, and tests not yet run |
| `RELEASING.md` | Signed, notarized release builds and the Sparkle appcast: secrets, `scripts/package.sh`, `scripts/generate-appcast.sh`, the Release workflow |
| `.claude/skills` | Project-level agent skills (design engineering, Apple design, Swift) — MIT, © Emil Kowalski |

## License

Stow is free software, licensed under the [GNU General Public License v3.0](LICENSE). Bundled
third-party components keep their own licenses — see `THIRD_PARTY_NOTICES.md` (7-Zip is LGPL and
ships as a separate, unmodified executable).
