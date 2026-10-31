# Product clarity audit — 2026-10-31

## Evidence and ownership

The user requested publishing the Browser/Details findings first, then reviewing the rest of
the product for similarly obscure design. The first three issues were published before the
broader findings were filed. All issue titles, bodies and comments are in English.

Source baseline: fetched main `29c521fd1e1301936c573b2235e3576681d47971`. The working checkout
remains at `3e7d998` with documentation edits; latest-main sources were read from a temporary
export to avoid overwriting that work. The user's screenshot is Browser appearance evidence.
All other findings are source/copy analysis, not a new native interaction run, matched visual
comparison, ArcZip observation, VoiceOver test or usability study. No app source was changed.

Claude Code owns visual design, hierarchy and motion. Codex / Grok Bot owns behavior, state,
scope, errors, cancellation, tests and accessibility semantics. Publishing an issue does not
assign an unknown account or establish an active Claude session or visual approval. Preserve
basic keyboard/focus access and system display/motion preferences; dedicated VoiceOver
acceptance remains deferred under #93.

## Published issues

| Task | Evidence and desired outcome |
| --- | --- |
| [#229: Contextual archive findings](https://github.com/skyswordw/stow/issues/229) | User-confirmed removal of permanent Checkup promotion and prominent normal-state Details text. Keep checks, ordinary findings in Archive Info, relevant problem notices and truthful planned/completed handling. Chinese “安全检查” overstates what metadata checks establish. |
| [#230: Details scope and copy](https://github.com/skyswordw/stow/issues/230) | Identify archive versus selection facts; explain measured sizes, missing metadata, staged values, archive-relative location, password status and app-signature meaning. Wording/layout proposals remain recommendations. |
| [#231: Toolbar composition](https://github.com/skyswordw/stow/issues/231) | Evaluate the user's central Search/trailing controls suggestion. #215/#216 already delivered upper-toolbar search and stable editing; do not reopen them as missing functionality. |
| [#232: Batch outcomes and access to results](https://github.com/skyswordw/stow/issues/232) | `BatchStack` treats inactive/nonfailed batches as done even when jobs were cancelled. Only four rows plus static “+ N more” are rendered; later failures and their recovery controls cannot be reached in that panel. Preserve cancellation and completed outputs while making every result reachable. |
| [#233: Tray action scope](https://github.com/skyswordw/stow/issues/233) | “Extract Here” means beside each source archive; “Send to Main Window” opens one archive but otherwise opens Pack. Explain the actual task, targets and destinations without changing policy silently. |
| [#234: Missing-part compact errors](https://github.com/skyswordw/stow/issues/234) | `.missingVolume` uses a specific full title but `.damaged` kind; the compact `brief` therefore says “Damaged — download it again”. Preserve the actual cause and recovery in short messages. |

Suggested execution priority: #232/#234 affect truthful status and recovery. Coordinate
#229–#231 as one Browser design pass while keeping reviewable implementation boundaries.
#233 is a task-predictability improvement. This is prioritization advice, not a release gate.

## Existing issues updated

- [Actions #161](https://github.com/skyswordw/stow/issues/161#issuecomment-6544529005): Settings
  still says suggestions sit beside Extract, implies More includes the front action, and
  describes activation only after selection despite the no-selection Install App offer.
  Current source supports hover on the front button and edges; the hover explanation is not
  a defect. Older edge-only design prose must not be treated as the current runtime contract.
- [Settings #162](https://github.com/skyswordw/stow/issues/162#issuecomment-6544529796): the
  quarantine toggle leads with a technical term; folder-scope explanations differ between
  Installing and Integration; “Integration” and preset “destination” can obscure tasks.
  Review effect-first copy without changing security defaults, grant scope or storage keys.
  The grouped sidebar and Actions example already exist; the eleven-tab baseline is historical.
- [Pack #153](https://github.com/skyswordw/stow/issues/153#issuecomment-6544530587): distinguish
  planned verification from a completed test; make support-files/metadata summaries and
  purpose-reset scope understandable. Custom split sizes and per-job advanced options already
  exist. Preserve these controls and their single model.
- [Browser #160](https://github.com/skyswordw/stow/issues/160) and
  [product umbrella #104](https://github.com/skyswordw/stow/issues/104) now begin with the current
  direction and issue map, explicitly superseding the old permanent-Checkup requirement.
  Source-access wording continues under [#213](https://github.com/skyswordw/stow/issues/213).

## Coverage and useful behavior to preserve

| Surface | Review outcome |
| --- | --- |
| Browser, Details, search and editing | #229–#231. Existing staged-save disclosure, Revert, archive identity and full/nested paths are useful. |
| Actions and Settings example | #161 follow-up; preserve the contextual primary action, deliberate activation and complete menu access. |
| Glance | Reviewed identity, close/pin/full-window controls and opening states. Task-specific help already explains the compact/full transfer. No new defect filed from this pass. |
| Pack | #153 follow-up; retain format capability explanations, filename privacy, estimates and visible rename/omission consequences. |
| Tray | #233. Collection already explains temporary copies and preservation of originals; Remove from Tray has useful source-preservation help. |
| Welcome and onboarding | Drop copy already distinguishes opening one archive, extracting several and packing other files; avoid inventing another onboarding layer. General safety wording should align with #229's limited claims. |
| Settings and permissions | #162/#213; scoped reset, saved-password behavior and Integration's descendant/revocation caveats are useful. |
| File associations | Copy already explains double-click defaults, previous-app restoration and the macOS confirmation step. No additional issue established. |
| Password and preview states | Purpose-specific password prompts and reason-specific preview failures already identify the next step. Preserve them. |
| Conflict and install prompts | Existing copy explains Keep Both, Merge, Replace and Trash consequences. Signature meaning is covered by #230; preserve confirmation behavior. |
| Batch progress and errors | #232/#234; short summaries must preserve actual outcome/cause and offer access to every affected item. |
| Finder Quick Look | Its Checkup label and all-clear line need consistency with #229; no new extension registration or native validation performed. |

The recurring issues are unclear subjects/destinations, technical terms preceding practical
meaning, and prose that has drifted from actual state. This review does not establish that
every named feature needs renaming or that the product needs a wholesale visual rewrite.

Validation for this documentation/publication task: verify issue bodies/links, updated parent
direction, source references and local Markdown diffs. App build/test and runtime acceptance
belong to implementation; no runtime result is inferred from these checks.
