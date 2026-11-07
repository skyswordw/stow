# Issue #161 keyboard acceptance — 2026-11-06

Baseline: `8418e01` (same tree as main `432d994`), isolated `app.stow.DraftReview` app. macOS Keyboard navigation was initially off, enabled through System Settings for testing. No Finder/Quick Look extensions were registered. Synthetic demo data is explicitly distinguished from the subsequent real-file check.

## Reproduced

- Welcome / `recents`: actual Tab input reached the sixth Recent row (Kickoff Deck.zip); AX reported that row focused while the scroll position stayed at zero and no focused row was visible. The fifth row was also behind the fade.
- Pack / password + expanded More Options: actual Tab input reached Password, Suggest, confirmation and Review names without bringing them into view. Independently, the native sheet retained a 580 x 438 frame after SwiftUI content and min/max constraints grew to 580 x 895. Both the fixed sentence and footer could be clipped; scrolling alone cannot repair this.

## Corrected finding

The Glance notice is not ordered after the bottom controls. A cold launch already focuses the notice, so a trace that starts *after* the first Tab records navigation first and the notice at the wraparound. On the unmodified baseline, Space before any Tab expands the notice; Tab moves to Back; Shift-Tab returns to the notice. No Glance production change is needed. Earlier claims that this observation establishes a Tab-order defect are superseded.

## Functional change

Opt-in scroll regions reveal focused controls outside their visible area, allowing room for edge fades and using immediate scrolling. The existing focus binding is reused for password fields and custom focus rings. Pack's measured, screen-bounded content size is applied to its native window as an absolute size, preventing the stale initial frame from clipping fixed controls.

Claude Code owns visual/motion treatment; Codex owns focus, scrolling, window sizing and regression checks. No new visual approval is claimed. This is keyboard and AX-assisted functional testing, not VoiceOver acceptance; #93 remains deferred.

## Native checks completed

- Recent: six forward Tab stops and reverse traversal back to the first row. The last row and its ring become visible; reverse traversal scrolls back up.
- Pack: password, Suggest, confirmation, Show password, Review names, More Options, Format, For, Password mode, Compression, Split, Verify, Encrypt file names, Mac support files and CPU controls are reachable. The scrolling region follows focus. CPU menu opens with Space and dismisses with Escape. Reverse traversal returns to Password and typing works. The fixed sentence, Save as, Cancel and Pack controls remain visible.
- Glance: baseline Space / Tab / Shift-Tab establishes notice-before-navigation order as described above.

## Automated checks

- Full suite: 713 tests in 106 suites passed, zero failures/skips.
- Simplified Chinese: 1,276/1,276 strings translated.
- Final focused suite: 3 tests passed, including the additional measured-window sizing/stability regression (the prior full run contains the first two focus tests).
- Real inputs were granted through the native Add Files picker: three text files, 67 bytes total. Password mismatch disabled Pack; correcting confirmation enabled it. Cancelling the destination picker preserved the password, name and verification choice. Creating an AES ZIP with verification succeeded and opened it in Browser. Independent 7-Zip integrity and extraction checks passed, all three extracted hashes matched the originals (with the intentional Windows rename `report?.txt` → `report-.txt`), and every source hash remained unchanged. Temporary evidence: `/tmp/stow-focus-161/fixtures/verified.json`.

Human acceptance remains pending. #161's broader Actions packaged-build matrix and #104's real system display-preference matrix are not claimed complete by these bounded keyboard checks.

## Pack human feedback and correction

The user passed the Recent-list check but rejected Pack: focus appeared to remain on one large More Options rectangle. The earlier Pack acceptance statement was incomplete: AX confirmed the active child, but the custom ring on the whole DisclosureGroup disabled native focus effects on its descendants and painted the whole expanded group. That visual focus failure is functional and must be fixed before acceptance.

More Options and Review names now keep the native disclosure header and its custom ring separate from the expanded controls. The children retain their native focus rings. Native rechecking in zh-Hans/dark mode confirmed individual Format and CPU picker rings, forward/reverse traversal with scroll following, collapse skipping hidden controls, and the independent focus ring of a renamed-file input. The corrected code passed the full local suite: 714 tests, zero failures/skips. No new human Pack acceptance is claimed yet. Claude Code retains visual/motion review of the disclosure composition.

## CPU selector proposal — not yet a confirmed redesign

The user questioned the long per-core menu on high-core-count machines and suggested numeric entry. Recommended interaction: retain an explicit inherited/default mode (normally all cores, but accurately show an existing global CPU limit) and offer a custom integer field, optionally with a stepper. Show the number of available logical processors; accept 1 through the available count. Do not label logical processors as physical cores, silently overwrite global Settings, or convert an empty/invalid partial edit into an unintended execution limit. Preserve the existing saved-value and effective-limit contracts and the warning that some formats cannot use all cores. Claude Code owns composition and copy treatment; Codex owns parsing, validation, state and engine limits. This proposal is recorded for discussion; no CPU control change or visual approval is included in this fix.
