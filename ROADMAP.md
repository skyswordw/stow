# Roadmap

Where Stow is, what's left to reach — and pass — ArcZip Pro's feature set, and what hasn't been
tested yet. Feature-by-feature status lives in [PARITY.md](PARITY.md); the design rules every item
must follow are in [DESIGN.md](DESIGN.md).

*Last updated 2026-11-02 (Pacific/Honolulu), after the 0.1.3 release, real WeChat acceptance, and the window/menu stability repairs in #266. Tracking: [#39](https://github.com/Beastry/stow/issues/39); native acceptance: [#38](https://github.com/Beastry/stow/issues/38).*

---

## Where we are

**Implemented today:** real archives open, browse, preview and extract through a sandboxed 7-Zip
engine; real thumbnails, Space-bar Quick Look, hover previews, column view, back/forward, path bar,
path search with a background index, nested archives, legacy filename encodings; packing to ZIP, 7Z
and TAR variants with levels, encryption, split volumes and Windows-safe names; Finder Quick Look
for 34 archive types, Finder menu, Services, default-app settings, launch at login; disk images
without mounting; app/font/PKG installs with signature checks; Extract All options, conflict
handling and batch extraction; password prompt with retry and an optional Keychain vault. Editing,
Glance, Tray, Settings, onboarding and Simplified Chinese are also built; [PARITY.md](PARITY.md)
distinguishes working features from those still awaiting macOS verification. Open Recent uses real
bookmark history, and Glance now has optional colourful window controls (off by default).

