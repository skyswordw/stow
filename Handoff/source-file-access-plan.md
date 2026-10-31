# Source-file authorization and recovery

Research and implementation plan, 2026-10-27. Tracking: [#210](https://github.com/skyswordw/stow/issues/210).
This follows the original other-app guidance in #19 and the user's real WeChat RAR failure.

## Decision

Keep the main app and archive engine sandboxed. When a user-initiated archive open is denied,
offer the native system picker at the immediate source directory. The user can authorize that
directory or select only the original archive. Verify actual source readability, continue the
pending open automatically, and remember successful directory access with a security-scoped
bookmark. A failed recovery ends with actionable copy/export guidance, not another automatic
authorization attempt. Full Disk Access is not an onboarding prerequisite or the default remedy.

Codex / Grok Bot owns authorization, scope lifetime, errors, cancellation, tests and accessibility
semantics. Claude Code owns visual design and motion. The interaction described here is a
functional contract and review brief, not evidence of Claude approval or a new assignment.

## Evidence and limits

1. [Apple WWDC23, What's new in privacy](https://developer.apple.com/videos/play/wwdc2023/10053/),
   app sandbox chapter: Apple recommends `NSOpenPanel` for selecting files or folders in another
   developer's app container. The picker can start at a specified directory. This is the direct
   platform basis for the proposed recovery.
2. [Apple DTS, On File System Permissions](https://developer.apple.com/forums/thread/678819):
   sandbox extensions and mandatory access controls are distinct. Directory access normally
   covers descendants, but does not override all protected locations. Persistent access uses
   security-scoped bookmarks. Stable signing identity matters to persistent OS consent.
3. [Apple DTS, Full Disk Access in a sandboxed archive app](https://developer.apple.com/forums/thread/124895):
   Full Disk Access does not remove sandbox constraints. Selecting an archive does not itself
   grant permission to create extracted files beside it. Source and destination access remain
   separate concerns.
4. [Apple announcement, October 2, 2026](https://developer.apple.com/news/?id=p6zjojqw): additional
   Full Disk Access consent controls are planned, explicitly citing increasingly autonomous AI
   agents. The announcement supplies no rollout version, date or replacement API. It does not
   announce removal of Full Disk Access.
5. Local `/Applications/ArcZip.app`, version **1.1.5**: `codesign -d --entitlements :-` shows no
   main-app `com.apple.security.app-sandbox` entitlement. The Chinese string resource contains
   `onboarding.v2.access.detail` requesting Full Disk Access for sources such as WeChat, and
   `box.source_access.message` directing users to Files & Folders / source-app access on a failed
   Box drop. These are static observations, not a live success trace or the author's explanation
   for choosing that architecture. Possible convenience/engineering benefits are inferences.

The current source implementation treats EACCES/EPERM as an opportunity to request scoped access,
not a diagnosis of which OS policy blocked the read. Residual denial retains the actual errno.
Never infer "TCC", "sandbox" or "corrupt archive" solely from a container path or permission error.

## Existing gap

`AppState.open` previously called `OtherAppFiles.canRead` and immediately emitted OPN-101.
The existing `FolderAccess` store already supported Finder actions, split archives and installs,
but the ordinary document/drop path did not attempt authorization. The old helper also wrote
EACCES into copied details even when the actual error was EPERM. Finder Open previously had a
separate preflight, which could bypass the new cancellation and recovery contract.

## Interaction and implementation contract

- Probe the source. Readable sources require no extra interaction; missing files and other I/O
  errors retain the normal error path. This recovery applies to top-level single-archive opens,
  including Finder Open. Batch extraction/packing and arbitrary Tray operations are not silently
  rerouted through this flow.
- On read-access denial, use an asynchronous `NSOpenPanel` with its initial directory set to the
  immediate parent. Default to directory selection, with an **Allow only this archive** checkbox
  to switch to single-file selection. Accept the original archive or that directory. Validate before confirmation;
  unrelated files and broader ancestors are not valid choices in this recovery window.
- Explain scope explicitly. With Stow's existing user-selected read-write entitlement, the system
  grant can allow both reads and writes. A folder grant covers other files and subfolders, not
  only archives. Do not describe it as OS-enforced read-only access or silently expand it to the
  home directory / entire app container.
- Activate the selected URL's scope and retry the source read. A successful panel response or
  `startAccessingSecurityScopedResource()` alone does not establish readability. Conversely,
  a false return from that API does not imply denial if an implicit grant already permits access.
- Save folder access only after read-back. Keep a session lease through browser use. Single-file
  selection does not save a parent-directory grant; existing Recent Archives behavior may retain
  a bookmark to the selected file. Split-volume discovery still requests its own directory access
  if a single-file grant cannot read siblings.
- Restore the lazy folder store before the first source probe after launch. Preserve explicitly
  selected nested directories even when an ancestor is also remembered, because sandbox coverage
  does not imply the same mandatory-access permission. Reauthorization refreshes the exact path.
- Report bookmark-creation failure as a nonfatal notice: the archive opens for this session but
  Stow may ask again next time. Directory permissions remain listed in Integration settings.
- Remove forgets Stow's saved directory bookmark and releases that store's active scope. It is
  not a universal TCC reset: an open browser, recent-file bookmark or OS implicit grant may still
  permit access. Do not promise immediate system-wide revocation.
- Cancellation and superseding opens dismiss the picker and suppress stale work. Balance every
  successful scope acquisition; a cancelled request must not save a grant or publish an error.
  Failed authorization gets one bounded attempt, then fallback. No Full Disk Access prompt loop.
- Preserve the descriptor-only archive engine boundary, source bytes, existing destination
  checks, and staged-edit confirmation. Source recovery must never use the destination action
  label "Choose Another Folder".

## Tasks and acceptance

1. [#211 — Functional implementation](https://github.com/skyswordw/stow/issues/211): implement
   recovery and lifecycle, truthful diagnostics/persistence handling, localized native controls,
   and regression coverage. Run build, full tests, localization export and generated-plist checks.
2. [#212 — Native acceptance](https://github.com/skyswordw/stow/issues/212): real WeChat open-with,
   double-click and drag; Finder control/handoff; folder versus file selection; split archives;
   residual denial; cancel/supersede; restart and removal; exact signed build/OS/app identities.
   Compare against ArcZip without assuming its static strings prove success. Use disposable
   received attachments; independently verify source hashes. Coordinate signed artifacts under
   #32 and native evidence under #38. Do not register temporary worktree extensions.
3. [#213 — Claude Code review](https://github.com/skyswordw/stow/issues/213): English/zh-Hans,
   source-versus-destination wording, long paths, keyboard/focus, Welcome/Browser/Glance transitions,
   failure/persistence notice and light/dark states. Preserve all functional constraints.

Injected probes and picker answers verify branching, cancellation, errors, scope balancing and
the real archive-engine continuation, but **cannot certify native TCC, real drag delivery or
cross-launch consent**. Those remain in #212 until evidenced on the intended signed artifact.
Dedicated VoiceOver investigation retains the priority recorded in #93; preserve existing
semantics and basic keyboard behavior throughout this work.

## Implementation and validation record

Implemented on `codex/source-file-access`, based on `d253dea`:

- `SourceReadAccess` coordinates one native recovery attempt, a session scope lease, read-back,
  cancellation and nonfatal persistence errors. `AppState` resumes the existing open and guards
  against stale completion. Finder Open uses that same route.
- `FolderAccess` restores saved scopes before the first read, refreshes reauthorized paths, and
  preserves explicitly selected descendants instead of pruning them under ancestor grants.
- OPN-101 reports the actual errno; scope text and Integration settings have Simplified Chinese
  translations. Input authorization is not conflated with output-folder recovery.

Validation on Apple silicon, **macOS 27.2 (26B123), Xcode 27.1 (27A9275)**:

- Full `xcodebuild ... test`: **563 tests / 86 suites passed** after the final source changes.
- Normal `xcodebuild ... build`: passed. `xcodegen generate` leaves all committed plists unchanged.
- `scripts/check-localizations.sh zh-Hans`: **0 missing translations out of 1067 strings**.
- Native normal-build sandbox verified with `codesign`: app-sandbox and app-scoped bookmarks
  enabled, **no absolute-path read exception**. Test-host builds add a root-read exception;
  the post-test launch with that exception was excluded, then the normal build was regenerated
  and its entitlements rechecked before the final native repeat.
- Final normal app executable SHA-256: `c1a0d57d8f6d81ab6586f2289b20cfa77cd7d98e312e4d2258601d81c00f5301`.

Native checks used generated ZIPs outside the app container, passed as launch-argument paths
through the real `AppState.open` route. They were not opened by a file importer first, and the
picker appeared on a genuine denied read. No privacy settings or Finder/Quick Look registration
were changed. These are ordinary-directory sandbox checks, **not a WeChat-container/TCC test**.

| Check | Evidence / scope |
| --- | --- |
| Folder grant and automatic continuation | Native Allow opened the same pending archive and listed `hello.txt`, 38 bytes; repeated on the final normal binary. |
| Restart and previously unseen sibling | Created `final-sibling.zip` after granting the folder, quit and relaunched the unchanged final normal binary. It opened directly without another picker. |
| Remove / reauthorization | Removed the task-owned folder through Integration, quit and relaunched a normal sandbox build. The source picker reappeared. The final repeat's grant was removed again after verification. |
| Single-file choice | Native checkbox enabled file selection; selecting the requested file opened it. A new process opening its sibling still required authorization. Integration listed only the separately authorized folder, not the single-file parent. |
| Cancel and Escape | Returned to Welcome without an error sheet. |
| Wrong file | Native picker rejected a different fixture. The final code uses a custom validation error domain so macOS does not append misleading Finder-permissions repair advice to a selection error. |
| Localization / appearance | English dark and zh-Hans light native picker states inspected. This is a functional inspection, not Claude Code visual approval. |
| Integrity / cleanup | All 8 fixture ZIPs retained SHA-256 `6553d9c079f7b4973d606e74d9b4cdcf4d9093b5b6202c2e13e63d2407d3ea4d`. Task-created saved folder authorization was removed; the test instance was quit and Settings returned to General. |

Native testing caught two defects in the first implementation and led to fixes: a mixed file/folder
picker defaulted to a file, so directory-first mode now has an explicit single-file checkbox; and
lazy bookmark restoration happened after the first read, so restoration now precedes probing.
The latter has a regression test. Cancel/supersede, real-engine continuation, exact selection,
residual errno, vanished source, persistence failure, scope balancing and nested/stale bookmark
restoration also have automated coverage.

Still open in #212: real WeChat 4.1.15 attachment double-click/open-with/drag, signed release
identity and updates, Finder extension/Quick Look handoff, real protected-container denial after
selection, and the native split-volume matrix. ArcZip 1.1.5 permission behavior remains static
bundle evidence in this task. #213 remains the visual/copy review task.
