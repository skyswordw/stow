# Collaboration

## Working language

- Use **English** for issue titles, descriptions, and comments; PR titles, descriptions,
  and review comments; commit messages; and agent handoff documents.
- Use English for code identifiers, source comments, and developer documentation, following
  the surrounding code's conventions. Apply this rule to new work and substantive updates.
- Keep user-facing translations in their intended languages. Preserve original quotations,
  logs, and filenames when they are needed as evidence.
- Match the user's preferred language in direct conversation.

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
