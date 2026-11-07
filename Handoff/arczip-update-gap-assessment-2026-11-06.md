# ArcZip update gap assessment — 2026-11-06

**Follow-up:** the user subsequently approved these priorities and authorized the first functional
wave. [Roadmap #39](https://github.com/Beastry/stow/issues/39) now tracks implementation #312–#315
and compatibility investigations #316–#317. The observations below retain the original pinned
baseline; current implementation status is in [ROADMAP.md](../ROADMAP.md). Zstd-in-7Z failure is
now reproduced with ordinary, Delta, encrypted and split fixtures; exFAT mounting is blocked by
the host driver ([evidence](exfat-verification-2026-11-06.md)). Those findings supersede the earlier
“probable gap” and “not yet run” notes, respectively.

Recommendation: close everyday extraction and output-management gaps first. Add richer previews
and password management in a later feature wave. Do not turn every competitor bug fix or output
policy into a Stow feature requirement.

## Evidence and scope

- ArcZip's live [official changelog](https://arczip.app/changelog/?lang=zh), read in a browser on
  2026-11-06 (Pacific/Honolulu), lists **1.2.2 (349), dated November 6**. The search/web extraction
  initially returned an older page ending at 1.2.1; the live page resolved that discrepancy.
- Recent comparison window: **1.1.5 through 1.2.2**, following the repository's 1.1.4 native audit.
  Earlier omissions from 1.1.2–1.1.3 are listed separately below.
- Stow baseline: fetched upstream main **432d994ae40941946508f1cd39bb2bf24cc9b576**,
  including merged PR #311. The current working branch is older; this assessment uses an isolated
  source snapshot of main, not that branch's feature set. Existing working changes were preserved.
- Stow findings are source inspection, existing test/documentation inspection, and one read-only
  `Vendor/7zip/7zz i` capability probe of the pinned 26.04 executable. No new native workflow,
  performance, exFAT, codec-fixture or VoiceOver acceptance run was performed. “Implemented” does
  not mean shipped in the installed release or newly verified end to end.
- ArcZip statements below are vendor release claims, not newly observed native behavior.
  Prior native evidence remains in the three `arczip-*-native-*` reports.
- Priorities and proposed behavior below are recommendations, not confirmed user decisions.
  Codex / Grok Bot owns behavior, state, security, errors, cancellation and tests. Claude Code owns
  visual design and motion. No implementation assignment or Claude review is claimed.

## Recent releases

| Official release | Main additions relevant to this review |
| --- | --- |
| [1.2.2 (349), November 6](https://arczip.app/changelog/?lang=zh#release-1-2-2-349) | Count-based splitting; Box Save To; compression tuning; exFAT extraction repair. |
| [1.2.1 (336), November 3](https://arczip.app/changelog/?lang=zh#release-1-2-1-336) | Zstd-in-7Z reads; selective-output changes; destination-sheet, password-prompt and responsiveness repairs. |
| [1.2.0 (327), November 2](https://arczip.app/changelog/?lang=zh#release-1-2-0-327) | Password book; batch password reuse; per-purpose defaults; multi-password extraction; result organization and window refinements. |
| [1.1.5 (273), October 25](https://arczip.app/changelog/?lang=zh#release-1-1-5-273) | Hover media playback; preview loading improvements; staged-edit browsing and compatibility repairs. |

Dates are the vendor's displayed dates; its publication timezone is not established.

## Ranked adoption list

Effort is relative engineering scope, not a delivery estimate: S = localized change; M = several
components; L = engine/security/lifecycle work with substantial validation. P1 = next functional
wave; P2 = worthwhile follow-up; P3 = demand-driven. There is no newly reproduced P0 defect here.

| Priority / effort | Capability | Stow main finding | Recommendation and acceptance focus |
| --- | --- | --- | --- |
| **P1 / M** | Batch encrypted extraction with session password reuse | **Missing in the batch route.** `BatchQueue.run` lists and extracts without `PasswordHook` or a batch password context. Single-window retry and opt-in Keychain recall already exist. | Wire prompts to the owning batch and reuse only successfully validated passwords during that batch. Support cancel/skip without blocking later jobs; retain failed/skipped originals. Do not require persistent password saving. This removes a common interruption rather than building a new password-manager product. |
| **P1 / M** | Complete, success-aware cleanup of split archives | **Partial.** Aftercare only trashes the URLs it receives; the batch passes each job URL, not a verified volume set. It marks a successful extraction return as done without inspecting `placement.skipped`. | Resolve exact volume membership and authorization, and allow source cleanup only after complete success. Inspect all single, batch and install callers. Never use a broad sibling wildcard. Cover partial placement, missing volumes and Trash failure before enabling whole-set cleanup. The skipped-result concern is a code-review finding, not a newly reproduced data-loss incident. |
| **P1 / S–M** | Per-purpose default format, separate from one-job changes | **Partial.** Settings persist compression level per audience, but no per-audience format. Pack's level picker writes the saved level immediately. | Persist a format and level per destination; keep a job's edits local unless the user explicitly saves defaults. Preserve custom format choices and existing preference migration. Validate all packing entry points, including the new draft workflow. |
| **P1 / M** | Tray Save To for an already-created temporary group | **Partial workflow gap.** Collect can choose a persistent destination before creation; packing already has a destination chooser. A temporary group lacks a direct general Save To action afterward. | Add a keyboard-accessible export action for owned temporary results. Reuse scoped destination access and safe copy/publish; retain the original on cancel/failure. Do not redesign normal packing to create temporary output merely to match ArcZip. Integrate with current Tray dismissal/Keep Open rules and #287. |
| **P2 / M** | Split by requested number of volumes | **Missing.** `SplitSize` and the engine request represent bytes per volume; the UI's part count is an estimate. | Useful for sharing a fixed number of parts, but less frequent than a file-size cap. Produce the actual requested count from final compressed size, rather than dividing estimated input size. Handle tiny archives, cancellation, temporary-space needs, encryption and reopen/verification. Existing custom size splitting should remain. |
| **P2 / M–L** | Play audio/video inside hover previews | **Missing in Stow's own hover renderer.** Audio shows metadata/artwork; video shows a generated frame. System Quick Look/Open are separate existing routes. | Add bounded native playback after extraction correctness work. Prefer silent video and explicit audio play as a proposal; release files/players on dismissal and selection change. Include resource limits and pointer movement into controls. Treat streaming/range reads as a separate, larger optimization, especially for solid archives. |
| **P2 / L** | Named, searchable, reusable password library | **Partial.** Keychain storage is already opt-in, bound to archive identity, with automatic recall and Forget/Remove All. No named secret editing/search/copy, Pack password picker or separate save/unlock controls. | Start with independent save/auto-unlock preferences and reuse in Pack. Add management only with a clear demand case. Authentication, lock behavior, clipboard lifetime and migration need explicit contracts; avoid inventing a custom master-password system merely for parity. |
| **P2 / L** | Different passwords within one archive, with partial completion | **Missing as a structured workflow.** `ArchiveSource` holds one password; extraction sends one password and stages the operation as a unit. | Worth supporting for compatibility, beginning with independently encrypted ZIP entries. Define per-entry/group retry and skip reporting; preserve the original whenever results are incomplete. Do not weaken current rollback guarantees globally, and do not promise arbitrary solid/encrypted-group recovery. |
| **P2 / M** | Optional common result folder for batch output | **Different policy.** Batch currently gives each archive its own Extract All placement; selected entries land side by side. Single selected items already lose unselected ancestor directories. | Offer grouping only if it solves a concrete organization need. Keep source boundaries clear and collision behavior explicit. Do not automatically copy parent-plus-child selections twice or remove existing Merge/Replace/Skip controls just for parity. |
| **P3 / S** | In-app post-update overview | **Not found.** Sparkle and website release notes already exist. | A Help entry linking to concise release notes is sufficient initially. A new modal on every update has little value during core-product completion. |

## Compatibility and performance work: validate before claiming a gap

| Area | Evidence in Stow | Next useful check / adoption decision |
| --- | --- | --- |
| **Zstd-compressed 7Z** | `.zst`/`.tar.zst` support is real, but is not proof of a Zstd coder inside 7Z. The pinned 26.04 `7zz i` lists a zstd format handler but no Zstd entry in its 7Z codec list. No dedicated Zstd-in-7Z fixture was found. | **P1 compatibility spike; probable codec gap.** Obtain independent ordinary/Delta/encrypted/split fixtures, compare listing, preview and extraction, then decide on an upstream-compatible decoder path. Do not label TAR.ZST creation as coverage, or claim confirmed failure without a fixture run. |
| **exFAT and helper-file handling** | Stow already preserves explicit helper selections, ordinary hidden files and package contents. It restores AppleDouble metadata and audits destination staging. No explicit exFAT acceptance evidence was found in the inspected tests. | **P1 validation.** Run destination-volume tests including metadata-generated `._` files, selected helpers, app resources, conflicts and cancellation. A competitor's exFAT failure does not establish Stow's failure. Fix only reproduced behavior. |
| **ZIP names, separators, ZIP64 and appended bytes** | Legacy-name repair, format detection and special ZIP handling already exist; PARITY documents #207. | Extend the corpus with contradictory name records, multibyte separator bytes and backslash directories. Compare displayed names with extracted paths and exact bytes. Track coverage gaps rather than recreating an existing feature. |
| **Output placement responsiveness** | `Placement.place` performs synchronous filesystem work around asynchronous conflict prompts; Tray collection also performs synchronous copies. Async signatures alone do not establish off-main execution. | Profile thousands of entries and cross-volume collection, then move expensive work off the main actor where demonstrated. Preserve cancellation and transactional publication. No comparative performance ranking is established. |
| **Content-aware compression** | Creation largely delegates one compression plan to 7-Zip; no separate content-sampling policy was found. Existing documentation credits ZIP's handling of incompressible entries. | **P2 benchmark first.** Measure time, output size and temporary space on video/design/mixed corpora. Consider a measured policy only where it beats current defaults without unexpected expansion or degraded compression. Do not infer ArcZip's algorithm from marketing claims. |
| **Glance selection and action hit regions** | Glance uses a SwiftUI Table with selection binding. Full Browser's grid has explicit marquee handling; no equivalent custom blank-area marquee was found in Glance. Native Table behavior still needs observation. | Verify blank-area marquee, modifiers, autoscroll and every expanded action hit target in Glance. Treat this as a possible interaction gap, not a confirmed runtime failure. |
| **Destination sheets and window ownership** | `ExtractDestination` already uses an asynchronous sheet when a key window exists; PR #311 adds independent archive sessions. | Exercise rapid repeat clicks, archive switches, close/cancel and two windows. Do not reopen “add native sheets” as a new feature. |

## Already present or deliberately different

- Independent archive windows, cascading placement and cross-window copy are on main through
  [#311](https://github.com/Beastry/stow/pull/311); they are not new backlog items.
- New-archive drafts are implemented (`ArchiveDraft`, `ArchiveDraftView`, `DraftBrowsing`). The
  older local brief's proposed status must not be mistaken for current implementation status.
- Staged editing already has a pending listing and local input mapping; review folder replacement,
  search and undo regressions rather than adding a second editing system.
- Selected `A/B/file.txt` already exports as `file.txt`; Extract All can already avoid an extra
  wrapper for one top-level item. ArcZip's latest grouping rules are a product-policy difference.
- Batch aftercare already waits until the queue drains and includes successful jobs only; the
  remaining question is completeness within a returned job and complete split-volume membership.
- Native Quick Look, Finder services, custom-size splitting, encrypted ZIP/7Z creation and basic
  Keychain recall already exist.
- License recovery, paid tiers and device activation do not apply to free/open-source Stow.
- Number animations and selection-border treatment are optional Claude Code review inputs, not
  functional parity requirements. Retain Stow's current display/motion preference support.
- Do not reopen the confirmed macOS 26 minimum, sandbox model, or deferred VoiceOver milestone
  merely to match ArcZip. #93 stays deferred unless new ordinary-use stability evidence warrants it.

## Earlier omissions worth retaining in the list

These predate 1.1.5 and were not adequately represented by the old parity summary:

| Capability | Current finding | Recommendation |
| --- | --- | --- |
| ZIP/ZIP64 and RAR archive comment display | No archive-comment model/UI path found; Finder comments are a separate feature. | **P2 / M.** Add bounded plain-text display/copy in Archive Info, with correct decoding. ZIP first; RAR only with verified parser support. |
| Finder double-click quick extraction | Finder extraction actions exist, but no default-open quick-extract preference was found. | **P2 / M.** Optional and off by default, retaining a clear browse override and disk-image exceptions. Requires reliable open-event routing and destination authorization. |
| Traditional Chinese and in-app language choice | English and Simplified Chinese; settings explain the macOS per-app language route. | **P3 / M.** Add Traditional Chinese when audience demand justifies translation/QA. An in-app language switch is optional; preserve task/unsaved-edit handling if added. |

## Source anchors for implementation follow-up

All paths below refer to the pinned main commit, not the older working tree:

- [Batch queue](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Batch/BatchQueue.swift),
  [password retry](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Browser/PasswordHook.swift),
  [vault](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Password/ArchivePasswordVault.swift).
- [Extraction](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Engine/Extraction.swift),
  [placement](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Engine/Placement.swift),
  [aftercare](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Install/Prompts.swift).
- [Packing model](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Model/Packing.swift),
  [defaults](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Pack/PackController.swift),
  [creation engine](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/Shared/SevenZip%2BCreate.swift).
- [Tray](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Tray/Tray.swift),
  [preview service](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Preview/PreviewService.swift),
  [preview rendering](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Preview/PreviewViews.swift),
  [settings](https://github.com/Beastry/stow/blob/432d994ae40941946508f1cd39bb2bf24cc9b576/App/Settings/PreferenceViews.swift).

Suggested sequence: batch password handling → success-aware volume cleanup → per-purpose defaults
and Tray export. Run the codec/exFAT compatibility checks alongside that wave. Follow with preview
playback and count-based splitting; reserve full password-library and multi-password archive work
for their own scoped designs. Existing functional issue tracking (#38, #287) should be reused where
applicable; this report creates no GitHub issues or implementation commitments.
