# #91 — Real sample ZIP for Try the Sample

## Decision
Neil chose a genuine example ZIP over removing Try the Sample or keeping a labelled fake.
This also advances #69 (Try the Sample opens the same Harbor content as screenshots) without
inventing new demo assets outside that issue's CC0 / existing-folder scope.

## What changed
- `Resources/Sample/Harbor Rebrand Handoff.zip` packs the real files under
  `Resources/Sample/Harbor Rebrand Handoff/` (rebuild: `zsh scripts/make-sample-zip.sh`).
- Welcome / Onboarding / File › Open Sample Archive call `AppState.openSample()`, which opens
  that ZIP through `open(url)` — browse, preview, Extract, and Install Fonts use the engine.
- Unsupported fictional entries (`.app`, `.pkg`, `.mov`, `.wav`, nested `.7z`) are **not** in the ZIP.
- `SampleArchive.make()` remains for `DemoScene` / design-review listings only.

## Out of scope (still #69)
Retaking website screenshots / walkthrough frames, and handing the sample to the #31 video.
