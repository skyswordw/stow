# Stow migration to Beastry

Prepared on 2026-10-31 (Pacific/Honolulu). Status: repository transferred to Beastry/stow; see the
[execution record](beastry-migration-execution.md) for verified results. The baseline below
records the earlier planning inspection. Organization-wide policies were not changed.

## Direction and timing

Target: transfer the existing public `skyswordw/stow` repository to `Beastry/stow`,
keeping the repository name, Git history, and existing collaboration records.

At planning time, the user reported that Claude Code was developing current work. The recommended
cutover point is after that work has completed, been reviewed and merged, and
`main` has passed its checks. Preparation may continue now. Do not transfer during
active development or signing/publishing jobs. There is no requirement to close
every backlog issue before migrating.

Claude Code owns UI visual design and motion. Codex / Grok Bot own migration
correctness, state, security, errors, tests, and accessibility semantics. This
migration does not change product design. Full VoiceOver acceptance remains
deferred under AGENTS.md; issue #93 stays open.

## Observed baseline

Read-only GitHub API and source inspection on the preparation date established:

| Area | Observation | Migration implication |
| --- | --- | --- |
| Organization | `Beastry`, Free plan; no repositories returned | `stow` is available; recheck immediately before transfer |
| Owners | `skyswordw` and `neardws` are active organization admins (Owners); no pending invitations returned | Both collaborators already belong to the destination |
| Base permission | `read`; members may create repositories | Recommend base permission `none` and explicit access for future repositories; public code stays publicly readable |
| Organization 2FA | Requirement is disabled | Confirm both owners' account readiness before enabling a requirement; individual 2FA status was not inspected |
| Organization Actions policy | API returned 403; current CLI credential lacks `admin:org` scope | Check policy and runner availability in organization Settings; do not infer that Actions is disabled |
| Source repository | Public, not a fork, default branch `main`; current user has admin access | Use native transfer; keep public visibility |
| Repository access | `skyswordw`: admin; `neardws`: write | Recheck after transfer; organization Owner rights will apply |
| Branch protections | No repository rulesets returned; `main` protection endpoint reports unprotected | No existing branch gate to preserve; recommend adding an agreed PR/CI rule after discovering the destination check names |
| Repository Actions | Enabled; all Actions allowed; SHA pinning not required; default token permission `read`; Actions cannot approve PR reviews | Preserve least-privilege defaults and verify workflow-specific grants |
| Runners | CI, Release, Snapshots and Fuzz use `xcode-27` and `/Applications/Xcode_27.app`; repository self-hosted runner list is empty | Verify this label and Xcode path work in Beastry; runner provenance/organization entitlement is not established by that empty list |
| Pages | Workflow deployment; no custom domain; `github-pages` environment permits branch `main` | Verify environment policy and redeploy; query actual destination Pages URL |
| Releases | Published `v0.1.0`, `v0.1.1`, `v0.1.2`, each with appcast, DMG and checksum | Inventory and verify transferred assets without replacing existing releases |
| Live update feed | Latest appcast is version `0.1.2`, build `516`; enclosure uses the old repository URL | Preserve old-client compatibility; recheck latest build at cutover |
| Webhooks / deploy keys | Both API lists are empty | Recheck at cutover; GitHub App installations are a separate inventory |

Open PRs at inspection time:

- #237: Design: real demo content (#69), branch `claude/69-real-demo-content`.
- #239: Visual pass: contextual archive notices and Details scope (#229, #230),
  branch `claude/229-230-details-findings-f1c142`.
- #240: Tray and batch panel visual pass (#233, #232),
  branch `claude/233-tray-batch-visuals-bf83f7`.

Some associated CI/Snapshots runs were queued or running. This is a point-in-time
inventory, not proof of which task Claude Code is currently executing or its
review status. Reconcile these PRs with the collaborator at cutover.

Nine repository secret names were visible, without reading any values:
`APPLE_TEAM_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_ID`,
`ASC_API_KEY_P8_BASE64`, `DEVELOPER_ID_IDENTITY`, `DEVELOPER_ID_P12_BASE64`,
`DEVELOPER_ID_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`.
No repository Actions variables were returned. Secret usability and off-platform
recovery backups have not been verified.

## Prepare before the cutover

1. Finish the current Claude Code work and obtain a green, recorded `main` SHA.
   Preserve local uncommitted work and other worktrees. At inspection, DESIGN.md,
   Handoff/ui-motion-claude-code.md and two clarity briefs already had local work;
   this plan does not alter them.
2. Inventory GitHub App integrations used by both collaborators, including any
   coding agents, review bots, CI services, and fine-grained PAT repository grants.
   Check/install the required Apps for Beastry and authorize destination access.
   App permissions have not been inspected. Do not transfer ownership of an App
   merely because its installed repository is moving.
3. Check Beastry Settings for allowed Actions, workflow token defaults, runner
   labels/access, and any organization rulesets. Confirm Pages deployment is
   allowed. Resolve missing access before beginning the transfer.
4. Recommend base permission `none`, explicit repository/team grants, and required
   2FA after both owners confirm readiness and recovery access. Do not enforce
   2FA blindly: noncompliant accounts may lose access.
5. Confirm secure recovery copies of the existing Developer ID certificate/private
   key, notarization credentials, and Sparkle signing key. Repository secrets
   normally remain associated with a transferred repository. Keep them scoped to
   this repository; expanding them to all organization repositories is unnecessary.
6. Prepare a focused migration patch after the current work settles. Keep its
   destination feed changes on a branch until the destination URLs exist. Avoid
   a broad replacement of historical issue/PR links or Apple team identifiers.

## Source changes to prepare

