# UI and motion handoff — Claude Code

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
