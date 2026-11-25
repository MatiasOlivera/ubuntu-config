# plan.md - `121-automate-the-release-sequence`

## Architecture

One release entry point plus one pinned-tool helper, driven locally for
preparation/preview and by GitHub Actions for publication. The promotion merge
is the only approval: no command runs after it.

1. **`cliff.toml` (new).** The single source for git-cliff's tag pattern,
   Conventional Commit parsers, Keep a Changelog groups, commit/issue links and
   bump rules. Pre-1.0 breaking changes stay minor; an untagged start is
   `v0.1.0`. It drives only version computation and the exhaustive changelog —
   the release page stays GitHub-generated (ADR 0004, narrowed by ADR 0016).
2. **`scripts/git-cliff.sh` (new, sourceable helper + CLI).** Resolves git-cliff
   **2.14.2** from the publisher's release archive, verifies the archive against
   the publisher's `.sha512` asset, caches the verified binary under
   `${XDG_CACHE_HOME:-$HOME/.cache}/ubuntu-config/git-cliff/2.14.2/`, and prints
   its path. Both the workflow and local preview use it; `GIT_CLIFF` overrides
   the path so tests never download anything. The repo already treats publisher
   checksums as the integrity source (ADR 0003, 0007).
3. **`scripts/release.sh` (new, single entry point).** Modes:
   - `prepare` — runs on `develop`: clean tree, synced with `origin/develop`,
     ahead of `main`, latest develop check green, computed tag absent locally
     and on origin. Regenerates `CHANGELOG.md` stamped with the computed
     version, commits `chore(release): <version>`, pushes, then opens a
     `develop → main` promotion PR (or re-stamps an already-open one so two PRs
     cannot compete). The PR body carries the reviewed changelog section and a
     verification checklist naming the merge-commit requirement and automatic
     publication.
   - `preview` — runs on `develop`: read-only. Prints the computed version, the
     changelog section that would be stamped, and the notes returned by
     GitHub's generate-notes API for the upcoming tag against the develop tip.
     Compares `.github/release.yml` on `develop` with `origin/main` and warns
     when the target would use different grouping. Writes nothing, creates no
     tag/release, performs no push.
   - `publish` — invoked by the workflow after a merged `develop → main` PR.
     Verifies HEAD on `main` is a two-parent merge whose develop-side parent is
     reachable from `origin/develop`; verifies the computed version matches the
     stamped changelog section; refuses an existing tag pointing elsewhere.
     Then creates and pushes an annotated tag at the merge commit, generates
     notes from the same merge SHA via the API into a temporary file, publishes
     with `gh release create --notes-file … --verify-tag --target <merge>`, and
     merges `main` back into `develop` through a detached scratch worktree so
     the tag is an ancestor of `develop`. An EXIT trap removes the scratch
     worktree and notes file. If the tag or release already exists from a
     partial previous run, it resumes instead of duplicating; it never moves a
     tag at a different commit.
4. **`.github/workflows/release.yml` (new).** Triggers on `pull_request`
   `closed` for `main`, only when `merged` is true, `head.ref == develop` and
   `head.repo.full_name == github.repository`. Grants `contents: write` and
   `actions: read`, checks out with full history, installs the pinned tool via
   the helper, and runs `publish`. A concurrency group prevents duplicate runs
   for one promotion. The existing `.github/workflows/test.yml:3-6` is
   untouched.
5. **`tests/release-test.sh` (new).** Auto-run by `tests/test.sh:156-161` (the
   `*-test.sh` glob). Uses real `git` in temporary bare-origin/local clones,
   stubs `gh` on `PATH` and overrides `GIT_CLIFF`, so no network, credentials,
   tag or release is touched. Covers: wrong-branch and dirty-tree refusal,
   existing-tag refusal, read-only preview, merge-shape and target guards,
   ungreen checks, tag/release creation with the API body, merge-back, resume,
   and checksum failure.
6. **Docs.** Add a "Releasing" section to `README.md` near the Testing
   (`README.md:174`) and Project structure (`:263`) sections; update the release
   issue template (`.github/ISSUE_TEMPLATE/6-release.md:8-41`) so its checklists
   describe automation instead of manual tag/release steps; add one pointer in
   `AGENTS.md` so agents know the mechanism exists. ADR 0016 records the
   decision.

## Data models

