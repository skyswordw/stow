# Compact editing and drag selection — #156 / #171

Codex owns functional correctness and accessibility semantics. Claude Code retains the final
compact layout, labels, materials and motion under #159. This change reuses existing editing
controls; it does not redesign Browser/Actions/Glance or claim Claude visual review.

Glance now renders the native EditingName/RenameField used by Browser, including validation
and staged tags. It reuses the existing unsaved/external-change bars. The active presentation
owns editing notices; retained hidden views cannot dismiss or present the other window's
validation. Escape cancels an inline rename before clearing selection or closing the compact
window. Add/Replace/Delete/Save continue through the same shared BrowserModel and EditSession.
Review the compact arrangement in #159; these functional controls need not wait for that design.

For #171, file-promise drags capture the pressed selection before AppKit can narrow it. Both
tables ignore native selection writes during the owned drag and restore the original scope on
mouse-up/session end, provided archive identity and folder still match. Hit-testing identifies
actual table rows without relying solely on SwiftUI hover timing. Normal event delivery stays
intact; the fix does not swallow another window's clicks or globally override keyboard focus.

Validation includes a hosted Glance editor regression, drag binding/end-state tests and native
task-fixture checks. Native review initially used an integrated candidate with #154/#155/#165;
the final PR is based on main with #168/#170/#155 and is verified separately. Disclose exact
final CI/native evidence in the PR. A no-target drag/cancel is distinct from Finder receiving
all promised files; the broader drag/VoiceOver/environment matrix stays in #38.

#172 was not reproduced on the initial macOS 27.2 integration: Down and Command-A worked. It
remains open for the reported macOS 27.0.1 behavior; no speculative focus override is included.
