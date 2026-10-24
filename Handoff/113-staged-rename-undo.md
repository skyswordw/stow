# Staged edit undo wiring — #113

Codex owns functional undo wiring and regression coverage. Claude Code owns visual
and motion treatment (#104); this change introduces no visual or motion design.

The source-level disconnect is lifecycle ownership: the full BrowserView delegate
owned the manager, while streamed listings replace Level/EditSession, Glance did
not attach an editing delegate, and full/Glance view replacement could abandon the
history. Session-to-manager wiring depended on a later SwiftUI change callback.
SwiftUI content also had no explicit connection to the delegate's manager.

BrowserModel now owns a single manager and connects every new session synchronously.
Both presentations expose that manager through the SwiftUI environment and the native
window delegate. Reattaching a delegate restores its previous window's delegate;
changing archives selects the new model's history without clearing the old one's.
Explicit operation groups disable event-based grouping so each gesture remains one edit.
Save locking still gates both menu validation and direct undo/redo, and successful
writes clear the saved session's actions. Failed writes retain them.

Four new @Test methods exercise native window lookup, responder lookup, action names,
exact edit counts, streamed listing replacement, archive/window switching, and save
locking. Existing real ZIP successful-save and external-change failure tests now
obtain the manager through NSWindow rather than injecting a standalone UndoManager.
MIN_TESTS increases from 390 to 394.

Linux validation: diff whitespace checks, catalog JSON parsing, and test-count delta
checks. Xcode/AppKit execution and localization export are unavailable here. The
reported native failure cannot be reproduced on Linux; these source-level lifecycle
findings still require macOS verification of SwiftUI delegate forwarding and menus.

Native verification: rename a real ZIP entry with list and grid focus; use Edit > Undo,
Command-Z and Shift-Command-Z; repeat add/delete/replace; open another archive; switch
Glance to full and back with pending undo and redo. Verify Save disables undo while
running, clears history after success, and preserves history after failure. Compare
the single-edit interaction with ArcZip while retaining Stow's vocabulary.

Closes #113 after native validation.
