# 266-opening captures (Claude Code visual pass on #266)

- `browser-opening-*-before-after.png`: the Browser while an archive is still opening (`browser-opening` scene), before | after.
- `titlebar-opening-vs-loaded-before-after.png`: top = opening state, bottom = loaded Browser. Left is before (traffic lights and title jump), right is after (identical).
- `timeline-*`: real opens through the engine, captured 0.05 / 0.15 / 0.3 / 0.6 / 1.2 s after launch (top to bottom; Glance left to right). Small = 13-file ZIP, big = 60,060-entry ZIP. The `open` scene's window is resized to 1120x700 by the harness partway through, so one frame may show a taller window.
- `timeline-glance-remembered-after.png`: `openPreferred` with Glance as the chosen window; one window per frame (no Welcome).
- `settings-glance-{light,dark}-{en,zh}-before-after.png`: Settings › Glance, before | after.
- `glance-opening-*`: Glance's opening view (it looks the same after 0.4 s; it now waits that long before showing its words).
