# Search coverage disclosure (#131)

Codex owns omission classification, model state, cancellation, tests, and accessibility
semantics. Claude Code owns visual design and motion; this functional implementation
has not received Claude Code review.

Search keeps ordinary and successfully indexed nested matches. When nested inspection
finishes, a nonmodal disclosure above results reports the number of unsearched inner
archives. Expand it for full paths, password/read/size/count reasons, and Locate buttons.
Locate clears search and selects the archive in its containing folder, without opening
it or prompting. Explicit Open retains the normal password/recovery flow. Empty results
say only that searched items did not match. Background loading never requests passwords.

Review the simple native disclosure, constrained scrolling for multiple omissions,
long paths, keyboard/VoiceOver navigation, and English/Simplified Chinese in small windows.
Compare archive discovery/open interactions with ArcZip while retaining Stow vocabulary;
no native comparison was possible on Linux. No new motion is intended.

Validation: four new @Test declarations (including zero/nonzero result arguments),
CI minimum 410 → 414. Static JSON/translation checks and git diff checks run on Linux;
Swift compilation, tests, localization export, and native interaction QA require macOS CI.
