# Native staged-edit Undo/Redo — #113 and follow-up to #124

Codex / Grok Bot owns functional command routing and regression coverage. Claude Code
owns visual design and motion (#104). This change uses the standard Edit menu and
shortcuts without introducing visual or motion treatment.

## Confirmed cause

PR #124 made BrowserModel own a persistent EditingUndoManager and connected streamed
sessions synchronously. Those changes preserve history, but did not connect the real
SwiftUI commands to that history. Temporary instrumentation of the running macOS app
showed a completed rename with one operation and `canUndo == true` in the model's
manager. The key SwiftUI `AppKitWindow`, its hosting view, and the native `undo:` action
all resolved a different, empty NSUndoManager, even though EditingWindowDelegate was
still installed. The real window's getter bypasses the delegate's supplied manager.
The old bare-NSWindow tests could not reproduce that behavior.

The earlier handoff incorrectly stated that the SwiftUI environment supplied the
model's manager. That injection was removed before #124 merged because the SDK's
EnvironmentValues.undoManager is read-only; it was not part of the merged fix.

## Command routing

EditingUndoCommands replaces SwiftUI's default undo/redo group. It selects the model's
history only for the key archive window whose EditingWindowDelegate still owns that
model. The manager retains the existing per-gesture groups, names, and save lock.
Each invocation checks focus again instead of relying on an earlier menu snapshot.

Editable NSTextView responders, including native field editors, retain their own
history and receive AppKit's `undo:` / `redo:` actions. An empty text history must never
fall back to archive edits. Sheets, modal windows, unrelated windows, and stale window
ownership also exclude archive routing. Native undo and window notifications refresh
menu state; equal snapshots do not trigger a window/menu refresh loop.

The existing model-owned history still survives full/Glance switching. Successful saves
clear saved-session actions; failed saves retain operations and undo history.

## Regression coverage

Four additional tests cover a hosted window whose undo getter ignores its delegate,
command dispatch, empty field-editor history, archive/window isolation, save locking,
and attached-sheet exclusion. The earlier plain-window tests remain to cover ordinary
AppKit windows. Existing real-ZIP tests cover successful and failed save histories.
The CI floor is 425 tests.

The first native candidate passed Edit > Undo Rename, keyboard Redo, and search Undo
Typing without changing the staged archive rename. Final packaged verification is
recorded in the issue and PR before closure; model tests alone do not close #113.
