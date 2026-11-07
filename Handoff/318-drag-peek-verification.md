# Glance drag-out and Peek verification — #318

## Current handoff status — #332

The user paused Codex testing on 2026-11-06 and requested Claude Code to investigate and refine
Browser/Glance drag interactions and motion in [#332](https://github.com/Beastry/stow/issues/332).
The current visual result is not accepted. PR #320 remains draft, preserving the latest candidate
for inspection; Claude may replace its design and gesture approach. No Claude session was launched.

The user's latest physical report on `16c700b`: the first drag could start, subsequent drags often
became multi-selection, and a file drag image lingered. The isolated review process was fully
restarted. The subsequent candidate starts from the recognizer action after arbitration, cancels
released pending actions, explicitly resets at session end, prevents overlapping sessions, and
prioritizes file-drag recognition over the table's primary-mouse selection gestures. Build 32002
contains this candidate; it has not received physical acceptance. Testing stopped at the user's
request. No further test/UI operations are part of the handoff preparation.

## Functional contract and ownership

Glance and Browser support the same deferred file-promise drag-out for files, folders and
multiple selected entries. A press or drag cancels pending/visible Peek without consuming
input. A later hover starts with the existing first-preview delay. Ordinary hover-only
neighbor scanning stays immediate.

Codex owns event routing, cancellation, state and tests. Claude Code retains visual/motion
ownership. No visual approval or animation tuning is claimed. #93 remains deferred.

## Native investigation

The initial window-ownership and row-hit fixes did not complete the repair: the user still
could not drag, although Peek no longer obstructed the operation. That failed acceptance
supersedes any assumption that the first two commits resolved the entire native gesture.

On macOS 27.2 (26B123), a diagnostic trace showed a session requested by a local event monitor
starting only after mouse-up when the monitor swallowed subsequent drag events. AppKit's
native table tracking also does not consistently send movement through that monitor.

The draft implementation attaches one native gesture recognizer to each archive table,
resolves the pressed row across columns, preserves an existing multi-selection and begins
the file-promise session through the macOS 27 gesture API. macOS 26 uses the existing event API
from the gesture callback. The grid/column monitor now leaves native events unconsumed.
Table contents, data sources, delegates, selection clicks, double-click and editing remain
with SwiftUI/AppKit. Rebuilt hosts replace stale recognizers; replacing an archive invalidates
its pending press.

## Earlier observed delivery — before the latest repeated-drag correction

An isolated `Stow Drag Review` app retained sandboxing, used a separate bundle identifier
and omitted Finder/Quick Look extensions. Registered extensions were not replaced.
A temporary blue drop region used a real `NSView` dragging destination and
`NSFilePromiseReceiver.receivePromisedFiles` inside `performDragOperation`. The region and
all diagnostic logging were removed from product sources after verification.

Using the real `DragPeek.zip` fixture, native receiver callbacks completed with no errors:

| Check | Observed result |
| --- | --- |
| Single `alpha.txt` drag | File delivered with exact fixture bytes |
| Multi-selection: `alpha.txt`, `beta.txt`, `Folder` | All delivered, including `Folder/note.txt`; all three source rows remained selected |
| Existing `alpha.txt` at destination | Normal conflict prompt; Keep Both delivered `alpha 2.txt` with exact bytes |
| Browser grid → Browser list → retained Glance | Selection survived the window/view changes |
| Enter Folder, drag `note.txt` from the Size column | File delivered after the round trip, with exact fixture bytes |
| Cancel a subsequent `note.txt` drag with Escape | Source selection retained; no additional `note 2.txt` appeared |

The received `alpha.txt`, `alpha 2.txt`, `beta.txt`, `Folder/note.txt` and `note.txt` were each
compared byte-for-byte against their ZIP entries. Local diagnostic evidence is retained in
`/tmp/stow-pr320-acceptance/native-delivery-results.json` and
`/tmp/stow-pr320-session-events.log`.

## Automated validation

The last completed local run before the pause passed all 728 tests in 106 suites. Regression coverage includes
retained Browser/Glance routing, native table hit regions, replacing stale gesture hosts,
invalidating a press when the archive changes, three consecutive native gesture attempts,
release before the queued action, retry after refused startup, multi-selection restoration, file-promise
extraction, cross-archive copying, Peek cancellation, editing and keyboard focus. The previous
CI run passed 722 tests before the additional native regression cases. Checkpoint CI is
tracked on draft PR #320; automated checks do not approve interaction or motion quality.

## Evidence limits

CUA's fast synthesized drag could release before AppKit began tracking. A second synthesized
stroke within the native receiver completed the drop. These are actual AppKit receiver and
filesystem-delivery checks, not a claim of a single physical mouse stroke or smoothness review.
Direct cross-application Finder delivery could not be confirmed with this automation; the
same tool also failed to complete the ArcZip Mini comparison drop. ArcZip's Mini and the same
fixture were inspected, but its physical drag timing is not inferred from those observations.

The macOS 26 fallback has build coverage but was not run on a macOS 26 host. AX-assisted UI
inspection is not VoiceOver testing. Do not label these remaining checks as passed, or ask the
user to repeat acceptance on the strength of unit tests alone.
