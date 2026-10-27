# Tray cross-display activation verification

The cross-display finding from [PR #187](https://github.com/skyswordw/stow/pull/187)
is superseded by the home-based activation in
[PR #189](https://github.com/skyswordw/stow/pull/189). The native checks below confirm
that the original reproduction no longer opens a remote Tray on current main.

## Functional contract

A drag activates the Tray only at its actual home: under its menu-bar icon, at the
edge where it will appear without an icon, or over a position chosen by moving the
panel. Moving a file to another display's right edge must not open the panel on the
source display. This preserves #189's interaction; it does not make the Tray follow
the pointer or add a new activation region.

Only a deliberate drop or Add Files adds items. Automatic reveal preserves the
source app's focus. Menu-bar and keyboard activation remain directly available.

Codex / Grok Bot owns this functional verification and regression coverage. Claude
Code retains ownership of visual treatment and motion; no new design approval is
claimed by this report.

## Native verification — 2026-10-26

Tested the Debug app built from main commit
`30a1836df2f87e78a847cd3cdd487f1389390d1e`, on macOS 27.2 with Xcode 27.1. Only
task-owned scratch files were used, with system mouse events explicitly authorized
by the user. No extension-registration script was run.

AppKit display geometry, in points:

| Display | Frame |
| --- | --- |
| Primary, Mi Monitor (1) | `(0, 0, 1920, 1080)` |
| Portrait display to its left, Mi Monitor (2) | `(-1080, -510, 1080, 1920)` |

Finder's source window remained on the primary display. A second scratch-folder
window provided a safe drop destination at the other display's right edge.

| Check | Result |
| --- | --- |
| Icon on: drag from the primary Finder window to AppKit `(-10, 580)` | No full Tray appeared on either display, including while held. Finder received the file in the scratch destination. |
| Icon off: repeat the same cross-display drag | No full Tray appeared. Finder received the second file in the scratch destination. |
| Icon off: approach the Tray's actual primary-display home at `(1850, 525)` | Tray appeared on the primary display and accepted exactly one 44-byte test file. The original remained in Finder. |
| Source focus during all three drags | Finder stayed the foreground application. |

Each run verified a new drag-pasteboard change count with readable file URLs and
inspected actual window-server panel bounds while the mouse remained down. The
successful home approach and drop are the positive control for the two suppressed
cross-display approaches.

The old #187 build (`e8b25ebf3fbc911ac3ff550ce3c451b3ff9c09b3`) opened a panel on
the primary display for the same cross-display approach, with the icon both on and
off. This is the behavior corrected by #189. The earlier review description should
not be applied to #189's replacement activation rule.

The task-owned Tray reference was removed, and the original effective settings
were restored: icon on, automatic reveal on, pinned on, idle timeout 30 seconds.

## Regression coverage

`Tests/TrayTests.swift` now exercises all three homes (`menuBar`, `screenEdge`, and
`placed`) against the native cross-display coordinates. It rejects the other
display's edge while keeping the actual home reachable, and checks the reverse
arrangement with a negative screen origin and a vertically offset portrait display.
The CI minimum increases by the two added parameterized test methods.
The complete local suite passed: 509 tests in 80 suites, including all six new
display/home cases, with zero failures or skips. The Simplified Chinese
localization check passed for all 1041 strings; XcodeGen produced no plist changes.

This focused verification does not establish full acceptance of #189's hint motion,
Reduce Motion / Reduce Transparency, promised-file drops, or all cancellation paths.
