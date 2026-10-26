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
| **Content is the hero** | Keep archive content readable and give navigation, Details and floating actions coherent depth and Liquid Glass treatment. Claude Code owns the surface composition, including purposeful overlapping controls. |
| **Say it in a sentence** | Options are expressed as a readable sentence ("Pack 12 items as ZIP for Windows PCs"), not a dialog of checkboxes. |
| **Trust is visible** | Every opened archive gets a safety summary. Risky things are explained in plain words, not error codes. |
| **Fast hands, no animation** | Keyboard actions and things done 100×/day never animate. Motion is reserved for spatial changes and rare moments. |
| **Forgiving** | Nothing touches the original until "Save". Every destructive step is undoable or staged. |

## Vocabulary (our own — do not borrow competitor names)

| Concept | Name in Stow | Notes |
| --- | --- | --- |
| Main window | **Browser** | File workspace and a fixed Details pane; no left navigation pane in the current direction |
| Information pane | **Details** | File preview, identity and properties; archive information when nothing is selected |
| Compact quick window | **Glance** | Small floating window near the pointer for quick extract |
| Context actions | **Actions** | Coherent floating action region for the current selection |
| Drop shelf | **Tray** | Floating panel that collects files from anywhere |
| Purpose presets | **"For…" destinations** | Windows PCs · Macs · Linux & servers · Web upload |
| Compression dialog | **Pack sentence** | Sentence-builder with tappable tokens |
| Safety report | **Checkup** | Shield button in the title bar; findings in Archive Info |

**Current direction after the user's PR #177 review, 2026-10-24:** the full Browser remains
the default; Glance is optional. The full Browser has a file workspace and **fixed, visible
Details**, with no Details collapse toggle. Remove the separate left folder-navigation pane
from the proposed Browser composition; retain navigation through the files, breadcrumbs,
history, parent navigation and search. This supersedes the earlier optional-left/optional-right
pane studies. Claude Code owns the final visual composition and motion.

The user chose **Actions** as the English public name and confirmed floating Actions. The
bottom action region should contain commands, without repeating the selected filename/size
summary next to Quick Look; those facts belong in Details. The supplied ArcZip collapsed and
expanded action-stack crops are the preferred interaction reference to investigate. Neither
a single enclosing capsule nor fidelity to Codex's earlier mockups is required. See the
[current direction and evidence](Handoff/browser-design-direction-reset.md).

