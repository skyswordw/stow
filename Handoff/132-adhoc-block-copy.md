# Issue #132 — Conditional signature warning copy

The installation warning previously guaranteed that macOS would block an ad-hoc app
on first launch. A non-quarantined locally built app does not necessarily encounter
that decision. Signature classification alone cannot predict Gatekeeper's outcome.

Changed the shared `CodeSignature.Verdict.finding` explanations for ad-hoc, unsigned,
and unnotarized apps to say macOS **may** block the first opening. The identity and
notarization warnings remain explicit. Simplified Chinese uses the same conditional
meaning. Unnotarized-app settings guidance now applies only if opening is blocked.

`Prompts.ask` uses the shared finding and still asks “Install it anyway?” with
“Install Anyway” and the safe default “Cancel”. The inspector uses that same finding.
Classification, signature validation, confirmation requirements, and quarantine handling
are unchanged. No project generation or Xcode project changes were made.

Codex owns this functional accuracy correction. Claude Code retains ownership of visual
design and motion under DESIGN.md and Handoff/ui-motion-claude-code.md; no review or
approval is claimed. Interaction intent: retain clear risk information and explicit
consent without predicting a guaranteed OS launch decision. No layout or motion change
is proposed. ArcZip remains the archive-interaction comparison target; native comparison
was not available in this environment.

Validation: parsed the string catalog, checked all three changed English/zh-Hans entries
and matching format placeholders, verified the unconditional wording is absent from the
signature source, and ran `git diff --check`. No new @Test declarations (also zero net
new versus origin/main); MIN_TESTS remains 410. Native Swift/macOS tests and Xcode
localization export could not run here because Xcode is unavailable; CI must run them.
