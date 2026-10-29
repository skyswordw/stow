# Browser toolbar: search placement and editing discovery

Native comparison and next-iteration brief, 2026-10-27. Tasks:
[#215 — Search](https://github.com/skyswordw/stow/issues/215),
[#216 — Editing discovery](https://github.com/skyswordw/stow/issues/216).
Both refine Browser #160 under visual-review umbrella #104.

## User request and status

The user observed that Stow still places Search beside the address/breadcrumbs and suggested
moving it above to give the path more room. They also could not see Delete or Save and asked
whether users would overlook archive editing. The requested work in this pass is a detailed
comparison and actionable issues, not implementation of a new toolbar.

The next direction is **Search in the upper toolbar, with navigation space reserved for the
path**, plus **editing that can be discovered before the first edit**. This supersedes the older
requirement to keep Search in a separate capsule in the navigation row. A stable Delete/Save
pair in the upper toolbar is the recommended implementation direction, subject to Claude Code's
composition and responsive design. Exact button order, colors, materials, dimensions, animations
and the treatment of the existing pending-changes bar are not approved visual specifications.

Keep full Browser as default, fixed Details, no separate left navigation pane, and the floating
Actions direction. This follow-up does not reopen those decisions or change archive capabilities.
Claude Code owns visual design and motion; Codex / Grok Bot owns scope, state, keyboard routing,
security, cancellation, tests and accessibility semantics. No new Claude session or approval is
claimed. Dedicated VoiceOver acceptance remains deferred under #93.

## Comparison method

- Installed ArcZip **1.1.5 (273)** and Stow **0.1.2 (516)**, Apple silicon/macOS 27.2.
- Current main **9b9202a** was inspected. Relevant Browser/Editing files match the worktree;
  the installed Stow version/build is known, but its exact source commit was not independently
  established from bundle metadata. Native behavior is reported as installed-app evidence.
- Generated independent ZIP copies with `report.txt`, `notes.txt`, and
  `Documents/Projects/2026/Client Deliverables/Review Round 03/Long Folder Name/design-notes.txt`.
  Root files and deep navigation were exercised. Independent compressed TAR copies held the
  same entries. Only task-owned fixtures were edited.
- UI was inspected through real clicks, keyboard input, AX state and native screenshots. These
  are functional observations, not a VoiceOver pass or a measured usability study. Native window
  widths/view modes were not normalized; do not infer pixel-perfect space savings from captures.

## Observed behavior

| Task / state | ArcZip | Stow |
| --- | --- | --- |
| Open a clean ZIP | Upper row: view modes, disabled Delete, disabled Save, Search icon | Upper toolbar: archive identity, view modes, Checkup. Search field is permanently beside navigation; no Delete/Save toolbar affordance |
| Activate Search | Clicking the icon expands and focuses a field in the same upper row | Command-F focuses the existing field in the navigation row |
| Search | `report` filters to the root file; Escape cleared and collapsed search in this run | From the deep folder, `report` finds the root file; Clear Search restores the deep folder. A single native Escape attempt did not visibly clear; source implements clear-then-release-focus, so keyboard acceptance needs a focused retest |
| Deep path | Separate navigation row; the upper search control does not share its horizontal allocation | Earlier ancestors scroll/fade away while Search retains space on the same row. At the longest fixture path, the visible leading context began around `2026` |
| Select one ZIP file | Delete becomes enabled; Save stays visible and disabled | Context menu exposes Add Files, Rename, Replace and Delete; the toolbar still does not announce editing |
| Delete the selected fixture entry | No confirmation appeared for this single-file action. Row remained dimmed with a red marker. Save became green/prominent; extraction controls were disabled | Entry disappeared from the staged listing. A bottom bar appeared with an unsaved-change count, a statement that disk contents are unchanged, Revert and Save |
| Finish the edit | Save committed the deletion, then became disabled in its existing position | Revert restored the original listing and removed the entire bottom bar |
| Compressed TAR | Delete/Save remained visible, and selecting an entry enabled Delete. No mutation/save of this format was attempted | Edit context-menu commands were disabled; help explained that compressed TAR is read-only in Stow |

Independent ZIP inspection after ArcZip Save found `report.txt` absent, other entries retained,
and no CRC failure. Stow's ZIP still contained `report.txt` while its UI showed the staged deletion;
Revert was then used, and its source was not saved or modified. ArcZip comparison windows were
closed; Stow was returned to the bundled sample that had been open before the comparison.

This supports the user's concern about **discoverability**. It does not establish that Stow lacks
editing, that people actually forget the feature at a measured rate, or that ArcZip's supported
formats and deletion-row presentation should be copied.

## Source findings

- `BrowserChrome.swift` / `BrowserNavigation` hosts Search beside `NavigationCapsule` and gives
  it **150 / 220 / 240 pt minimum / ideal / maximum** width. Those are source constraints, not
  native measurements. Moving it removes that width claim from the path row, but the combined
  upper toolbar must still be tested at its smallest supported width.
- `BrowserView.swift` exposes no Delete/Save toolbar controls. It inserts `UnsavedChangesBar`
  only while `editSession.isEdited`; external modification switches to `ExternalChangeBar`.
- `EditingViews.swift` already contains Save, Revert, unsaved-change disclosure, saving progress,
  and Reload / Save a Copy recovery. Replacing their visual location must preserve these states.
- `ContentViews.swift` / `EntryMenu` has editing commands and refuses direct edits to nested
  search hits. `BrowseCommands.swift` has Save/Command-S, Save a Copy, Revert, Add, Delete,
  Replace and Find. Its comment claiming Search already lives in the toolbar is stale relative
  to the actual Browser view and should be corrected with #215.
- `EditSession` and existing keyboard/Undo routing are the source of capability and state.
  Do not implement a second editing controller or derive permissions from format labels alone.

## Search task — #215

The observable outcome is that navigating a long path no longer competes with a permanent
search field on the same row. Clicking Search and Command-F must reach one query and one result
set in the upper toolbar. ArcZip's icon-to-field transition is an observed reference; Claude
chooses the presentation and sizing.

Preserve query, search scope, indexing/coverage information, nested results, folder/history and
selection behavior. Define clear, collapse and Escape explicitly: do not hide an active filter
without an indication. Retain Stow's clear-then-return keyboard contract unless a behavior change
is called out. Search text deletion/Undo must never delete archive entries or undo archive edits.
Glance currently has no independent Search UI; preserving shared state does not require adding
one in this task.

Acceptance includes deep/long paths, long archive titles, root and nested hits, no results,
indexing, skipped coverage, CJK IME, switching view modes, and supported minimum window width.
Check expanded Search with the proposed editing controls, Checkup and encrypted-archive controls.

## Editing task — #216

Provide a stable visible editing entry before users discover a context-menu action. A toolbar
Delete/Save pair with truthful disabled states is the recommended starting point. Make Add,
Rename and Replace findable without turning every edit operation into a permanent button.

| State | Functional requirement |
| --- | --- |
| Clean, no selection | Save is visibly available as a capability but disabled; Delete has no target |
| Eligible selection | Delete targets selected entries inside this archive, not the source archive on disk |
| Pending changes | Save commits the existing edit session; keep change count, Revert/Undo and staged-write disclosure |
| Listing / saving / blocked operation | Reuse actual capability checks; prevent provisional edits or duplicate saves and retain progress/failure behavior |
| Read-only / locked / unsupported context | Explain the actual restriction; preserve Extract and Repack where available; no format-support expansion is implied |
| Nested search hit | Do not delete a parent-archive entry using an inner result's path |
| External modification | Preserve conflict detection, Reload and Save a Copy; a prominent Save must not bypass source preservation |
| Search / rename / another window focused | Text and window ownership remain authoritative for Delete and Undo |

Claude should explain the relationship between toolbar Save and the existing bottom pending-change
bar. Avoid competing prominent Save controls while preserving clear pending-state disclosure;
the bar's exact composition is open to design. Keep existing save/discard-on-close behavior,
multi-selection normalization and Undo/Redo. Validate Delete -> Undo -> Redo -> Save and other edit
operations using disposable fixtures and independent source/final-byte checks.

## Delivery boundaries

Both issues need English/zh-Hans, light/dark, basic keyboard/focus checks and system display/motion
preferences. Compare before/after at matched normal and minimum supported widths. Saving failure,
external change, multiple selection, nested results, encryption and narrow-window overflow are
acceptance cases; they were not all exercised during this discovery audit. The installed ArcZip
account's entitlement tier was not separately audited; no free-versus-Pro claim is made.

This pass changes the current brief and creates tasks only. It does not move Search, add toolbar
buttons, claim final visual approval or claim that dedicated VoiceOver testing has been completed.
