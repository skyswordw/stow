# Issue #133 — Running-app installation refusal

Installing over a running target now throws `EngineFailure.appRunning` (raw value 11),
which maps to `INS-161`. The existing localized message names the target and tells the
person to quit it, then install again. Failure offers Try Again without appending archive
corruption advice. Typed classification takes precedence over diagnostic words and
destination heuristics, including when the app name contains “Data Error”. NSError
round-tripping preserves the condition. Existing raw values and codes remain unchanged.

The refusal still occurs before replacement confirmation and placement. The staged copy
is discarded by the existing defer; the installed app is preserved. Stow never quits the
target. A test-only running-app predicate override exercises this path without launching
or terminating an application; production continues to use NSWorkspace path matching.

Codex owns functional correctness, error classification, cleanup, and tests. Claude Code
owns UI visual design and motion; no Claude Code review or acceptance is claimed. This
change uses existing failure presentation and retry semantics. For subsequent review,
keep the quit-before-retry instruction clear in both the failure card and failed rows.
Compare recovery interactions against ArcZip while retaining Stow vocabulary. No native
ArcZip comparison was possible in this environment.

Validation: added two @Test declarations versus origin/main and raised MIN_TESTS from
410 to 412. Extended existing stable-code and engine-contract tests. Installer coverage
asserts the original version and signature survive, replacement is not prompted, and no
staging folder remains. Failure coverage asserts typed precedence, NSError round-trip,
retry, and absence of archive-damage advice. Localization JSON parsing, the new zh-Hans
translation, test-count accounting, and git diff --check passed locally. Swift, Xcode,
and macOS runtime tests are unavailable here; CI must compile and run the macOS suite
and localization export. Stow.xcodeproj was not created or edited.
