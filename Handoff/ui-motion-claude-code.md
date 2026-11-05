# UI and motion handoff — Claude Code

## Tray, creation and entry-point functional handoff — #286

The [functional implementation brief](286-functional-followups.md) records the new interfaces and bounded
native evidence for #287–#294. Tray gains a master switch and optional residency; the user
reconfirmed outside-click dismissal without an idle timer. Welcome exposes Open/Create/Settings;
New/Create opens an editable draft sharing Pack internals, while gathered inputs keep quick Pack.
Sample leaves production bundles and becomes an explicit browser download. Search gains a
separate Close action. These changes supersede primary Welcome sample placement and mandatory
production bundling; they do not require copying ArcZip's visual composition.

Claude Code owns final visual treatment and motion. The draft workspace, settings form and
functional controls are implementation scaffolding, not approved visual designs. Preserve the
state/routing/close/undo/security contracts in the brief; the Pack sentence is not a required
composition for the new draft workflow. See #286 for task dependencies and #38 for remaining
physical-input/signed-integration checks. No collaborator session or visual acceptance is claimed.

The user has explicitly assigned UI visual design and animation to **Claude Code**.
Codex supplies interaction intent and functional constraints. The proposals below are
starting points for Claude Code's judgment, not approved final visual designs.

The [Tray cross-display verification](tray-cross-display-verification.md) records
that #189 supersedes the cross-display finding from #187: activation now follows
the Tray's actual home, and another display's edge does not open a remote panel.
Codex verified the original native reproduction and the actual-home drop path;
Claude Code retains visual and motion ownership.