**Released:** notarized **v0.1.3 (592)** is the latest published release, from `ec480387`,
following v0.1.0–v0.1.2. The installed `/Applications/Stow.app` passed the full notarized-bundle
verification with zero problems; enabled Finder/Quick Look extensions point to that app.
This is current-machine evidence, not a clean-Mac acceptance pass. See
[GitHub Releases](https://github.com/Beastry/stow/releases) and [RELEASING.md](RELEASING.md).

**Merged after that release:** #266 (`ec0a2e1`) fixes direct document launch via an unnecessary
Welcome window, remembers the last selected Browser/Glance mode, and repairs two actual 0.1.3
crashes (recursive editing-window delegates and Finder menu callback actor isolation).
**These repairs are not in v0.1.3.** Their 655-test local suite, complete zh-Hans coverage
(1,202 strings), Universal 2 and snapshot CI passed; a new signed artifact and native acceptance
remain in #212/#38. #265 is closed as an implementation fix, not signed-release acceptance.

**Current remaining work:** signed repaired-build integration and the environment matrix
(#32/#38/#210/#212), Actions acceptance (#161), real system display/motion preference checks
(#104), and media/video delivery (#69). DMG AES (#84), Intel/Rosetta (#144) and dedicated
VoiceOver/#93 remain explicitly deferred. Homebrew own-tap publish is wired
(`Beastry/homebrew-tap`, `brew install --cask Beastry/tap/stow`); verify install on a clean Mac after the next published release. Actions extensions / a possible plugin ecosystem
are a demand-driven long-term candidate (#268), not a 1.0 gate.

## Goal

Every ArcZip Pro capability, free and open source, with a design that is calmer and clearer:
contextual archive findings with details available on demand, clear packing outcomes and options,
and relevant Actions without overwhelming the file workspace. The full Browser keeps Details
visible; navigation and Actions float over the files. DESIGN.md is the current visual/motion
direction; historical mockups and permanent Checkup-promotion proposals are superseded.

---

## Wave 2 — implemented features and remaining verification

These features are built. The lists describe their scope; pending desktop, layout and integration
checks remain recorded in [PARITY.md](PARITY.md) and *Tests not yet conducted* below.

### E. Editing archives
- Add, delete, replace and rename items in ZIP / 7Z / TAR; Save; undo/redo for every edit.
- Edits are staged; the original is replaced only by an atomic swap after a successful write, with
  rollback on failure.
- Detect the archive changing on disk while edits are pending → Reload or Save a Copy.
- Rename the archive itself (including SMB/NAS shares); keep the browsing position after saving.
- Read-only formats (RAR, DMG, ISO, packages) say so and offer "Extract and repack as ZIP/7Z".
- *Verification:* round-trip, cancel and fault-injection tests cover preserving the original;
  native ZIP editing/Save/Undo and external-change recovery passed; wider format and SMB/NAS checks remain pending.

### F. Glance — the compact window (ArcZip "Mini")
- Opens near the pointer (clamped to the screen), browse and extract in a small window.
- Pin on top; switch Glance ↔ full window keeping folder, selection and history.
- Opening preference: Last Used Window, Full Browser or Glance (#266, merged after v0.1.3).
  Explicit legacy fixed-mode choices are preserved; new/default users remember their last switch.
- Liquid Glass material with a solid fallback for Reduce Transparency.
- Optional red / yellow / green Close, Pin and Open in Full Window controls (#86), in Settings ›
  Glance, off by default. Borderless Glance has its own functional Close/Pin/Expand controls.
- *Verification:* shared state, Columns selection and native Browser/Glance round trips have evidence.
  #266 adds restart/mode-memory checks; exact signed repaired-build and real display-preference
  acceptance remain open. English/Chinese light/dark snapshots are not that acceptance.

### G. Tray in the menu bar (ArcZip "File Box")
- Menu-bar icon; Tray appears when dragged files reach it (#180). The local 2026-11-04
  implementation replaces idle hiding with outside-click/application-switch dismissal
  when unpinned; Keep Tray Open prevents it. Related surfaces and active drags are protected.
  See the [behavior, validation and ownership brief](Handoff/tray-keep-open-2026-11-04.md);
  Claude Code visual/motion review remains pending.
- Folder browsing, previews, multi-select, drag out.
- Actions: Pack, Extract, Collect into a Folder (then rename), Share, Reveal, Send to the main window.
- Border-colour setting.
- *Verification:* real-file actions are built; drag-in/out still needs a hand-test (see below).

### H. Settings, onboarding, updates, translation
- A Settings window hosts Extraction, Installing, File Types and Integration plus General
  (appearance, default view, CPU cores),
  Packing defaults (audience, level, volume size), Hover previews on/off, Glance, Tray, Passwords
  (show by default, for Chinese/Japanese input methods), Advanced (temporary-file usage and
  clean-up, reset all preferences), open-source licence viewer.
- First-run onboarding: what Stow does, file associations, Finder extension, Tray — skippable,
  re-openable from Help.
- Updates with Sparkle (appcast on GitHub Releases); installs wait until running tasks finish.
  Done in #35: Sparkle 2.10 (sandboxed: installer + downloader XPC services, no network
  entitlement), Stow › Check for Updates…, General › Updates, relaunch held while busy, appcast
  signed by `scripts/generate-appcast.sh` in the Release workflow. Still to test: a real update
  between published releases, including busy-task/relaunch behavior (Tests #21).
- Simplified Chinese localization via String Catalogs; remaining layout checks are tracked below.
- *Verification:* #162 is closed after Settings presentation, persistence/reset contracts and
  native sidebar/reopening/deep-link checks. The user exercised File Types and observed macOS
  confirmation per type. Exact per-format outcomes/restore and full keyboard navigation remain
  in #38; screenshots cover both languages and themes.

## Wave 3 — smaller gaps and going further

| Item | Notes |
| --- | --- |
| Actions (formerly Next Steps): list of alternative actions, customise which show, restore suggestions | done (#20, renamed in #161): a More menu (⋯) beside the stack lists every other action that applies; Settings › Actions shows or hides each one (or Actions itself) and restores the defaults |
| Checkup: warn when the extension doesn't match the real format (ZIP with prepended data, SFX) | done (#16): Checkup names the real format, self-extracting stubs, and data before or after the archive |
| iCloud placeholders: wait for download, cancel | built (#18), pending a real iCloud check: opening a placeholder asks for the download, shows its progress and opens when it's here; Cancel or Escape stops waiting |
| Open Recent menu with clear history | done (#83): Welcome and File › Open Recent share real security-scoped bookmark history and Clear; missing/trashed files are hidden, not forgotten. Sample names only in `-StowScene recents` via `recents.preview(...)` for screenshots |
| Search across nested archives | done (#21): search reads the archives inside the open one (one level, up to 40 archives / 512 MB each / 2 GB total), lists matches under the archive’s name, and Show opens it with the match selected; deeper levels: open the inner archive and search again |
| ✅ Streaming listings beyond ~100k entries (#78) | First rows from streamed XPC chunks; final listing remains authoritative; cancellation stops 7zz. See StreamingListingBenchmark. |
| Reading files dropped from other apps (e.g. WeChat) with scoped recovery | #214/#223 implement file/folder authorization and retry; #264 makes bookmark-save failure non-modal. On installed 0.1.3 the user manually dragged and double-clicked a real WeChat RAR; source/drag-copy hashes matched, and four extracted files matched archive CRCs. Signed folder grant/restart/sibling isolation/removal also passed with task fixtures. Remaining signed repaired-build, split and alternate-entry matrix: #210/#212 |
| Error details with codes for bug reports | done (#14): every failure has a stable code (`EXT-120`, see [ERROR-CODES.md](ERROR-CODES.md)) and Copy Details |
| Create disk images (DMG) | done (#23, #77): Pack › DMG for Macs; default HFS+ `makehybrid` then `convert` by level; optional APFS via `create -srcfolder` with HFS+ hybrid fallback; Applications → /Applications shortcut for drag-to-install. Optional Finder window chrome done (#85): `.DS_Store` icon positions, solid-color background, and best-effort app-derived volume icon, written before image creation without mounting. Picture backgrounds excluded: Carbon Alias requires the mounted volume. Deferred: AES password (#84; App Sandbox blocks MediaKit attach for `hdiutil`/`diskutil` encrypt on macOS 27) |
| TAR.ZST creation | done: 7-Zip writes the TAR, Stow's linked zstd 1.5.7 compresses it (Linux audience, splits into volumes, verified by 7-Zip) |
| Restore Mac metadata on Stow's own extraction | done (#17): Finder comments and tags come back from ZIP, 7Z, TAR, TAR.GZ/BZ2/XZ/ZST, for Extract All, one file or one folder (`__MACOSX` and inline `._` companions). Not carried: disk images (7-Zip leaves out their attributes) and Linux `tar --xattrs` headers |

## Design polish (applies across waves)

| Area | Plan |
| --- | --- |
| App icon | Implemented: amber parcel icon in `Design/AppIcon.svg` and the Icon Composer document, with light/dark/tinted appearances; further tuning is optional. |
| Welcome window | Real Open Recent is done (#83), with a responsive layout and a smaller empty-state drop target; further spacing and title-bar polish is optional. Screenshot sample recents remain in DemoScene only. |
| Motion audit | #104 tracks current native acceptance. #255/#260 implement display-preference and accent-contrast fixes; #261/#262 refine encrypted states and Actions motion. Real System Settings switches still need acceptance. Claude Code owns visual/motion treatment. |
| Consistency | One progress capsule style for packing, extracting, installing and batch; one prompt style for conflicts, signatures and passwords. |
| Accessibility | Baseline semantics and keyboard paths are implemented (#29), with display-preference support. Complete VoiceOver support is not claimed: #93 and dedicated VoiceOver acceptance are deferred at low priority. Preserve existing names, keyboard/focus and system preferences; ordinary-use crashes remain functional stability defects. |
| Empty and error states | Every failure says what happened and what to do, in plain words, with one action. |
| Website | `scripts/website-shots.sh` retakes every screenshot and walkthrough frame in light and dark. Browsing shots open Try the Sample's own ZIP through the engine; the install walkthrough shows a separate app build ("Harbor Prototype 1.3.zip") because the sample holds no app. The historical #31 issue is closed; actual video delivery and remaining Pack/release-shot refresh remain tracked by #69. |

## Release engineering

| Item | Why |
| --- | --- |
| Developer ID signing and notarization | Shipped through v0.1.3 (#32): `scripts/package.sh`, `scripts/verify-app-bundle.sh` and the **Release** workflow sign inside-out, notarize, staple and verify; see [RELEASING.md](RELEASING.md). Team-signed Finder hand-off uses the App Group (`YNQ2233752.app.stow.Stow`); ad-hoc builds keep the private pasteboard fallback. Clean-Mac Gatekeeper and live Finder hand-off remain manual (#32/#38, Tests #17). |
| Universal 2 build (arm64 + x86_64) | done (#33): Release builds `$(ARCHS_STANDARD)` for every target; CI's `universal` job builds Release and `scripts/check-universal.sh` fails unless the app, StowEngine.xpc, its 7zz and both extensions carry arm64 and x86_64. Rosetta probes of the x86_64 7zz are informational; a full x86_64 test run is a manual `workflow_dispatch` option. Real Intel hardware remains untested. |
| Signed DMG + GitHub Releases + Sparkle appcast | v0.1.0–v0.1.3 published. The **Release** workflow (#34/#35) builds the notarized DMG, signs it with Stow's EdDSA key and writes `appcast.xml`, then attaches both to a draft release. Publication makes the appcast available at `releases/latest/download/appcast.xml`; a live update/relaunch hand-test remains (Tests #21). |
| Homebrew cask | Shipped to own tap (#36): `packaging/homebrew/stow.rb`, `scripts/render-cask.sh` and the `Homebrew cask` workflow fill in version + DMG checksum per published release, audit, install/uninstall once, and push `Casks/stow.rb` to [Beastry/homebrew-tap](https://github.com/Beastry/homebrew-tap) (`brew install --cask Beastry/tap/stow`). Official `homebrew/homebrew-cask` remains optional (`stow` collides with the homebrew/core formula). |
| CI | `.github/workflows/ci.yml` tests pushes to main and PRs on GitHub's `xcode-27` runner (preview image: macOS 27, Xcode 27). Fails if 7zz is missing or any test is skipped; also builds Universal 2 Release, packages an ad-hoc DMG and checks a throwaway-key appcast. Developer ID signing/notarization run in the Release workflow; clean-Mac checks are manual. Moving off the preview image once GA remains open. |
| Fuzzing | done (#37): `Tests/FuzzTests.swift` mutates ZIP, 7Z, TAR (.gz/.bz2/.xz), RAR 4/5 and DMG seeds (truncation, bit flips, header/trailer corruption, huge length fields, splices, zero runs) and checks that 7zz never crashes or hangs, the engine only fails cleanly and survives, and extraction stays inside its folder; plus libarchive's malformed-RAR regressions. ~15 mutants per seed on every CI run; `.github/workflows/fuzz.yml` runs hundreds weekly and on demand, keeping any failing input |

---

## Unimplemented features (summary)

Remaining feature and delivery gaps:

- DMG AES password creation (#84), deferred because the sandbox blocks the MediaKit attach path.
- Automated Finder-menu repair: sandbox restrictions leave System Settings and relaunch guidance.
- Official homebrew/homebrew-cask submission (optional; token collision with GNU Stow).

Editing, Glance (including colourful controls), Tray, Settings, onboarding, Simplified Chinese,
Actions customisation, iCloud download handling, Open Recent, nested search, promised-file drops,
DMG creation and the app icon are implemented. Items marked 🧪 in [PARITY.md](PARITY.md) still need
verification; they are not unimplemented features. Clean-Mac Gatekeeper, live Sparkle updates and
other manual checks remain below. Harbor sample files and Try the Sample wiring are on main (#70). Website shots and hover-demo thumbs use those assets. Website shots and walkthrough frames have been refreshed in stages with `scripts/website-shots.sh` (#69); the browsing shots come from the bundled sample ZIP, so they match Try the Sample. The latest #69 evidence records Browser/Details/Tray retakes in #247; Pack walkthrough refresh after #245 and the full video remain open. Signed builds now exist, so lack of any signed build is no longer the blocker.

## Tests not yet conducted

Automated tests cover the engine, packing, extraction, editing, placement/conflicts, signatures,
hand-off tokens, associations logic, browsing, streaming listings, search, encodings, passwords,
recents and settings. CI requires at least 658 reported tests after the test-history isolation follow-up (#273). The following tracks remaining
verification toward 1.0 (including automated coverage whose manual or longer-running counterpart
is still open). Explicitly deferred work is not a merge or release blocker for the current milestone:

| # | What | Why it hasn't been done / how to run it |
| --- | --- | --- |
| 1 | Signed Finder menu and external drives | Installed 0.1.3 extensions now point to `/Applications/Stow.app`. Actual menu callback crash is repaired in #266; validate the new signed artifact and full hand-off matrix. |
| 2 | Source/destination folder grants and Finder entry points | Signed-app folder Allow, automatic retry, second file after restart, sibling isolation, wrong-file refusal, Escape and Forget/restart passed. Finder hand-off and remaining cases stay in #212. |
| 3 | Default app changes and restore | User exercised File Types and confirmed per-type macOS dialogs. Record exact selected types, resulting associations and Switch Back; the full matrix is not yet verified. |
| 4 | Repair Finder Menu via Settings | Correct installed extension registration verified; the complete System Settings/relaunch recovery workflow remains unverified. |
| 5 | Real font-library installation/activation | Scratch font installation, unsupported formats and Skip/Replace passed; real user font activation remains untested. |
| 6 | Downloaded/quarantined vendor archives | Generated quarantined ZIP extraction preserved bytes and quarantine. Wider real-vendor/Gatekeeper matrix remains. |
| 7 | Finder drag-out and Tray workflows | #171/#172/#176 are closed; the main fix is `8293e06`. Real WeChat drag-in passed with a human gesture and hash checks. This does not complete Grid/List drag-out, repeated/cancelled drags or Tray acceptance. |
| 8 | Passwords and CJK IMEs | Native real encrypted ZIP entry, wrong-password retry, Return, Escape and close cancellation passed. Chinese/Japanese IME composition remains separate. |
| 9 | Pack destination/conflict dialogs | Passed: Cancel preserves original; Keep Both and Replace produce exact expected bytes and recoverable prior files. See #38. |
| 10 | Encrypted/split/verified packing stress | Bounded native pack/reopen/recovery checks passed; the historical SIGTERM needs an extended repetition campaign. |
| 11 | Quick Look after clean installation/update | Correct 0.1.3 plugin path is registered; clean-account install/update behavior remains unverified. |
| 12 | Large archives and disk pressure | Native 2.2 GB Store ZIP round trip and low-space EXT-130 recovery passed. Broader ZIP64, repeated pressure and private-copy exhaustion remain. |
| 13 | SMB/NAS and real iCloud | No suitable environment/evidence for the full open/extract/pack/rename matrix. |
| 14 | Wider archive corpus | Real WeChat single RAR passed; split RAR5 samples were prepared and CLI-checked, not accepted through the signed UI. SFX, legacy encodings and cross-platform corpus remain. |
| 15 | Keyboard and display preferences | Basic keyboard/undo and bounded native walkthroughs passed; full keyboard-navigation-on focus, Pack keyboard and real Reduce Motion/Transparency/Increase Contrast checks remain. VoiceOver/#93 are deferred, not passed. |
| 16 | Physical Intel and macOS 26 | Universal 2 CI passes; x86_64 7zz exits 132 under Rosetta (#144). Physical Intel/macOS 26 remain unverified; Intel/Rosetta investigation is deferred. |
| 17 | Signed release / Gatekeeper / App Group | Installed 0.1.3 passed complete notarized-bundle verification with zero problems. Clean-Mac/account behavior and signed post-#266 runtime acceptance remain #32/#38/#212. |
| 18 | Fuzzing | Bounded deterministic malformed-archive CI is implemented and passing. Extended multi-hour / coverage-guided campaigns are separate unfinished scope. |
| 19 | Website browser/device matrix | Safari/Firefox and real-phone acceptance remain beyond prior desktop-engine/mobile-emulation evidence. |
| 20 | CI | #266 passed 655 local tests, no failures/skips, 1,202 translated strings, generated-plist consistency and build-test/Universal 2/snapshot CI. |
| 21 | Sparkle update between published releases | Releases through v0.1.3 and appcasts exist. Actual download/install, busy-task deferral and relaunch remain unverified; a version already being installed does not establish how it was updated. |

## Long-term candidates — revisit on demand

[**Extensible Actions / Shortcuts / optional plugin ecosystem — #268**](https://github.com/Beastry/stow/issues/268).
The user confirmed this as long-term planning, not immediate implementation or a 1.0 gate.
Possible stages are useful built-in actions, user-configured actions / Shortcuts integration,
a bounded extension interface, and only then a shareable action library or marketplace if
usage warrants it. No runtime, SDK, distribution scheme, schedule or marketplace commitment
has been chosen. Revisit after concrete repeated workflows or developer demand establish a need.
Keep Actions contextual and compact; preserve Stow's archive-write, cancellation and cleanup
contracts. Codex owns functional/security contracts; Claude Code owns visual/motion treatment.
