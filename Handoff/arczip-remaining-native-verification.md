# Remaining native parity verification — 2026-10-23

## Build identity and scope

Apple silicon, macOS 27.2 (26B118). ArcZip 1.1.4 (255), Pro Trial active. The published
`/Applications/Stow.app` remains 0.1.1 (279); Finder and Quick Look registration still points
there. The runs below used separately named exact CI artifacts, not that older installation.
Each downloaded app passed deep/strict signature validation before use.

- Baseline main `9b792dd353c76695d024566b7f09003cb7612fbc`, successful CI 40063471966,
  `/tmp/stow-remaining-ci-9b792dd/Stow.app`. Earlier install trials used a local exact-main
  Debug copy; do not conflate the two.
- Split candidate `a1cb74662d787ce310ef99b5f7d29dbdb9930158`, CI 40066589291.
- Undo candidates `b005185eb61c91cd30768d9f4cb373c988827cc5` (40065492671) and
  `b7fd460049460ab3235ca52c98fd34d163c1325e` (40067270633).
- Installation fix `cc68d23990e0b718f0a63877e6a2a087e46afdf8`, CI 40068677669,
  `/tmp/stow-pr134-cc68d23/Stow.app`. Merged in #134 after all required checks passed.

- Final combined candidate `b79b5d443f68c2a387a960cb755a49782f64b667`, CI 40070706382:
  421 tests / 72 suites, zero failures/skips, 0 missing / 955 translations, Universal2 and
  snapshots. Its native Save Copy / window URL / search interaction passed together.
- Main after functional merges: `ec376533081e16e370db0962afe0836467a3fff2`.

Native operation used Computer Use. Shell checks generated original test fixtures and
independently validated archives, signatures, modes, hashes and cleanup; they did not drive UI.
No competitor code was decompiled. This is additional evidence, not a full hardware/release
certification or a claim that all ArcZip Pro behavior matches.

## Verified installation behavior

All app/font choices used picker-selected scratch destinations. The PKG was generated for
current-user-only installation and contained only a text payload, no scripts or executables.

