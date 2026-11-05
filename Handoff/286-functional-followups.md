# Functional handoff: Tray, creation and entry points

Parent plan: [#286](https://github.com/Beastry/stow/issues/286). This branch implements the
functional portions of #287–#294. It is not a release, a Claude Code visual approval, or a
claim that the complete signed/physical-input matrix has passed.

## Interfaces for Claude Code

- **Tray settings (#288):** `TrayController.isEnabled` / `setEnabled(_:)`,
  `SettingsKeys.trayEnabled` and `SettingsPane.tray` are authoritative. `TraySettingsView`
  is a minimal functional form; replace its presentation without duplicating state.
  Fresh installs start disabled. A one-time migration preserves effective prior availability
  using persisted Stow preferences/history/onboarding state, not registered defaults.
  Reset returns to disabled without remigrating. Disable preserves files/drafts/pin choice,
  stops listeners and hints, and rejects later reveal callbacks. No inactivity timer returns.
- **Dismissal (#287):** a new outside press with no other button down reconciles obsolete
  drag/drop-target state before classifying the click. This fixes the reproducible state
  sequence in which a missing drag-end callback made the first click only clear protection.
  Pin, related menus/pickers and Quick Look still protect the panel. The user's exact physical
  sequence has not been independently captured; do not claim every second-click cause is fixed.
- **Residency (#289):** `ApplicationLifecycle` coordinates window presentation, ongoing work
  and Tray enablement. Requested window handovers remain protected until their window arrives.
  With no windows/work, enabled Tray uses accessory mode; disabled Tray terminates through
  the normal delegate. Minimized windows count. Explicit Quit refuses to kill active jobs and
  retains existing unsaved-edit checks. A changed creation draft also gets Save/Discard/Cancel.
  Closing a Browser with an accepted job retains its model and source scope until it settles;
  reopening restores that job. An unacknowledged background failure remains recoverable on
  reopening instead of silently ending the process. The obsolete Hide Dock checkbox is removed;
  its stored value is not reused as a competing lifecycle preference. Login remains opt-in.
- **Status menu (#290):** normal click toggles; right/Control-click opens native Open Tray,
  Open Stow, Create Archive…, Settings…, Quit Stow. Open Tray is idempotent. Menu tracking
  is a related interaction. Settings deep-links to Tray; Quit uses `NSApp.terminate`.
- **New archive (#291/#293):** `AppState.beginNewArchive()` and `showCreationWindow` route
  Welcome, Command-N and the status menu to one `ArchiveDraft` in scene `creation`.
  Repeating New focuses the current draft without replacing it or an edited Browser archive.
  `ArchiveDraftView` is a deliberately plain functional surface, not a proposed final layout.
  Claude Code owns the empty/populated workspace, title/format editing and configuration design.
  Its window delegate must retain/forward SwiftUI's delegate and preserve close protection.
- **Draft model:** import real files/folders (including promised-file entry), retain source
  scopes, reject failed imports atomically, number colliding root names, remove selected
  subtrees, and undo/redo without changing source files. Closed drafts reject late work.
  Save refreshes URL metadata and refuses missing/changed source types instead of dropping rows.
  The planned list is not an archive on disk; do not show final compressed bytes or encryption.
- **Shared configuration:** `PackSheet(request:draft:didCreate:)` reuses the pack engine,
  compatibility, encryption/splitting, destination authorization, collision and verification
  paths. Configuration/destination cancel preserves the draft; applicable non-secret options
  remain in memory. Passwords are not persisted in the draft configuration. Failed/cancelled
  creation retains sources; successful creation opens the real output and closes the draft.
  The current sentence composition is not a constraint on Claude Code's new-draft design.
  Existing Tray/Finder/drop quick Pack stays a short path through the same engine.
- **Sample (#292):** production Release excludes `Sample` via the resource build setting;
  Debug keeps fixtures for offline tests/snapshots. The bundle verifier rejects production
  sample payloads. Download Sample… opens a browser to an existing immutable official ZIP;
  Help exposes its adjacent credits/licenses. No new network entitlement/helper is introduced,
  and no missing-bundle fallback fabricates an archive. The ZIP is pinned to main revision
  `33d533e7a74c0f6c862ce49a8d0fc72e93a71e90`, 3,420,145 bytes, SHA-256
  `ba553f99430c316d924750c5a123ce076264f2837e5e1a40d9dbe70831707ef4`.
- **Search (#294):** `ToolbarSearchField.close` clears the query, releases focus and closes
  expansion; Clear Search still clears/refocuses without closing. The capsule background,
  rather than a parent gesture, handles empty-space focusing so a close click cannot refocus.
  Keep the field explicitly named Search, the IME Escape guard, Command-F, file focus recovery,
  leftward expansion and stable trailing controls. Claude Code owns the two controls' treatment.

## Native evidence and limits

Native checks used an ad-hoc copy with bundle ID `app.stow.FunctionalQA` and no Finder/Quick Look
plugins. The installed application was not replaced and no extension registration script ran.
This is development-build evidence, not signed integration acceptance or VoiceOver testing.

Verified through CUA/AX: Welcome Create/Settings entries; fresh Tray disabled; explicit enable
and disable; enabled Tray opens from its shortcut; empty draft with Save disabled; real source
selection; Remove then Command-Z; Command-S opens configuration; cancellation preserves both
name and files; closing a changed draft offers Save/Discard/Cancel and Cancel keeps it; actual
creation of a ZIP followed by opening it in Browser. Independent ZIP reading matched the exact
37 source bytes and expected single path. Search no-result filtering, Close restoring files,
arrow-key file selection and Command-F reopening also worked. Explicit Quit ended the QA process.
A later code refinement names the search field explicitly after AX exposed an inherited button name.

The automation's background window/key state made ordinary Settings close input inconclusive;
that does not establish a working last-window/residency matrix. Still required: actual cross-app
mouse input and physical drag/end/cancellation paths for #287; real menu-bar right/Control-click;
last-window/PID/Dock transitions with Tray on/off, settings, minimized windows and jobs; full
signed Finder/Services/Quick Look launch and login behavior; actual IME composition and display
preferences. Track functional runtime checks in #38 and visual/motion work in #104 and the
individual issues. Dedicated VoiceOver remains deferred under #93.

## Validation

The final full macOS suite passed **680 tests in 102 suites**. Localization export passed with
**0 missing translations out of 1,232 strings**. Debug and Release build succeeded; the Release
bundle omits Sample, and all **12 Mach-O binaries** passed Universal 2 checking. The explicit
browser-download URL returned HTTP 200; downloaded bytes matched the pinned source ZIP's
SHA-256 above. Focused lifecycle/draft/search tests and the native evidence are complementary. Do not equate model tests with
physical input or native code-signing/integration checks. Release sample exclusion removed the
6.8 MiB fixture directory; that is not a measured DMG-download saving or a total-app-size claim.

Codex / Grok Bot owns correctness, state, security, cancellation, errors, tests and accessibility
semantics. Claude Code owns composition, typography, materials, icon treatment and motion.
No Claude account is assigned and no collaborator session or visual acceptance is claimed here.
