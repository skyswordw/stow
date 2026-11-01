# Functional clarity implementation — 2026-10-31

The user authorized Codex to implement all independently actionable findings from the
[clarity audit](product-clarity-audit-2026-10-31.md). Baseline: main `29c521f`.
Codex / Grok Bot owns behavior, scope, state, errors, cancellation, security, tests and
accessibility semantics. Claude Code owns final visual hierarchy, layout and motion. Existing
native controls and styles are used for functional controls; no Claude review is claimed.

## Delivered behavior

- #234: missing-part failures have their own semantic kind, compact guidance and existing
  EXT/OPN-102 code. They no longer become damaged-file/download-again messages in batch rows.
- #232: terminal batch summaries count completed, stopped and failed jobs separately. A stopped
  batch has the stopped glyph, not a success check. Show All Results exposes every row in a
  bounded scroll region, including later recovery actions. Results stay until Clear Results,
  whose help states that extracted files remain. Stop All keeps previously completed outputs.
  The worker no longer waits inside a six-second dismissal timer; queued work/retries arriving
  during aftercare start afterward, and their scoped grants are not released with the old run.
- #229: remove the permanent Browser Checkup button. Archive Info opens from the title menu
  even during selection. Normal reports and ordinary archive metadata live behind More Archive
  Information. Caution/planned-handling/completed-audit findings remain discoverable in a native
  disclosure above the files in Browser and Glance. The finding's words, not severity, establish
  whether an action is planned or complete. Finder Quick Look omits routine all-clear reports
  and shows specific relevant findings without Checkup branding. Engine checks are unchanged.
- #230: Details headings identify archive/file/folder/selection scope. Packed figures distinguish
  container size from summed packed file data; provenance survives relisting. Saved archive
  figures and current unsaved totals are qualified at their own rows. Unknown data and pending
  packing have specific wording. Archive-relative locations can wrap fully and be copied.
  Selected ancestor/descendant entries are counted once in combined size. Developer verification
  copy identifies signature/notarization without claiming Stow scanned contents for malware.
- #233: Tray names Pack All Shown versus Pack Selected; extraction says it writes beside original
  archives, with mixed-input and destination help. The former Send to Main Window command names
  Open Archive in Full Window or Open Packing Window according to the existing routing rule.
- #161/#162: Actions help reflects the actual front/alternative/menu behavior and no-selection
  app offer. The quarantine toggle describes its first-open effect; Installing explains folder
  descendants and forgetting saved authorization consistently with Integration. Preference keys
  and security defaults remain unchanged. Finder & Permissions and recipient-preset labels
  replace ambiguous category/destination copy.
- #153: planned verification and completed verification have distinct wording. Metadata summaries
  name Finder files versus Finder tags/attributes. Reset These Options identifies the local
  options scope. Existing compression/format/purpose/default behavior remains unchanged.

## Review boundaries

#231's central Search/trailing-controls composition stays with Claude Code. This implementation
only removes the already-rejected Checkup button; it does not relocate Search or redesign the
remaining toolbar. Review the batch disclosure/scroll region, archive-notice disclosure and
Archive Info popover in normal/narrow widths, both languages and display preferences. Preserve
access to later failures, current warnings during selection and archive information during
selection when replacing their visual treatment.

Open design PRs #235 (Pack report) and #236 (Actions/Browser close-out) were inspected to avoid
reimplementing their visual changes. They are not dependencies or evidence of visual approval
for this change. Coordinate shared documentation/catalogs when merging.

Dedicated VoiceOver acceptance remains deferred under #93. AX-assisted checks must be reported
as such; no claim to fix the separate AX investigation is made.

## Validation

- Full local test suite: 595 tests in 88 suites passed, zero failures.
- New regressions cover missing-part versus damaged-data messages and stable error codes;
  mixed/stopped batch state; retained later failures; cancellation preserving completed results;
  Details scope, ancestor/descendant totals and packed-size provenance; ordinary Quick Look
  findings remaining quiet.
- Simplified Chinese localization export: 0 missing translations out of 1148.
- AX-assisted native checks with the `batch-results` fixture: Show All 5 Results exposes the
  fifth missing-part failure and its recovery/error-details actions; Clear Results removes the
  result panel; selecting README changes Details to File Info while notices remain available.
  Archive Info opens from the title menu during that selection, More Archive Information reveals
  findings, and Escape dismisses the popover without clearing the selection. This is not
  VoiceOver testing or a real batch extraction run.
- Rendered and inspected English light/dark batch states, Chinese selected-file Details, and
  the archive-info popover. A generated real two-file ZIP was listed through the engine at
  900 × 640 in Chinese: no all-clear banner/button appears, and archive scope is explicit.
  The same ZIP rendered through the in-app Quick Look scene, not a registered Finder extension.
- The real ZIP also exposed an existing Quick Look “0% smaller” label for packed bytes exceeding
  original bytes; compact preview now reports the packed bytes without a false savings claim,
  with regression coverage for larger/equal/smaller values.

![Real ordinary ZIP, Chinese, 900 × 640](evidence/2026-10-31/clarity-normal-archive-zh.png)

The screenshot records a functional baseline, not approved final composition. The toolbar
placement proposal in #231 is intentionally still outstanding.
- No Finder/Quick Look registration script is run; installed system-integration artifacts remain
  outside this task. No visual design acceptance is inferred from functional checks.