No schema or migration. The durable artifacts are:

- `CHANGELOG.md` — generated, committed on `develop`, never hand-edited; its
  top section is stamped with the version and used as a publish guard.
- A `v`-prefixed annotated tag at the promotion merge commit on `main`, also
  reachable from `develop` after merge-back.
- One GitHub release whose body is the generated notes from the target ref.

## API contracts

- `scripts/release.sh <prepare|preview|publish>` → exit 0 on success; non-zero
  with a `release:`-prefixed message naming the failed guard on refusal.
  Satisfies every acceptance scenario in `spec.md`.
- `scripts/git-cliff.sh` → prints the absolute path of the verified pinned
  binary, or exits non-zero on checksum/source failure. `GIT_CLIFF` overrides
  resolution for tests. Satisfies "release tooling is accountable".
- `POST /repos/{owner}/{repo}/releases/generate-notes` with `tag_name`,
  `previous_tag_name`, `target_commitish` → `{name, body}`; creates nothing.
  `preview` targets the develop tip, `publish` targets the merge SHA on `main`;
  `publish` sends the returned `body` verbatim as `--notes-file`. Satisfies
  "preview is read-only", "unpromoted notes configuration", and "published notes
  match the release target".
- Workflow event contract: `pull_request.closed`, `merged == true`, base `main`,
  head `develop` in the same repository. Any other event exits 0 without
  publishing. Satisfies "the promotion merge is the approval gate" and
  "publishing refuses a non-merge or wrong-target promotion".

## Decisions

- `docs/decisions/0016-release-automation.md` (accepted, 2026-11-25):
  automated sequence with the promotion merge as sole approval; version and
  exhaustive changelog from a pinned, integrity-checked commit-history tool;
  release notes generated at the target ref; merge-anchored tags reachable from
  the integration branch. Supersedes the external-generator rejection in
  `0004-release-notes-grouping`, whose grouping rules remain authoritative.

## Risks

- **Wrong-event publication.** A push or a PR from a fork branch named
  `develop` must not publish. Mitigation: workflow guards `merged`, base, head
  and repository identity before checkout; the script re-verifies merge shape
  and ancestry.
- **Preview drift.** Labels can change between the local preview and the
  workflow run, so notes may differ. Mitigation: the workflow prints the notes
  immediately before creating the tag/release and publishes that exact body;
  local preview is explicitly labeled as projected.
- **Back-merge conflicts.** `develop` may advance after the release commit.
  Mitigation: merge in a detached scratch worktree and fail with a clear
  conflict message rather than forcing a push; no state is left in the
  repository on failure.
- **Version/changelog disagreement.** Two runs could compute different
  versions if commits land after preparation. Mitigation: publish compares the
  computed version with the changelog section at the merge commit and refuses
  to tag on mismatch.
- **Publisher checksum trust.** Archive and checksum come from the same
  publisher. This is the repo's existing integrity model (ADR 0007); a
  compromised publisher is out of scope.
- **Tool availability in CI.** The runner must have `sha512sum` and `tar`
  (coreutils). Both are present on GitHub-hosted Ubuntu runners; the helper
  fails closed if either is missing.
- **Scope discipline.** No deployment, package publishing, release bot, hotfix
  workflow or rewriting of past releases; existing tags stay as they are.

## Assumptions

- `git-cliff --bumped-version` prints the next `v`-prefixed version from
  history and respects the configured bump rules. Source: git-cliff usage and
  configuration docs fetched via Context7 on 2026-11-24. Verification: run the
  pinned binary against `origin/develop` during implementation and assert the
  output in the hermetic test via the stub.
- GitHub's generate-notes endpoint accepts a not-yet-created tag name when
  `target_commitish` is supplied and stores nothing. Source: REST docs fetched
  2026-11-24. Verification: read-only preview probe plus a stubbed request test.
- `gh release create --verify-tag --target <sha> --notes-file <path>` publishes
  with the given body and fails if the tag is absent. Source: `gh release
  create` CLI behavior used by the reference repository's release script.
  Verification: hermetic stub asserts arguments; first real workflow run is the
  live check.
- The promotion PR is merged with a merge commit by the maintainer. Source:
  `AGENTS.md:88-92` (Git flow, release only `develop → main`) and the issue
  template's existing checklist. Verification: the publish guard rejects
  squash/rebase merges explicitly.
