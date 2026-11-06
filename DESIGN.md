# Stow — Design Language

## Current creation and entry-point direction — 2026-11-05

Follow [the current Pack/Browser brief](Handoff/pack-creation-direction-2026-11-05.md).
The user wants a Browser-consistent creation workspace, **Pack…** for new output, the original
sentence builder as the primary configuration, and unrestricted format controls inside **More
Options**. Add General Sharing; recommendations must not be hard format restrictions. The
previous compact draft composition and separate Save form from #297 are superseded. Claude Code
owns the new visual treatment in #302; Codex owns functional integration. Status-menu Open Tray is removed;
Open Stow/Settings must come to the front. Dock exposes current windows and existing recent history.

## Tray, creation and entry-point functional handoff — #286

The [functional implementation brief](Handoff/286-functional-followups.md) records the new interfaces and bounded
native evidence for #287–#294. Tray gains a master switch and optional residency; the user
reconfirmed outside-click dismissal without an idle timer. Welcome exposes Open/Create/Settings;
New/Create opens an editable draft sharing Pack internals, while gathered inputs keep quick Pack.
Sample leaves production bundles and becomes an explicit browser download. Search gains a
separate Close action. These changes supersede primary Welcome sample placement and mandatory
production bundling; they do not require copying ArcZip's visual composition.

Claude Code owns final visual treatment and motion. The draft workspace, settings form and
functional controls are implementation scaffolding, not approved visual designs. Preserve the
state/routing/close/undo/security contracts in the brief. The current user direction above restores
the Pack sentence for both draft creation and quick Pack. See #286 for task dependencies and #38 for remaining
physical-input/signed-integration checks. No collaborator session or visual acceptance is claimed.

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
| Archive findings | **Archive Info** | Background checks remain; relevant notices appear with the files, ordinary findings are disclosed in archive information. Checkup remains an internal name. |

