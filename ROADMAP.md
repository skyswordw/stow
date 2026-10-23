# Roadmap

Where Stow is, what's left to reach — and pass — ArcZip Pro's feature set, and what hasn't been
tested yet. Feature-by-feature status lives in [PARITY.md](PARITY.md); the design rules every item
must follow are in [DESIGN.md](DESIGN.md).

*Last updated 2026-10-20, after wave 1 landed on `main` (156 automated tests passing).*

---

## Where we are

**Works today (wave 1):** real archives open, browse, preview and extract through a sandboxed 7-Zip
engine; real thumbnails, Space-bar Quick Look, hover previews, column view, back/forward, path bar,
path search with a background index, nested archives, legacy filename encodings; packing to ZIP, 7Z
and TAR variants with levels, encryption, split volumes and Windows-safe names; Finder Quick Look
for 34 archive types, Finder menu, Services, default-app settings, launch at login; disk images
without mounting; app/font/PKG installs with signature checks; Extract All options, conflict
handling and batch extraction; password prompt with retry.

**Not yet:** everything in the tables below. Stow has **no signed build and no release** yet — it
has to be built from source.

## Goal

Every ArcZip Pro capability, free and open source, with a design that is calmer and clearer:
plain-words Checkup on every archive, the Pack sentence instead of option dialogs, one right next
step instead of menus, Liquid Glass used for floating controls only, and no animation on anything
done a hundred times a day.

---

## Wave 2 — the remaining ArcZip Pro features

Each item is sized for one focused session, on its own branch, merged through an integration branch
with the full test suite and light/dark screenshot review (as wave 1 was).

### E. Editing archives
- Add, delete, replace and rename items in ZIP / 7Z / TAR; Save; undo/redo for every edit.
- Edits are staged; the original is replaced only by an atomic swap after a successful write, with
  rollback on failure.
- Detect the archive changing on disk while edits are pending → Reload or Save a Copy.
- Rename the archive itself (including SMB/NAS shares); keep the browsing position after saving.
- Read-only formats (RAR, DMG, ISO, packages) say so and offer "Extract and repack as ZIP/7Z".
- *Done when:* round-trip tests for every editable format, including cancel mid-save and a
  simulated write failure leave the original byte-identical.

### F. Glance — the compact window (ArcZip "Mini")
- Opens near the pointer (clamped to the screen), browse and extract in a small window.
- Pin on top; switch Glance ↔ full window keeping folder, selection and history.
- Setting: open in Glance by default from Finder and Quick Look.
- Liquid Glass material with a solid fallback for Reduce Transparency.
- *Done when:* snapshots at every screen edge, both themes; switching preserves state (tests).

### G. Tray in the menu bar (ArcZip "File Box")
- Menu-bar icon; Tray appears while something is dragged and hides after a configurable idle time;
  pin open.
- Folder browsing, previews, multi-select, drag out.
- Actions: Pack, Extract, Collect into a Folder (then rename), Share, Reveal, Send to the main window.
- Border-colour setting.
- *Done when:* every action works on real files; drag-in/out tested by hand (see *Tests not yet run*).

### H. Settings, onboarding, updates, translation
- A Settings window hosting the panes that already exist as standalone views (Extraction,
  Installing, File Types, Integration) plus: General (appearance, default view, CPU cores),
  Packing defaults (audience, level, volume size), Hover previews on/off, Glance, Tray, Passwords
  (show by default, for Chinese/Japanese input methods), Advanced (temporary-file usage and
  clean-up, reset all preferences), open-source licence viewer.
- First-run onboarding: what Stow does, file associations, Finder extension, Tray — skippable,
  re-openable from Help.
