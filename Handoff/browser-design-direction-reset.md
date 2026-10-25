# Browser direction after the PR #177 review

This brief supersedes the composition instructions and structural mockups in the earlier
product review, #160/#161 and Codex's initial #177 review comments. The user reported that
those instructions pulled Claude Code away from an earlier, more convincing Liquid Glass
design. Codex supplied overly specific composition rules; they are withdrawn as acceptance
criteria. This document updates the handoff, not the running app.

## Confirmed user decisions

- The full Browser remains the default; Glance is the optional compact mode.
- Full Browser Details stays visible and fixed. Remove its collapse affordance from this
  direction. Details contains content preview, file identity and properties, and archive
  information when nothing is selected; calling the entire pane Preview is too narrow.
- Floating Actions remains the feature direction and public name. Remove the duplicate
  filename/size summary beside Quick Look. The user clarified that this refers to the selected
  item's bottom summary, not the hover-preview feature. Item facts belong in Details.
- The user prefers ArcZip's overall Liquid Glass completion and the action-stack treatment in
  the supplied crops. Fidelity to Codex's old mockups is no longer a requirement.

## Left navigation: recommendation and the actual requirement

The user again questioned the need for a left navigation pane. Codex recommends removing it
from this Browser composition, including a permanent Folders toggle: a directory tree is one
possible navigation tool, not a functional requirement. PR #177 currently starts with that
pane closed but still retains it; that is not the same as the proposed simpler composition.

Preserve the ability to enter folders, reach a parent or archive root, traverse history,
search and locate nested results. Start with the file workspace and path/navigation controls.
A future directory overview needs evidence from a deep-archive task before adding another
pane. Claude Code chooses the visual solution; Codex / Grok Bot verifies path and state
correctness. Existing preferences do not override the user's newer fixed-Details direction.

## Direct action-stack reference

User-supplied ArcZip crops from this review:

| Collapsed stack | Expanded choices |
| --- | --- |
| ![Layered action stack](evidence/2026-10-24/arczip-actions-collapsed-user.png) | ![Separate Extract and Install Application choices](evidence/2026-10-24/arczip-actions-expanded-user.png) |

These images show compact overlap, a visible hint of further actions and separated readable
choices when expanded. They do not establish what triggers expansion, its timing, keyboard
behavior or the rule selecting the front action. Check those in the actual app before
claiming parity. The user's lower-left filename concern is a separate duplication issue.

Claude Code should explore this interaction using Stow's own appearance. The earlier demand
for a single enclosing capsule or a permanently printed Actions/filename block is withdrawn.
Expansion must have a usable keyboard/click path as well as any pointer treatment. Passing
over a filename or an action must never execute extraction or installation. Operation scope
must remain understandable, especially for multiple selection and while an operation runs;
that does not require repeating a filename card next to the buttons.

The earlier blanket instruction to keep Extract visually primary for every file kind was a
product proposal, not an engine/security requirement. Claude Code may propose a clearly
labelled contextual front action, including Install, while retaining deliberate activation,
an accessible extraction alternative and the existing installation confirmations, signature
and running-app safeguards. No automatic installation or changed safeguard is authorized
by these appearance references.

## Handoff method

Codex / Grok Bot should provide tasks, observed failures and functional invariants, then let
Claude Code design the visual solution. Label a proposal as a proposal and explain the task
behind it. A mockup is an exploration, not an implementation specification. Review a design
against the user's goals and real reference behavior, rather than similarity to Codex's
sketch. Use a small interaction prototype or actual app states before another broad rewrite;
this does not add a user approval gate to already authorized work.

Useful acceptance tasks: select a file and extract it; deliberately choose Install or Extract
for an app; navigate a deep/nested archive and return; find a search hit; cancel a password or
operation; retain staged edits and Undo through full/Glance switching. Include keyboard access,
real content, narrow windows, light/dark and accessibility fallbacks. Claude Code owns grouping,
materials, shape, density and motion. Codex / Grok Bot owns scope, state, errors, safety and
accessibility semantics. Record actual reference triggers separately from visual preferences.
