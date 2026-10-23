# Collaboration

## Ownership

- **Claude Code owns UI visual design and motion:** layout, spacing, typography, color,
  materials, icon treatment, visual hierarchy, transitions, and animation tuning.
- **Codex owns functional correctness:** archive behavior, state, security, errors,
  cancellation, tests, and accessibility semantics. Codex may implement functional controls
  needed by a fix; their visual and motion treatment remains pending Claude Code review.
- Codex should describe interaction goals, states, constraints, and design ideas as a brief
  for Claude Code. These proposals are references, not final visual approval.
- Record this ownership in relevant issues and PRs. Do not claim Claude Code has reviewed,
  accepted, or started a task without evidence, or assign an unknown GitHub account.

Follow [DESIGN.md](DESIGN.md) and the current
[UI and motion handoff](Handoff/ui-motion-claude-code.md). Compare archive interactions
against **ArcZip** while retaining Stow's own vocabulary and design language.

This division does not add a user approval gate to already authorized work.