- Updates with Sparkle (appcast on GitHub Releases); installs wait until running tasks finish.
  Done in #35: Sparkle 2.10 (sandboxed: installer + downloader XPC services, no network
  entitlement), Stow › Check for Updates…, General › Updates, relaunch held while busy, appcast
  signed by `scripts/generate-appcast.sh` in the Release workflow. Still to test: a real update
  from one published release to the next (Tests #21).
- Simplified Chinese localization via String Catalogs, with a layout check of every screen.
- *Done when:* every setting key has a control; screenshots of every pane in both languages and
  themes.

## Wave 3 — smaller gaps and going further

| Item | Notes |
| --- | --- |
| Next Steps: list of alternative actions, customise which show, restore suggestions | done (#20): a More menu (⋯) on the capsule lists every other step that applies; Settings › Next Steps shows or hides each step (or Next Steps itself) and restores the defaults |
| Checkup: warn when the extension doesn't match the real format (ZIP with prepended data, SFX) | done (#16): Checkup names the real format, self-extracting stubs, and data before or after the archive |
| iCloud placeholders: wait for download, cancel | built (#18), pending a real iCloud check: opening a placeholder asks for the download, shows its progress and opens when it's here; Cancel or Escape stops waiting |
| Open Recent menu with clear history | welcome window "Recent" still shows sample names |
| Search across nested archives | done (#21): search reads the archives inside the open one (one level, up to 40 archives / 512 MB each / 2 GB total), lists matches under the archive’s name, and Show opens it with the match selected; deeper levels: open the inner archive and search again |
| Streaming listings beyond ~100k entries | 100,500 entries open in 2.8 s today |
| Reading files dropped from other apps (e.g. WeChat) with permission guidance | built (#19), pending a real WeChat/Mail check: archives an app only promises during a drag are received first; a file macOS won't let Stow read gets plain words naming the app (`OPN-101`) and how to get a copy |
| Error details with codes for bug reports | done (#14): every failure has a stable code (`EXT-120`, see [ERROR-CODES.md](ERROR-CODES.md)) and Copy Details |
| Create disk images (DMG) | done (#23, #77): Pack › DMG for Macs; default HFS+ `makehybrid` then `convert` by level; optional AES-256 password via `diskutil image create from --encrypt --stdinpassphrase` (macOS 27; clear error if it fails; never writes an unencrypted image), APFS via `create -srcfolder` with HFS+ hybrid fallback, and an Applications → /Applications shortcut for drag-to-install. Deferred: Finder window chrome (`.DS_Store` / background art) |
| TAR.ZST creation | done: 7-Zip writes the TAR, Stow's linked zstd 1.5.7 compresses it (Linux audience, splits into volumes, verified by 7-Zip) |
| Restore Mac metadata on Stow's own extraction | done (#17): Finder comments and tags come back from ZIP, 7Z, TAR, TAR.GZ/BZ2/XZ/ZST, for Extract All, one file or one folder (`__MACOSX` and inline `._` companions). Not carried: disk images (7-Zip leaves out their attributes) and Linux `tar --xattrs` headers |

## Design polish (applies across waves)

| Area | Plan |
| --- | --- |
| App icon | Stow has none yet. Design one in the amber "parcel" language of the website mark, all sizes, light/dark/tinted. |
| Welcome window | Feels empty at large sizes: real Open Recent, a smaller drop target, a quieter title bar. |
| Motion audit | Run the `review-animations` skill over every transition; enforce DESIGN.md (no animation on keyboard actions, exits faster than entrances, springs only where touched). |
| Consistency | One progress capsule style for packing, extracting, installing and batch; one prompt style for conflicts, signatures and passwords. |
| Accessibility | done (#29): composed VoiceOver labels (grid, list, columns, Glance, Tray, nested search results, Next Steps summary), headers for the rotor, reading order sidebar → content → inspector → Next Steps, keyboard paths (Tray rows, onboarding, Quick Look); no animation for keyboard actions, solid surfaces under Reduce Transparency, stronger outlines and metadata under Increase Contrast. Manual VoiceOver checklist in #66 / #38 |
| Empty and error states | Every failure says what happened and what to do, in plain words, with one action. |
| Website | Real product video of Pack and Checkup; screenshots refreshed from the release build. |

## Release engineering

| Item | Why |
| --- | --- |
| Developer ID signing and notarization | Gatekeeper; also unlocks App Group containers. Pipeline in place (#32): `scripts/package.sh`, `scripts/verify-app-bundle.sh` and the **Release** workflow sign inside-out, notarize and staple; see [RELEASING.md](RELEASING.md). App Group Finder hand-off (`YNQ2233752.app.stow.Stow`) is in: Team-signed builds use the shared container, ad-hoc builds keep the private pasteboard fallback. Still to do: the first notarized build verified on a clean Mac (Tests #17) |
| Universal 2 build (arm64 + x86_64) | done (#33): Release builds `$(ARCHS_STANDARD)` for every target; CI's `universal` job builds Release and `scripts/check-universal.sh` fails unless the app, StowEngine.xpc, its 7zz and both extensions carry arm64 and x86_64, then runs the x86_64 7zz under Rosetta. A full x86_64 test run is a manual `workflow_dispatch` option |
| Signed DMG + GitHub Releases + Sparkle appcast | first public download. The **Release** workflow (#34) builds the notarized DMG, signs it with Stow's EdDSA key and writes `appcast.xml` (`scripts/generate-appcast.sh`, #35), and attaches both to a draft release; the app's feed is `releases/latest/download/appcast.xml`, so an update reaches people when the draft is published |
| Homebrew cask | template and tooling done (#36): `packaging/homebrew/stow.rb`, `scripts/render-cask.sh` and the `Homebrew cask` workflow fill in version + DMG checksum per release, audit, and install/uninstall once. Still to do: the first signed release DMG (#32, #34), then publish to a tap (or homebrew/cask under a non-conflicting token — `stow` is a homebrew/core formula) |
| CI | `.github/workflows/ci.yml` builds and tests every push and PR to main on GitHub's `xcode-27` runner (preview image: macOS 27, Xcode 27). Fails if 7zz is missing or any test is skipped. Still to do: release builds, signing, and moving off the preview image once it is GA. |
| Fuzzing | done (#37): `Tests/FuzzTests.swift` mutates ZIP, 7Z, TAR (.gz/.bz2/.xz), RAR 4/5 and DMG seeds (truncation, bit flips, header/trailer corruption, huge length fields, splices, zero runs) and checks that 7zz never crashes or hangs, the engine only fails cleanly and survives, and extraction stays inside its folder; plus libarchive's malformed-RAR regressions. ~15 mutants per seed on every CI run; `.github/workflows/fuzz.yml` runs hundreds weekly and on demand, keeping any failing input |

---

## Unimplemented features (summary)

Everything marked ⬜ or 🎨 in [PARITY.md](PARITY.md):

- Editing existing archives (add/delete/replace/rename, save, undo, change detection, rename archive)
- Glance compact window (near pointer, pin, switch with state, open-by-default)
- Tray in the menu bar (auto-show, idle hide, pin, collect-into-folder, share, send to window, border colour)
- Settings window and every Settings control (General, Packing defaults, volume size, CPU cores,
  hover toggle, password display, temp-file clean-up, reset, licence viewer)
- Onboarding, Simplified Chinese
- Next Steps customisation and alternative-actions list
- iCloud placeholders, Open Recent, search across nested archives
- Reading files from other apps' containers
- DMG creation
- App icon; signed, notarized, universal release

## Tests not yet conducted

Automated tests cover the engine, packing, extraction, placement/conflicts, signatures, hand-off
tokens, associations logic, browsing, search, encodings and passwords (156 tests). The following
have **not** been done and must be before a 1.0:

| # | What | Why it hasn't been done / how to run it |
| --- | --- | --- |
| 1 | Finder context menu clicked through by a person (Extract Here, Extract To…, Compress, Open in Stow), including external drives | needs Accessibility to drive Finder; run by hand after `scripts/register-extensions.sh` |
| 2 | One-time folder grant panel (Allow / choose another folder / cancel) from a Finder action | headless runs used Stow's own container |
| 3 | Changing the default app for a type end to end (macOS shows its own confirmation per type) | the live check stopped at the system dialog |
| 4 | Repair Finder Menu flow (System Settings switch, relaunch Finder) | sandbox refuses `pluginkit`/`LSRegisterURL`; verify the guidance works |
| 5 | Installing a font into the real `~/Library/Fonts` | tests used a scratch folder; needs one Allow click |
| 6 | Download-quarantine carried over during a real Extract All into a folder picked in the Open panel | unit-tested only |
| 7 | Drag-out to Finder with a real mouse, icon **and** list view | verified up to the drag session and promise fulfilment; list view (NSTableView) unverified |
| 8 | Typing into the password sheet, including Chinese/Japanese input methods | no desktop control in the sessions |
| 9 | Pack save panel and Replace / Keep Both alert by hand | headless runs share the code, not the dialogs |
| 10 | Encrypted + split + verified 7Z packing once died with SIGTERM | passed 3/3 reruns; not reproduced — needs a stress loop |
| 11 | Quick Look extension after installing from a DMG on a clean account, and after updates | only tested from the build folder |
| 12 | Archives of several GB, low disk space, and the engine's temporary copy while packing | packing needs space for the input plus the archive |
| 13 | SMB/NAS and iCloud Drive locations (open, extract, pack, rename) | not tested |
| 14 | Real-world corpus: multi-part RAR5, self-extracting EXE, ZIPs from Windows/Linux tools, legacy encodings beyond the fixtures | fixtures are synthetic |
| 15 | Accessibility: VoiceOver, keyboard-only use, Reduce Motion/Transparency, Increase Contrast | automated parts covered (#29); the manual VoiceOver/keyboard/display-settings checklist is on #38 |
| 16 | Intel Macs and macOS 26.0 (development was on Apple silicon, macOS 27) | the universal Release build is checked in CI (#33) and the test suite passed as x86_64 under Rosetta, but the x86_64 7zz dies with "Illegal instruction" under Rosetta; nothing has run on real Intel hardware or on macOS 26.0 |
| 17 | Signed/notarized build behaviour (Gatekeeper on extracted apps, extensions, App Group hand-off on a clean Mac) | notarized DMG published; clean-Mac Gatekeeper + live Finder hand-off still to run by hand (#38) |
| 18 | Fuzzing malformed archives | automated (#37): a deterministic set on every CI run, a longer weekly run (`fuzz.yml`). Still open: a sustained multi-hour run with no findings, and coverage-guided fuzzing of Stow's own parsers (AppleDouble, tar headers) |
| 19 | Website in Safari, Firefox and on real phones | checked in one desktop browser engine and a 375 px emulation |
| 20 | CI | runs on GitHub's `xcode-27` runner (`.github/workflows/ci.yml`); ad-hoc signed, so signed-build behaviour is still item 17 |
| 21 | Sparkle: a real update from one published release to the next (check, download through the downloader service, install outside the sandbox, relaunch waiting for a running extraction) | needs two published, notarized releases; CI checks signing, the bundle layout and the appcast signature only |
