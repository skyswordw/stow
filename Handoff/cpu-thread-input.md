# Pack CPU thread input

## Confirmed direction

The user chose one numeric input in Pack > More Options. Its starting value follows Settings: an explicit global limit is shown as that number; the all-cores default is shown as the current available logical-processor count. Do not add a separate mode menu, presets, or a second custom-value control. This supersedes the earlier two-control and preset proposals.

Use **CPU threads** / **CPU 线程数** for the row. This is a compression-thread limit, not physical-core selection. The available count and the existing note that formats may use fewer threads remain concise secondary text. Codex owns validation, scope, focus and engine behavior; Claude Code owns final visual/motion/copy treatment. No new visual approval is claimed.

## Functional contract

- Untouched input retains the existing `nil` per-job override and follows the saved `PackCPUCores` value. A global preference update refreshes an untouched input.
- Editing creates a per-job override without writing global Settings. A valid explicit value remains fixed if the global preference changes.
- Accept whole numbers from 1 through the available logical-processor count. Preserve partial/invalid text while editing; do not silently clamp it or turn a blank into inheritance.
- Invalid input keeps Pack disabled, with an error visible beside the fixed footer even if More Options is collapsed. Recheck validity when dispatching Pack.
- Reset More Options clears the override and any invalid edit, restoring the current Settings value. Reopening a draft restores the saved numeric override; old out-of-range values are bounded consistently with the existing engine policy.
- Native text-field focus and scroll following remain enabled. The sheet budgets its scrolling area below its parent window's top so validation cannot push the footer offscreen.

## Reference wording

7-Zip's [official dialog source](https://github.com/ip7z/7zip/blob/main/CPP/7zip/UI/GUI/CompressDialog.rc) labels the parameter “Number of CPU threads.” The [official German WinRAR distributor's 5.90 history](https://www.winrar.de/info2.php) records a Threads input bounded by the available logical CPUs. These are wording/control references, not evidence for a universal recommended thread count. Stow does not promise that using every thread is always fastest.

## Validation

Native checks on the isolated Stow Test app in zh-Hans:

- A `PackCPUCores=3` launch override appears directly in the single input; the machine reports 10 available threads.
- Blank, 0, 1.5 and 11 remain visible as invalid edits and disable Pack; correcting to 2 enables it.
- Reset from a blank edit restores 3 and removes the error.
- Collapsing More Options retains the explicit 2-thread choice in its summary.
- A real file packed with that choice produced a ZIP with successful app verification. Independent ZIP CRC/content checks and a source-content comparison passed; evidence is `/tmp/stow-cpu-input/verified.json`.
- Focus/sizing and numeric-state regression tests cover inherited versus explicit values, invalid/overflowing text, restored limits and machines up to 256 available threads.

Full local suite: 719 tests in 107 suites passed with zero failures/skips. Simplified Chinese: 1,283/1,283 strings translated. Final human confirmation of this control remains pending. Dedicated VoiceOver remains deferred under #93; this does not complete the broader #161/#104/#38 matrix.
