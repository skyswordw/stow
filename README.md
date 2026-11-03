# #104 motion review: frame bursts

Made with `scripts/motion-bursts.sh` (`-StowBurst <transition>`). Each sheet has one row per step and
frames at fixed offsets after it (the label under each frame is its real time). Steps happen by
click, by key (a synthetic key press current at the moment of the change), or on their own.

- `after/<transition>-<light|dark>-<none|motion|transparency|contrast>.jpg`: this PR, plain and with
  each launch-argument override (`-StowReduceMotion`, `-StowReduceTransparency`, `-StowIncreaseContrast`).
- `before/`: the same sites on the commit before the fixes (`none` and `motion`), for the four that changed.
- `stills/`: Reduce Transparency override, before/after: Details' backdrop (`list-*`) and Quick Look's
  lock badge (`quicklook-dark-window*`).

These are override captures. AppKit's own window animations, system controls and system glass only
follow the real System Settings switches; that pass is still to do (checklist in #104).

Known limit of the synthetic key: a view that picks its animation in `body` (Actions region, batch
panel, folder-access card, lock badge) doesn't see it, so those "by key" rows show the click's motion.
Disclosures now decide at the moment of change and are filmed correctly.
