# Stow

A native macOS archive tool: browse, preview and extract 30+ formats, and pack files that work on the
recipient's computer. *Stow* is a working name.

**Status:** design prototype. The interface is real SwiftUI running on fictional sample data; the
7-Zip engine, XPC helper and Quick Look extension come next.

## Requirements

- macOS 26 or later (uses Liquid Glass APIs directly — no fallbacks)
- Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
xcodegen generate
xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build build
open build/Build/Products/Debug/Stow.app
```

Tests (Swift Testing): `xcodebuild -project Stow.xcodeproj -scheme Stow -derivedDataPath build test`

`Stow.xcodeproj` is generated — edit `project.yml`, not the project.

## Design review screenshots

```bash
scripts/snapshot.sh <scene> [light|dark]   # → snapshots/
```

Scenes: `welcome`, `grid`, `list`, `fonts`, `search`, `activity`, `pack`, `tray`.

## Layout

| Path | What |
| --- | --- |
| `DESIGN.md` | Design language: principles, vocabulary, color, type, motion values |
| `App/Model` | Value types: archive listing, Checkup findings, Next Steps, packing rules |
| `App/Design` | Tokens (space, radius, motion), flow layout, thumbnails |
| `App/Browser` | Main window: sidebar + archive card, grid/list, inspector, Next Steps capsule, hover preview |
| `App/Pack` | The Pack sentence and its compatibility report |
| `App/Tray` | Floating drop shelf |
| `App/Welcome` | Empty state / drop target |
| `website/` | Marketing site |
| `.claude/skills` | Project-level agent skills (design engineering, Apple design, Swift) — MIT, © Emil Kowalski |
