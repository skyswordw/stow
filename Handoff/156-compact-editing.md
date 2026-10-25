# Compact editing — #156

Codex owns functional correctness and accessibility semantics. Claude Code retains final
compact layout, labels, materials and motion under #159. This change reuses existing editing
controls; it does not redesign Browser/Actions/Glance or claim Claude visual review.

Glance now renders Browser's native EditingName/RenameField, including validation and staged
tags. It reuses the existing unsaved/external-change bars. The active presentation owns editing
notices; a retained hidden window cannot present or clear the other window's validation.
Escape cancels an inline rename before clearing selection or closing the compact window.
The native editor requests focus after its cell joins the window, so a detached Table cell
cannot lose the initial focus request; only the filename stem is selected.
Add/Replace/Delete/Save still use the shared BrowserModel and EditSession. Review the compact
arrangement under #159; these functional controls need not wait for that design.

Hosted-editor regressions verify the actual native text field, first responder, filename-stem
selection, delayed window attachment and retained Undo. The delayed-attachment test failed
before the focus repair. Native review also reproduced the lost-focus problem, then verified
direct typing after menu activation, Escape cancellation with selection/window preservation,
staged status, Undo in Glance and Redo in Browser, duplicate-name feedback in Glance, Save and
Add/Replace panel cancellation. The saved task ZIP was independently read to verify exact renamed
and nested payload bytes. Normal Quit after this non-drag sequence exited cleanly; that does
not establish cancelled-drag cleanup.

The earlier review also explored #171 drag preservation. That experiment exposed unresolved
event tracking and cancelled-promise lifetime (#176). It was removed from this change before
merge, including its table bindings and tests; those issues remain separate and open. Do not
claim the drag experiment passed native acceptance because its model tests passed.

#172's macOS 27.0.1 focus failure was not reproduced on macOS 27.2, either in the initial
integration or the main-based branch: Down and Command-A worked. It remains open; no speculative
focus override is included. Broader CJK IME, VoiceOver, Finder drag and environment matrices
remain explicit in #38.
