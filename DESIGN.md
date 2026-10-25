# Stow — Design Language

> Working name. Check trademarks before launch.

**Ownership:** Claude Code owns UI visual design and motion. Codex provides interaction
intent and functional constraints; see [AGENTS.md](AGENTS.md) and the
[current handoff](Handoff/ui-motion-claude-code.md).

Stow is an archive tool for macOS. The design goal is not "a nicer file list". It is an app that
answers the three questions people actually have when they meet an archive:

1. **What's in it?** — see contents instantly, preview without extracting.
2. **Is it safe?** — know before extracting whether anything is odd.
3. **What do I do next?** — the right next step is already on screen.

And when packing: **"Will it work on their computer?"**

---

## Principles

| Principle | What it means here |
| --- | --- |
| **Native first** | SwiftUI + AppKit, Liquid Glass, SF Symbols, system font, system controls. No web views, no custom chrome that fights the OS. |
| **Content is the hero** | Glass is the floating control layer; the archive's contents are the solid layer beneath. Never glass on glass. |
| **Say it in a sentence** | Options are expressed as a readable sentence ("Pack 12 items as ZIP for Windows PCs"), not a dialog of checkboxes. |
| **Trust is visible** | Every opened archive gets a safety summary. Risky things are explained in plain words, not error codes. |
| **Fast hands, no animation** | Keyboard actions and things done 100×/day never animate. Motion is reserved for spatial changes and rare moments. |
| **Forgiving** | Nothing touches the original until "Save". Every destructive step is undoable or staged. |

## Vocabulary (our own — do not borrow competitor names)

| Concept | Name in Stow | Notes |
| --- | --- | --- |
| Main window | **Browser** | Content workspace with optional folder navigation and preview |
| Compact quick window | **Glance** | Small floating window near the pointer for quick extract |
| Context actions | **Actions** | Coherent floating action region for the current selection |
| Drop shelf | **Tray** | Floating panel that collects files from anywhere |
| Purpose presets | **"For…" destinations** | Windows PCs · Macs · Linux & servers · Web upload |
| Compression dialog | **Pack sentence** | Sentence-builder with tappable tokens |
| Safety report | **Checkup** | Badge on the archive card + detail popover |

**Confirmed direction, 2026-10-24:** the full Browser remains the default; Glance is optional.
The user chose **Actions** as the English public name and confirmed the **floating Actions**
direction. They also asked to reduce the bulk of the current three-pane composition, using
ArcZip's content-first layout as a reference. The proposed structure gives files the main
surface, with folder navigation and preview available as needed; exact defaults and final
visual treatment belong to the #160 design brief. Existing builds still say “Next Steps”;
[issue #161](https://github.com/skyswordw/stow/issues/161) tracks the public-copy and presentation
transition. “快捷操作” is a proposed Simplified Chinese localization, pending copy review.
Internal types and stored preference keys may retain their existing names. Preserve explicit
user preferences. Other layout/material defaults remain proposals in the
[product design review](Handoff/product-design-review-2026-10-24.md).

## Color

- **Accent — Amber** `#D97B2B` (light) / `#F0954A` (dark). Warm, like kraft paper and parcel tape;
  stands apart from the sea of blue utilities. Used sparingly: primary button, selection tint,
  the drop target, and the Checkup badge when everything is fine is *green*, not amber.
- Everything else is system semantic color (`.primary`, `.secondary`, `.separator`, materials).
- Status: safe = system green, caution = system yellow, blocked = system red. Always paired with an
  icon and words — never color alone.

## Type

System font (SF Pro), Dynamic sizes via text styles. Hierarchy is weight + size together.

| Role | Style |
| --- | --- |
| Archive title on card | `.title3`, semibold |
| Section headers | `.subheadline`, semibold, secondary |
| Row title | `.body` |
| Metadata | `.callout` / `.caption`, secondary, **monospaced digits** for sizes & counts |
| Pack sentence | `.title2`, regular; tokens semibold in accent |

Numbers that change (counts, sizes, progress) use `.monospacedDigit()` and
`.contentTransition(.numericText())` so they don't jitter.

## Space & shape

- 4-pt grid. Spacing tokens: 4, 8, 12, 16, 24, 32.
- Corner radii are **concentric**: a window-level panel 16, cards inside 12, chips inside 8.
- Separation by spacing and subtle fills first; hairline separators only where lists need them.

## Motion

Values from Apple's fluid-interface guidance and Emil Kowalski's design-engineering rules
(see `.claude/skills/apple-design`, `.claude/skills/emil-design-eng`).

| Moment | Motion | Value |
| --- | --- | --- |
| Actions region appears | Spring, from bottom, scale 0.96 → 1 + opacity | `response 0.32, damping 1.0` |
| Actions content changes on selection | **None** (frequent) — numbers use numeric text transition | — |
| Floating chrome leaves (Actions, pack capsule, batch panel) | Ease-out fade with a smaller drop — faster than it came | 180 ms |
| A step finishes or fails on its own | Ease-out, never a spring (nobody touched it) | 200 ms |
| Capsules or the inspector shown/hidden by a key (arrows, ⌘A, Esc, ⌥⌘I) | **None** | — |
| Drop target on drag-over | Spring scale 1.0 → 1.015, accent tint fades in | `response 0.25, damping 0.9` |
| Hover preview | 450 ms delay for the first; **instant & unanimated** for neighbours while one is open; closes instantly | 140 ms fade |
| Tray panel show/hide | Same edge in, same edge out: scale 0.96 → 1 from the menu bar + opacity (`Motion.presence`) | `appear` in, `exit` out; **none** for ⌥⌘T and Esc |
| Glance opens (click, Finder) | Content springs out of the pointer, scale 0.96 → 1 + opacity; glass fades in | `response 0.32, damping 1.0` |
| Glance via ⌥⌘G, Esc, Glance ↔ full window by keyboard | **None** | — |
| Pack sentence token change | Blur-crossfade of the token text | 180 ms |
| Welcome and Browser windows replace each other (an archive opens or closes) | The system's own window opening and closing; **none** when a key press switched them | — |
| View-mode switch, keyboard nav, search filtering | **No animation** | — |
| Button press | System controls handle it | — |

Reduced Motion: springs become 150 ms opacity fades (exits 100 ms); nothing translates or scales.
Reduced Transparency: glass falls back to solid window background (the system does this for us).

## Signature details

- **Compact archive identity** in the Browser's title/navigation region. Detailed file counts,
  packed → unpacked sizes and compression facts have one home in Archive Info. Keep encryption
  and Checkup directly discoverable when the optional folder tree and preview are closed.
- **Checkup** lists findings in plain words: "2 files would extract outside the folder — they'll be
  kept inside", "1 app inside is not signed".
- **Pack sentence** shows a live compatibility report underneath: names that will be adjusted for
  Windows, Mac-only files left out, the estimated size.
- **Empty states** teach: the welcome window *is* a drop target and says what dropping does.
  It is a **window of its own**, fixed and compact (640 × 600) like most welcome windows: it can't
  be resized or zoomed. The drop zone sits on top, Recent below; with no history the drop zone is
  the whole window. Opening an archive brings up the Browser window at its last size and place and
  closes the welcome; closing the archive brings the welcome back. Only one of them is open at a time.

## Not doing (on purpose)

- No toolbar full of icons. Primary action (Extract) is prominent; the rest live in Actions and menus.
- No splash, no onboarding carousel.
- No animated keyboard navigation, no bouncing on menus.
