# Feature parity: ArcZip 1.1.1 → Stow

Goal: everything ArcZip does, done at least as well, plus what it doesn't do. Stow is open source
and free — there is no Free/Pro split, so every row below ships to everyone.

**Sources** (2026-10-20): arczip.app pages (features, formats, FAQ, changelog 1.0.0 → 1.1.1) and a
static look at the notarized ArcZip 1.1.1 (222) bundle — its `Info.plist`s, entitlements, extension
points and English UI strings. No code was decompiled or run.

**What the bundle shows about ArcZip's architecture**

| Piece | ArcZip | Stow |
| --- | --- | --- |
| Engine | Bundled official `7zz` + ZIPFoundation | Bundled official `7zz` (pinned, checksum-verified) |
| Parsing process | `ArcZipArchiveService.xpc` (no sandbox entitlements) | `StowEngine.xpc`, **sandboxed**, gets a read-only file handle, never a path |
| Main app | **Not sandboxed**; onboarding asks for Full Disk Access | Sandboxed, user-selected files only. Finder actions ask once per folder (security-scoped bookmark, README › Sandbox and Finder actions); install to /Applications still needs a decision |
| Extensions | Finder Sync (`com.apple.FinderSync`), Quick Look preview (zip/7z/tar only) | Both; Quick Look covers all 34 registered types and runs its own sandboxed engine copy |
| Services menu | 5 Finder services | Same set |
| Updates | Sparkle | Sparkle (open-source appcast on GitHub Releases) |
| Licensing | Ed25519-signed licenses, device seats, trial, Keychain | **None** — open source |
| Languages | English, Simplified Chinese | English, Simplified Chinese at launch (String Catalog) |
| OS | macOS 14+ | macOS 26+ (decision recorded in README) |

Legend: ✅ works · 🎨 designed, UI only (simulated) · 🧪 built, pending verification · ⬜ not started · ➕ Stow goes further

---

## 1. Opening & browsing

