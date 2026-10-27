# Settings navigation structure — #162 (Codex / Grok Bot functional scaffolding)

Claude Code owns final navigation layout, grouping chrome, spacing, typography, materials
and motion. This handoff records the functional map and reset/routing contracts shipped so
Claude can restyle without redoing behavior. Ideas below are suggestions, not visual approval.

## Ownership

| Owner | Responsibility |
| --- | --- |
| Claude Code | Sidebar vs tabs, category chrome, detail-pane scrolling, density, copy polish, motion |
| Codex / Grok Bot | `SettingsCategory` / `SettingsPane` map, deep-link routing, page vs all reset semantics, storage keys, AX names as semantics, tests |

Coordinate with Browser #160, Actions #161, Glance #159 and umbrella #104. Do not silently
change security defaults (quarantine, password Keychain opt-in) or wipe folder grants.

## Confirmed product facts

- Public English name **Actions** (Settings pane `nextSteps`, title "Actions").
- Full Browser is the default; Glance preferences stay explicit (`openInGlance` default off).
- Deep links must keep working: Actions › Customize → Actions page; Welcome / Integration
  → their panes; `-StowSettingsPane` demo flag. Raw values (`general`, `nextSteps`, …) stay.

## Information map (proposal for Claude)

| Category | Panes (stable raw values) |
| --- | --- |
| General | `general` |
| Archive Work | `extraction`, `installing`, `packing` |
| Interaction | `nextSteps` (Actions), `previews` |
| Security | `passwords` |
| System Integration | `fileTypes`, `integration` |
| Advanced | `advanced`, `licenses` |

Source of truth: `SettingsCategory` and `SettingsPane.category` in
`App/Settings/SettingsPane.swift`. Today `SettingsView` still uses the eleven-tab `TabView`
so behavior stays reviewable; Claude may replace chrome with a stable category sidebar +
scrollable detail using this map. Prefer not to make the window jump height merely because
an explanation is longer.

Glance appearance/material toggles currently live on **General**; Claude may regroup those
controls under Interaction visually while keeping the same keys unless a reviewed migration
is necessary.

## Reset scope

API: `SettingsKeys.reset(_ scope: ResetScope, in:)` with `.all` or `.pane(_)`.

- **Reset This Page** (Advanced › Reset, page picker) clears only
  `SettingsKeys.resettableEntries(for:)`.
- **Reset All Preferences** clears every `SettingsKeys.resettable` entry.
- Never cleared by either: Keychain password vault contents, folder grants / security-scoped
  bookmarks, `PreviousDefaultApps`, onboarding completion, `destination.severalFolders`.
- Passwords page reset clears show/remember toggles only, not saved Keychain items.
- Actions page already has **Restore Defaults** for suggestion visibility; that matches
  page reset for `nextSteps.*`. Claude may unify the wording.

After a General or Integration page reset, Advanced also reloads appearance / updater /
`IntegrationSettings` the same way Reset All does.

## Routing

`SettingsRouter.show(_ pane:)` sets the pane and invokes the scene `openSettings` hook.
Call sites: Customize Actions, Welcome, demo scenes. Prefer `show` for new deep links.

## Suggested Claude outcomes (optional)

1. Category sidebar with scrollable detail; keep window width predictable.
2. Short contextual example on Actions that connects toggles to the Browser capsule
   (non-executable simulation).
3. Group Glance material with other Interaction prefs once layout moves.
4. Put long per-app language instructions behind disclosure.
5. Matched before/after evidence: en/zh, light/dark, short window, long password/folder lists.

## Verification for this scaffolding PR

- Unit tests: category partition, resettable key coverage, page vs all reset isolation,
  router `show`, category title localization.
- Existing deep-link and Settings tests remain green.
- Visual chrome intentionally unchanged pending Claude.

## Out of scope here

- Final sidebar / Liquid Glass treatment.
- Native VoiceOver acceptance (#93 deferred).
- #91 sample / #69 assets.
