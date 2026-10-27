# Browser + Actions visual iteration brief — #160 / #161

Claude Code owns this pass. Codex / Grok Bot do **not** ship a substitute visual PR.
Current main already includes the merged #177 content-first Browser and floating Actions.
Neil asked for another visual/copy round against the #177 review and the direction reset.

## Read first

1. [browser-design-direction-reset.md](browser-design-direction-reset.md) (merged via #178)
2. DESIGN.md + [ui-motion-claude-code.md](ui-motion-claude-code.md)
3. Issue comments on PR #177 (especially the Liquid Glass / Details / control-layer notes):
   https://github.com/skyswordw/stow/pull/177#issuecomment-6394820869
   https://github.com/skyswordw/stow/pull/177#issuecomment-6394911600
   https://github.com/skyswordw/stow/pull/177#issuecomment-6395112336
4. Issues #160 and #161 (current direction sections supersede older mockup-fidelity text)

## Confirmed user decisions (do not regress)

- Full Browser default; Glance optional.
- Details fixed and visible; no collapse toggle; pane named Details, not Preview.
- Floating Actions; remove duplicate filename/size beside Quick Look (facts live in Details).
- Prefer ArcZip Liquid Glass coherence; Codex mockup fidelity is **not** acceptance.
- Left tree is not a functional requirement; keep folder entry, parent/root/history, search.
- Install safeguards and explicit activation stay; no silent default-Install policy changes.

## Goals for this iteration

1. Coherent Liquid Glass family across navigation, view controls, floating Actions, Details rim.
2. Details content design (bounded preview, identity, compact properties) — not a sparse form.
3. Resolve competing control layers / duplicated Preview vocabulary where any remains.
4. Location copy uses real archive path semantics (Codex owns correctness if touched).
5. Actions stack optical weight; matched flat/deep en/zh light/dark evidence via
   `scripts/snapshot.sh`.

## Functional constraints (Codex review if behavior changes)

Preserve BrowserModel state, search without sidebar, Extract All vs selection scopes,
cancellation, password/Checkup discoverability, keyboard focus, existing AX semantics.
List any behavior change explicitly in the PR. VoiceOver native pass remains deferred (#93).

## How to launch Claude Code on Mac mini A

Claude CLI is installed at `/opt/homebrew/bin/claude` (2.1.31) but needs interactive login
(`claude` currently reports Invalid API key — run `/login` in the CLI or complete auth in
Terminal as Neil).

Suggested flow:

```zsh
cd /Users/neardws/stow-work/main-baseline
git fetch origin
git worktree add -b design/160-161-visual-iter3 /Users/neardws/stow-work/design-160-161-iter3 origin/main
cd /Users/neardws/stow-work/design-160-161-iter3
scripts/fetch-7zip.sh
xcodegen generate
claude   # after auth: point it at issues #160 #161, this brief, and snapshot.sh
```

Open the design PR against main; keep the branch after merge. Do not claim Claude reviewed
unless the PR is actually from Claude Code.