**Clarity update, confirmed 2026-10-31 (#229/#230):** remove the permanent Checkup button
and prominent normal-status report. Keep archive checks and concrete notices, without implying
malware scanning or general safety. Archive Info remains reachable from the title menu during
selection; Details labels its archive/file/folder/selection scope. This supersedes the historical
always-visible shield guidance. See the [functional implementation handoff](Handoff/clarity-functional-implementation.md).
The title bar's composition is now #242's floating-path direction, under Browser layout; the
centered-search proposal (#231, PR #241) is superseded.

**Current direction after the user's PR #177 review, 2026-10-24:** the full Browser remains
the default; Glance is optional. (Since 2026-11-02 archives open in the window used last, which is
the Browser until someone switches; see Browser layout › Opening an archive.) The full Browser has a file workspace and **fixed, visible
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

The app, Settings, the More menu, File › Actions and the website say **Actions** (Simplified
Chinese **快捷操作**); [issue #161](https://github.com/skyswordw/stow/issues/161) tracked the
transition. Internal `NextStep*` types and stored preference keys keep their existing names. Preserve explicit
user preferences where compatible with these newer product decisions. The
[earlier product design review](Handoff/product-design-review-2026-10-24.md) retains historical
evidence; its optional-pane composition and mockups are superseded.

## Browser layout (#160, #161)

**Floating-path direction (#242, user's choice 2026-10-31).** The user compared interactive
alternatives and chose this one; it supersedes the centered Search of #231/PR #241 and the
plain path-row and bottom-path studies.

- **Title bar.** The archive's name and menu lead, with its password control right after the name
  when encrypted: the lock alone, its words ("Unlock Archive…") in its help and accessibility label. Everything you do with the archive is grouped at the **trailing edge**, in this
  order: **Search → view modes → Delete · Save**. Search is a magnifying-glass button; a click or
  ⌘F opens it into a field that grows **leftward**, toward the name, so the view and editing
  controls never move. It stays open while it has the keyboard or a query and closes when it
  lets go empty. Opening by click grows the capsule over 0.26 s (closing 0.18 s), ease-out with no
  overshoot, stepped frame by frame because the toolbar doesn't follow SwiftUI animations; ⌘F, Esc
  and Reduce Motion change it at once (`SearchWidthMotion`). It's the Browser's own field (the
  system toolbar field always settles last, at the window's end) with the system field's
  contracts: one query, Esc clears it and returns the keyboard to the files in one step. Open, it
  carries two controls that never share a glyph (#294): **Clear** is the system field's filled
  circle inside the text, shown only with a query, and keeps Search open with the keyboard;
  **Close** (a plain ×, medium weight) sits past a hairline at the capsule's trailing end in every
  state, so it never moves, and does what Esc does: clears, closes and hands the keyboard back.
  Both are as quiet as the magnifying glass until the pointer is over them (no hover animation),
  with an 18 × 22 pt hit area. A pointer Close shrinks the field like any close (0.18 s); CJK input
  composes in it without filtering on half-typed pinyin, and while an input method is composing,
  Esc is the input method's (it cancels the composition; Search stays open). `TitleBarLayout` gives it room
  from free space first, then from the name (which truncates in the middle), never from the path.
- **Save is an arrow into a box** (`square.and.arrow.down`, as the save confirmation shows), a
  system symbol like Delete's `trash`, so the two share one weight and size; a custom floppy disk never
  matched (user's choice, 2026-11-01). Extract's arrow comes *out* of a bin, so the two read apart.
  Named "Save Changes" with ⌘S in its help. Disabled when there's nothing to save.
- **Extraction is a box with an arrow out of it** (`arrow.up.bin`): Extract All and the Actions
  stack's Extract, with their words kept. Pack keeps its box.
- **Path.** The floating capsule over the files keeps Back · Forward · Up and the route. A short
  path takes its natural width; the whole route shows while it fits. A deep one folds the folders
  after the archive into a **⋯ menu**, one at a time, keeping the archive it starts from and where
  you are; at the very narrowest only ⋯ and where you are (truncated in the middle) remain.
  Every part stays one click away, and Search opening never takes the path's width.

**Shape (#242).** One set of shape tokens, concentric where surfaces nest, not one radius
everywhere. Details, the path capsule and the bottom capsules all stand **8 pt** (`Radius.windowInset`)
off the window's and the files' edges, so their edges line up, and the top of Details is level
with the top of the path. Details is the panel in the window's corner, so its radius is the
window's (≈ 26 pt) less that inset: **18 pt**. Every floating capsule is 38 pt tall (radius 19,
also ≈ window radius − inset) with 30 pt buttons concentric inside at a 4 pt inset. The system
inspector's own edge (its glass, side shadow and hairline) is replaced by the window's background,
so Details' rounded rim is its only outline: no square strip beside it, no doubled edge. It is the
window's own background material, not a flat colour, so in dark mode it takes the same wallpaper
tint as the files' side and the title bar reads as one surface from edge to edge.

**Toolbar Search and editing (#215/#216, 2026-10-30).** Search moved from the navigation row to
the title bar (where in the title bar is now #242's, above). The navigation row keeps its whole
width for the path.
Delete and Save sit in their own capsule after the view modes from the moment an
archive opens, disabled when there's nothing to delete or save, so editing is found before the
first edit. Save is the one Save in the full window: with changes pending it becomes a prominent
**Save** pill (accent, with its name); the bottom bar keeps the change count, "Nothing changes on
disk until you save." and Revert, and shows saving progress. Glance has no title bar, so its bar
keeps its own Save. Delete stays quiet: it only stages a change. Add Files, Rename and Replace
stay in the Edit menu and the item's context menu. The
[native comparison and functional brief](Handoff/browser-toolbar-search-editing.md) records the
ArcZip observations behind this.

| Region | Holds |
| --- | --- |
| Title bar | Leading: archive name/menu and subtitle, then the password control when encrypted. Trailing: **Search** (a button that opens leftward), view modes, **Delete · Save**. Narrow windows give up the view modes first (the View menu has them, ⌘1–3); Search, editing and password access stay |
| Navigation, floating over the files | Back · Forward · Up and the path; a short path takes only its width, a deep path uses the whole row and folds its middle folders into a ⋯ menu |
| Files | The main surface: grid, list or columns. In the list, the name takes the spare width before size, kind and date grow |
| Details (always there, right) | An inset panel, not a strip of the window, 8 pt off the window's edges with an 18 pt radius. Its heading names the subject with a glyph and words: **Archive Info**, **File Info**, **Folder Info** or **Selection Info**. Then a content-sized preview, the name and kind, and properties as label ↔ value rows with hairlines (Size, Packed file data with the saving underneath, Modified, **Location in archive** stacked under its label at full width: “Showcase.zip › Showcase › Docs”). A note that qualifies a figure sits under that figure, in the accent when it counts unsaved changes. An app leads Developer Verification with the developer, then what was verified. **Archive Info** when nothing is selected: the three figures, the password control, then routine facts and ordinary notes behind More Archive Information. No toggle, no close button, no action buttons |
| Archive controls, floating bottom leading | **Glance** in a glass circle of its own (switching windows isn't done to the archive), then **Extract All** (box-with-arrow icon) in its capsule, mirroring ⋯ beside the Actions stack |
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
put, unaccented (in Glance, a selection's stack takes its place; see Glance layout). Archive facts live in one place, Archive Info, reached from Details with nothing
selected and the title menu. Everything floating shares one family: glass
capsules, buttons concentric inside them (button radius + inset = capsule radius), all 38 pt tall.
Details is a solid reading surface with the same light rim, brighter along its top edge.

**Actions' states, all in the same place.** Ready is the stack. A step that has started but measured
nothing yet (a password, the engine starting) shows its capsule with a turning ring and no
percentage; then the ring fills with the percentage beside it, and Stop. Done says where things
went, with Show in Finder; a failure grows into a card with what happened, its one action, Copy
Details and Dismiss. Stopping leaves nothing behind and the stack comes straight back. While a step
runs, Extract All waits, dimmed, its help tag saying why; while the archive is still being listed,
Actions and Extract All are dimmed the same way. A dimmed stack button gives up the accent rather
than fading. In a narrow window the words give way first: stacked labels shorten in the middle
(280 pt at most), a failure card puts Copy Details under its action, and several results inside
other archives say only "Select one result to show it".

**Opening an archive (#265, user's choice 2026-11-02).** Finder, Quick Look, Recent and a drop on
the welcome open an archive straight into its window, picked before anything shows: the window used
last (the full Browser until someone switches to Glance, and still remembered after Stow quits), or
always the Browser, or always Glance, as Settings › Glance says. The welcome never shows in between;
launching Stow without an archive still shows it, and design snapshots never change the remembered
window. The Browser comes up already in its own shape: its title bar's height with the bar hidden,
the traffic lights where they'll stay, and the archive's name and kind ("ZIP archive") where its
title menu will be. The files, the path and Details arrive with the listing, which only adds the
chevron and the file count to the title. A read that takes longer than 0.4 s fades in a small spinner
and *Opening “Harbor.zip”…* in the middle, with Cancel (Esc); Glance shows the same words above its
window controls, and its Close stops it. A quick open shows neither.

## Tray dismissal — direction confirmed 2026-11-04

The user accepted outside-click dismissal for an unpinned Tray and **Keep Tray Open**
for persistent display. A manually opened Tray must not disappear just because time
passes or the pointer leaves. The local functional implementation removes idle dismissal;
pinning controls persistence, not window level. Keep drag reveal, protect active drags
and Tray-owned dialogs/previews, and retain explicit Close/Escape while pinned.
Successful drops stay visible for confirmation until the next dismissal action.

The [current Tray brief](Handoff/tray-keep-open-2026-11-04.md) separates confirmed
decisions, native ArcZip 1.2.1 evidence and engineering requirements. It supersedes
older idle-dismissal guidance, not the actual-home drag activation contract.
Codex / Grok Bot owns behavior, state, tests and accessibility semantics; Claude Code
owns visual expression and motion.

**How it looks (#282).** Back, Keep Tray Open and Close are Glance's circular window
controls (`ActionButtonStyle`, 26 pt, hover fill). Kept open is `pin.fill` in the accent
inside an accent ring, the same on-state as Glance's Pin on Top, so it reads by shape as well
as colour; not kept open is the plain `pin`. Close stays right beside it: it still closes a
Tray that's kept open. Clicking the pin says what changed for 2 s in a small glass capsule
hanging under it — *Stays open until you close it* / *Hides when you click elsewhere* — that
takes no clicks and covers only the top of the first row. The help tags say the same at more
length, and Settings › Tray explains it in the Showing and Hiding footer (no setting of its
own any more). Chinese calls the Tray 托盘 everywhere and the pin 保持打开.

## Glance layout (#159)

Glance is the Browser made small: the same archive, folder, selection and history, the same
floating family, and no Details or Search. It's **borderless**, as ArcZip's Mini is (user's
choice, 2026-10-27): no title bar and no traffic lights. The archive is named in a header inside
the window and the folder in a bar under it, with Stow's own pieces.

**Selection scope when switching from Columns (#160):** Columns can select a folder in
one column while showing its contents in the next. Glance shows that folder's parent list
with the folder selected, so selection actions always refer to a visible row. Returning to
Columns opens the currently selected folder's contents again; selections and navigation made
in Glance take precedence. These presentation transfers add no Back/Forward history entries
and retain the archive level and Browser view preference.

| Region | Holds |
| --- | --- |
| Header (no title bar) | The archive's format badge (32 pt), its name semibold with “ZIP archive · 17 files” under it, wherever you are inside it; when encrypted, a 20 pt lock badge right after the name: accent-filled while locked, a spinner while a password is checked, a quiet open lock once one has worked. Dragging the header moves the window; the window keeps its title for the Window menu |
| Navigation, floating under the header | The Browser's capsule: Back · Forward · Up │ the path from the archive down, running the window's width (no Search beside it); a deep path folds its middle folders into a ⋯ menu and keeps where you are in view (#242) |
| Files | Name and size, straight on the window's one surface: Liquid Glass with a wash of the window colour for legibility, or classic frosted (Settings › Glance); solid under Reduce Transparency. No card, no frame. The badge and the rows' icons share the 16 pt margin |
| Window controls, floating bottom leading | **Close** · **Pin on Top** · **Open in Full Window** in one glass capsule of icon buttons, like the navigation capsule's. Pinned: the pin fills in the accent with a ring round it |
| Archive controls, floating after them | **Extract All**, one extraction button at a time: while a selection's Actions offer its Extract, Extract All steps aside (sinking as the stack rises) and comes back as the selection clears, because beside the stack it had room only for its icon, which is Extract's icon, and read as a second Extract. User's choice, 2026-11-02, over ArcZip Mini's way (both buttons, Extract All in words): it holds at any width and for any stack, without widening Glance. File › Extract All (⇧⌘E, under File › Extract ⌘E) reaches the whole archive meanwhile, without clearing the selection (#249). With Extract hidden in Settings › Actions (it waits in ⋯), Extract All stays, so the bar always has one extraction button. When the row still has no room for its words (beside a progress capsule, whose ring and words don't repeat its icon), it keeps its icon alone. While changes are pending or saving it drops the accent, so the bar's Save, right under it, is the one prominent action |
| Actions, floating bottom trailing | The full window's stack and rules: one prominent action at a time, Install App alone for an archive that's one app |
| Under the files | The full window's unsaved-changes and changed-on-disk bars |

**Colourful window controls** (Settings › Glance) fill the same three buttons, in the same
capsule, with the traffic lights' colours: red Close, yellow Pin on Top and green Open in Full
Window, their symbols always showing, dark as the traffic lights' are (white wouldn't read on
yellow). Nothing moves or changes size when the setting changes. Pinned adds a darker ring round
the pin's button. Not ArcZip's separate circles (user's call, 2026-10-27): the capsule keeps the
window's controls one group, and a compact Extract All would otherwise read as a fourth window
control.

Glance asks for a password with a card in the window, as ArcZip's Mini does, over everything else
dimmed; see Encrypted archives.

## Encrypted archives (#104)

One lock, the same in every place it shows, and it never moves when its state changes:

| State | Title bar (full window) | Glance header | Archive Info | A locked file's preview (Details) |
| --- | --- | --- | --- | --- |
| Locked | The lock glyph in the accent, on the title bar's plain glass button: findable, but not a second filled accent beside Extract All | 20 pt badge filled with the accent, white lock | Accent lock, “Encrypted”, **Enter Password…** in the accent | The file's icon with an accent lock badge, the reason, **Enter Password…** |
| Checking | A small spinner in the lock's place; clicking it cancels | Spinner in the badge; clicking cancels | Spinner, “Unlocking…”, **Cancel** | The button keeps its size, shows the spinner and “Unlocking…”; clicking it cancels |
| A password has worked | The open lock, quiet (secondary) | Quiet open lock on a faint circle | “Password available”, no action (a ZIP can still have files with another password) | The preview itself |

**Asking.** The full window asks in the system sheet (`PasswordSheet`, 460 pt). Glance is narrower
than that sheet (440 pt, 400 at the least) and has no title bar for a sheet to drop from, so it asks
with the same card *in* the window: centred, the window colour with a hairline rim and a soft
shadow, everything behind it dimmed (black 20 %, 36 % in dark) and taking no clicks. The card fills
the window less a 12 pt margin, at most 420 pt, and puts its footnote on its own line, under the
words, above Cancel · Unlock. Same words, field, Show password, keys (Return unlocks, Esc cancels)
and answers as the sheet. A rejected password says so right under the field. While a password is
checked the card is gone and the lock spins: the checking belongs to the lock. If it's wrong the
card comes back where it was, only fading in, so asking again doesn't look like a new start.

**Preparing a preview.** An encrypted file's Quick Look waits until it's read, so the window can
ask for the password first. For anything that takes a while, a small glass capsule (32 pt) floats
over the top of the files, under the path: *Preparing “Report.pdf” for Quick Look* (or *Preparing 3
files…*) with Actions' ring, turning until the engine measures something, then filling with the
percentage beside it, and **×** to stop (so does Esc, as before). It waits 0.4 s before showing, and
the wait starts again after a password is typed, so a quick read never flashes it; it stays hidden
while the password is asked for. It isn't a step: it takes nothing from Actions' place, and Extract
All stays ready.

## Settings layout (#162)

Thirteen pages are too many for toolbar tabs, so Settings is System Settings' shape: a fixed sidebar
beside one page. The window is 756 pt wide (a 196-pt sidebar, a 560-pt page) and keeps its size
when the page changes; a long page scrolls, and the window can be made taller (its width is fixed).
Switching pages doesn't animate.

| Sidebar group (`SettingsCategory`) | Pages |
| --- | --- |
| General | General: appearance, the Browser's first view, app language, updates |
| Archive work | Extraction · Installing · Packing |
| Interaction | Actions · **Glance** · **Tray** · Previews |
| Security | Passwords |
| System integration | File Types · Finder & Permissions |
| Advanced | Advanced (cache, reset) · Licenses |

The groups are separated by space, not headings, so no heading repeats the name of the only page
under it. Every page is a grouped form: one choice per row, its explanation in the section's
footer right under it, no boxes of our own. Plain sidebar symbols, no coloured tiles.

- **Actions** keeps the master switch first, then a **Preview** (#161): pick a sample selection
  (two photos, an app, fonts…, or nothing selected in an archive of one app) and a small drawing
  shows the Browser's stack twice — at rest (More ⋯, the front action, the edges of the others
  above it) and fanned out (what pointing at it or clicking the edges shows). Two rows under it
  say what each menu holds: More (⋯) is every action but the front one; File › Actions is all of
  them. Recomputed from the toggles below. The drawing is flat (no glass), smaller than the real
  buttons and takes no clicks, so it reads as a picture, not a control; VoiceOver reads it as one
  sentence (what's in front, what's behind it).
- **Installing** and **Finder & Permissions** show folder access the same way (#162): a folder
  symbol, the folder's name over its path (home as `~`), **Forget** on the trailing edge, and the
  same footer sentences about subfolders and what Forget does. **Passwords** lists saved passwords
  in the same row: a locked-document symbol, the archive's name over the folder it's in (the name
  isn't repeated in the path), **Forget** on the trailing edge. The first-open-check toggle's footer
  is two short paragraphs: what the check is, then when to turn it on.
- **Glance** starts with where archives open: **Open archives in** Last Used Window (the default),
  Full Browser or Glance, its footer saying what Last Used Window remembers and that ⌥⌘G moves an
  open archive between the two (see Browser layout › Opening an archive). Then, under Appearance,
  the window material and colourful controls. While Reduce Transparency is on, the
  footer says Glance is solid whatever is chosen; the choice itself is kept.
- **Tray** (#288) has its own page, like Actions: the master switch **Enable Tray** first, with
  a footer that says what it means once Stow's last window closes (on: Stow keeps running without
  a Dock icon so the Tray stays ready; off: Stow quits once its work finishes) and that opening at
  login lives in Finder & Permissions. Then **Showing and Hiding**: the menu-bar icon (its
  subtitle says Control-click opens Stow's menu), drag reveal (its subtitle says where to drag:
  up to the icon, or to the right edge without it), and ⌥⌘T as a read-only row; the footer says
  how the Tray hides and that the pin keeps it open, plus how to reach it when the icon and drag
  reveal are both off. Then **Appearance** with the border colour. While Tray is off everything
  under the switch is disabled and its words go tertiary (a grouped form greys a disabled
  switch but not its title); the values are kept. No idle timer, by the user's choice (#286).
  The status item's Control/right-click menu is native and short (#290): Open Stow,
  Create Archive… · Settings… (straight to this page) · Quit Stow, no key equivalents shown.
- **General** shows the language in use and folds the macOS how-to into a disclosure.
- File Types drops its own heading in Settings (the title bar names the page); its standalone
  scene keeps it. Its introduction lines up with the form's headers and footers, and its buttons
  with the edges of the list's cards.
- In Simplified Chinese the page is **访达与权限**, macOS's own name for Finder, like every other
  Finder string on that page and in Welcome.

## New archive draft (#293, revised 2026-11-05)

The current contract is [Pack creation direction](Handoff/pack-creation-direction-2026-11-05.md).
New/Create opens one editable draft of real sources; **Pack…** opens the same sentence builder
as quick Pack. Name/format choices carry through unchanged unless the user changes them. The
More Options controls bind to that same state and expose all supported output formats without
silently changing the recipient. General Sharing adds a neutral cross-platform purpose. Existing
archive edits retain Save. Cancel/failure preserves the draft and source access; success opens
the real archive. The title format menu uses direct actions rather than an inline picker nested
inside a menu.

Claude Code should make the draft a Browser-consistent workspace. The previous #297 card/heading
composition and its separate Save form are superseded, not acceptance references. Preserve file
selection, add/remove/undo, source safety, keyboard routing and system display/motion preferences.
The existing workspace remains the functional baseline until that visual follow-up lands.

## Color

- **Accent — Amber** `#D97B2B` (light) / `#B85E1C` (dark). Warm, like kraft paper and parcel tape;
  stands apart from the sea of blue utilities. Used sparingly: primary button, selection tint,
  and the drop target. No permanent all-clear badge is shown for archive metadata checks.
  Dark mode's amber is deep so that white words on an accent fill reach 4.5 : 1 (the earlier
  `#F0954A` gave 2.3). Accent **words and symbols** use `.accentText`, which lifts the accent's
  lightness in dark mode until it reads at 4.5 : 1 on a dark panel (amber becomes about
  `#DF772B`); fills, rings and selection use `.tint`. macOS uses Stow's amber only when the system
  accent is Multicolor; otherwise both follow the person's own accent.
  The Quick Look extension has no asset catalog and always shows amber, so `ArchivePreview.amber`
  writes the same values out (Increase Contrast included); `QuickLookAccentTests` keeps them equal.
- Everything else is system semantic color (`.primary`, `.secondary`, `.separator`, materials).
- Status: completed = system green, caution = system yellow, blocked = system red. Always paired with an
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
- A surface in a window corner takes the window's radius less its inset: the Browser's Details is
  18 pt at an 8 pt inset (`Radius.windowPanel`). Floating capsules are 38 pt (radius 19) at the
  same inset. Consistent means concentric, not one number (#242).
- Separation by spacing and subtle fills first; hairline separators only where lists need them.

## Motion

Values from Apple's fluid-interface guidance and Emil Kowalski's design-engineering rules
(see `.claude/skills/apple-design`, `.claude/skills/emil-design-eng`).

| Moment | Motion | Value |
| --- | --- | --- |
| Actions region appears (full window and Glance) | Spring, from bottom, scale 0.96 → 1 + opacity | `response 0.32, damping 1.0` |
| Actions content changes on selection | **None** (frequent) — numbers use numeric text transition | — |
| Floating chrome leaves (Actions, pack capsule, batch panel) | Ease-out fade with a smaller drop — faster than it came | 180 ms |
| A step finishes or fails on its own | Ease-out, never a spring (nobody touched it) | 200 ms |
| A step has started but measured nothing yet | A quarter arc turns in the progress ring; it stands still under Reduce Motion | 1 turn/s, linear |
| Actions shown/hidden or its stack opened/closed by a key (arrows, ⌘A, Esc) | **None** | — |
| Actions stack fans out (pointer rests 140 ms on it, or its edges clicked) | Spring: each action rises from behind the front button, scale 0.9 → 1 + opacity; folds back with an ease-out 450 ms after the pointer leaves (ArcZip lingers 0.5–1 s; it also opens at once, which flashes on every pass, so Stow waits 140 ms). Choosing an action or a new selection folds it at once, unanimated. Fade only under Reduce Motion | `response 0.32, damping 1.0` in, 180 ms out |
| Drop target on drag-over | Spring scale 1.0 → 1.015, accent tint fades in; on Welcome, Open and Create Archive fade to 35 % in place (nothing moves) so the drop is the one ask | `response 0.25, damping 0.9` |
| Tray rows a drop (or Add Files…) brought in, new or already there | Accent ring and faint tint **at once**; fade out after 1.2 s; scrolled into view if below the fold (no scroll animation under Reduce Motion) | fade `Motion.status` 200 ms |
| Hover preview | 450 ms delay for the first; **instant & unanimated** for neighbours while one is open; closes instantly | 140 ms fade |
| Tray panel show/hide, including an outside click or app switch hiding it | Same edge in, same edge out: scale 0.96 → 1 from the menu bar + opacity (`Motion.presence`). Hiding on an outside click uses the same quick exit: the click has already reached what it was aimed at, and the Tray only gets out of its way | `appear` in, `exit` out; **none** for ⌥⌘T and Esc |
| Keep Tray Open toggled | The pin's symbol swaps with the system replace effect, its accent ring fades in or out, and the note under it drops 4 pt into place (scale 0.96 → 1 from its top-trailing corner) and fades out 2 s later. **None** when Space toggled it (the note still shows, unanimated); under Reduce Motion the symbol swaps at once and the ring and note only fade | `status` 200 ms in, `exit` 180 ms out |
| Files dragged in another app (#180) | Nothing comes out at the start. The menu-bar icon becomes `tray.and.arrow.down`; without an icon, a 44 pt piece of Tray glass with that symbol fades up where the Tray comes out (scale 0.9 → 1). The Tray comes out **at once** when the drag reaches 160 pt in front of its home (under the icon as wide as the Tray, at the screen's edge as tall as it, or over where it was put), stays for the rest of the drag, and goes back 0.8 s after the drag ends if nothing was dropped. ArcZip's Box: no reveal at drag start; opens at once ~150–165 pt under its icon, about its own width; stays while dragging; gone within ~3 s of a drag with no drop | hint `appear` in, `exit` out; fade only under Reduce Motion |
| Password card in Glance appears / goes | A click: scale 0.96 → 1 + opacity, dimming fades in; it eases out. Asked again after a wrong password: fade only. **None** when a key (Return, Esc, Space) caused it | `appear` in, `exit` out |
| Preparing-a-preview capsule appears / goes (after 0.4 s) | Ease-out fade with a 4 pt drop and scale 0.96 → 1 from its top; fades out. Its ring as Actions' | `status` in, `exit` out |
| An archive's opening status (Browser, Glance) | Waits 0.4 s, then fades in; nothing moves. The listing replaces it at once; the title bar is already in place | `status` in |
| Glance opens (click, Finder) | Content springs out of the pointer, scale 0.96 → 1 + opacity; glass fades in | `response 0.32, damping 1.0` |
| Glance via ⌥⌘G, Esc, Glance ↔ full window by keyboard | **None** | — |
| Pack sentence token change | Blur-crossfade of the token text (the chevron stays put) | 180 ms |
| Pack password check rows (re-enter, mismatch) appear or go | Ease-out fade, never a spring; **none** when typed | 200 ms |
| Pack part-size editor (Custom…) | The system popover, out of the control that was clicked: the sentence's last words, the Split archives menu, Settings › Packing. Nothing changes until Use | system |
| More Options opened on a short screen | Once the section has opened, the middle scrolls its heading to the top so the opened rows are in view; **none** (a jump) when a key opened it or under Reduce Motion | `response 0.32, damping 1.0` |
| Details' disclosures (More Archive Information) and the notices card open or close | Ease-out, never a spring; **none** when a key (Space) toggled it | `status` 200 ms |
| The password control changes state (locked → checking → open) | Ease-out as a check finishes; the symbol swap cross-fades under Reduce Motion; **none** when Return started the check or Esc cancelled it | `status` 200 ms |
| Folder access wasn't saved: the card comes and goes | Fade; **none** when dismissed from the keyboard | `exit` 180 ms |
| Welcome and Browser windows replace each other (an archive opens or closes) | The system's own window opening and closing; **none** when a key press switched them | — |
| View-mode switch, keyboard nav, search filtering | **No animation** | — |
| Button press | System controls handle it | — |

Reduced Motion: springs become 150 ms opacity fades (exits 100 ms); nothing translates or scales.
Glass that morphs from one shape into another (Actions' front button into its progress capsule)
cross-fades instead, the lock's symbol swap cross-fades, Search opens at once, the password card
and the preparing-a-preview capsule only fade, and the preparing ring stands still.
Reduced Transparency: Stow's glass and materials fall back to the solid window background with a
hairline edge (`accessibleGlass`); Glance is solid whatever material Settings chose. System glass
buttons do this themselves.
Increase Contrast: the floating capsules, Details, notices and the Tray take a visible border, the
accent pill is outlined, metadata steps up from tertiary to secondary, and the accent deepens to
`#A8551C` in light and dark, so white words on it reach 5.3 : 1 (4.5 : 1 needed; the usual light
amber gives 3.1). Accent words in dark mode lift to 7 : 1.
Design snapshots force Stow's side of all three with `-StowReduceMotion YES`,
`-StowReduceTransparency YES` and `-StowIncreaseContrast YES` (#104): views read Reduce Motion as
`\.reducesMotion`, models and controllers as `DisplayPreferences.reducesMotionNow`, never the system
value directly. What AppKit draws only follows the real setting: system controls, the accent's
high-contrast variant, the system's window opening and closing (Glance → full window by click, Welcome ↔
Browser). `-StowBurst <transition>` (`scripts/motion-bursts.sh`) records a
transition frame by frame, by click and as after a key press, for review.

## Signature details

- **Compact archive identity** in the Browser's title/navigation region. Detailed file counts,
  packed → unpacked sizes and compression facts have one home in Archive Info. Keep encryption
  and relevant archive notices directly discoverable. Full Browser Details stays visible; Glance provides the
  optional compact experience. The exact home of Archive Info remains Claude Code's decision.
- **Archive findings** describe the specific scope and consequence. Their text distinguishes a
  listing-time protection planned for extraction from a completed extraction audit. Ordinary
  notes are available in Archive Info; normal state does not promote a separate Checkup feature.
  Findings that need attention show as one tinted card above the files (Browser and Glance), aligned
  with the navigation capsule: the most important finding's glyph and title, “+N more”, and a native
  disclosure that gives its consequence and then the others. Cautions use the system's multicolour
  warning triangle; planned or completed handling uses the blue half shield. Quick Look shows the same
  card's first finding with its consequence under it. A normal archive shows no card and no line.
- **Folder access wasn't saved** (#253) is the quietest card of that family, above the findings
  card in Browser and Glance: same shape, inset and callout size, but a neutral tint (no severity
  colour, since nothing is wrong with the archive), a secondary `folder.badge.questionmark`, the
  title with its one-sentence consequence always shown under it, and Copy Details with the code
  under the words. A small × at the title's line dismisses it (it fades out), instead of a button
  that would outweigh the findings card. It never takes focus or blocks the files.
- **Pack sentence** shows a live report underneath of what it will do. When the archive is split it
  leads with what comes out: about how many parts, their numbered names ("Harbor.zip.001 – .003"),
  each part's limit, and that opening it needs every part and an app that joins them. A caution
  (the recipient may not be able to open it) comes before even that. Then what changes on the way:
  names adjusted for Windows (with Review names right under that line), Mac-only files left out (or
  kept, when More Options kept them), links left out; then what's simply true of the format.
  "All names work there" is good news, so it stays, but last: never above a change (#153). The footer says the size as an estimate in words ("About 27.3 MB in 3 parts"), beside
  Cancel and Pack, where it stays in view however far the middle scrolls. **More Options** is a full-strength heading
  that lists its current settings while closed, under the title and lined up with it, each fact
  whole and never cut off: compression, a planned check while it's on, then every choice changed
  from the purpose, last and marked with the same amber pencil as the open rows, with **Reset These
  Options** straight after them. A planned check has a hollow dotted check ("Will verify archive
  contents"); the filled check and "contents verified" belong to the finished pack only. Inside, hairlines divide a few groups: what comes
  out (compression, parts, verify), a disk image's layout, what the password covers, what a Mac
  adds, CPU cores. A purpose's own defaults are checkboxes showing what will happen; one changed
  from the purpose says so under it. While something differs, Reset also closes the open section,
  under its last row, with its reach in words: the purpose's usual choices, for this archive only;
  compression stays as set and Settings don't change. Nothing to reset, no Reset. Choices a format can't offer say why in plain words instead of only in a
  tooltip; a choice that can't apply at all (Encrypt file names without a password) isn't shown.
  **Custom…** opens one part-size editor in a popover from whatever was clicked, with the part
  count and part names for these items as people type. When the screen is short, only the middle of the sheet scrolls (its
  cut-off edge fades) and the name, Cancel and Pack stay put.
- **Empty states** teach: the welcome window *is* a drop target and says what dropping does.
  It is a **window of its own**, fixed and compact (640 × 600) like most welcome windows: it can't
  be resized or zoomed. The drop zone sits on top, Recent below; with no history the drop zone is
  the whole window. Opening an archive brings up the Browser window (or Glance, when that's the window
  used last) at its last size and place and closes the welcome; the Close Archive command brings the welcome back. Closing the Browser window
  with the traffic light or ⌘W ends that archive session and leaves Stow running without a window;
  reopening Stow from the Dock shows Welcome. Only one of them is open at a time.
- **Welcome's actions** (#291) sit inside the drop zone, under what dropping does: **Open
  Archive…** and **Create Archive…** side by side at one width, Create the prominent glass button
  on the trailing side, as a Mac pair puts its primary. Both reach the same routes as ⌘O and ⌘N
  (`AppState.beginNewArchive()` for Create; a repeated click focuses the one draft). Their tooltips
  name the shortcut. With keyboard navigation on, the window starts on Create. **Settings** belongs
  to the app, not to what's dropped, so it is an icon-only gear in the top-trailing corner that
  mirrors the traffic lights: their vertical centre, and the close button's leading inset as the
  gear glyph's trailing inset (measured from the window's own close button, so it follows the
  system's metrics). Its glyph is a traffic light's size (14 pt, medium weight to carry the
  filled lights' weight); it is secondary and borderless, with a faint 22 pt hover circle; under
  Increase Contrast it is full strength with a hairline ring of that circle. Its accessibility name is "Settings…" and its
  tooltip names ⌘,. The actions keep their words: they are the primary choices. A short window
  drops the format chips first, then the icon; the two actions always stay. The sample is not on
  Welcome. *Supersedes* the earlier Open Archive… / Try the Sample pair and its prominent sample
  button, and the first #299 draft's bottom-leading "⚙ Settings…" footer (user feedback: the
  corner suits it, and a text label there felt uncoordinated).
- **The sample** (#292) is a web download, so it lives with the app's web pages: **Help ›
  Download Sample Archive** beside **Sample Credits and Licenses**, and the same button in Welcome
  to Stow with a caption that says the browser saves it and the ZIP is then opened normally. No
  ellipsis (nothing is asked before the browser takes over), no shortcut, no in-app progress or
  error: the browser shows both. It left the File menu, which holds commands that act here.

## Not doing (on purpose)

- No toolbar full of icons. Primary action (Extract) is prominent; the rest live in Actions and menus.
- No splash, no onboarding carousel.
- No animated keyboard navigation, no bouncing on menus.
