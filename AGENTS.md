# Collaboration

All rules and responsibilities assigned to Codex in this document apply equally to
Grok Bot.

## Working language

- Use **English** for issue titles, descriptions, and comments; PR titles, descriptions,
  and review comments; commit messages; and agent handoff documents.
- Use English for code identifiers, source comments, and developer documentation, following
  the surrounding code's conventions. Apply this rule to new work and substantive updates.
- Keep user-facing translations in their intended languages. Preserve original quotations,
  logs, and filenames when they are needed as evidence.

## Ownership

- **Claude Code owns UI visual design and motion:** layout, spacing, typography, color,
  materials, icon treatment, visual hierarchy, transitions, and animation tuning.
- **Codex and Grok Bot own functional correctness:** archive behavior, state, security, errors,
  cancellation, tests, and accessibility semantics. Both may implement functional controls
  needed by a fix; their visual and motion treatment remains pending Claude Code review.
- Claude Code preserves the functional contracts and accessibility behavior described in the
  handoff, and calls out any behavior change a design needs explicitly in its PR.
- Codex and Grok Bot should describe interaction goals, states, constraints, and design ideas as a brief
  for Claude Code. These proposals are references, not final visual approval.
- Record this ownership in relevant issues and PRs. Do not claim Claude Code has reviewed,
  accepted, or started a task without evidence, or assign an unknown GitHub account.

Follow [DESIGN.md](DESIGN.md) and the current
[UI and motion handoff](Handoff/ui-motion-claude-code.md). Compare archive interactions
against **ArcZip** while retaining Stow's own vocabulary and design language.

This division does not add a user approval gate to already authorized work.

## Accessibility priority for the current milestone

- Full VoiceOver support, dedicated screen-reader refinement, and native VoiceOver acceptance
  testing are deferred while the core product is being completed. Missing VoiceOver validation
  alone is not a merge or release blocker for the current milestone.
- Preserve existing accessibility semantics, meaningful control names, basic keyboard access,
  focus behavior, and support for system display/motion preferences. Make low-cost improvements
  alongside functional work; do not require a separate VoiceOver campaign for every PR.
- Record known AX/VoiceOver limitations in the relevant issue. Keep #93 open as a low-priority,
  deferred investigation; do not claim it is fixed without evidence. Crashes reproduced during
  ordinary mouse or keyboard use remain stability defects and are prioritized by their impact.
- Computer Use may use AX for functional testing. Report AX-tree inspection/activation separately
  from actual VoiceOver testing. Assess an AX failure that blocks automation on its testing impact;
  it does not automatically make complete VoiceOver support a product acceptance requirement.
- This confirmed priority supersedes VoiceOver acceptance gates in older briefs and PR checklists.
  Ownership above remains unchanged.

## Design handoffs and review

- Separate confirmed user decisions, observed reference behavior, functional requirements and
  optional visual ideas. Describe the task and observable outcome behind a requirement.
- Codex / Grok Bot mockups are exploratory. Fidelity to them is not an acceptance criterion;
  Claude Code may replace their composition, control grouping and material treatment.
- Use actual ArcZip interactions and user-supplied references before inventing interaction
  details. Static screenshots establish appearance/states, not their trigger or timing.
- Review state, scope, keyboard access and security as functional requirements. Let Claude Code
  choose their visual expression, and explain any behavior change explicitly.
- When user feedback supersedes guidance, update the current brief and mark obsolete mockups
  and PR comments as superseded. Keep one current direction instead of accumulating conflicting
  instructions. The current Browser decisions live in DESIGN.md and its linked handoff.

## Build and check

Full details are in [README.md](README.md); CI enforces the last two checks.

- Run `scripts/fetch-7zip.sh` once in each checkout or worktree. It puts the pinned 7-Zip into
  the gitignored `Vendor/`.
- `Stow.xcodeproj` is generated and gitignored. Edit `project.yml`, not the project, and run
  `xcodegen generate` after changing it or adding or removing source files.
- Build: `xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build build`
- Test: `xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build test`
- When validating Finder or Quick Look installation, run `scripts/register-extensions.sh`
  with the exact intended app path. A routine build/test must not replace the user's registered
  extensions with a temporary checkout. Coordinate signed system-integration artifacts with
  the release collaborator; see #32 and #38.
- Design screenshots: `scripts/snapshot.sh <scene> [light|dark]`. Scenes are listed in the README.
- Every user-facing string needs a Simplified Chinese translation:
  `scripts/check-localizations.sh zh-Hans`.
- Commit any plists that `xcodegen generate` rewrites; CI fails when they differ from `project.yml`.

## Where things are

- [README.md](README.md): requirements, archive engine and Finder integration architecture, and
  the source layout table.
- [DESIGN.md](DESIGN.md) and [Handoff/](Handoff/): design language, current briefs, native audits.
- [PARITY.md](PARITY.md): feature comparison with ArcZip.
  [ROADMAP.md](ROADMAP.md): remaining work and tests not yet run.
- [RELEASING.md](RELEASING.md): signed and notarized builds, Sparkle appcast, release workflow.
- [ERROR-CODES.md](ERROR-CODES.md): the user-visible error codes; `ErrorCodeTests` pins them.
