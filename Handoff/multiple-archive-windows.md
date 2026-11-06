# Independent archive windows and cross-archive copy — #308

## Confirmed user decision

On 2026-11-06 (Pacific/Honolulu), the user chose one independent window per archive so archives can be viewed side by side and files copied between them. Tabs are not the requested first implementation. The Dock recent archive list is already flattened above the window list by #307.

Claude Code owns visual composition and motion. Codex owns session/window state, command routing, archive operations, security, cancellation and tests. This work reuses the Browser and native window/toolbar controls; it does not claim Claude Code visual acceptance.

## Functional behavior

- Finder multi-file open and the Open panel open all selected archives. A canonical source already open or opening focuses its existing session. Browser/Glance preference still applies to each session. Draft Pack completion and explicit Tray-to-Browser routes open a separate Browser without replacing an edited archive.
- Each session owns its model, passwords, source scope, loading/cancellation, edits, Undo, operations and cloud-download progress. Recent history and Tray remain shared. New sessions never run the app's startup temporary-file cleanup.
- File/Edit/View/Go commands follow the key archive window. Browser/Glance transitions affect only their owning session. Closing one archive leaves the others intact. Quit checks all dirty sessions and preserves the normal cancellation/busy rules. Accepted background work retains source access until it finishes.
- Cross-archive drag is a **copy**. A process-local capability binds one gesture to the source level and displayed revision; the existing external file promises remain available to Finder. The destination consumes the batch once and stages one Add operation in the target folder. Existing Keep Both naming and read-only refusal apply. Undo removes the batch; Redo retains its staged bytes. Save is the only action that writes the destination archive.
- Pending source edits are exported privately for the copy; the source archive, edit plan and Undo history remain unchanged. Passwords are requested in the source session. Extraction still uses the sandboxed engine and auditing, helper-file policy and quarantine propagation.
- Source identity is checked before and after asynchronous work. Closing a participating session cancels its transfers; a stale source/destination revision or changed destination level is refused. Temporary data is retained for target Undo/Redo and removed on save, discard, reload or session teardown. Cancelling/failing delivery removes its staging directory.

## Architecture boundaries

`AppState` retains its primary session and owns additional session states. Secondary Browser windows are AppKit windows hosting the existing `RootView` with that session's environment; the primary SwiftUI scene and demo/test entry points remain supported. `ArchiveWindows.swift` coordinates identity, focus and presentation. `ArchiveTransfer.swift` owns the process-local drag capability and audited copy; `EditSession` owns accepted staging lifetime. Full app-wide services are not duplicated when a session is created.

## Validation and remaining acceptance

The initial full run passed 706 tests in 105 suites; final follow-up validation is recorded in the PR. Tests cover simultaneous real opens, canonical deduplication, independent dirty/Undo state, password ownership, window/Glance routing, exact-byte target Save/reopen, folder/multi-item copying, source pending edits, conflicts, stale source/closed destination, and native pasteboard token encoding. Follow-up tests cover read-only/self-drop refusal, external source changes and encrypted delivery/cancellation.

Native CUA/AX checks on disposable ZIPs opened independent Source, Target and Third windows, verified Third Delete/Undo and dirty Close/Cancel, verified Target remained clean, and verified a Third Browser/Glance round trip followed by closing Third left Target open. The native Open panel was explicitly observed with Target and Third both selected. One earlier Command-A attempt did not select all files and is not multi-open evidence.

Actual physical cross-window drag acceptance still needs a human pointer pass on the final build: file/folder/multi-selection, target subfolder, conflict, encrypted-source cancellation, Undo/Redo and target Save/reopen. CUA window-menu tiling was inconclusive; do not call it a product failure or claim a completed pointer drag. No VoiceOver or signed Finder/Quick Look installation acceptance is claimed; #38/#93 retain their existing scope. Do not replace registered extensions with this QA bundle.
