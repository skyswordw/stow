# Issue #130 — Window document identity

Browser and Glance represent the outermost archive's source URL. Attaching a new
model to a reused window replaces the previous identity; streamed listing updates
and navigation apply the same policy. Nested browsing retains the outer document
identity rather than exposing an extracted cache path. Sample/no-source archives
and the welcome window clear stale metadata.

Save, Save a Copy, and Rename continue adopting their resulting archive URL; the
window derives its identity from the current outer level. Replacing a delegate's
model detaches the previous model from that window so late callbacks cannot reset
its metadata. Archive contents, staged edits, and undo history are not reset by
metadata synchronization.

Three new EditingWindowTests cover reuse/sample clearing, streaming, and nested
return navigation with Browser/Glance attachment and retained edits/undo. Existing
EditSessionTests now assert representedURL after actual Save, Save a Copy, and
Rename; Rename also retains a pending edit. MIN_TESTS increases from 410 to 413.

Validation here is limited to static checks on Linux; no Xcode/AppKit execution
was possible. On macOS, run the unit suite and verify packaged AX window URL after
Save A → open B, nested enter/back/forward/up, sample/welcome, Save a Copy, Rename,
and Browser ↔ Glance. Compare document identity interactions with ArcZip while
retaining Stow vocabulary; no native comparison is claimed here.

Codex owns this functional metadata/accessibility correction. Claude Code retains
UI visual design and motion ownership under DESIGN.md and the current UI/motion
handoff. No visual or motion changes or Claude Code review are claimed.
