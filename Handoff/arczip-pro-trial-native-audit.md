# ArcZip Pro trial comparison — 2026-10-23

This supplements the [free-tier audit](arczip-1.1.4-native-audit.md). The user activated the
trial before this session. ArcZip's About page showed **Trial**, version **1.1.4 (255)**.
No purchase, license change, or account credential operation was performed.

## Build identity

- Stow baseline: main **`b83de40e444804070d80b92c4be0ae4fcde30347`**, successful universal
  [CI run 40058563544](https://github.com/skyswordw/stow/actions/runs/40058563544).
  Downloaded its DMG, verified it, extracted the app, passed deep/strict code-signature
  verification, and verified the running executable at `/tmp/stow-pro-audit-b83de40/Stow.app`.
- ArcZip: `/Applications/ArcZip.app`, **1.1.4 (255)**, Pro Trial active.
- Apple silicon, **macOS 27.2 (26B118)**; English app interfaces. Dates use Pacific/Honolulu.
- Native interactions used Computer Use; ZIP CRCs, archive integrity, and output hashes used
  independent file/CLI checks. All inputs/writes were generated scratch fixtures.
- The separately installed signed Stow release remains older. Other agents' open fix PRs
  were not substituted for the baseline or declared verified by this audit.

## Operational results

| Workflow | Native observation and independent evidence |
| --- | --- |
| Pro filename search | ArcZip found `Docs/Nested/deep.txt` with `deep` and `Docs/日本語.txt` with `日本語`. Space on the Unicode result opened the real text in Quick Look. Stow also found the Unicode entry and Open launched TextEdit with exact contents from its preview cache. |
| Search across an inner ZIP | ArcZip returned **No Results** for `Needle`, although `inner.zip` contains `Nested Needle.md`. Do not treat recursive global search as demonstrated ArcZip behavior. Stow's inability to open that inner ZIP remains #112, independently of parity. |
| PDF preview | ArcZip loaded the real six-page `guide.pdf`; Quick Look displayed the cover, all six page entries, and readable document text. This is not a timing/resolution benchmark of Pro hover previews. |
| Staged rename | ArcZip renamed `old.txt` to `renamed.txt`; the original ZIP hash remained unchanged before Save. |
| Undo / Redo | ArcZip offered **Undo Rename**. Undo restored `old.txt` and disabled Save; Command-Shift-Z restored `renamed.txt` and enabled Save. Stow baseline still disabled Undo/Redo after the corresponding rename. Evidence added to [#113](https://github.com/skyswordw/stow/issues/113). |
| Save ZIP edits | ArcZip Save succeeded; independent ZIP validation found no CRC error, exact original text under `renamed.txt`, the other file and empty folder preserved. Stow baseline still failed opening internal `.stow-saving` with EPERM, retained its edit plan, and preserved the original hash. Evidence added to [#114](https://github.com/skyswordw/stow/issues/114). |
| Windows purpose + compression level | ArcZip switched from Balanced to Smaller and prompted for `CON.txt` → `CON-file.txt` and `question?.txt` → `question-.txt`. It produced a valid ZIP with exact input bytes and unchanged source names. Stow's matching purpose workflow passed in the earlier audit. |
| Linux TAR creation | ArcZip's Linux and Servers / TAR choice showed Store Only and disabled password protection with an explicit explanation. It created a TAR containing the exact 41-byte `add.txt`, independently checked with Python's TAR reader. |
| Encrypted ZIP creation | ArcZip created a password-protected ZIP from the same 41-byte text. Independent 7-Zip integrity testing and streaming decryption passed with exact source bytes. Its encryption algorithm was not established. The post-baseline candidate below also read this ZIP natively. |
| Encrypted 7Z creation | ArcZip created a single-volume 7Z with Fastest (store), a synthetic password, and encrypted filenames. Independent 7-Zip reported `Copy 7zAES`, `Everything is Ok`, and 105,000,000 unpacked bytes. |
| Cross-app encrypted read | Stow prompted for the ArcZip-created archive's encrypted file list, unlocked it, and extracted `split-input.bin`. SHA-256 exactly matched the 105,000,000-byte input. No Keychain credential was saved. |
| Encrypted split creation | ArcZip's same input with encrypted filenames and **100 MB** volumes failed with `File operation failed: 分卷临时文件超出登记目录或所有权不一致`. No final volume or partial output remained in the chosen output folder. Turning off splitting produced the valid single-volume archive above. This is a limitation observed in the comparison app, not a new Stow defect. Stow's existing valid-volume reopening failure remains [#116](https://github.com/skyswordw/stow/issues/116). |
| Open File Flow | Temporarily enabled Plain Text (initially no enabled formats). Selecting `report.txt` offered Open File; TextEdit opened the exact text from ArcZip's ContentCache. Restored the checkbox to off / zero selected formats afterward. Stow's matching Open action also launched actual text from search results. |
| Box controls | Temporarily enabled Box, opened it from Window, checked pin/unpin and the empty drop surface. A copied Finder file did not appear after Command-V. Actual drag collection/processing was not established, so this is not a failed drag test or full Box/Tray parity pass. Restored unpinned / disabled. |

## New Stow findings and bounded fixes

- [#127](https://github.com/skyswordw/stow/issues/127): a single search match displayed
  **1 results in browse.zip**. Preserve the numeric interpolation and provide English singular /
  plural catalog variants; retain Chinese argument ordering and locale number formatting.
- [#128](https://github.com/skyswordw/stow/issues/128): **Looking inside 1 more archive…** remained
  visible for several minutes after the read finished, until the query changed. Make
  `NestedSearch` observable so completion invalidates the browser even when no new hits arrive.
- [#130](https://github.com/skyswordw/stow/issues/130): after a successful Save and opening a
  different archive, native represented-window URL still identified the previously saved ZIP.
  Titles/listings/content were correct. This needs a separate window/document-identity policy;
  no wrong-content or Finder-action failure is claimed from metadata alone.

The search fixes passed the focused `NestedSearchTests` suite, including success and failure
completion without added hits. Compiled catalog checks covered English and Simplified Chinese
counts 0, 1, 2, and 1,000; localization export reported 0 missing out of 936 translations.
Native verification of the local Debug build from the fix branch showed **1 result in browse.zip**
and **Search 9 files** after the first unchanged Unicode query completed. Its app path was
`/tmp/stow-pro-audit-b83de40/DerivedData/Build/Products/Debug/Stow.app`; signature and process path
were verified. This local fix verification is distinct from the CI baseline above.

The broader local run did **not** pass: 392 tests / 68 suites reported 97 issues, predominantly
engine input-open EPERM failures under `stow-in-*`. A separate six-test Extraction suite on
unmodified main `b83de40` also failed with five issues, including the same temporary-input EPERM.
This establishes a pre-existing local sandbox problem; it does not turn the full run green or
replace CI. The attempted single-method baseline filter selected zero tests and was discarded;
the six-test suite is the actual baseline evidence. See #112/#114 and candidate PR #123.

## Post-baseline engine fix verification

[PR #123](https://github.com/skyswordw/stow/pull/123), head
`bc874f5ef7b72392fb1cf7db97bb6f0d33f8666a`, passed 397 tests / 69 suites, 0 missing / 938
translations, Universal2/package and snapshots. Its downloaded app at
`/tmp/stow-pro-audit-pr123/Stow.app` passed signature/process-path checks and native verification:

- Full Browser and Glance opened the original inner ZIP; Back restored the parent selection.
  The real Markdown preview worked. Parent search found the nested file and opened it selected.
- A separate ordinary 7Z inside a ZIP opened and previewed its actual 32-byte text.
- The ArcZip-created encrypted ZIP inside another ZIP listed public names, offered Unlock,
  cancelled without losing browsing state, then retried and previewed the exact 41-byte text.
- A fresh generated ZIP staged a rename without changing the original hash. Save then succeeded;
  independent CRC validation and comparison against every original entry passed, including the
  empty folder. The resulting hash matched ArcZip's edited equivalent:
  `b8eb2534380bc13fc31a550f0b72cd66748cd8c77c36c0ef4272751657dc1907`.

PR #123 was merged as **`be9d48380318c9d18bf01ad9106d8fa0d2a18b56`**. Its descriptor copying
preserves sandbox boundaries but adds private disk I/O/storage; huge/network-volume performance
remains in #38. Search PR #129 was rebased onto that main for combined verification. These later
results supersede the baseline failures for nested opening and Save, not the unrelated Undo,
split-volume, helper-filtering, statistics or AX-error investigations.

## Remaining comparison scope

- Pro hover-preview timing/high-resolution behavior, all compression algorithms/levels,
  additional purpose permutations, and split ZIP creation.
- ArcZip editing add/replace/delete, save failure/cancel/external-change handling, and broader
  undo sequences. This session established its actual rename/undo/redo/save flow only.
- Real Box drag-in, item navigation, duplicate handling and processing; matched Finder drag-out,
  current signed Finder/Services/Quick Look integration and Sparkle, as in #38.
- App/font/PKG installation and replacement/running-app checks in an isolated account or VM.
  Quick Install/quarantine removal stayed off; no actual user Applications/Fonts installation,
  file association change, security grant, or sharing action was performed.
- The broader macOS 26 / Intel / clean-account / network-volume / accessibility / display matrix
  remains in [#38](https://github.com/skyswordw/stow/issues/38). A Pro trial does not substitute
  for those environments.

Computer Use occasionally retained a dismissed menu or lost the frontmost application.
Affected scratch app sessions were restarted; these tool-observation anomalies were not filed
as application defects. Typing a synthetic password dropped its final punctuation in one
attempt; a verified paste unlocked successfully, so that attempt is not password incompatibility.

## Ownership

Codex / Grok Bot owns functional state, archive behavior, localization correctness and tests.
**Claude Code owns visual design and motion** under [AGENTS.md](../AGENTS.md) and
[#104](https://github.com/skyswordw/stow/issues/104). Keep progress honest, preserve visible ordinary
results during nested inspection, and distinguish skipped inner archives from a successful
full search. These are interaction constraints for Claude Code, not a claim of visual approval
or that a Claude Code session has started.
