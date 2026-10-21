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
| Main app | **Not sandboxed**; onboarding asks for Full Disk Access | Sandboxed, user-selected files only. Some flows (install to /Applications, Finder actions) need a privileged helper or user-granted folder access — see *Integration* |
| Extensions | Finder Sync (`com.apple.FinderSync`), Quick Look preview (zip/7z/tar only) | Planned: both, Quick Look covering every format the engine opens |
| Services menu | 5 Finder services | Planned: same set |
| Updates | Sparkle | Sparkle (open-source appcast on GitHub Releases) |
| Licensing | Ed25519-signed licenses, device seats, trial, Keychain | **None** — open source |
| Languages | English, Simplified Chinese | English, Simplified Chinese at launch (String Catalog) |
| OS | macOS 14+ | macOS 26+ (decision recorded in README) |

Legend: ✅ works · 🎨 designed, UI only (simulated) · ⬜ not started · ➕ Stow goes further

---

## 1. Opening & browsing

| ArcZip | Stow | Notes / how Stow goes further |
| --- | --- | --- |
| 30+ formats: zip zipx 7z rar cbr tar tgz tbz tbz2 txz gz bz2 xz lzma lz dmg iso cab cpio arj lha lzh xar rpm msi pkg jar apk spk exe(SFX) swf .001 | ✅ via 7zz (needs format registration in Info.plist) | ➕ compressed tarballs (.tar.gz/.tgz/.tar.xz/.tar.bz2/.tar.zst/.tar.lz…) browse as the tar inside: two 7zz piped, nothing written to disk. ➕ “Show Package Contents” on .docx/.xlsx/.pptx/.epub/.pages opens them as the ZIPs they are |
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
| Read-only preview of DMG/ISO (mount read-only, verify, skip installer extras like the Applications alias) | ⬜ (session D) | |

## 2. Previews

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Space → Quick Look of an entry; arrow keys switch target | ✅ | System Quick Look panel; arrow keys move the browser's selection and the panel follows; several selected page with ← →; ⌘Y too |
| Hover preview after ~1 s (images, PDF, Office, text, Markdown, CSV, code, audio artwork, video frames); toggle in Settings | ✅ previews · ⬜ Settings toggle | Real content read from the archive: images (downsampled), PDF/Office/others (Quick Look), Markdown (rendered), CSV (table), code/logs (monospaced, unwrapped), fonts (the real face), audio (artwork, title, length), video (a frame, length). ➕ 450 ms, then neighbours open instantly |
| Thumbnails in icon view | ✅ | Quick Look thumbnails, only for tiles on screen, batched into one engine trip; files over 48 MB keep their icon |
| Quick Look extension for archives in Finder | ⬜ (session B) | ➕ all formats, not just zip/7z/tar; shows Checkup summary |
| Encrypted entries: preview after unlock | ✅ with the hook | Previews use the password that opened a nested archive; for the outer archive, once the password branch stores it |
| Extract to temp & open with default app | ✅ | Open / double-click / ⌘↓. Files land read-only in a per-window cache (512 MB, least recently used first, keyed by archive identity + entry path + date), removed on close and quit, swept at launch |
| Drag out to Finder | ✅ | `NSFilePromiseProvider` per item; extracted only when dropped, through the usual staging and no-clobber placement, progress in Next Steps |

## 3. Extraction

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Extract all / selected / drag-out to Finder | ✅ | drag-out: file promises, see Previews |
| Extract All → folder named after archive | ⬜ | |
| After Extract All: keep / move archive to Trash / ask | ⬜ | |
| Auto-close window after extract / install | ⬜ | |
| Same-name folder conflicts: Merge / Keep Both; file Replace | ⬜ (no-clobber today) | |
| Skip system metadata (__MACOSX, AppleDouble, .DS_Store, Thumbs.db, desktop.ini) while keeping dotfiles like .gitignore | ✅ helper filter in Shared | |
| Unsafe paths, special files (FIFO, sockets, devices), links | ✅ containment | ➕ explained in Checkup |
| Password archives (incl. RAR), incorrect-password retry, CJK passwords (show-password for IME) | ⬜ in progress (side session) | |
| Batch extraction queue, stacked progress windows | ⬜ | |
| Staged writes, cleanup on cancel/failure | ✅ | |
| Integrity check of disk images before browsing | ⬜ | |