| ArcZip | Stow | Notes / how Stow goes further |
| --- | --- | --- |
| 30+ formats: zip zipx 7z rar cbr tar tgz tbz tbz2 txz gz bz2 xz lzma lz dmg iso cab cpio arj lha lzh xar rpm msi pkg jar apk spk exe(SFX) swf .001 | ✅ via 7zz; 34 types registered (Shared/ArchiveTypes.swift), disk images & installers as Alternate | ➕ add zstd/.tar.zst, .deb, .cbz/.cb7, .epub/.docx “Show Package Contents” |
| Icon, list, **column** views | ✅ icons, list, columns (⌘1 ⌘2 ⌘3) | Column view has a preview column with the file's real content |
| Folder navigation, back/forward history, Up One Level, path bar | ✅ | ⌘[ ⌘] ⌘↑ ⌘↓; going back selects where you came from; the path bar spans nested archives |
| Marquee selection, arrow-key navigation, Shift-extend, scroll-into-view | ✅ | Grid: arrows by row/column, ⇧ extends, ⌘/⇧ click, marquee (⇧/⌘ adds), type-to-select, Return opens, Space Quick Look. No animation on keyboard moves |
| Archive search by name **or path**, background full-file index with progress | ✅ | Terms match anywhere in the path (“docs/ handoff”), case/accent/width-insensitive, name matches first. Index builds in the background in chunks; the search field reads “Indexing… 12,000 of 40,000” and results grow while you keep browsing. ⬜ search across nested archives |
| Nested archives opened in place, depth limit, encrypted nested containers | ✅ | Depth limit 8. Passwords through an injectable `PasswordHook` (wire to the password sheet when that branch merges); without it, “needs a password” is reported |
| Archive details / inspector, archive overview | ✅ | ➕ Checkup; inspector shows real previews, several selected stack real thumbnails |
| Show/hide macOS auxiliary items (__MACOSX, .DS_Store) | ✅ View › Show macOS Helper Items (⌘⇧.) | Hidden by default, dimmed when shown, never extracted |
| Mixed / legacy filename encodings (GBK etc.), garbled-name repair | ✅ | ➕ Raw name bytes come from a second listing under a Latin-1 locale, so nothing is lost; each name is read in the encoding that suits it (mixed archives read right), a banner says how, and Read Names As… previews every encoding live. Extraction renames to the shown names |
| Extension ≠ real format detection; ZIP with prepended/appended data; SFX RAR/7Z | partly (7zz) | ⬜ say so in Checkup |
| Lazy browsing of huge archives (browse before index finishes) | ✅ | 100,500 entries open in 2.8 s (Release; 7-Zip's own listing is ~0.9 s of that), browse at once while search indexes (0.18 s). Scrolling 100,000 items: grid median 4.0 ms / p95 6.3 ms of main-thread work per step, list median 5.3 ms / p95 8.2 ms (`-StowScrollBenchmark`). ⬜ stream the listing itself |
| iCloud placeholders: wait for download, cancel | ⬜ | |
| Open Recent menu, clear history | 🎨 recents are sample · ⬜ | |
| Read-only preview of DMG/ISO (mount read-only, verify, skip installer extras like the Applications alias) | ✅ through the engine, no mounting (HFS+, APFS, ISO; zlib/LZFSE/LZMA) | ➕ nothing is attached, so nothing to detach or report busy; opens at the volume with the app selected; background art, volume icon and "drag here" shortcuts hidden and left out; checksums checked in the background; encrypted images explained with an Open in Finder way out; unfinished downloads caught |
| Compressed tarballs; documents that are ZIPs | ✅ | ➕ .tar.gz/.tgz/.tar.xz/.tar.bz2/.tar.zst/.tar.lz… browse as the tar inside (two 7zz piped, nothing written to disk), so the inner-.tar fallback no longer shows for them. ➕ “Show Package Contents” on .docx/.xlsx/.pptx/.epub/.pages opens them as the ZIPs they are |

## 2. Previews

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Space → Quick Look of an entry; arrow keys switch target | ✅ | System Quick Look panel; arrow keys move the browser's selection and the panel follows; several selected page with ← →; ⌘Y too |
| Hover preview after ~1 s (images, PDF, Office, text, Markdown, CSV, code, audio artwork, video frames); toggle in Settings | ✅ previews · 🧪 Settings toggle (pending verification) | Real content read from the archive: images (downsampled), PDF/Office/others (Quick Look), Markdown (rendered), CSV (table), code/logs (monospaced, unwrapped), fonts (the real face), audio (artwork, title, length), video (a frame, length). ➕ 450 ms, then neighbours open instantly |
| Thumbnails in icon view | ✅ | Quick Look thumbnails, only for tiles on screen, batched into one engine trip; files over 48 MB keep their icon |
| Quick Look extension for archives in Finder | ✅ | ➕ all 34 types, not just zip/7z/tar; one-line Checkup, encryption, sizes; 3 s timeout with fallbacks; Open in Stow. .tar.xz/.tar.gz show the inner .tar until tarballs are unwrapped |
| Encrypted entries: preview after unlock | ✅ with the hook | Previews use the password that opened a nested archive; for the outer archive, once the password branch stores it |
| Extract to temp & open with default app | ✅ | Open / double-click / ⌘↓. Files land read-only in a per-window cache (512 MB, least recently used first, keyed by archive identity + entry path + date), removed on close and quit, swept at launch |
| Drag out to Finder | ✅ | `NSFilePromiseProvider` per item; extracted only when dropped, through the usual staging and no-clobber placement, progress in Next Steps |

## 3. Extraction

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Extract all / selected / drag-out to Finder | ✅ | drag-out: file promises, see Previews |
| Extract All → folder named after archive | ✅ automatic (one item lands as itself) or always | |
| After Extract All: keep / move archive to Trash / ask | ✅ with “Don’t ask again” | |
| Auto-close window after extract / install | ✅ setting | |
| Same-name folder conflicts: Merge / Keep Both; file Replace | ✅ Merge / Keep Both; Replace / Keep Both / Skip; “do the same for the rest” | ➕ replaced items go to the Trash; stopping undoes everything placed so far; apps are never merged |
| Skip system metadata (__MACOSX, AppleDouble, .DS_Store, Thumbs.db, desktop.ini) while keeping dotfiles like .gitignore | ✅ setting, on by default | ➕ Finder tags, comments and other Mac details in AppleDouble are put back on the files |
| Unsafe paths, special files (FIFO, sockets, devices), links | ✅ containment | ➕ explained in Checkup |
| Password archives (incl. RAR), incorrect-password retry, CJK passwords (show-password for IME) | ✅ sheet with retry for opening (encrypted 7z file lists), extracting and nested archives; password kept in memory while the archive is open · 🧪 (pending verification) show-password-by-default setting | ZIP passwords outside ASCII get a warning when packing |
| Batch extraction queue, stacked progress windows | ✅ File › Extract Archives… or drop several; compact progress stack | conflicts and keep/trash asked once per batch |
| Staged writes, cleanup on cancel/failure | ✅ | |
| Integrity check of disk images before browsing | ✅ in the background (browsing doesn’t wait) | |

## 4. Creating archives

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Create ZIP / 7Z / TAR (+gz/bz2/xz) | ✅ | Sandboxed engine; files stream in as an Apple Archive, the archive streams back. .tar.zst: the bundled 7zz can only read zstd, so not yet |
| Purpose presets: General sharing, Windows, Mac-to-Mac (xattrs), Linux & servers (Unix attrs), smaller archive | ✅ Windows/Mac/Linux/Web | ➕ each audience changes the archive itself: Windows/Web get safe names, NFC, no Finder files, no links; Linux keeps links and modes; Mac keeps tags/xattrs as `__MACOSX` AppleDouble (ZIP) |
| Compression levels: Store, Fastest, Fast, Balanced, Maximum, Smallest (LZMA2 solid block sizes, store incompressible files) | ✅ More Options | -mx 0/1/3/5/7/9 with 7-Zip's solid-block defaults; ZIP stores incompressible files per entry |
| Each preset remembers its level; default preset & level in Settings | ✅ remembered · 🧪 Settings UI (pending verification) | Last audience is remembered too |
| Windows filename check with editable suggested names | ✅ | ➕ clashes after renaming (incl. case-only) are numbered; edited names are made safe too |
| AES encryption (ZIP), header/filename encryption (7Z); ZIP passwords ASCII-only warning | ✅ | Password goes to 7-Zip on stdin, never argv |
| Split volumes, default volume size | ✅ 100 MB / 700 MB / 4 GB · 🧪 default in Settings (pending verification) | `Name.7z.001…`; Archive Utility can't open split ZIPs |
| Verify integrity after creating | ✅ More Options | Failed test keeps nothing |
| CPU core limit for compression | ✅ `PackCPUCores` key (0 = all) · 🧪 Settings UI (pending verification) | |
| Replace / Keep Both when archive exists | ✅ | Replace moves the old archive and its volumes to the Trash |
| Create disk image (DMG) | ⬜ | (string present in ArcZip; low priority) |
| Quick Compress with defaults (Finder) | ✅ Services and Finder menu pack through the create engine (`EnginePacker`) | names like Finder (“Report.zip”, “Archive 2.zip”) |

Entry points: New Archive (⌘N) file picker, drops on the welcome window, the Tray's Pack button.
Progress and result appear in a Next Steps-style capsule (Stop, Show in Finder).

## 5. Editing existing archives

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Add, delete, replace, rename items; save; undo/redo | 🧪 E1 engine; ⬜ UI and undo/redo | ZIP / 7Z / TAR; pending macOS verification |
| Original untouched until save; rollback on failure | 🧪 same-volume atomic save | Fault injection and byte-identity tests; pending macOS verification |
| Detect archive changed on disk → reload or save a copy | ⬜ | |
| Rename the archive itself (incl. SMB/NAS) | ⬜ | |
| Keep browsing position after save | ⬜ | |

## 6. Next Steps (ArcZip “Flow”)

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Install app from archive/DMG to /Applications; replace existing; reveal in Finder | ✅ one-time folder grant (see README › Installing) | replace shows both versions, old copy to the Trash; refuses while the app is running |
| Signature & notarization check (unsigned / ad-hoc / unnotarized / unknown) with warnings | ✅ SecStaticCode + requirements | ➕ plain-word verdict in Checkup and the inspector (“Check Signature” before installing) |
| Optional quarantine-flag removal | ✅ off by default, explained | installed apps keep the archive’s quarantine so Gatekeeper still checks them; if macOS refuses removal, Checkup says so |
| Honour developer “drag to X” DMG layouts | ✅ | APFS images give the target; HFS+ ones only reveal a link named “Applications” |
| Install fonts (OTF/TTF/TTC) to user library, replace existing | ✅ Replace / Skip | web fonts reported as not installable |
| PKG: prepare safely, hand off to Installer | ✅ unpacked beside the archive, removed when Installer quits | |
| After install: keep/trash archive, close window | ✅ | |
| Alternative actions list; customise which actions show; restore suggestions | ⬜ | |

## 7. Compact window (ArcZip “Mini”) → **Glance**

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Opens near the pointer, compact browse/extract | ✅ | clamped to the visible screen; name + size list, Next Steps, Extract All |
| Pin on top | ✅ | remembered |
| Switch Glance ↔ full window keeping location, selection, history | ✅ | one shared browser; ⌥⌘G |
| Default to Glance when opening from Finder/Quick Look | ✅ | Settings › General |
| Liquid Glass / classic material; colourful window controls option | ✅ glass, solid under Reduce Transparency | ⬜ colourful window controls option |

## 8. Collecting files (ArcZip “File Box / Shelf”) → **Tray**

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Menu-bar icon, auto-show on drag, collapse after inactivity (configurable), pin open | 🎨 floating panel · ⬜ menu bar, auto-show | |
| Folder browsing, previews, multi-select, drag out | 🎨 list + drag-out | |
| Actions: compress, extract, collect into a folder (then rename), share, reveal, send to main window | 🎨 Pack/Clear · ⬜ rest | |
| Border colour setting | ⬜ | |

## 9. System integration

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Finder context menu (Finder Sync) incl. optional external drives; Repair Finder menu (re-register, restart Finder) | ✅ menu, external-drive setting · 🎨 repair (sandbox: LSRegisterURL/pluginkit refused, so it opens the extension switch and explains relaunching Finder) | Extract Here, Extract To…, Open in Stow, Compress with Stow… |
| Services: Extract Here, Extract To…, Quick Compress, Compress…, Send to app | ✅ (Quick Compress waits on the create engine) | results revealed in Finder; progress on the Dock icon |
| File associations UI: choose formats, set/restore default app, report result | ✅ model + view · 🧪 Settings host (pending verification) | ➕ remembers each type's previous app; reports refusals and types macOS kept |
| Launch at login, Dock icon hides with last window | ✅ (opt-in) | login item shows macOS's real status |
| URL scheme for extension → app hand-off (one-time requests) | ✅ | ➕ 128-bit one-time tokens, 60 s, no paths in URLs |
| Reading files dropped from other apps (WeChat etc.), permission guidance | ⬜ | |

## 10. Settings, onboarding, maintenance

| ArcZip | Stow | Notes |
| --- | --- | --- |
| General: appearance (light/dark/auto), default view, CPU cores | 🧪 pending verification | |
| Compression defaults, Extraction defaults, Flow, Box, Mini panes | ⬜ | |
| Password field: show by default (for CJK input) | 🧪 pending verification | |
| Advanced: temp-file usage & cleanup, reset all preferences | 🧪 pending verification | |
| Onboarding: intro, file associations, Finder extension, permissions, interactive Box demo | 🧪 pending verification | |
| Updates: automatic check, install after tasks finish | ⬜ | |
| Open-source licence viewer | 🧪 pending verification | |
| Native dialogs, detailed error codes + request IDs for support | partial | |

## Deliberately not copied

- Trials, activation codes, device seats, refunds — Stow is free and open source.
- Full Disk Access as a default ask — Stow stays sandboxed and asks for the narrowest access a flow needs.

## Where Stow already goes further

- Checkup on every archive, in plain words.
- Pack sentence with a live compatibility report (ArcZip shows a preset picker).
- Engine never sees a path; extraction is streamed and audited twice.
- Warm hover previews (instant once one is open).
