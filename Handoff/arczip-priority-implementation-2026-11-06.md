# Approved priority follow-ups — 2026-11-06

The user approved the [ranked assessment](arczip-update-gap-assessment-2026-11-06.md), requested
GitHub planning updates and authorized implementing the first wave. [Roadmap #39](https://github.com/Beastry/stow/issues/39)
retains the lower-priority backlog; there was no existing organization Project to duplicate.

## Implemented behavior

- **#312:** BatchQueue and Finder/Tray extraction validate a password against listing and actual
  extraction before retaining it for the batch. Failed candidates do not remove a password that
  may work for another archive. Skip Archive continues with later work. Prompt cancellation is
  question-scoped and waits behind an existing question; a background request prepares its own
  Browser/Glance presenter. Keychain persistence retains the existing opt-in setting.
- **#313:** Capture file identity and exact numbered ZIP/7Z membership before the operation.
  Cleanup runs only after complete output placement; skipped or safety-filtered content retains
  the original. Revalidate the captured set before Trash. Partial Trash failure attempts rollback;
  incomplete rollback names recoverable Trash items. Unsupported multipart families are retained.
- **#314:** Settings explicitly owns per-audience default format/level. Every supported format
  remains selectable regardless of recommendation. Draft, Pack and Quick Compress use a snapshot;
  changing a job does not overwrite defaults. Existing level keys survive and missing format
  values default to ZIP. Quick Compress handles full compound suffixes and collision numbering.
- **#315:** An existing owned temporary Tray result can be exported with Save To. A native folder
  chooser precedes background destination-side staging and exclusive publication. Name collisions
  are numbered; failure/cancel retains the original. The persistent row keeps destination access
  for the Tray session. Keep Open is respected. Existing Pack work, pending requests and retained
  retry state block export to avoid competing temporary-source cleanup. Updates/quit see export
  as active work. Temporary originals remain until normal startup cleanup because a preview or
  existing consumer may still reference them.

## Compatibility conclusions

**#316: support should be added in a dedicated change.** Independently generated ordinary,
Delta-filtered, encrypted, split and encrypted-split Zstd-in-7Z fixtures round-trip correctly in
their producing implementations. The stock bundled 7-Zip 26.04 lists them but cannot decode
their contents (`Unsupported Method`). The fixture README records producer versions and payload
hash. The sandboxed probe also reproduced a separate diagnostic bug: complete split archives
misreported this codec failure as missing volumes. This change preserves the original unsupported-
method diagnostic instead. The compatibility tests explicitly exercise known safe failure; passing them must never
be reported as decoder support. A future decoder needs positive exact-byte tests, broader solid/
multi-file/corruption coverage, sandbox/cancellation review and release/Universal 2 validation.
The fixture producer is not a new application dependency or bundled engine.

**#317: repair decision remains pending evidence.** A healthy disposable exFAT image was made,
but the host cannot load/mount its exFAT filesystem. No product failure or successful exFAT
extraction is claimed. See the [driver evidence and follow-up recipe](exfat-verification-2026-11-06.md).
All task-created virtual attachments were detached; no physical disk was changed.

## Review and acceptance limits

Functional review found and repaired two additional regressions: export versus existing Pack
cleanup, and compound-extension collision numbering. Focused tests cover those scenarios along
with actual encrypted batch extraction, default migration/entry-point consistency, exact volume
membership, changed sources, incomplete results and rollback. Parent integration records full
build/test/localization results in the PR.

Remaining limits:

- Numbered `.zip.001` / `.7z.001` cleanup is supported; RAR multipart, classic zNN and unknown
  numeric families have no authoritative membership model here and are conservatively retained.
- A large individual `FileManager.copyItem` is not interrupted mid-call. Cancel keeps the UI
  responsive and prevents publication after the call finishes, then cleans staging.
- No new real Trash, native multiwindow password, physical cross-volume, clean-account or signed
  installation acceptance is claimed. Registered Finder/Quick Look extensions were not replaced.
- Codex / Grok Bot owns functional state/security/cancellation/tests. Claude Code owns visual and
  motion review of the new settings rows, Save To action and batch-password wording. These are
  functional controls, not approved final visual designs; no Claude session was dispatched.
- Preserve keyboard names/focus and system display/motion preferences. Full VoiceOver acceptance
  and #93 remain deferred under the current milestone decision.
