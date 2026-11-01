# Details clarity review — 2026-10-31

Published follow-ups: [Checkup #229](https://github.com/skyswordw/stow/issues/229),
[Details #230](https://github.com/skyswordw/stow/issues/230), and
[toolbar #231](https://github.com/skyswordw/stow/issues/231). The later
[product-wide audit](product-clarity-audit-2026-10-31.md) rechecked these findings against
fetched main `29c521f` and records additional issues. The Details logic and cited Checkup
semantics remain present there; upper-toolbar Search and stable Delete/Save have since shipped.

## Scope and evidence

The user asked whether Details has the same hard-to-understand presentation as Checkup.
Reviewed the supplied Browser screenshot and source at `3e7d998`: `DetailsView.swift`,
`ArchiveInfoView.swift`, `ArchiveUnlockControl.swift`, `PreviewViews.swift`,
`PreviewService.swift`, `BrowserModel.swift`, `Archive.swift`, `Checkup.swift`,
`CodeSignature.swift`, and `Resources/Localizable.xcstrings`.

The screenshot shows one search result, no selected row, archive-wide statistics in Details,
and a prominent normal Checkup report. It establishes appearance only. The additional states
below were inspected in source, not reproduced in the running app. No new ArcZip interaction,
VoiceOver test, or native layout validation is claimed.

Codex / Grok Bot owns functional semantics and this review; Claude Code owns visual design,
grouping, hierarchy and motion. No Claude Code assignment, acceptance or review is implied.

## Confirmed decisions and review inputs

- Confirmed in this conversation: keep the underlying archive checks, remove the permanent
  Checkup toolbar button and prominent all-clear explanation, keep ordinary findings in Archive
  Info, and surface concrete problems where relevant. Users should not have to learn Checkup
  as a separate feature. This supersedes historical always-visible shield requirements.
- Existing confirmed direction: full Browser Details remains fixed and visible. This review
  does not reopen pane visibility or remove useful previews and file properties.
- User suggestion for exploration: search in the middle, view/action controls on the right.
  The screenshot places search above Details, which can suggest the wrong search scope.
  Exact alignment, width and responsive treatment remain Claude Code's decision.
- Details copy and grouping changes below are recommendations, not confirmed user decisions.

## Findings and proposed outcomes

| Current evidence | Understanding problem | Proposed outcome |
| --- | --- | --- |
| The heading always says Details, whether showing Archive Info, a file, or a selection. In the screenshot one search result sits beside “Files 4.” | Users must infer whether facts describe the archive, current folder, search results or selection. The archive name helps but does not explicitly state scope. | Make the subject clear: archive information with nothing selected; file/folder information for one item; “N items selected” for multiple items. These are possible labels, not mandatory heading layouts. Filtering alone must not silently change archive statistics into result statistics. |
| Archive Info shows Total size and Compressed size; Chinese uses “总大小” and “压缩后大小”. | “Total” does not say what is counted. Readers may confuse logical file bytes, packed entries and the physical archive file. | Label the measured quantity and scope. Explain file-content total versus packed data only as needed. Do not simply rename the packed figure “archive file size”: the model can aggregate entry packed sizes or use a container fallback. Exact physical bytes require a matching data source. Logical bytes are not exact disk-space requirements. |
| The screenshot gives 70 bytes, 78 bytes, then “11% larger.” | An ordinary small archive's ratio can read like a defect despite having no useful consequence for the current task. | Keep raw facts available; give compression percentages lower priority or reveal on demand. Do not present an ordinary negative saving as a warning. |
| Checkup has a toolbar button, a section introduction and an all-clear paragraph; its Chinese name is “安全检查”. | Repetition dominates an ordinary archive. The Chinese name and green shield can imply malware scanning or comprehensive safety. | Apply the confirmed decision above. Preserve actual protections and meaningful findings without an all-clear feature promotion or broad safety claim. |
| Encryption: None is always present. Encrypted archives also show a lock row and an encryption finding. | Normal absence takes space; encrypted state can be repeated without making the next action clearer. | Prefer one clear password status and an explicit password action when needed. Ordinary encryption metadata can remain in archive information. A stored password does not mean every entry is decrypted or the archive is no longer encrypted. |
| Unknown packed size becomes “Unavailable” / “不可用”; new/replaced entries use “When you save” / “存储时压缩”. | Missing metadata can look like a broken feature; pending packed size can be mistaken for a ready value. | Explain that the archive does not provide an individual packed size, when that is the known reason; describe staged values as available after saving. Do not invent a reason the model cannot establish. |
| During staged edits, saved packed figures appear alongside current file count/total, with a general “As last saved” note below the group. | It is unclear which values refer to the saved archive and which include edits. | Attach the saved/pending qualification to the affected figures. Keep current selection and unsaved state understandable. |
| Location shows an archive/folder breadcrumb, including nested archives. | “Location” may be read as a Finder path or extraction destination. | A label such as “Location in archive” can establish scope. Preserve the full nested route and access to the untruncated value. |
| App selections show Signature, Check Signature, notarization verdicts and explanatory text. | A technical heading asks the user to understand a mechanism before learning what it establishes. | Lead with developer identity and what was verified, with technical evidence available beneath it. Keep checks on request or before install; do not imply malware-free content or turn unknown states into a clean verdict. |
| Multi-selection shows “N items” and one Size sum. | It does not explicitly say “selected”; folder/descendant overlap could make a naive sum misleading. | State selection scope. Before revising totals, verify overlap handling for recursive search and mixed folder/file selections; this review does not claim a reproduced counting defect. |

The pane has useful behavior worth preserving: actual content previews, filename and type,
selection-specific properties, nested archive paths, and explanatory preview failures.
Preview failures already distinguish password requirements, oversized files, empty files and
unsupported kinds; avoid replacing those with a generic “Unavailable.” The separate nested-hit
detail currently uses a thumbnail and properties rather than the rich-preview branch; keep
that distinction clear rather than implying a full preview was attempted.

## Functional requirements for the design revision

- A person should be able to identify what the pane describes, understand useful size/location
  facts, and see an actionable problem without reading an introduction to an internal feature.
- Keep Archive Info reachable from the archive title menu while any selection is active.
- Preserve protections, extraction policies, installation confirmation, cancellation and error
  handling. Removing the Checkup button is not removal of the checks or their audit results.
- Distinguish a pending protection from a completed one. Listing-time statements must not say
  a link was blocked on disk before extraction occurs. Already-handled findings remain inspectable.
- Relevant warnings must stay discoverable even when Details shows a selected file; do not move
  all warnings into the no-selection pane and make them disappear at the moment of action.
- Distinguish metadata inspection, explicit archive verification and app signature assessment.
  Do not promise malware scanning or complete safety based on any generic green status.
- Preserve meaningful control names, keyboard access, focus, password recovery and system
  display/motion preferences. Full VoiceOver acceptance remains deferred per AGENTS.md.
- Any implementation needs consistent English/Simplified Chinese copy and checks for no
  selection, one file, a folder, multiple items, filtered results, nested results, locked content,
  missing metadata, staged edits and meaningful findings. Include narrow windows and long paths
  when Claude Code validates the visual treatment.

This is a source-and-screenshot review plus an updated brief. No app source or localization
values were changed, and no runtime test results are implied.