## 4. Creating archives

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Create ZIP / 7Z / TAR (+gz/bz2/xz) | 🎨 Pack sentence · ⬜ engine | ➕ .tar.zst |
| Purpose presets: General sharing, Windows, Mac-to-Mac (xattrs), Linux & servers (Unix attrs), smaller archive | 🎨 Windows/Mac/Linux/Web | |
| Compression levels: Store, Fastest, Fast, Balanced, Maximum, Smallest (LZMA2 solid block sizes, store incompressible files) | ⬜ | |
| Each preset remembers its level; default preset & level in Settings | ⬜ | |
| Windows filename check with editable suggested names | ✅ rules + report · ⬜ editable names | |
| AES encryption (ZIP), header/filename encryption (7Z); ZIP passwords ASCII-only warning | 🎨 · ⬜ | |
| Split volumes, default volume size | 🎨 · ⬜ | |
| Verify integrity after creating | ⬜ | |
| CPU core limit for compression | ⬜ | |
| Replace / Keep Both when archive exists | ⬜ | |
| Create disk image (DMG) | ⬜ | (string present in ArcZip; low priority) |
| Quick Compress with defaults (Finder) | ⬜ | |

## 5. Editing existing archives

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Add, delete, replace, rename items; save; undo/redo | ⬜ | |
| Original untouched until save; rollback on failure | ⬜ (pattern exists for extraction) | |
| Detect archive changed on disk → reload or save a copy | ⬜ | |
| Rename the archive itself (incl. SMB/NAS) | ⬜ | |
| Keep browsing position after save | ⬜ | |

## 6. Next Steps (ArcZip “Flow”)

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Install app from archive/DMG to /Applications; replace existing; reveal in Finder | 🎨 | needs privileged path or user-granted /Applications access |
| Signature & notarization check (unsigned / ad-hoc / unnotarized / unknown) with warnings | ⬜ | ➕ already surfaced in Checkup design |
| Optional quarantine-flag removal | ⬜ | off by default, explained |
| Honour developer “drag to X” DMG layouts | ⬜ | |
| Install fonts (OTF/TTF/TTC) to user library, replace existing | 🎨 | |
| PKG: prepare safely, hand off to Installer | 🎨 | |
| After install: keep/trash archive, close window | ⬜ | |
| Alternative actions list; customise which actions show; restore suggestions | ⬜ | |

## 7. Compact window (ArcZip “Mini”) → **Glance**

| ArcZip | Stow | Notes |
| --- | --- | --- |
| Opens near the pointer, compact browse/extract | ⬜ | |
| Pin on top | ⬜ | |
| Switch Glance ↔ full window keeping location, selection, history | ⬜ | |
| Default to Glance when opening from Finder/Quick Look | ⬜ | |
| Liquid Glass / classic material; colourful window controls option | ⬜ | |

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
| Finder context menu (Finder Sync) incl. optional external drives; Repair Finder menu (re-register, restart Finder) | ⬜ | |
| Services: Extract Here, Extract To…, Quick Compress, Compress…, Send to app | ⬜ | |
| File associations UI: choose formats, set/restore default app, report result | ⬜ | |
| Launch at login, Dock icon hides with last window | ⬜ | |
| URL scheme for extension → app hand-off (one-time requests) | ⬜ | |
| Reading files dropped from other apps (WeChat etc.), permission guidance | ⬜ | |

## 10. Settings, onboarding, maintenance

| ArcZip | Stow | Notes |
| --- | --- | --- |
| General: appearance (light/dark/auto), default view, CPU cores | ⬜ | |
| Compression defaults, Extraction defaults, Flow, Box, Mini panes | ⬜ | |
| Password field: show by default (for CJK input) | ⬜ | |
| Advanced: temp-file usage & cleanup, reset all preferences | ⬜ | |
| Onboarding: intro, file associations, Finder extension, permissions, interactive Box demo | ⬜ | |
| Updates: automatic check, install after tasks finish | ⬜ | |
| Open-source licence viewer | ⬜ (THIRD_PARTY_NOTICES.md exists) | |
| Native dialogs, detailed error codes + request IDs for support | partial | |

## Deliberately not copied

- Trials, activation codes, device seats, refunds — Stow is free and open source.
- Full Disk Access as a default ask — Stow stays sandboxed and asks for the narrowest access a flow needs.

## Where Stow already goes further

- Checkup on every archive, in plain words.
- Pack sentence with a live compatibility report (ArcZip shows a preset picker).
- Engine never sees a path; extraction is streamed and audited twice.
- Warm hover previews (instant once one is open).