Existing main builds still say “Next Steps”;
[issue #161](https://github.com/skyswordw/stow/issues/161) tracks the public-copy and presentation
transition. “快捷操作” is a proposed Simplified Chinese localization, pending copy review.
Internal types and stored preference keys may retain their existing names. Preserve explicit
user preferences where compatible with these newer product decisions. The
[earlier product design review](Handoff/product-design-review-2026-10-24.md) retains historical
evidence; its optional-pane composition and mockups are superseded.

## Browser layout (#160, #161)

| Region | Holds |
| --- | --- |
| Title bar | The archive's name with a ⌄ menu (Archive Info, Show in Finder, Rename, Close), “ZIP archive · 17 files” under it; view mode; **Checkup** shield (and the password lock when encrypted) at the trailing edge |
| Navigation, floating over the files | One glass capsule: Back · Forward · Up │ the path (a short path takes only its width; a deep one scrolls and fades at its start). **Search** in its own glass capsule on the trailing side |
| Files | The main surface: grid, list or columns. In the list, the name takes the spare width before size, kind and date grow |
| Details (always there, right) | An inset panel, not a strip of the window: a content-sized preview, the name and kind, then properties as label ↔ value rows with hairlines (Size, Compressed size with the saving underneath, Modified, **Location** as the real path: “Showcase.zip › Showcase › Docs”). **Archive Info** when nothing is selected. No toggle, no close button, no action buttons |
| Archive controls, floating bottom leading | One glass capsule: **Glance** · **Extract All** |
| Actions, floating bottom trailing | ⋯ More, then the **stack**: the front action in the accent with the edges of the others showing behind it. No name or size: Details says what's selected. With nothing selected, **Install App** alone when the archive is one app |

**The Actions stack.** The front button is what the selection is most likely for: **Install** for
an app, fonts or an installer package, otherwise **Extract**. The other shown steps wait behind it,
nearest first, and fan out above it, the same width as the front, when the pointer rests on the
stack or its edges are clicked; leaving folds them back, and Esc folds them before it clears the
selection. Only the strip above the front button opens the stack, so a click or an accessibility
press aimed at it can never land on the front action. Pointing only reveals: every action takes a
click, and the existing install confirmations and signature checks are unchanged. The front
button's help tag names what it acts on ("Install App: Harbor Prototype.app"). More (⋯) lists
every action except the front one; **File › Actions** lists all of them, front first, so the
keyboard reaches every action without macOS's keyboard navigation turned on. ⌘E still extracts
from the menu bar whichever button is in front.

With nothing selected, an archive that's one app offers **Install App** for that app, as ArcZip
does. It's the app Stow selects on opening: the only app or package at the top, beside at most
two other items, or any number on a disk image. It shows as a single button, with no edges and
no ⋯, since Extract All is already beside it. Its help tag names the app, and it runs the same
install, with the same confirmations and checks, on that app only. Hiding Install App or Actions
in Settings removes it; File › Actions still lists it. Glance shows the same pair: Extract All,
then Install App.

One prominent action at a time: Extract All carries the accent while Actions is down; once
Actions is up, for a selection or an archive's app, the stack's front does and Extract All stays
put, unaccented. Archive facts live in one place, Archive Info, reached from Details with nothing
selected, the Checkup button and the title menu. Everything floating shares one family: glass
capsules, buttons concentric inside them (button radius + inset = capsule radius), 36–38 pt tall.
Details is a solid reading surface with the same light rim, brighter along its top edge.

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
| Pack sentence | `.title2`, regular; tokens semibold in accent, each with a small pull-down chevron so it reads as a menu |

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
| Actions shown/hidden or its stack opened/closed by a key (arrows, ⌘A, Esc) | **None** | — |
| Actions stack fans out (pointer rests 140 ms on it, or its edges clicked) | Spring: each action rises from behind the front button, scale 0.9 → 1 + opacity; folds back with an ease-out 450 ms after the pointer leaves (ArcZip lingers 0.5–1 s; it also opens at once, which flashes on every pass, so Stow waits 140 ms). Choosing an action or a new selection folds it at once, unanimated. Fade only under Reduce Motion | `response 0.32, damping 1.0` in, 180 ms out |
| Drop target on drag-over | Spring scale 1.0 → 1.015, accent tint fades in | `response 0.25, damping 0.9` |
| Tray rows a drop (or Add Files…) brought in, new or already there | Accent ring and faint tint **at once**; fade out after 1.2 s; scrolled into view if below the fold (no scroll animation under Reduce Motion) | fade `Motion.status` 200 ms |
| Hover preview | 450 ms delay for the first; **instant & unanimated** for neighbours while one is open; closes instantly | 140 ms fade |
| Tray panel show/hide | Same edge in, same edge out: scale 0.96 → 1 from the menu bar + opacity (`Motion.presence`) | `appear` in, `exit` out; **none** for ⌥⌘T and Esc |
| Glance opens (click, Finder) | Content springs out of the pointer, scale 0.96 → 1 + opacity; glass fades in | `response 0.32, damping 1.0` |
| Glance via ⌥⌘G, Esc, Glance ↔ full window by keyboard | **None** | — |
| Pack sentence token change | Blur-crossfade of the token text (the chevron stays put) | 180 ms |
| Pack password check rows (re-enter, mismatch) appear or go | Ease-out fade, never a spring; **none** when typed | 200 ms |
| Welcome and Browser windows replace each other (an archive opens or closes) | The system's own window opening and closing; **none** when a key press switched them | — |
| View-mode switch, keyboard nav, search filtering | **No animation** | — |
| Button press | System controls handle it | — |

Reduced Motion: springs become 150 ms opacity fades (exits 100 ms); nothing translates or scales.
Reduced Transparency: glass falls back to solid window background (the system does this for us).

## Signature details

- **Compact archive identity** in the Browser's title/navigation region. Detailed file counts,
  packed → unpacked sizes and compression facts have one home in Archive Info. Keep encryption
  and Checkup directly discoverable. Full Browser Details stays visible; Glance provides the
  optional compact experience. The exact home of Archive Info remains Claude Code's decision.
- **Checkup** lists findings in plain words: "2 files would extract outside the folder — they'll be
  kept inside", "1 app inside is not signed".
- **Pack sentence** shows a live compatibility report underneath: names that will be adjusted for
  Windows, Mac-only files left out, the estimated size. **More Options** is a full-strength heading
  that lists its current settings while closed; inside, choices a format can't offer say why in
  plain words instead of only in a tooltip. When the screen is short, only the middle of the sheet
  scrolls (its cut-off edge fades) and the name, Cancel and Pack stay put.
- **Empty states** teach: the welcome window *is* a drop target and says what dropping does.
  It is a **window of its own**, fixed and compact (640 × 600) like most welcome windows: it can't
  be resized or zoomed. The drop zone sits on top, Recent below; with no history the drop zone is
  the whole window. Opening an archive brings up the Browser window at its last size and place and
  closes the welcome; closing the archive brings the welcome back. Only one of them is open at a time.

## Not doing (on purpose)

- No toolbar full of icons. Primary action (Extract) is prominent; the rest live in Actions and menus.
- No splash, no onboarding carousel.
- No animated keyboard navigation, no bouncing on menus.