This document records a handoff; it does not mean a Claude Code session has been dispatched.
Track the design work in [issue #104](https://github.com/skyswordw/stow/issues/104).

## Tray Keep Open and outside dismissal — 2026-11-04

Track the UI/motion work in [#282](https://github.com/Beastry/stow/issues/282).
Follow the [current Tray brief](tray-keep-open-2026-11-04.md). The user accepted
outside-click dismissal when unpinned and persistent display when pinned, replacing
idle dismissal. Preserve drag reveal and explicit close, and protect related dialogs,
previews, drafts and ongoing work. ArcZip 1.2.1 still exposes an idle countdown and
Keep Box Open; the brief records the native evidence and its limits separately from
Stow's accepted direction.

Codex / Grok Bot owns state/event handling, preferences, localization, keyboard and
accessibility semantics, and functional tests. Claude Code owns pin-state treatment,
control composition, materials and motion. Existing controls provide the functional
baseline; proposed visual ideas are optional. The functional implementation is now in
the local working tree, with validation recorded in the brief. Claude Code visual/motion
review remains pending; no collaborator session has been dispatched.

## Password-card and Actions command contracts — #261, #161

Glance's password card blocks archive menu commands as well as controls behind it. Menu
handlers recheck the current question when dispatched; Extract All and selected extraction
also reject direct dispatch while it is pending. Password-field typing undo remains local
to the field. Close remains available and cancels Glance's current question before hiding
the retained window. A hidden Glance cannot present or cancel the full Browser's question.

Quick Look progress callbacks belong to the request that created them; cancelled or replaced
requests cannot advance a newer preview. Actions menu ordering observes the same stored
suggestion preferences as the on-screen stack, so changing Settings takes effect immediately.

Codex owns these functional safeguards and regression tests. Claude Code retains the password
card, lock, progress capsule and Actions visual/motion treatment. Dedicated VoiceOver remains
deferred under #93; native display-preference and release-matrix checks remain under #38.

## Columns-to-Glance selection scope — #160

Claude Code's acceptance report on #160 identified a functional mismatch: after Left in
Columns, the current folder itself is selected in the preceding column. Glance then showed
its contents while Extract acted on the invisible folder. This report is independent of
#254's visual changes; the broader Browser acceptance issue remains open.

Codex's correction preserves the selected object and reveals its row in Glance's parent
list. Returning to Columns opens the currently selected folder, without restoring an old
selection over navigation, edits or search performed in Glance. Ordinary file selections,
multiple selections, search results, nested archive levels and Back/Forward history are
preserved. No Browser view preference changes and no archive operation runs during transfer.

This is a functional scope correction, not a new visual composition or motion direction.
Claude Code retains visual/motion ownership. Dedicated VoiceOver validation remains deferred
under #93; this change does not close the residual native QA work tracked in #38.

## Extract All menu access — #248, #249

The user confirmed #248's one-extraction-button rule for Glance. File › Extract All
(⇧⌘E), next to File › Extract (⌘E), provides archive-wide extraction without clearing
the selection. It uses the same operation and loading/running-step restrictions as the
Extract All button. It targets the key Browser or Glance window, including while editing
text there; Settings, Tray, other windows and modal sheets cannot extract a background archive.

Codex owns the command routing, availability and tests. Claude Code retains review of the
menu title and placement; no visual approval is claimed. The Glance bottom bar and its
motion remain as implemented in #248. Dedicated VoiceOver validation remains deferred (#93).

## Browser floating-path direction — #242 (2026-10-31)

The user selected the floating-path Browser: path capsule over the files, Glance · Extract All
and Actions floating along the bottom, fixed Details, and the title bar's controls grouped at
the trailing edge as Search → view modes → Delete · Save, with Search opening leftward. Save is
an arrow into a box; extraction uses a box with an upward arrow; corners are one concentric system.
Claude Code's implementation and the exact rules are in [DESIGN.md › Browser layout](../DESIGN.md).
This supersedes #231's centered Search (PR #241) and its handoff text below; the plain path-row and
bottom-path alternatives are rejected. Functional contracts (Search/Esc/⌘F, Save flow and enabled
states, Actions stack, installs and signature checks) are unchanged; see the PR for any
behavior notes.

## Browser toolbar follow-up — #215, #216 (2026-10-27)

The [native toolbar comparison](browser-toolbar-search-editing.md) records the user's request
to move Search above the path and improve Delete/Save discoverability. It supersedes earlier
instructions requiring Search beside the breadcrumbs. Search moves into the upper toolbar;
a stable Delete/Save entry is the recommended editing direction. The exact composition and
pending-changes-bar treatment remain Claude Code's responsibility. Preserve fixed Details,
floating Actions, staged edits, source preservation, save/conflict recovery and keyboard routing.
PR #222 delivered the toolbar controls and system toolbar search. Its documented behavior change
is that Escape clears Search and returns keyboard focus to the files in one step. The
[2026-10-31 functional verification](open-issue-verification-2026-10-31.md) records current-main
search, command routing, staged Delete/Undo/Redo/Save and Browser/Glance checks. Claude Code
retains visual/motion ownership; this functional verification is not a new visual approval.

## Source authorization window ownership — #213 (2026-10-31)

The recovery picker previously attached to any key non-panel window, including Settings. It now
uses a visible Browser, Welcome or Glance window that has no attached sheet. A focused archive
window takes precedence; otherwise Glance, Browser, then Welcome are preferred. Hidden windows,
unrelated windows and sheets cannot own it; with no eligible host it opens independently.

Codex owns this routing correction and its regression tests. Scope validation, explicit Allow,
verified reads, persistence and cancellation retain their existing contracts. Claude Code owns
presentation and motion. Real WeChat/signed-build acceptance remains #212; the optional
nonmodal persistence-warning proposal in PR #223 is not implemented by this change.

## Functional clarity implementation — 2026-10-31

Read the [implementation handoff](clarity-functional-implementation.md) for #229/#230/#232–#234
and the functional/copy portions of #153/#161/#162. The user authorized Codex to implement all
independently actionable findings. The prior permanent-Checkup requirement is superseded; the
central-search toolbar composition once kept in #231 is superseded by #242. New result/disclosure controls
use existing native styles and still need Claude Code's visual review. No active assignment or
visual acceptance is claimed. The [audit](product-clarity-audit-2026-10-31.md) distinguishes
source findings from native evidence and links the published issues.

## Browser window close and Dock reopen — 2026-10-28

Codex owns this lifecycle correction; Claude Code retains visual and motion ownership.
No animation timing or material changes, or Claude Code review, are claimed.

The installed Stow 0.1.2 (516) retained its BrowserModel after the Browser window closed.
Reactivation consequently restored the old archive. The user's captured frame additionally
shows Welcome briefly behind Browser. The reopen delegate both explicitly presented a window
and returned permission for AppKit's default reopen handling, leaving two presentation paths.

Closing Browser with its close button or Command-W now clears the archive after the existing
unsaved-edits gate accepts the close, cancels pending opening/unlocking, and releases the archive's
security scope. It does not automatically present Welcome while the app stays in the background.
The next reopen explicitly presents Welcome and suppresses AppKit's additional default handling.
Close Archive remains an explicit return to Welcome. Browser-to-Glance transfers must establish
Glance ownership before closing Browser, preserving the same model and editing history.

Native comparison: ArcZip 1.1.5 returns to its welcome state after closing an opened ZIP and
reactivating. Final validation uses main `9b9202a` plus this change, including the current Browser
and Glance UI and scoped source-authorization recovery. Native close-button/reactivation checks
show only Welcome; repeated opens and Browser/Glance round trips preserve the expected state.
The earlier native unsaved-rename check confirmed Cancel retains edits and Don't Save closes the
archive; the temporary rename was not saved. These are AX-assisted checks, not VoiceOver testing.

Validation: 568 tests passed with no failures or skips; all 1067 user-facing strings have Simplified
Chinese translations. The first incremental test host stalled during dynamic-library loading;
a clean build in a separate derived-data directory completed the full suite successfully.
Recordings remain local investigation artifacts; some desktop footage was occluded by other apps,
so it is not exhaustive frame-by-frame motion approval. The installed application and registered
Finder/Quick Look extensions were not replaced.

## Pack › DMG Finder layout — #85

Confirmed scope: optional Finder window layout, default off, next to the Applications shortcut.
It adds icon positions, a solid-color background and a best-effort app-derived volume icon in
staging, without attaching the image or changing sandbox entitlements. Picture backgrounds
remain excluded: DSStore documents that their Carbon Alias requires the final mounted volume.
AES (#84) remains deferred.

Functional requirements: the labeled toggle is keyboard accessible, only available for DMG,
and clears when leaving DMG or restoring purpose defaults. Pack notes explain the extras;
Browser and extraction hide them through the existing installer-extra rules. A metadata write
failure fails packing; a missing icon does not. The initial layout places the first app left,
Applications right and other visible items in a grid. This is an exploratory functional baseline,
not visual approval or a claim of observed ArcZip trigger/timing behavior. Actual ArcZip Finder
interaction comparison and macOS Finder validation remain pending.

Codex owns implementation, state, errors, security and tests. Claude Code owns the toggle's
visual treatment and generated Finder composition, spacing, color, icon sizing and motion.
No Claude Code review, acceptance or active assignment is implied.

## Current Browser direction — PR #177 review, 2026-10-24

Read the [direction reset](browser-design-direction-reset.md) first. The user explicitly
reported that Codex's prescriptive structure study pulled Claude Code away from the preferred
Liquid Glass design. The old mockups are retired as implementation/acceptance targets.

Current decisions: full Browser remains the default; Details is fixed and visible there,
without a collapse toggle. Drop the separate left navigation pane from the proposed composition
and preserve folder/history/search tasks through other controls. Floating Actions remains;
remove its repeated selected-filename/size summary beside Quick Look. The user's ArcZip action
stack crops are direct reference evidence for the next iteration, with trigger/timing still
to be checked. Claude Code owns the composition, materials and motion; Codex / Grok Bot owns
functional semantics. This changes the brief, not the app implementation.

## Earlier product-wide audit — superseded composition

The [product design review](product-design-review-2026-10-24.md) adds native ArcZip/Stow
evidence, proposed panel/action responsibilities, a state matrix and a sequenced issue map.
The user confirmed the full Browser as the default and **Actions** as the English public
name for Next Steps, and subsequently confirmed floating Actions. They requested a lighter
Browser composition: optional folder navigation and preview should give the file list more
space, using ArcZip as the structural reference (#160). Those optional-pane proposals have now
been superseded by the current direction above.
The running baseline still uses the old name; #161 tracks the transition.
“快捷操作” remains a proposed Chinese localization. Claude Code owns final visual/motion
treatment; Codex / Grok Bot owns functional review. No new Claude session is implied.

Focused briefs: [Browser #160](https://github.com/skyswordw/stow/issues/160),
[Actions #161](https://github.com/skyswordw/stow/issues/161),
[Settings #162](https://github.com/skyswordw/stow/issues/162),
[Glance #159](https://github.com/skyswordw/stow/issues/159), and
[Pack #153](https://github.com/skyswordw/stow/issues/153). Coordinate existing Tray/install
PR #154 and Pack PR #155 rather than restarting those implementations. Historical references
to Next Steps below describe the baseline, not a second product feature.

## Starting point

Use [DESIGN.md](../DESIGN.md): native SwiftUI/AppKit, content before chrome, Liquid Glass
for a coherent interface, a restrained amber accent, semantic status with words and icons,
and Stow's own Browser / Glance / Actions vocabulary. ArcZip is the interaction and visual
completion reference. Observe its actual behavior and the user's reference details; Claude
Code should exercise visual judgment instead of reproducing Codex's structural sketches.

Functional changes already merged:

- [PR #100](https://github.com/skyswordw/stow/pull/100): website says “Made for Mac.
  Designed with Liquid Glass.” The actual minimum remains macOS 26+.
- [PR #101](https://github.com/skyswordw/stow/pull/101): accurate encryption labels,
  compression display, settings accessibility, language guidance, and scrolling.
- [PR #103](https://github.com/skyswordw/stow/pull/103): explicit archive password entry,
  verified unlock, password-aware previews, retry, and cancellation.

These merges establish behavior, not Claude Code approval of their appearance or motion.
The latest published installation is 0.1.1 (279); these changes are on main after that
release. Before visual comparison, build current main, confirm the running app's path and
build identity, and record the commit and comparison-app version. The latest [remaining native audit](arczip-remaining-native-verification.md) now records
exact-build installation, editing, compression and recovery checks. Screenshots from CI remain
separate from that interaction evidence. #93 remains open; the functional Undo repair for
#113 follows #124 in [PR #149](https://github.com/skyswordw/stow/pull/149) and the
[undo handoff](113-staged-rename-undo.md). It introduces no visual or motion treatment.

## 1. Make encryption discoverable without blocking browsing

**Intent:** someone who can see filenames should still understand that file contents need
a password, where to enter it, and whether a read has actually succeeded.

ArcZip 1.1.4 (255) lists filenames from an ordinary encrypted ZIP before password entry
and offers a clickable title-bar lock. That is consistent with ZIP headers being public.
Stow should keep useful browsing available and make the password action easy to discover.

| State | Interaction contract | Visual question for Claude Code |
| --- | --- | --- |
| Encrypted contents, no usable password | A labelled lock action opens password entry; public filenames remain browsable. | Make the lock discoverable in Browser and compact Glance without competing with Extract. |
| Password prompt | Explain why a password is needed; permit cancel and optional Keychain saving. | Refine hierarchy, field/error placement, focus, and concise English/Chinese copy. |
| Verifying | Read an encrypted entry to verify; prevent duplicate unlock requests; allow cancellation. | Show progress with stable layout and restrained feedback. |
| Successful read | Refresh previews; reuse credentials where applicable. Current status is “Password Available”. | Convey useful progress without claiming every entry is unlocked: ZIP entries can use different passwords. |
| Wrong password or cancelled | Keep browsing state; allow retry; cancellation never saves late credentials. | Keep errors near the action and avoid success-like motion or repeated modal surprises. |
| Locked inspector preview | Offer “Enter Password…” as an explicit action. | Clarify the relationship between the preview message and toolbar lock. |

Explicit open/preview can request a password. Hover and background preview work must never
open a password prompt. A successful listing alone is not proof of successful decryption.
Do not infer AES-256 from a boolean encryption flag. Keychain storage remains opt-in;
passwords never belong in command arguments or logs.

Relevant files:

- `App/Browser/ArchiveUnlockControl.swift`, `BrowserModel.swift`, `BrowserView.swift`
- `App/Glance/GlanceView.swift`
- `App/Password/PasswordPrompt.swift`, `PasswordSheet.swift`
- `App/Preview/PreviewService.swift`, `PreviewViews.swift`, `QuickLookController.swift`
- `App/Browser/InspectorView.swift`, `SidebarView.swift`
- `Tests/PasswordTests.swift`

## 2. Make settings easy to scan and fit

**Proposal:** keep the common choice prominent, place explanations next to the choice they
explain, and let long content scroll without hiding controls. Claude Code should decide
the final grouping, density, window sizing, copy treatment, and spacing.

Review General's long per-app language guidance, Passwords with a long saved-password
list, Next Steps controls, and Integration folder grants. The current General height of
700 and Passwords height of 560 are functional accommodations, not final design targets.
Language guidance must describe the actual macOS workflow unless a working in-app picker
is implemented. Preserve explicit accessibility names/hints and keyboard access; decorative
icons must not replace control names.

Relevant files: `App/Settings/PreferenceViews.swift`, `SettingsPane.swift`,
`NextStepsSettingsView.swift`, and `App/Integration/IntegrationView.swift`.

## 3. Distinguish a sample from real archive operations

[Issue #91](https://github.com/skyswordw/stow/issues/91): the product choice is a genuine ZIP.
Try the Sample opens `Resources/Sample/Harbor Rebrand Handoff.zip` through the normal engine
(`AppState.openSample()`). Do not present `DemoScene` / `SampleArchive.make()` simulated
extraction or installs as verified release behaviour — those remain design-review only.
Screenshot/video asset retakes stay on [#69](https://github.com/skyswordw/stow/issues/69).
See `Handoff/91-real-sample-zip.md`.

## Motion intent

Follow the existing motion table in DESIGN.md. Claude Code owns animation treatment and
tuning. Preserve these interaction constraints:

- Keyboard navigation, search filtering, view changes, and keyboard-triggered show/hide
  remain immediate. Frequent selection changes should not make the interface feel delayed.
- Password verification is asynchronous feedback: it should not bounce like a direct
  manipulation or imply success before a read finishes.
- Avoid moving the lock/action target when status text or progress changes.
- Hover preview keeps its deliberate first delay and immediate warmed-neighbor behavior.
- Respect Reduced Motion and Reduced Transparency; retain understandable status and focus
  when animation or glass is absent.

## Review and delivery

Include before/after evidence in the design PR, explain the hierarchy and motion choices,
and link the functional issues/PRs above. Check English and Simplified Chinese, light and
dark appearances, compact Glance and small windows, long filenames/password lists,
keyboard focus, Reduced Motion, and Reduced Transparency. Preserve meaningful accessibility
labels as part of implementation.

**Confirmed priority, 2026-10-26:** dedicated VoiceOver refinement and native VoiceOver
acceptance are deferred while the core product is being completed. Missing VoiceOver validation
is not a merge or release blocker for the current milestone. This supersedes VoiceOver gates
in earlier briefs and PR checklists. Basic keyboard access, focus behavior, existing accessibility
semantics, and display/motion preferences remain functional requirements. Computer Use AX
inspection/activation is useful evidence, but must not be reported as a completed VoiceOver pass.

Exercise a real public-header encrypted ZIP, encrypted filenames, wrong password, cancel,
successful read, and mixed-password entries. Functional tests should protect state and
cancellation behavior; screenshots alone cannot prove it. The #103 baseline passed 390
tests, localization checks, Universal 2 build, packaged-app launch, and en/zh light/dark
snapshot CI; that does not establish final visual quality.

[Issue #93](https://github.com/skyswordw/stow/issues/93), an accessibility activation crash
reproduced in published 0.1.1, remains open as a low-priority, deferred investigation, not a
current milestone blocker. Do not close it on the strength of this visual review or assume #103
fixed it. If the crash is reproduced during ordinary mouse or keyboard use, prioritize that
evidence as a stability defect independently of the deferred VoiceOver work.

## Split-volume recovery (#116)

Codex owns volume discovery, descriptor assembly, password routing, errors, and tests.
Claude Code owns any subsequent visual or motion treatment of the native folder-access
prompt and recovery card (#104); no design review is claimed here.

Interaction contract: opening a Stow-created `.zip.001` or `.7z.001` discovers matching,
contiguous numbered siblings. If the sandbox cannot read the containing folder or its
parts, request explicit folder access, explaining why all parts are needed. Cancel
stops opening. Missing/inconsistent parts get OPN-102 recovery with Show in Finder:
put all parts together and reopen `.001`. Complete encrypted 7Z should reach the
existing password flow, as ArcZip does in the issue report. Preserve Stow's vocabulary,
keyboard access, and existing prompt semantics. Native ArcZip comparison remains pending.

The app assembles readable regular-file parts into an immediately unlinked temporary
file, then sends only its descriptor and the inner archive name to the sandboxed engine.
This avoids a new directory capability or XPC surface. Memory is bounded to 1 MiB;
opening, extracting, and verifying each require temporary disk space equal to the
combined archive size and an extra sequential read/write pass. Cancellation closes the
unlinked descriptor. Consider a future multi-descriptor protocol if this overhead
becomes material; do not replace it with an ambient directory grant to the engine.

## Packed size semantics (#115)

Codex owns this correction: compressed TAR and solid archives use container bytes for
root statistics; shared or unknown entry sizes display “Unavailable”, including folder
aggregates. ZIP retains per-entry packed totals. Saved statistics remain the sidebar
baseline during staged edits. No visual redesign or motion change is intended.
Claude Code retains ownership of label hierarchy and visual treatment under #104;
this functional change does not imply visual approval.

## Input-read and staged-save failures (#112, #114)

Codex owns the descriptor staging, sandbox boundaries, failure classification, and tests.
Descriptor-backed archives now materialize as real engine-private files before 7-Zip opens
them; no filesystem entitlements change. This includes nested open/search and verification
of a saved replacement. Failed saves keep the original and pending edits; Save remains the
retry control. Cancellation does not show a save-error prompt.

Input-open permission errors must explain that Stow could not read the archive (OPN-101),
without offering the destination action Choose Another Folder. The
[source-access recovery plan](source-file-access-plan.md) adds a native picker for the original
source file or its containing folder, followed by automatic retry; this is source authorization,
not a change of extraction destination. Claude Code reviews its wording and transitions in #213.
Save errors use the existing Failure prompt with
Copy Details, rather than an internal temporary pathname as the heading. Claude Code owns
visual and motion review under #104; this functional change does not imply design approval.
Compare these recovery interactions with ArcZip while retaining Stow vocabulary. Native
and packaged-XPC verification remains CI-gated because implementation ran on Linux.

## Installation refusal recovery (#132, #133)

Codex / Grok Bot owns the signature facts and typed running-app refusal. Signature warnings
must describe possible launch blocking without predicting the host's Gatekeeper decision
from signature facts alone. Running-app refusal is INS-181: ask the user to quit the installed
app and retry, explain that it was not changed, and never suggest archive damage or quit the
app automatically. Keep the existing confirmation, retry, dismiss, and Copy Details controls.
Claude Code owns visual hierarchy and motion review under #104; these functional copy/state
changes do not imply visual approval. The full Browser AX recursion remains separately open
in #93; a successful Glance recovery does not close it.

## Remaining native audit follow-ups (#143)

The [remaining verification report](arczip-remaining-native-verification.md) records additional
functional fixes and unresolved limits. In #143, showing helper items makes them visible and
explicit selection extracts them correctly, but Checkup still says they are hidden and will
not be extracted. Claude Code owns copy hierarchy and presentation: distinguish default
Extract All filtering from deliberate showing/selection. Codex / Grok Bot owns the facts and
extraction semantics; preserve explicit selection and existing safety boundaries.

Search coverage in #136 now discloses omitted inner archives and Locate avoids opening or
unlocking them. Review the retained inspector / Next Steps selection after Locate followed by
a zero-result query. These are interaction briefs, not visual approval or evidence that Claude
has started the review. #119 remains the separate visual/motion PR.

## Non-modal source bookmark notice — #253

A successful archive open whose folder bookmark cannot be saved now carries a dismissible
notice in Browser and Glance. It never uses the open-failure sheet or appears on Welcome.
Browsing and commands remain available; dismissing only removes the notice. Copy Details and
GEN-180 remain reachable. Each standardized source-folder path warns once per app session,
only after an archive opens successfully; failed or cancelled opens do not consume the warning.
The existing English and Simplified Chinese copy is retained.

Codex owns this state, diagnostic and test implementation. The view uses existing native
text and buttons as a functional baseline. Claude Code retains final visual/motion ownership;
no design acceptance is claimed. Preserve the non-modal behavior and compact Glance usability.

Claude Code's visual pass (2026-11-03) gives it the archive notices' card shape with a neutral
tint and a small × for Dismiss; see DESIGN.md › Signature details. State, copy, Copy Details,
GEN-180 and the once-per-folder rule are unchanged.

## Direct document launch and remembered window — 2026-11-02

Confirmed user feedback supersedes the earlier fixed-default opening direction: external
archive opens should enter Browser's loading/content state directly, without first flashing
Welcome. New/default installations remember the last explicitly selected Browser or Glance
across close/reopen and app restarts. The preference also permits a fixed Browser or fixed
Glance, and preserves explicitly saved legacy fixed-mode choices. Welcome remains appropriate
when launching Stow without a document or explicitly closing an archive. Snapshot runs must
not change the user's remembered choice.

Codex owns launch routing, persistence, cancellation and the regression tests. The loading
state and picker use existing native controls as functional treatment; Claude Code retains
visual/motion ownership. No visual acceptance is claimed. Pending opens and open errors belong
to Browser (or the chosen Glance); closing an obsolete Welcome must not cancel their work.

Claude Code's visual/motion pass (2026-11-02) is recorded in DESIGN.md › Browser layout › Opening
an archive and the motion table: the Browser's opening state takes the Browser's own title bar
(same height, hidden bar, the archive's name in the title menu's place), the status waits 0.4 s
before fading in (Browser and Glance), and Cancel also answers Esc. The Settings footer and the
Simplified Chinese terms (压缩包, 完整浏览器窗口) were clarified. Routing, persistence and
cancellation are unchanged.

Two actual 0.1.3 (592) crashes were symbolicated against matching release dSYMs. Browser's
editing delegates could form a forwarding cycle during key-window changes at an extraction
panel; replacement proxies now forward directly to the native delegate and stale proxies
cannot reclaim the window. Finder requested its menu on an XPC queue and tripped
MainActor.assumeIsolated; menu construction now synchronously enters main only when needed.
These are ordinary window/menu stability defects, not completion of deferred #93.
