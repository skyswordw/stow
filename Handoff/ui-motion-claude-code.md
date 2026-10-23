# UI and motion handoff — Claude Code

The user has explicitly assigned UI visual design and animation to **Claude Code**.
Codex supplies interaction intent and functional constraints. The proposals below are
starting points for Claude Code's judgment, not approved final visual designs.

This document records a handoff; it does not mean a Claude Code session has been dispatched.
Track the design work in [issue #104](https://github.com/skyswordw/stow/issues/104).

## Starting point

Use [DESIGN.md](../DESIGN.md): native SwiftUI/AppKit, content before chrome, Liquid Glass
for floating controls, a restrained amber accent, semantic status with words and icons,
and Stow's own Browser / Glance / Next Steps vocabulary. ArcZip is the comparison target
for archive interactions, not a visual template to copy.

Functional changes already merged:

- [PR #100](https://github.com/skyswordw/stow/pull/100): website says “Made for Mac.
  Designed with Liquid Glass.” The actual minimum remains macOS 26+.
- [PR #101](https://github.com/skyswordw/stow/pull/101): accurate encryption labels,
  compression display, settings accessibility, language guidance, and scrolling.
- [PR #103](https://github.com/skyswordw/stow/pull/103): explicit archive password entry,
  verified unlock, password-aware previews, retry, and cancellation.

These merges establish behavior, not Claude Code approval of their appearance or motion.
The latest published installation is 0.1.1 (279); these changes are on main after that
release. Before visual comparison, build current main, confirm the running app's path and
build identity, and record the commit and comparison-app version. Native verification was
last blocked by a locked Mac; screenshots from CI are not a substitute for interaction QA.

## 1. Make encryption discoverable without blocking browsing

**Intent:** someone who can see filenames should still understand that file contents need
a password, where to enter it, and whether a read has actually succeeded.

ArcZip 1.1.4 (255) lists filenames from an ordinary encrypted ZIP before password entry
and offers a clickable title-bar lock. That is consistent with ZIP headers being public.
Stow should keep useful browsing available and make the password action easy to discover.

| State | Interaction contract | Visual question for Claude Code |
| --- | --- | --- |
| Encrypted contents, no usable password | A labelled lock action opens password entry; public filenames remain browsable. | Make the lock discoverable in Browser and compact Glance without competing with Extract. |
| Password prompt | Explain why a password is needed; permit cancel and optional Keychain saving. | Refine hierarchy, field/error placement, focus, and concise English/Chinese copy. |
| Verifying | Read an encrypted entry to verify; prevent duplicate unlock requests; allow cancellation. | Show progress with stable layout and restrained feedback. |
| Successful read | Refresh previews; reuse credentials where applicable. Current status is “Password Available”. | Convey useful progress without claiming every entry is unlocked: ZIP entries can use different passwords. |
| Wrong password or cancelled | Keep browsing state; allow retry; cancellation never saves late credentials. | Keep errors near the action and avoid success-like motion or repeated modal surprises. |
| Locked inspector preview | Offer “Enter Password…” as an explicit action. | Clarify the relationship between the preview message and toolbar lock. |

Explicit open/preview can request a password. Hover and background preview work must never
open a password prompt. A successful listing alone is not proof of successful decryption.
Do not infer AES-256 from a boolean encryption flag. Keychain storage remains opt-in;
passwords never belong in command arguments or logs.

Relevant files:

- `App/Browser/ArchiveUnlockControl.swift`, `BrowserModel.swift`, `BrowserView.swift`
- `App/Glance/GlanceView.swift`
- `App/Password/PasswordPrompt.swift`, `PasswordSheet.swift`
- `App/Preview/PreviewService.swift`, `PreviewViews.swift`, `QuickLookController.swift`
- `App/Browser/InspectorView.swift`, `SidebarView.swift`
- `Tests/PasswordTests.swift`

## 2. Make settings easy to scan and fit

**Proposal:** keep the common choice prominent, place explanations next to the choice they
explain, and let long content scroll without hiding controls. Claude Code should decide
the final grouping, density, window sizing, copy treatment, and spacing.

Review General's long per-app language guidance, Passwords with a long saved-password
list, Next Steps controls, and Integration folder grants. The current General height of
700 and Passwords height of 560 are functional accommodations, not final design targets.
Language guidance must describe the actual macOS workflow unless a working in-app picker
is implemented. Preserve explicit accessibility names/hints and keyboard access; decorative
icons must not replace control names.

Relevant files: `App/Settings/PreferenceViews.swift`, `SettingsPane.swift`,
`NextStepsSettingsView.swift`, and `App/Integration/IntegrationView.swift`.

## 3. Distinguish a sample from real archive operations

[Issue #91](https://github.com/skyswordw/stow/issues/91) remains open. The PDFs are now real,
but the sample's listing and actions still use in-memory demonstration behavior. Do not
present simulated extraction, installation, or edits as verified archive functionality.

**Codex proposal for consideration:** use a genuine example ZIP if a sample ships in the
regular release, so the normal browse/preview/extract flow teaches the real product. An
alternative is to remove the regular-release entry and keep clearly marked design-review
scenes. Claude Code should propose the entry point, labelling, and empty-state treatment;
the product choice remains tracked in #91. Real screenshot/video assets are tracked in
[#69](https://github.com/skyswordw/stow/issues/69).

## Motion intent

Follow the existing motion table in DESIGN.md. Claude Code owns animation treatment and
tuning. Preserve these interaction constraints:

- Keyboard navigation, search filtering, view changes, and keyboard-triggered show/hide
  remain immediate. Frequent selection changes should not make the interface feel delayed.
- Password verification is asynchronous feedback: it should not bounce like a direct
  manipulation or imply success before a read finishes.
- Avoid moving the lock/action target when status text or progress changes.
- Hover preview keeps its deliberate first delay and immediate warmed-neighbor behavior.
- Respect Reduced Motion and Reduced Transparency; retain understandable status and focus
  when animation or glass is absent.

## Review and delivery

Include before/after evidence in the design PR, explain the hierarchy and motion choices,
and link the functional issues/PRs above. Check English and Simplified Chinese, light and
dark appearances, compact Glance and small windows, long filenames/password lists,
keyboard focus, VoiceOver labels, Reduced Motion, and Reduced Transparency.

Exercise a real public-header encrypted ZIP, encrypted filenames, wrong password, cancel,
successful read, and mixed-password entries. Functional tests should protect state and
cancellation behavior; screenshots alone cannot prove it. The #103 baseline passed 390
tests, localization checks, Universal 2 build, packaged-app launch, and en/zh light/dark
snapshot CI; that does not establish final visual quality.

[Issue #93](https://github.com/skyswordw/stow/issues/93), an accessibility activation crash
reproduced in published 0.1.1, remains a separate technical investigation. Do not close it
on the strength of this visual review or assume #103 fixed it.