| Files | Required outcome |
| --- | --- |
| `project.yml`, generated `App/Info.plist`, `App/Updates/UpdatePolicy.swift` | Feed becomes `https://github.com/Beastry/stow/releases/latest/download/appcast.xml`; regenerate the project and commit rewritten tracked plists |
| `Tests/UpdateTests.swift`, `scripts/verify-app-bundle.sh` | Expected feed matches the new canonical URL; existing signed-build and configuration restrictions continue working |
| `scripts/generate-appcast.sh`, `.github/workflows/release.yml` | Repository default and workflow `REPO` input agree with the app feed; download/release-note links use the destination; build monotonicity check still runs |
| `scripts/render-cask.sh`, `packaging/homebrew/stow.rb` | Update default repository and homepage; ensure `--repo` changes the rendered cask URL as well as the downloaded DMG URL |
| `README.md`, `RELEASING.md`, `ROADMAP.md`, `packaging/homebrew/README.md` | Current setup/release/website links refer to Beastry; a separate Homebrew tap remains a separate decision |
| `.github/workflows/pages.yml`, `scripts/build-site.py`, site output | Verify existing `GITHUB_REPOSITORY` substitution produces destination links; change only what verification demonstrates is necessary |

The cask renderer currently accepts `--repo` for fetching but copies a literal
old-owner URL from its template. Merely passing the new repository in the workflow
would leave the generated cask pointing at the old owner. Verify the generated
artifact itself.

Keep bundle IDs, App Group `YNQ2233752.app.stow.Stow`, Apple Team ID, signing
identity, and Sparkle public/private key pair unchanged for this repository move.
Moving to a GitHub organization is not an Apple Developer account migration.

## Cutover sequence

1. Agree a short window with the collaborator; pause merges and publishing and
   allow in-flight relevant workflows to finish. Record `main`, branch/tag refs,
   releases, secret names, Pages and access settings again.
2. Create a protected local `git clone --mirror` backup outside the checkout,
   verify its refs, and separately export Issues/PR metadata, settings and release
   assets/checksums. A Git mirror does not back up GitHub platform records or
   secret values. Preserve unpushed/local-only work separately.
3. Recheck `Beastry/stow` is absent. Transfer the existing repository through
   Settings > General > Danger Zone > Transfer ownership. Keep name and visibility.
   Do not pre-create a destination repository or replace the move with a push.
4. Verify repository identity/history, PRs/issues/assignments, releases/assets,
   owner/collaborator access, secrets, workflows and installed integrations.
5. Update each collaborator's checkout/worktree remote where needed:

   ```sh
   git remote set-url origin git@github.com:Beastry/stow.git
   git fetch origin
   ```

6. Reconcile/push the prepared migration branch against the recorded destination
   main; run CI and merge the focused URL/configuration changes when green.
7. Verify Pages source and `github-pages` branch policy, dispatch Pages, and query
   its actual `html_url` (expected host: `beastry.github.io`, path `/stow/`). Check
   homepage, docs, navigation, and download links. GitHub does not redirect the
   old Pages site. Accept a short website interruption or arrange an independent
   old-site landing route in advance if continuity is required; do not use the old
   repository slug for that route.
8. Exercise signed release/notarization/appcast generation using an unused version
   and a build above the latest published feed. Use a draft or artifact-only run;
   confirm the packaged app, Team ID, signatures, feed, key and asset URLs. Do not
   publish as a side effect of migration validation or overwrite published assets.
9. Resume normal merges once CI, website and old-client download/update paths are
   verified. Publishing the first destination release is a separate normal release
   action after its own validation.

## Verification and recovery

- Before and after transfer, compare branch/tag object IDs and published asset
  inventories/checksums. Native transfer should retain history and collaboration
  records, but record evidence rather than assuming completion.
- For the source patch, follow AGENTS.md: provision pinned 7-Zip in its checkout,
  run `xcodegen generate`, build/test, check zh-Hans localizations, and inspect
  generated plist diffs. Use existing update tests plus focused appcast/cask output
  checks. Do not register temporary Finder/Quick Look extensions during routine
  build/test; signed integration checks follow #32/#38 with the release collaborator.
- Fetch both the old and new latest appcast URLs with redirects enabled. Parse
  version/build and enclosure URLs. Verify the old enclosure URL still downloads
  identical bytes; HTTP success on the feed alone is insufficient.
- Test update checking with a genuine older signed Stow version. A real upgrade
  additionally needs a newer signed candidate; a draft is not served by `latest`.
  Record this distinction and complete upgrade acceptance at the first validated
  destination release. An unchanged feed saying “up to date” does not prove upgrade
  installation works.
- Recheck the latest build at release time; `516` is today's baseline, not a fixed
  next-release floor forever. Keep full Git history for commit-count build numbers.
- If signing, Apps, Pages, Actions or legacy redirects fail, keep publishing paused
  and repair the destination. Existing published assets stay intact. A code revert
  can restore configuration but cannot restore an organization policy or Pages host.
- Do not rely on transferring back as a guaranteed undo. Old namespaces may be
  retired and reverse-transfer permissions/policies may differ. Do not delete the
  destination or force-push history as a recovery procedure.
- Never recreate `skyswordw/stow`: doing so permanently removes GitHub's redirect
  and can break older installed clients. Historical evidence links may continue
  to use that redirect.

## References

- [GitHub: Transferring a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository)
- [GitHub: Preparing to require 2FA](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-two-factor-authentication-for-your-organization/preparing-to-require-two-factor-authentication-in-your-organization)
- [GitHub: Reviewing installed Apps](https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps)
- Local release contracts: RELEASING.md, AGENTS.md, and the current UI/motion handoff.