| Flow | Native result and independent evidence |
| --- | --- |
| App signature cancel / retry | Cancel left no installed output or staging. Install Anyway placed the generated v1 app with exact executable bytes and a valid seal. It launched normally, contradicting the old categorical Gatekeeper warning (#132). |
| App already running | Refusal preserved the installed version. Baseline appended misleading archive-damage advice (#133). Glance in the exact #134 Release app now offers quit/retry guidance, confirms unchanged installation and reports INS-181. |
| App duplicate decisions | Cancel preserved v1. Keep Both installed numbered v2 beside it. Replace installed v2 with a valid signature and preserved v1 in Trash. No hidden staging remained. |
| Fonts | Valid TTF bytes installed exactly; unsupported WOFF2 was counted and omitted. Duplicate Skip left bytes unchanged; Replace preserved the prior copy in Trash. No real `~/Library/Fonts` file was installed or activated. |
| PKG handoff | Stow staged the generated package and opened Apple Installer. Installer explicitly selected the home-only domain and completed without administrator authentication. Exact payload appeared only in its dedicated user-home folder; system `/Library` was untouched. After Installer quit, Stow removed its handoff staging. The test payload folder was moved back to scratch after validation. |

#134 fixes facts and recovery, not visual design. The separate full Browser AX recursion
still reproduces: opening its failed-install state from Glance and reading AX crashed the
exact Release artifact. `Stow-2026-10-23-201526.ips` reports main-thread SIGSEGV, stack overflow,
and repeated `AccessibilityNode.accessibilityLabel` / `labelExposedAs`; its Stow arm64 image
UUID `5677883F-466F-3B61-A9B1-185855A4DF00` matches that artifact. The earlier exact-main Debug
reproduction is `Stow-2026-10-23-185822.ips`. Evidence is in #93. Mouse-only causality is not
established. The partial #126 change does not justify closing #93.

## Verified compression and split reopening

Original inputs included repeated text, random bytes, an NFD filename, a 0755 script, a
relative symlink and a synthetic `Thumbs.db`. The source `.DS_Store` was absent when checked;
its earlier disappearance was not attributed to either product.

- Macs / ZIP / Smallest / Verify: native completion said tested. CRC and regular-file bytes
  matched; NFD name, symlink target, script permission and AppleDouble metadata were retained.
- Linux: TAR, TAR.GZ, TAR.XZ, TAR.BZ2 and TAR.ZST all completed with native verification. System
  tar independently read all outputs. Text and random bytes matched; symlink and 0755 mode
  survived; the helper was omitted as the preset described.
- Windows ZIP: Store, Fastest, Fast, Balanced, Maximum and Smallest all completed with native
  verification and independent CRC/byte checks. Store used method 0; the other outputs used
  Deflate. Identical sizes on this fixture do not establish a compression-ratio benchmark.
  The helper and symlink were omitted as disclosed.
- Windows 7Z / Balanced: native verification and independent pinned-7-Zip integrity test passed.
- Web / ZIP: native verification and independent exact-byte checks passed; helper/link filtering
  matched its compatibility explanation.
- Macs / DMG: system checksum validation and read-only mount passed. Mounted regular files
  matched input bytes; symlink and the helper were present. The image was detached afterward.
- Restored compression levels to Balanced for Macs and Windows, audience to Windows PCs and
  global Verify to off through a completed final pack. Linux level was never changed.

For #125, fresh 105,000,000-byte fixtures were created with pinned 7-Zip, split into
100,000,000-byte parts. Native opening is distinct from native creation:

- First-volume opening requested only the containing scratch folder. Cancel returned cleanly.
- Encrypted-filename 7Z: password Cancel and retry worked without Keychain saving. Extraction
  matched SHA-256 `06a9a5396694d3086c1be563afb41e352916564acb19ddae8ecee96c956263dc`.
- Missing tail volume produced the explicit all-parts advice and OPN-102. Restoring the tail
  allowed a successful password prompt and unlock.
- Ordinary split ZIP opened and extracted with the same exact SHA-256.

#125 was independently merged while verification ran; the evidence is posted on that PR.
Split 7Z still appears as ZIP in Welcome Recents despite correct Browser identification (#138).

ArcZip's ordinary ZIP / 100 MB split creation failed with the same temporary-volume ownership
error as its previously tested encrypted 7Z split. Neither attempt left a final or partial
output. These are limitations of the reference app, not Stow defects.

## Editing and Tray

Stow native Rename / Add Files / Replace / Delete staged four operations without changing
the original ZIP hash. Save succeeded. Independent CRC, exact replacement and retained-file
bytes, expected deletion and empty-directory preservation all passed. Replacement preview
showed the actual replacement text before saving.

An external writer added a generated marker. Stow detected the disk change, retained its
projection and replaced Save with Reload / Save a Copy. Cancelling Save Copy retained the
plan. Saving to a new file then failed with “replacement folder unavailable; save a copy
instead” (#137). The externally modified original hash was unchanged. Deliberate Reload
adopted the disk contents and dropped the staged projection.

Undo is still unresolved (#113). Both exact #124 candidate artifacts showed disabled Undo /
Redo after a staged rename. The latest candidate was also tested after Finder activation and
a clean Reload. Cancelling the native menu via its exposed Cancel action, then Command-Z,
left the renamed file and one unsaved change visible. No text field was active. #124 was
independently merged during testing; #113 was reopened with the newer evidence. Revert works.

ArcZip native Delete / Undo Delete / Redo Delete / Save passed; independent ZIP checks found
the selected file removed and all retained content exact. Its existing rename/undo/redo/save
pass is recorded in the preceding Pro report. A human-assisted drag added `Added.txt` to a
scratch encrypted ZIP; Save retained encryption on both entries. The actual destination was
that encrypted ZIP, not the originally suggested EditArc.zip, so no different-target claim is
made. Existing-archive replacement and broader failure/cancel behavior remain reference gaps.

Stow Tray Add Files collected a real 38-byte file, displayed its size/count, and packed it to
a ZIP whose bytes matched. The initially selected scratch folder was removed before this
check. Collection was cleared when the test process exited. Drag-in/out and duplicate drag
behavior are not counted as passed: Computer Use drag also failed to move a file within
Finder, so product failure could not be inferred. ArcZip Box processing still needs an actual
successful drag. Its prior pin/empty-state check is not full parity.

## Follow-up fixes and supplemental acceptance

The findings above retain their baseline evidence. Subsequent fixes were separately verified
and merged:

- [#134](https://github.com/skyswordw/stow/pull/134): conditional signature warnings and typed
  running-app recovery, closing #132 / #133. Exact CI Release native verification passed;
  413 tests / 72 suites, localization, Universal2 and snapshots passed.
- [#141](https://github.com/skyswordw/stow/pull/141): new Save Copy destinations use the existing
  parent to validate same-volume private staging. No parent grant or entitlement expansion.
  Exact Release head `9297c3f` from CI 40070128315 saved a new, precisely named copy after an
  external change. CRC/contents/empty folder/external marker passed, original hash unchanged,
  no sibling leftovers. A 16-test local Editing session run included a non-writable-parent
  regression. #137 is closed by this verified fix.
- [#142](https://github.com/skyswordw/stow/pull/142): Recents infers the supported split base
  name, with a truthful generic fallback. Native Welcome labels both known.7z.001 entries
  as 7Z and plain.zip.001 as ZIP. Existing badge treatment is reused; no visual redesign.
- [#135](https://github.com/skyswordw/stow/pull/135): Save A → Open B now exposes B's native
  representedURL; Glance preserves it and a no-source sample clears it. The final combined
  packaged app also saved a new copy, adopted its URL, then opened another archive with the
  correct URL. Independent saved bytes and source preservation passed. #130 is closed.
- [#136](https://github.com/skyswordw/stow/pull/136): native search now discloses one skipped
  locked inner archive alongside an ordinary result. Expanding names the password requirement;
  Locate selects without opening/unlocking. Zero results retain the disclosure and limited
  search wording. No background password prompt or locked inner filename leak. #131 is closed.
  Claude Code still owns visual/selection-scope review under #104: after Locate followed by a
  zero-match query, inspector / Next Steps retains the prior selection.

Additional native checks on the combined/source-equivalent artifacts:

- Explicitly selecting Thumbs.db after Show macOS Helper Items extracted only that file, with
  exact bytes (#121 / #109). The setting was restored. Checkup still claims those now-visible
  items are hidden and will not extract; [#143](https://github.com/skyswordw/stow/issues/143)
  records this copy/state brief for Claude Code.
- A 34,972-byte TAR.GZ correctly reports about 35 kB packed, 573 kB unpacked and 94% smaller;
  independent system-tar content checks had already passed (#122 / #115).
- A generated quarantine-marked ZIP underwent real native Extract All. Top-level and nested
  regular files had exact bytes and com.apple.quarantine on output. This is metadata propagation,
  not a production Gatekeeper/notarization pass or a claim of identical raw flag bytes.
- A dedicated 64 MB APFS image safely exercised insufficient space for a 105 MB input. Glance
  showed EXT-130 / Choose Another Folder. Choosing another scratch folder succeeded, with the
  exact input SHA-256. The small volume remained empty and was detached. Full Browser AX
  observation of its error state hit #93 again (`Stow-2026-10-23-203853.ips`).
- Native Windows ZIP / Store / Verify packing, reopening and extraction of a 2,200,000,001-byte
  sparse original passed. The 2,200,000,163-byte archive passed independent streaming CRC and
  full SHA-256; the extracted file also matched
  `81d6eae98077f8edd64f28cccd963d3f3976df02c49e098497b822acbef79e6b`.
  No hidden pack-output leftovers. This is an integrity/size-boundary check, not a compression
  benchmark, ZIP64-above-4-GB check, or peak-memory measurement.
- Native output-name collision Cancel preserved the first archive with no extra output; Keep
  Both wrote revision two under the displayed numbered name; Replace wrote revision three and
  left the original archive in Trash with its exact prior hash. Windows Balanced / Verify off
  and the original audience were retained after these checks.

Manual workflow dispatch [40069399962](https://github.com/skyswordw/stow/actions/runs/40069399962)
ran the optional x86_64/Rosetta XCTest suite: 413 passed, zero failures/skips. The separate
explicit x86_64 bundled-7zz smoke commands all exited 132, even `7zz i`. Overall green CI
cannot override those informational failures; the architecture of every spawned engine/tool
was not established by XCTest success. The cause and physical Intel behavior remain unresolved
in [#144](https://github.com/skyswordw/stow/issues/144) and #38 item 16.

## Remaining limits

| Remaining check | Concrete limitation / next environment |
| --- | --- |
| Hover timing / warmed neighboring previews / high-resolution behavior | Current Computer Use API has no documented hover/move primitive; selection preview is not a hover test. Needs real pointer interaction and timing evidence. |
| Cross-app drag-out, duplicates, Box processing | Automated drag failed its within-Finder control. One assisted drag is insufficient for the full matrix. Needs reliable real gestures. |
| Signed Finder, Services, Quick Look, Sparkle and clean install/update | Registered extensions still belong to published 0.1.1 (279); only Apple Development identity is available, no Developer ID. No production signature/notarization claim. See #32 / #38. |
| macOS 26, physical Intel, clean account and SMB/NAS/iCloud | No matching hardware/account/volume environment established; no available VM runtime found. Rosetta is supplemental, not native Intel evidence. |
| Real global font activation and quarantined downloaded apps | Scratch copy/replace was tested; no global font activation, quarantine removal or Gatekeeper bypass was performed. |
| IME composition, full VoiceOver and accessibility/display preferences | Basic password entry and AX paths were exercised; these broader human workflows remain pending. #93 is a confirmed blocker. |
| Extended large/archive stress and real-world corpus | A 2.2 GB native round trip and isolated low-space recovery passed; repeated pressure, larger ZIP64 archives and real-world corpora remain beyond this run. |

Bounded malformed-archive fuzzing already exists and passed in the full local/CI suites; the
old #38 wording “not started” is stale. Long-running fuzz campaigns remain a separate scope.

## Ownership and cleanup

Codex and Grok Bot own functional behavior, state, sandbox boundaries, errors, tests and
accessibility semantics. Claude Code owns layout, hierarchy, materials, icons and motion
under #104. The installation recovery and new Save Copy failure need accurate guidance and
stable controls; this report does not claim visual approval or dispatch of a Claude session.

Only generated fixtures and scratch outputs were edited. Recoverable replaced test app/font
copies remain in Trash. Generated app processes were stopped; no user application was quit
for replacement. Package handoff staging and its dedicated user-home payload were cleaned;
real Applications/Fonts and system Library were not modified by these install trials.
