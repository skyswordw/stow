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
