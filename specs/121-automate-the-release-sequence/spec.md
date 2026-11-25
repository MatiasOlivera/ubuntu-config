# spec.md - `121-automate-the-release-sequence`

## Context

Issue: [#121](https://github.com/MatiasOlivera/ubuntu-config/issues/121).

Cutting a release currently means following prose steps by hand. An agent that
follows that prose spends its context on a fixed sequence, and the text can drift
from what publishing actually requires. The easiest rule to get wrong is the one
from #57: generated release notes read `.github/release.yml` at the release
target ref, so a configuration change that has not been promoted has no effect
on the release.

The reference implementation in `MatiasOlivera/job-search-automation` has a
two-phase automated release procedure, a generated changelog, pinned version
bumping, and hermetic tests. This repository has none of that: only a release
issue template and ADR 0004, which says generated notes are the changelog and
that an external generator was rejected. This change makes the mechanism own
the sequence rather than the prose, and records the revised decision.

Decisions settled with the issue owner:

- The version is computed from Conventional Commits by a pinned git-cliff, not
  chosen by hand and not read from a release issue.
- A generated `CHANGELOG.md` is committed as the exhaustive, ungrouped record;
  GitHub-generated notes remain the release notes, grouped by labels at the
  target ref (ADR 0004 is narrowed accordingly).
- The human merge of the `develop → main` promotion pull request is the explicit
  approval. Create no tag or release before it; create both automatically when
  it happens.
- The read-only preview runs locally, on `develop`, before anything is
  published.
- The pinned git-cliff is obtained from its publisher with a checksum check, so
  the same version runs locally and in CI.

## User stories

- As the maintainer, I want one release command that verifies `develop`, computes
  the version, regenerates the changelog and opens the promotion pull request,
  so I never re-derive the sequence from prose.
- As the maintainer, I want to preview the computed version, changelog section
  and generated release notes before the promotion, so I can review what will
  be published without changing the repository.
- As the maintainer, I want the promotion merge to be the only approval gate,
  so a tag and release appear when I approve the promotion and never before.
- As the maintainer, I want the release notes to use the grouping configuration
  at `main`, so a configuration change still sitting on `develop` cannot
  silently claim to have changed a published release.
- As the maintainer, I want a committed generated changelog that survives
  regeneration without a diff, so the exhaustive history has one authoritative
  home.
- As the maintainer, I want a failed publish to be resumable when retried, so a
  tag created before a network failure does not block the release.
- As the maintainer, I want a wrong-branch, red-CI or squash-merged promotion to
  fail loudly, so a release is never cut from an unverified state.
- As the test-gate maintainer, I want the release behavior covered by hermetic
  tests with stubbed git and GitHub clients, so `./tests/test.sh` stays green
  without network, credentials or writes to a real repository.

## Acceptance criteria (BDD)

```gherkin
Scenario: prepare verifies develop and opens the promotion
  Given a clean develop checkout synced with origin and ahead of main
  And the latest check on develop is green
  When the maintainer starts the release preparation
  Then the next version is computed from unreleased Conventional Commits
  And the changelog is regenerated and committed with that version
  And a develop-to-main promotion pull request is opened
  And no tag or GitHub release exists yet

Scenario: preparation refuses an unverified state
  Given the checkout is on any branch other than develop
  When the maintainer starts the release preparation
  Then it fails with a message naming the branch it requires
  And it creates no commit, pull request, tag or release

Scenario: preparation refuses an existing version
  Given the computed version already has a tag locally or on origin
  When the maintainer starts the release preparation
  Then it fails before writing any file or opening any pull request
  And the existing tag is left untouched

Scenario: preview is read-only
  Given a checkout with unreleased commits and a configured release-notes file
  When the maintainer asks for a preview
  Then the computed version, changelog section and generated notes are shown
  And no tag, release, commit, file change or push is made

Scenario: an unpromoted notes configuration is not credited to a release
  Given the notes configuration differs between develop and main
  When the maintainer previews the release
  Then the notes shown are the ones the current release target would produce
  And a warning names the branch whose configuration would not take effect

Scenario: the promotion merge is the approval gate
  Given an open develop-to-main promotion pull request
  When the maintainer merges it with a merge commit
  Then a release is created automatically without another command
  And the release is tagged at the promotion merge on main
  And no tag or release was created before that merge

Scenario: publishing refuses a non-merge or wrong-target promotion
  Given a merged pull request into a branch other than main
  Or a main promotion merged by squash or rebase
  When the release automation runs
  Then it fails with a message explaining why the promotion cannot be released
  And no tag or release is created

Scenario: publishing refuses red checks on develop
  Given a merged develop-to-main promotion whose develop checks are not green
  When the release automation runs
  Then it fails before creating a tag or release
  And the failure names the ungreen checks

Scenario: published notes match the release target
  Given a promotion merged into main with a grouped notes configuration
  When the release is published
  Then the release notes use the grouping configured at main
  And regenerating notes for the published tag returns the same text
  And the release-labelled promotion pull request is absent from the notes

Scenario: the changelog is generated and stable
  Given a published release and its tag reachable from develop
  When the changelog is regenerated on a clean checkout
  Then the file is unchanged
  And commits from the published release are not listed again as unreleased

Scenario: a failed publish is resumable
  Given a publish that created the tag but failed before creating the release
  When the automation is retried
  Then it continues from the tag and publishes the release
  And it never moves a tag that points at a different commit

Scenario: release tooling is accountable
  Given a pinned release-tool archive whose checksum does not match the publisher's
  When the release automation tries to use it
  Then it fails closed with a clear message
  And no release step runs with that tool

Scenario: the static gate stays green
  Given the full change is applied
  When ./tests/test.sh is run without --vm
  Then all existing checks and the new release tests pass
  And no test needs network, credentials, sudo, apt or a real repository
```

## Constraints

- [ ] One release entry point in this repository, with a read-only preview mode
      and a publish mode invoked by the promotion workflow.
- [ ] The merge of a `develop → main` pull request is the only approval; no
      separate publish command is required after the merge.
- [ ] A tag or release is never created before that merge, and is never created
      from a non-`main` target, a non-merge promotion, or ungreen develop checks.
- [ ] Release notes come from GitHub's generated notes at the release target
      ref; ADR 0004's label grouping stays authoritative for the release page.
- [ ] The committed changelog is generated, never hand-edited, and regeneration
      on a clean tree produces no diff.
- [ ] Version computation uses a pinned, checksum-verified git-cliff, with the
      same version available locally and in CI.
- [ ] The tag is reachable from `develop` after publication, so the next
      changelog does not re-list released commits.
- [ ] Secrets are never committed; the workflow uses the repository's scoped
      token with only the permissions needed to tag, release and push back.
- [ ] Host-side tests stub git and GitHub clients and never mutate a real
      repository or publish a real release.
- [ ] `./tests/test.sh` stays green, including its existing setup-script
      contract checks.
- [ ] Out of scope: deploying an artifact, publishing a package, release bots
      that open their own pull requests, rewriting past releases, hotfix
      handling, and changes to the PR labeling convention (a hub standard).

## Assumptions

- git-cliff v2.14.2 is the current upstream release and publishes per-platform
  archives with `.sha512` checksum assets. Source: the GitHub releases API for
  `orhun/git-cliff` returned `v2.14.2` with `git-cliff-2.14.2-*.tar.gz.sha512`
  assets on 2026-11-24. Verification: pin that version at implementation time
  and fail closed if the publisher checksum does not match.
- GitHub's generate-notes endpoint accepts a tag name, a target commitish and a
  previous tag, and returns a body without saving a release. Source: GitHub REST
  docs for `POST /repos/{owner}/{repo}/releases/generate-notes`, fetched
  2026-11-24. Verification: one read-only preview probe against this repository
  plus a hermetic stub test.
- `.github/release.yml` exists on `main`, so notes generated at a `main` target
  can be grouped. Source: `git show origin/main:.github/release.yml` succeeded
  in this checkout. Verification: read the file at implementation time.
- GitHub-hosted runners provide `git` and `gh`, and a workflow can grant its
  token write access to repository contents. Source: the existing
  `.github/workflows/test.yml` uses `actions/checkout@v5` on `ubuntu-26.04`.
  Verification: the release workflow's first real run.
