# Tray: Keep Open and dismissal — 2026-11-04

Claude Code UI/motion follow-up: [#282](https://github.com/Beastry/stow/issues/282).

Status: functional implementation prepared for review; validation is
recorded below. The user subsequently authorized Codex to implement its portion before
Claude Code handles the interface. No Claude Code session has been dispatched, and no
visual approval or published release is claimed.

## Confirmed user direction

- An unpinned Tray closes on an outside click, rather than an idle countdown.
- A pinned Tray stays open across outside clicks and application switches.
- Moving the pointer away alone does not close a manually opened Tray.
- Drag reveal remains available; keep Tray open throughout the drag. An unused
  drag reveal can tuck away after the drag ends. A successful drop stays visible
  until the next dismissal action, so the result can be checked.
- Explicit Close and Escape remain available while pinned. Escape first cancels
  the current nested interaction, such as folder-name entry.
- Describe the control as **Keep Tray Open / 保持打开**, not as a window-level switch.
- Remove the default 30-second idle-dismissal behavior.

These decisions supersede the idle-dismissal direction. PARITY.md and ROADMAP.md
now describe the local functional implementation; older audit evidence is historical,
not a competing requirement.

## ArcZip evidence and limits

Native inspection on 2026-11-04: installed ArcZip **1.2.1 (336)**, as shown in
Settings > About; Pro displayed Inactive. Box was initially disabled and unpinned.
It was temporarily enabled for inspection and restored to disabled and unpinned.
The inactivity setting was left unchanged.

| Evidence | Observation |
| --- | --- |
| Settings > ArcZip Box | “Hide after inactivity” displayed **3 seconds**, with a displayed range of 1–6 seconds. This is the observed preference, not a verified factory default. |
| Settings help | “Keep Box open with the pin button. Dragging and processing pause the countdown.” This establishes the documented intent; processing was not exercised. |
| Window > ArcZip Box | Opens an empty Box with separate Keep Box Open and Hide Box controls. |
| Pin activation | AX name changes from Keep Box Open (`pin`) to selected Stop Keeping Box Open (`pin.fill`). |
| Idle comparison | The pinned Box remained the observed window after an explicit wait longer than 3 seconds. After unpinning and a later observation, the observed window returned to Settings without another click. This supports timer-based dismissal, not an exact timing measurement. |
| Outside-click attempts | Clicks reached the underlying Settings window in both states. The capture then returned only Settings, so it did not independently establish whether Box remained visible elsewhere. Do not claim a verified immediate outside-dismissal rule from this result. |
| Drag reference | DESIGN.md records the earlier #180 investigation: reveal near the icon, remain during the drag, disappear after an unused drag. Those observations are historical; real drag/drop and processing were not repeated in this 1.2.1 inspection. |

These are AX-assisted control checks and window screenshots, not VoiceOver testing.
ArcZip supports the meaning “keep open,” but its idle timer is not a requirement for
Stow. The accepted outside-click rule is an intentional Stow product decision.

## Functional contract for implementation

| State or action | Observable result |
| --- | --- |
| Open manually, unpinned | Remains open while idle; outside click dismisses. Pointer exit alone does nothing. |
| Pin | Remains open across outside clicks and application switches. Does not change window level, move the panel, or clear selection. |
| Unpin | Stays visible until the next qualifying dismissal; no immediate hide or restarted countdown. |
| Drag approaches actual Tray home | Reveal without stealing keyboard focus from the source app. Preserve #189's actual-home and cross-display behavior. |
| Active drag, inbound or outbound | Never dismiss in the middle of the drag. Do not mistake its originating mouse-down for a completed outside click. |
| Drag reveal ends without a drop | Use the existing unused-drag grace initially; cancel pending dismissal when pinned, interacted with, or successfully dropped on. Claude Code owns any motion/timing refinement. |
| Drop accepted, including an existing item | Keep the receipt/duplicate feedback visible. Do not auto-pin. The next outside click dismisses if unpinned. |
| Tray-owned menu, popover, picker, sharing UI or Quick Look | Interacting with that surface is part of the Tray workflow, not an outside dismissal. Escape closes the nested surface first. |
| Outside click during folder-name entry | Preserve the unsubmitted draft across automatic dismissal/reopen. Never implicitly submit or silently discard it. Explicit Cancel/Escape retains its current cancellation meaning. |
| Close, Escape at the top level, or the Tray toggle shortcut | Hide even if pinned. Hiding does not clear collected items or cancel an accepted archive/file operation. |
| Reopen | Preserve collection and pin preference. A persisted pin preference does not itself open Tray at application launch. |

Additional engineering decisions for this brief:

- Treat an explicit application switch (for example Command-Tab) like an outside
  interaction when unpinned. Do not implement this as unconditional key-window
  resignation: owned dialogs, Quick Look and drag reveal need exclusions.
- Cover other Stow windows as well as other applications. Dismissal must not consume
  the outside click; the intended underlying control receives it normally.
- Remove the idle picker from Settings in the same functional change. Retire the
  timer and ignore legacy `tray.idleSeconds` values, including Never. Keep the pin
  preference. Document the preference migration; do not reinterpret an old timeout
  as a new pin choice or reset unrelated preferences.
- If a job continues while hidden, its completion/error remains available on reopen;
  callbacks must not unexpectedly reopen Tray or lose operation state.

## Ownership and delivery order

| Work package | Owner | Deliverable |
| --- | --- | --- |
| Dismissal state and event handling | Codex / Grok Bot | Outside interaction classification, related-surface exclusions, drag protection, race cancellation, draft preservation and operation lifetime. |
| Preferences and semantics | Codex / Grok Bot | Remove idle UI/runtime behavior; preserve compatible preferences; meaningful toggle name/state, keyboard access, English and Simplified Chinese strings. |
| Visual state and copy presentation | Claude Code | Clear pinned/unpinned feedback, appropriate help text, relationship to Close, and Settings explanation in Stow's design language. |
| Motion | Claude Code | Reveal, dismissal and receipt transitions; preserve keyboard and system motion/display preference contracts. |
| Verification | Codex / Grok Bot, followed by Claude Code visual review | Behavioral tests and native evidence first; visual/motion review against those same states. |

The functional contract is implemented with existing controls/materials, tests and
localizations. Claude Code next refines visual treatment and motion against the same states. Functional controls may ship in the implementation PR, but their visual
treatment remains pending Claude Code review. Any requested behavioral deviation must
be called out explicitly. The UI/motion work is tracked in #282. No account is assigned and no collaborator
session has been started.

Optional visual ideas, not acceptance criteria: retain a pin metaphor with a
distinguishable selected state; explain the consequence in help text; keep Close
independently discoverable. Claude Code chooses composition, color, material and
animation. No mockup fidelity requirement or forced new badge is introduced.

## Acceptance checks

Codex should cover state transitions and cancellation races with meaningful tests:
pin/unpin, outside interaction, stale drag-dismiss tasks, accepted/delayed drops,
related-surface lifetime, and preserved drafts/items/jobs. Retire timer-specific
tests rather than leaving obsolete expectations.

Native checks must cover mouse clicks in Finder and another Stow window, Command-Tab,
menu-bar toggle, keyboard opening and Escape, pin/unpin, real drag-in/out and cancelled
drags, duplicate drops, Add Files/Collect destination pickers, Quick Look and sharing,
reopen during dismissal, and actual-home behavior across displays. Check both empty
and populated Tray. Distinguish automated AX checks from actual VoiceOver testing;
full VoiceOver acceptance remains deferred under AGENTS.md (#93).

Run the repository build/test and Simplified Chinese localization checks when code
changes. Do not register extensions from a temporary validation build. Claude Code
reviews pinned/unpinned, empty/populated and related-surface states in both themes,
with Reduce Motion and Reduce Transparency. The design requirements alone are not evidence of passing implementation tests;
see the delivery and validation record below.

## Source baseline

Inspected checkout HEAD: `3e7d998`; existing local design edits were preserved.
Relevant implementation: `App/Tray/Tray.swift`, `App/Tray/TrayModel.swift`,
`App/Settings/PreferenceViews.swift`, `App/Settings/SettingsKeys.swift`,
`Tests/TrayTests.swift` and `Tests/TrayCollectionTests.swift`.
The inspected baseline used a floating, non-deactivating panel and an idle timer.
The implementation retains that window level but replaces the timer with outside
interaction handling in `App/Tray/TrayDismissal.swift`.


## Functional delivery for Claude Code

Implemented locally on 2026-11-04:

- Observe both local and other-application mouse gestures without consuming them.
  Dismiss on completed outside clicks, not mouse-down; protect drags and the
  opening gesture. Observe application activation for keyboard application switches.
- Keep the pin preference; unpin does not hide immediately. Close and the existing
  Escape/toggle behavior remain available. Remove the idle timer and Settings picker;
  ignore the obsolete preference without converting Never into an implicit pin.
- Track related panels and nested interaction tokens for Add Files, Collect destination
  and authorization, and sharing. Protect Tray-owned Quick Look, child windows and menus.
  A hidden Tray no longer closes a preview owned by an unrelated browser.
- Keep collection, selection, draft, destination, result and error state when hidden.
  Accepted operations continue. Cancelled collection authorization restores the name.
- Cancel obsolete unused-drag dismissal on interaction, pin changes, accepted duplicate
  drops and reopening. Handle local mouse releases and outbound drag completion too.
- Keep the existing control composition and motion. The Chinese toggle name is now
  “保持打开”; help and Settings explain outside-click/app-switch behavior in both languages.

Claude Code can now refine the existing toggle, Close relationship, explanatory copy
presentation and motion. Preserve the functional rules above; do not reintroduce idle
hiding or replace them with unconditional window-resign handling. Review the same
empty/populated, pinned/unpinned, picker/menu/preview and drag states. No visual approval
is implied by the functional implementation.

## Original-checkout validation record

- Standard `xcodebuild ... -derivedDataPath build build`: passed.
- Full suite on the final source: **572 tests in 87 suites passed**, zero issues.
  Used `/tmp/stow-tray-validation-20261104` for derived data and the existing
  `build/SourcePackages` checkout. Final command was `xcodebuild -project
  Stow.xcodeproj -scheme Stow -derivedDataPath /tmp/stow-tray-validation-20261104
  -clonedSourcePackagesDirPath build/SourcePackages test-without-building`, after
  compiling and passing the focused Tray suite in that directory.
- The first incremental test host stalled in dyld before executing tests; a process
  sample confirmed the loader wait. A clean derived-data directory resolved it.
  One initial event-test fixture used a deferred window without a usable event window
  number; creating the test window eagerly fixed the fixture. The final full run passed.
- `scripts/check-localizations.sh zh-Hans`: **0 missing translations of 1070 strings**.
- `git diff --check`: passed. XcodeGen was rerun for the added source/test files;
  it produced no tracked plist changes.

Native checks used the exact temporary app at
`/tmp/stow-tray-validation-20261104/Build/Products/Debug/Stow.app`; its running
executable path was checked separately from `/Applications/Stow.app`.

| Native check | Result |
| --- | --- |
| Add Files picker | Added the synthetic `tray-check.txt` fixture; returned to the unpinned Tray with one item. |
| Click another Stow window, unpinned | Coordinate click in Welcome dismissed Tray; Window menu changed to Show Tray. |
| Same click while pinned | Tray remained open; Window menu still offered Hide Tray. |
| Explicit hide while pinned | Worked; reopening retained the pin and file. |
| Unpin | Tray remained visible; toggle name/help/state matched the new semantics. |
| Collection draft | Entered a synthetic folder name, closed Tray, reopened and verified the exact draft and original file remained. Cancel then removed only the draft. |
| Quick Look | Showed the fixture's actual text; closing the preview returned to Tray with its file. |
| Share picker | Opened and cancelled without selecting a service. Afterwards a click in Welcome dismissed Tray normally, demonstrating that the interaction hold was released. |

The pin preference was restored to its initial off state, the temporary app was quit,
and the temporary Finder window was closed. The installed app was not replaced and
`scripts/register-extensions.sh` was not run. These checks use AX actions and injected
mouse/keyboard events, not VoiceOver.

Remaining native coverage: real cross-application mouse clicks, system Command-Tab,
real drag-in/out and cancellation, multiple displays, and an actual sharing-service
completion. Cross-application CUA click attempts left Tray open; its Command-Tab
injection moved in-app focus rather than demonstrating the system app switcher.
Those attempts do not establish the real system-input path, so no cross-application
native pass is claimed. The event adapter's outside/drag classification has automated
coverage, but a physical-input check is still needed alongside Claude Code's UI review.


## PR integration validation

The scoped Tray change was moved to `codex/tray-keep-open` on current main
`7fed4d3`, preserving the newer Settings organization, Tray appearance and shared
display/motion preferences. Unrelated edits in the original checkout were excluded.

- Fresh worktree `xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build
  -clonedSourcePackagesDirPath /Volumes/DataHouse/codes/projects/stow/build/SourcePackages test`: **668 tests in 100 suites passed**.
- `scripts/check-localizations.sh zh-Hans`: **0 missing translations of 1205 strings**.
- XcodeGen produced no tracked plist differences; `git diff --check` passed.
- The earlier native evidence above belongs to the original checkout. No new native
  pass is claimed for the rebased app; remaining physical-input checks stay explicit.
- Claude Code's separate UI/motion task is [#282](https://github.com/Beastry/stow/issues/282);
  the functional PR must not close it.

## Claude Code visual and motion delivery — #282

Stacked on the functional branch (`codex/tray-keep-open`); the dismissal rules above are
unchanged. DESIGN.md › Tray dismissal and › Motion describe the result.

- **Pin state by shape, not colour alone.** Back, Keep Tray Open and Close use Glance's
  circular window controls (`ActionButtonStyle`, 26 pt, hover fill). Kept open is `pin.fill`
  in the accent inside an accent ring (Glance's Pin on Top on-state); not kept open is plain
  `pin`. The symbols keep their previous positions; the header grows by about 1.5 pt.
- **Immediate feedback.** Clicking the pin shows a 2 s glass note under it: *Stays open until
  you close it* / *Hides when you click elsewhere*. It takes no clicks and is hidden from
  accessibility, because the toggle's own value already reports the change.
- **Close.** Stays beside the pin; its help now says the files stay: *Close the Tray. Its
  files stay for next time.* Its name, Escape shortcut and folder-name exception are unchanged.
- **Copy.** Help: *Keep the Tray open when you click elsewhere or switch apps* / *The Tray
  stays open until you close it*. The Settings explanation moved from a loose row into the
  Tray section's footer, like Updates. The new Chinese strings called the Tray 暂存架; they
  now use 托盘 like the rest of the app, and 点按 for click. Unused catalog entries (two from
  before this change, three from the functional PR) were removed.
- **Motion.** Pin toggle: symbol replace + ring fade, note in with `status` (4 pt drop,
  scale 0.96) and out with `exit` after 2 s; none when Space toggled it; fade only under
  Reduce Motion. Reveal, outside-click/app-switch dismissal and the drop receipt were
  reviewed and kept: the exit is already the quick 180 ms ease-out, and the 1.2 s receipt
  stays readable now that a drop no longer risks an idle hide.
- **Demo tools.** `-StowTrayPinNote kept|hides`, the `tray-folder` scene and the `tray-pin`
  burst (it restores the saved `tray.pinned` value when done).

No behaviour change to dismissal, state or semantics is proposed. Evidence was made with
design snapshots (light/dark, English/zh-Hans, empty/populated/folder, both pin states,
Stow's Increase Contrast and Reduce Transparency overrides) and frame bursts with Stow's
Reduce Motion override. The system display switches themselves were not flipped, and
menus/pickers/Quick Look/Collect draft keep the existing composition (nothing in them
changed). No VoiceOver testing (#93).
