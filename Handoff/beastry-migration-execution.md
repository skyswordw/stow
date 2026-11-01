# Beastry migration execution record

Started 2026-10-31 (Pacific/Honolulu). The user authorized reviewing and merging
the completed PRs, then transferring Stow into Beastry. The earlier
[migration plan](beastry-migration-plan.md) records the planning baseline.

## PR review and integration

- #237: real website demo content, sample-backed browsing, and contextual-notice copy.
- #239: Details and archive-notice presentation. Functional review corrected an
  App Store developer-attribution error: store distribution does not establish
  Apple authorship. A regression test covers developer-identity evidence.
- #240: Tray command scope and batch-result presentation. Extraction scope,
  cancellation, result retention, and retry behavior remain unchanged; collapsed
  results prioritize failures/running work and Show All keeps every result reachable.
- #243: floating Browser navigation and toolbar. Search focus/Escape, marked-text
  composition handling, breadcrumb destinations, password controls, and editing
  behavior were reviewed. The combined tests cover file focus and inspector resizing.

Shared demo-scene, design-document and localization conflicts were integrated,
preserving the separate prototype-install archive, all new scenes, translated
strings, and the final floating-path direction. Claude Code retains UI visual
design and motion ownership; Codex reviewed functional correctness. Native
VoiceOver acceptance remains deferred under #93.

Local combined build and test: 615 tests in 91 suites passed; localization export
found 0 missing out of 1,185 strings. Website asset paths and inline JavaScript
syntax passed checks. All updated-head GitHub checks passed before cutover. PRs #237, #239, #240
and #243 were merged, and merged main d3ec297 passed CI. Website screenshot refreshes after subsequent design work remain separate
visual work, rather than an additional migration acceptance gate.

## Backup and access

The local backup directory is named `stow-to-beastry-2026-10-31`, outside the
checkout, with restrictive permissions. It contains a Git mirror with a successful
full integrity check, GitHub metadata exports, a bundle of local refs, a patch of
tracked working-tree changes, and an archive of untracked local documents.

All nine assets across releases v0.1.0, v0.1.1 and v0.1.2 were downloaded and
checked against GitHub's asset digests. A separate SHA-256 manifest records their
contents. Only secret names/metadata were exported; secret values cannot be read
back and were not exported.

Both `skyswordw` and `neardws` are organization Owners. Beastry's effective Actions
configuration was checked through an existing organization repository: Actions
enabled, all Actions allowed, default token permission read, PR-review approval
disabled. Stow's `xcode-27` jobs were identified as GitHub-hosted runners.

The direct organization Actions policy endpoint lacks CLI `admin:org` scope.
Personal GitHub App installation listing also requires a different token type;
those limitations are recorded rather than treated as proof of missing Apps.
The organization installation inventory shows Cursor with selected-repository
access; any desired access to Stow must be checked separately. No organization-wide
permission, 2FA, or unrelated repository settings were changed.

## Migration patch validation

The patch updates the canonical feed, configuration, release scripts, website
links, and Homebrew defaults for `Beastry/stow`. The cask template now substitutes
the repository and homepage so `--repo` affects the rendered URL as well as the
download. Release appcast generation receives the workflow's repository explicitly.

- Build and all 615 tests passed with the new feed configured.
- zh-Hans: 0 missing out of 1,185 strings; generated plist matches project.yml.
- Cask checks used the real v0.1.2 DMG: destination and alternate repository URLs,
  homepage, checksum, Ruby syntax, and invalid-repository rejection passed.
- Appcast dry run used a throwaway signing key: signing, signature verification,
  and destination download/release-note URLs passed. It does not establish access
  to production signing secrets or notarization credentials.

Bundle identifiers, Apple Team ID/App Group, signing identity, and Sparkle key
pair are unchanged. Published releases are preserved. Old clients' feed and DMG
URLs must continue through GitHub redirects; never recreate `skyswordw/stow`.

## Cutover results

The existing repository was transferred to **Beastry/stow**, retaining repository
ID **1427726812**, public visibility, and default branch main. Verification before
merging the migration patch confirmed:

- All 66 branch/tag references exactly matched the final pre-transfer snapshot.
- All 9 repository secret names and all 9 release asset IDs, sizes and digests matched.
- Every saved Issue/PR record and its assignees remained present and unchanged.
- Both collaborators have admin access; Actions remain enabled with default token
  permission read and workflow PR-review approval disabled.
- Pages remains a workflow site with no custom domain; the github-pages environment
  still restricts deployments to main.

[Migration PR #244](https://github.com/Beastry/stow/pull/244) passed all five checks
(build-test, universal, snapshots, package, cask) and was merged as 656f543. It also
updates the Homebrew CI audit for Homebrew 6: explicitly trust only the generated
stow-ci/local/stow cask in the disposable runner, without disabling tap trust.
The local origin remote now points to git@github.com:Beastry/stow.git. Other
collaborators must update their own local remotes.

[Pages deployment](https://github.com/Beastry/stow/actions/runs/41292524987) succeeded.
The new homepage at https://beastry.github.io/stow/ and rendered README return HTTP
200 and contain destination repository/site links. GitHub does not redirect the
old Pages host; repository redirects are separate.

Both old and new latest appcast URLs, and both old and new v0.1.2 DMG URLs, return
HTTP 200 after redirects and match their pre-transfer SHA-256 hashes. The installed
signed Stow 0.1.2 (build 516, using the old feed URL) completed Check for Updates
successfully both before and after transfer, reporting that it is up to date.
These native menu/alert checks used AX automation, not VoiceOver. No update was
installed. Actual upgrade installation remains acceptance work for the next
published release; an unchanged latest release cannot demonstrate that step.

Production signing, notarization, and appcast verification are tracked in the
[artifact-only Release validation](https://github.com/Beastry/stow/actions/runs/41292538244),
using version 0.1.3 with draft-release=false on 656f543. This is a validation build,
not an authorized publication: it must not create a release or version tag. The
[main CI workflow](https://github.com/Beastry/stow/actions/workflows/ci.yml?query=branch%3Amain)
validates the destination environment; documentation-only pushes supersede earlier main runs.

Preserve the original skyswordw/stow redirect namespace indefinitely. The current
published versions remain v0.1.0, v0.1.1 and v0.1.2; no existing release asset was
rewritten. No Finder or Quick Look registration was performed during this work.
