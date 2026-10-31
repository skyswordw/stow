# Open issue verification — 2026-10-31

Codex scanned all 17 open issues against main `29c521f`. Claude Code retains visual design and
motion ownership. This pass verifies delivered behavior, fixes source-picker window routing,
and adds repeatable packing stress coverage. It does not approve new visual treatment.

## Browser Search and editing — #215, #216

PR #222 delivered both requested toolbar features. Its description records Claude Code's
English/Chinese, light/dark, narrow-window, read-only and native editing evidence. Its explicit
Escape change is retained: clear Search and return the keyboard to the files in one step.

Independent native verification here used a locally built Debug app from main `29c521f`,
Xcode 27.2 (27B52), Apple silicon, macOS 27.2. The executable was
`build/Build/Products/Debug/Stow.app/Contents/MacOS/Stow` in this checkout. It opened a generated
four-file ZIP through the real engine with `-StowScene open`; no sample editing was simulated.
Computer Use supplied AX inspection/activation and keyboard input. This was not VoiceOver testing.

| Check | Observed result |
| --- | --- |
| Clean archive | Delete and Save both visible in the toolbar, both disabled |
| Command-F, query, Escape | Search filtered correctly; Escape cleared it and returned focus to the List outline |
| Arrow keys after Search | Selected the intended entry; Delete enabled while Save stayed disabled |
| Toolbar Delete | Removed only the selected row from the staged listing; showed pending-change disclosure and enabled Save |
| Source before Save | Original SHA-256 unchanged and all four original entries still readable |
| Command-Z / Command-Shift-Z | Restored the row and clean state, then restored the staged deletion |
| Toolbar Save | Committed the deletion, removed the pending notice and disabled Save |
| Command-Delete while Search has focus | Cleared query text; did not delete the selected archive entry or create pending edits |
| Search from Documents/Projects | Found a root entry; clearing restored the same folder |
| Browser → Glance → Browser | Preserved Documents/Projects and its contents/history controls |
| Columns, no-result Search, Escape, Down | Search retained text focus with no results; Escape restored Columns and arrow navigation worked |

Python's independent ZIP reader checked CRC and every remaining payload after Save. Only
`alpha.txt` was removed; `beta.txt` and both deep-folder files retained their original bytes.

- Original SHA-256: `43d5f2417c0dd516db14de446cd9ce6f4e65cb14c1cdea816f8ae2f3b58a5e50`
- Saved SHA-256: `bf8ae676961313fcf433c9cf4d2702ab92e704218f306c2bbe9dc2b379bc0a20`

These results, the merged implementation and PR #222's existing evidence complete the focused
Search placement and editing discoverability tasks. Broader CJK input/environment coverage stays
in #38, and dedicated VoiceOver work stays deferred in #93. Neither task requires another toolbar
implementation or a new design approval from Codex.

## Source recovery — #213

PR #223 identified an ownership problem: the native recovery picker could attach to Settings
simply because it was key when the open reached authorization. `SourceAccessPresentation` now
limits sheet hosts to visible Browser, Welcome and Glance windows without another sheet.
An eligible key window wins; otherwise Glance, Browser, then Welcome are preferred. If none is
eligible, the existing asynchronous standalone path remains available.

Regression tests exercise all three window identities (including SwiftUI identifier suffixes),
Settings/Onboarding exclusion, hidden windows, occupied hosts, sheet exclusion and fallback
priority. The focused source-recovery/window suite passed 17 tests. This is AppKit window-state
testing, not proof of real WeChat/TCC authorization. Scope validation, read-before-persist,
source integrity and cancellation behavior are unchanged. #212 and the broader #210 remain open.
The optional nonmodal persistence-warning proposal from #223 still belongs to a separate design
and functional decision.

## Encrypted split packing — #38 item 10

The new regression combines password-protected 7Z creation, encrypted filenames, 100,000-byte
parts and Verify in one `ArchiveCreation` operation through the sandboxed XPC service. It then
checks password refusal, lists/reopens the first numbered part through `ArchiveEngine`, extracts
through the engine's transfer path, and compares the incompressible 350,000-byte payload with
both the source and extracted file. The output directory must contain exactly the published parts.

`scripts/stress-encrypted-split.sh 20` passed **20 independent executions**, each with one passed
test, zero failures and zero skips. No SIGTERM was reproduced. The script checks each xcresult
for a nonzero test count; a green xcodebuild invocation that executes no tests is rejected.
On this Xcode, `-test-iterations 20` ran the Swift Testing method only once, so the script starts
separate test runs rather than claiming repetitions from that flag.

This is a bounded automated stress result, not a claim that the historical intermittent failure
is impossible. Larger archives, low-space pressure, real cloud/network volumes and physical
Intel hardware remain separate #38 coverage. All inputs and destinations were task-owned.

## Remaining issue disposition

| Issue | Disposition after this scan |
| --- | --- |
| #215, #216 | Delivered by #222 and independently verified above; ready to close |
| #213 | Picker-host functional fix in this change; remaining native/design follow-ups stay explicit |
| #212 | Requires real WeChat input and the intended signed build; synthetic permission failure is insufficient |
| #210 | Keep parent open for #212 and remaining recovery acceptance |
| #153 | Advanced Pack UI shipped in #195; native archive readback added in #205. Remaining manual UI/CJK coverage is not claimed here |
| #162 | Sidebar, Glance page and Actions preview shipped in #224; remaining native routing/long-list acceptance is not claimed here |
| #160, #161, #104 | Remaining visual/motion review belongs to Claude Code; no new design work or approval claimed |
| #144 | Low-priority direct x86_64 runtime investigation and physical Intel validation remain open |
| #93 | Dedicated AX/VoiceOver investigation remains explicitly deferred; not closed by these checks |
| #84 | DMG AES remains blocked by the sandbox-safe creation constraint; no entitlement weakening |
| #69 | Sample integrity already has #201/#203; website/video asset acceptance remains separate |
| #38 | Added bounded item-10 evidence; the broader environment matrix stays open |
| #32 | Signed/clean-account integration remains with the existing release collaborator and acceptance workflow |
| #39 | Umbrella remains open while its remaining acceptance/release tasks are open |

No installed app was replaced, no Finder/Quick Look extension was re-registered, and no release
was published. No user data, associations, real folder grants or saved credentials were changed.

## Final local validation

- Full suite: **592 passed**, zero failed, skipped or expected failures; checked with
  `scripts/ci-assert-tests.sh`. CI's minimum count is updated to 592.
- Simplified Chinese: **0 missing of 1,090 strings**.
- `xcodegen generate` left committed plists unchanged; `git diff --check` passed.
- The repeated packing run retained 20 successful xcresult bundles. Its result does not depend
  on the cosmetic progress counter or the broader full-suite result.
