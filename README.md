# #161 walkthrough and keyboard run — evidence

Native captures of a Debug build of `main` at `b8c4d38`, 2026-11-02. Stow was driven in the
background with computer use. The fixture is `Actions Mix.zip`: a folder with an app bundle, two
fonts, an installer package, a photo, a nested ZIP, text files and one long name. The captures
are window-only and mostly of windows that weren't key. That's why selections and switches look
grey and the glass looks flat.

## Walkthrough (find → customize → return)

| File | Step |
| --- | --- |
| `en-full-01-opened-nothing-selected.jpg` | Archive opened: only Glance and Extract All at the bottom; no Actions yet |
| `en-full-02-select-photo-actions-appear.jpg` | Selecting a photo brings in ⋯ and Extract, bottom right |
| `en-full-03-stack-fanned.jpg` | Clicking the edges fans out Quick Look above Extract |
| `en-full-04-customize-opens-settings-actions.jpg` | File › Actions › Customize Actions… opens Settings on the Actions pane |
| `en-full-05-suggestion-toggles.jpg` | Suggested Actions toggles |
| `en-full-06-preview-after-customizing.jpg` | Pack on, Quick Look off: the preview redraws |
| `en-full-07-return-stack-shows-pack.jpg` | Back in the archive: the same selection's stack now has Pack… behind Extract |
| `en-glance-08-same-selection-stack.jpg` | Glance keeps the selection and the stack; Extract All steps aside |
| `en-glance-09-fanning-out.jpg` | Fanning out in Glance (caught mid-rise) |
| `en-glance-10-settings-restored.jpg` | Customize Actions… from Glance, then Restore Defaults |
| `en-glance-11-return-defaults.jpg` | Back in Glance with the defaults |
| `zh-full-01-opened.jpg` … `zh-glance-07-return-defaults.jpg` | The same in zh-Hans, with the app selected (安装 App in front) and 安装 App then turned off |

## Keyboard run

| File | Step |
| --- | --- |
| `kb-01-right-arrow-selects-first.jpg` | Focus starts in the files: → selects the first item |
| `kb-02-cmd2-list-down-arrows.jpg` | ⌘↓ opens the folder, ⌘2 switches to List, ↓ moves the selection; the front action follows (Install Font) |
| `kb-03-cmd-e-extracted.jpg` | ⌘E extracts the selection |
| `kb-04-opt-cmd-g-glance-keeps-selection.jpg` | ⌥⌘G switches to Glance; the selection and list focus carry over |
| `kb-05-glance-shift-cmd-e-extract-all.jpg` | ⇧⌘E in Glance (key window) starts Extract All |
| `kb-06-keyboard-selects-app-install-front.jpg` | The app reached by arrows only: Install App in front |
| `kb-07a-stack-open.jpg`, `kb-07b-esc-right-after-opening-folds.jpg` | Esc right after fanning out folds the stack (it stays open without Esc) |
| `kb-08-settings-sidebar-arrows-to-actions.jpg` | Arrow keys in the Settings sidebar reach Actions |
| `kb-09a/b/c-glance-*.jpg` | Glance: the first Esc folds the stack, the second clears the selection and Extract All comes back |

## Observations

| File | What |
| --- | --- |
| `obs-glance-inactive-selection-faint.jpg` | Glance not key: the selected row (Harbor.jpg) is barely visible on the glass |
| `obs-file-actions-stale-front-is-extract.jpg` | After Install App was turned off, the stack's front is Extract, but File › Actions still listed Install App first |
