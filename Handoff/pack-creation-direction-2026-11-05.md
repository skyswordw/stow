# Pack creation direction — 2026-11-05

This is the current user direction after hands-on testing of #295–#301. It supersedes the
separate draft Save form and compact card composition in #297, the corresponding section of
DESIGN.md, and the earlier statement that the Pack sentence was optional for draft creation.
Codex owns functional state, routing, security, errors, cancellation, localization and tests.
Claude Code owns the Browser/draft visual composition, controls, hierarchy and motion. No
Claude Code session, review or acceptance is implied by this brief.

## Confirmed user decisions and observations

- Remove Open Tray from the status-item context menu: the ordinary icon click already toggles it.
- Open Stow and Settings from that menu must immediately present and activate their destination,
  even when another app is in front. The user reported both windows appearing only after a Dock
  click or app switch. Treat this as a functional defect; earlier lifecycle checks did not test it.
- Creation should feel like the Browser workspace, rather than a second Glance-like surface.
- Use **Pack…** for creating an archive, including its configuration and edited-draft prompt.
  **Save** remains for modifying an existing archive. Command-S may keep routing to the relevant
  document operation, but its menu label must reflect the focused draft versus existing archive.
- Restore the established sentence builder as the primary packing interaction, for both a draft
  and gathered files. The separate direct form introduced by #297 displaced a valued Stow feature.
- Keep direct, efficient controls inside **More Options**, sharing the same state with the sentence.
  Advanced format choice must expose all formats the engine can create, independently of recipient
  recommendations. Do not silently change the recipient policy to accommodate a format selection.
- Add **General Sharing**. The user cited ArcZip as a reference for this purpose.
- The draft's format menu was intermittently unresponsive. Preserve a format selected in the
  workspace when opening/cancelling packing; no mandatory second choice or reset in the sheet.
- Expose recent archives and current windows through the Dock context menu, including a current
  window checkmark. Use the existing bookmark-backed history and normal guarded open routes.

## Observed ArcZip reference, separate from Stow decisions

Native CUA/AX inspection on this machine found New/Create uses the main archive workspace:
view-mode controls, Delete, Save, Search, folder navigation, a file list, Add Files and an
Inspector. After adding a task-owned text fixture, Save opened a configuration surface.
General Sharing was selected with the help “Balance Compatibility and Efficiency”; it showed
ZIP, Balanced compression and macOS auxiliary-file cleanup. Other purposes included Windows,
Macs, Linux/servers and Smallest Possible. Advanced Options exposed Mac support files and split
volumes. Several controls were Pro-gated; none were unlocked or exercised. The test draft was
cancelled/discarded without producing an archive. These observations do not prove ArcZip's
output semantics or defaults across installations. The Dock appearance is user-reported; it was
not independently inspected through the available computer-use surface.

## Functional implementation and constraints

- Menu actions leave native tracking before opening a destination. The shared presenter requests
  regular activation, waits for that specific SwiftUI scene, restores a minimized window and
  orders it key/front. If activation is still absent it uses Launch Services to activate the
  existing app instance. It never chooses an arbitrary window or starts a second process.
- The draft title menu uses direct format actions, with its current format passed into the shared
  Pack state. Restore preserves advanced choices and recipient policy across cancellation.
- The sentence's format menu keeps short recommendations plus access to More Options. The advanced
  picker exposes all creation formats. Explicit custom format selection survives recipient changes;
  selecting a recommended format returns to guided behavior. Actual engine capability constraints
  still apply (for example TAR cannot encrypt, DMG cannot split). Existing password confirmation,
  archive safety, source scopes, destination authorization and collision handling remain required.
- General Sharing starts with ordinary ZIP/balanced settings when chosen from the default state,
  uses portable names, and omits Mac helper/AppleDouble metadata unless explicitly overridden.
  Existing saved recipient preferences are preserved; this does not migrate everybody's default.
- Draft creation, quick Pack and edits remain distinct states, with one packing engine. Original
  files remain untouched, no archive is fabricated before Pack, and failure/cancel retains the draft.
- Dock menu entries use the existing recent list with missing files filtered and bookmark resolution
  on invocation. Password-prompt gates apply. Only live/minimized work windows are listed, not Tray
  or permission panels. The custom menu is available while Stow is running; system-owned recent-file
  integration when it is not running is a separate follow-up if desired.

## Claude Code visual task — #302

Unify the new-archive workspace with the current Browser's reading/work area, title bar, navigation
and Details vocabulary. The observed ArcZip consistency is the reference outcome; copying ArcZip's
colors, its obsolete Stow sidebar pattern, or the old compact draft mockup is not a requirement.
Choose the right control grouping and hierarchy for adding/removing files, naming a draft and Pack.
Keep the restored sentence primary and the direct controls inside More Options; do not reintroduce
an independent competing Save form. Ensure the title format menu is reachable and does not imply
that the user must choose a format twice. The draft must clearly identify source sizes and unsaved
state, never fabricated compressed size or encryption. Preserve the functional contracts above.

Native acceptance still needs the user's real status-item and Dock inputs from another foreground
app. CUA/AX and isolated menu/model tests must be reported separately from these pointer checks.
VoiceOver remains deferred under #93; basic keyboard/names/display preferences remain required.

## Implementation validation

The local integrated functional tree passed 692 tests in 103 suites. zh-Hans export reported
0 of 1,270 missing translations; generated plists are unchanged. The first run exposed a live
external mouse click in an existing delayed Tray state test; that one test now injects disabled
system event monitoring while production defaults remain enabled. Event-adapter tests remain.

An isolated ad-hoc build (`app.stow.EntryReview`, no Finder/Quick Look plugins) was checked through
CUA/AX: the title menu selected TAR.XZ; Pack opened the original sentence with that format and the
previous recipient unchanged; General Sharing preserved the explicit custom format; More Options
listed all eight output formats; cancellation and reopening retained both format and purpose.
A real General Sharing ZIP was created and opened in Browser, and independent ZIP reading matched
the original fixture bytes. This does not establish physical title-menu reliability under every
pointer sequence, native status-item foreground activation or the actual Dock menu rendering.
Those input paths need user retest; #290 remains open. Claude Code's Browser visual task is #302.
