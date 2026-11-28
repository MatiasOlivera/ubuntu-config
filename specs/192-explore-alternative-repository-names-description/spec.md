# spec.md - `192-explore-alternative-repository-names-description`

## Context

[#192](https://github.com/MatiasOlivera/ubuntu-config/issues/192) is a
discoverability problem: `ubuntu-config` reads as narrower than the project,
which also covers rerun-safe package, desktop-app and dev-tool setup. The
GitHub description and the absence of topics give a visitor little help in
judging that scope. The name, description and topics are settled in ADR 0019;
the work left is to apply that identity consistently without changing how the
setup behaves.

## User stories

- As a GitHub visitor, I want the repository name, description and topics to
  state the full scope, so I can decide whether it is relevant without opening
  it.
- As someone following a link into the project, I want in-repository references
  to use the same name, so I never land on a stale self-reference.
- As a person who already ran the setup, I want a rerun after the rename to
  behave exactly as before, so my installed apps and recorded versions are not
  reinstalled or lost.
- As a coding agent, I want one consistent identity across active code and
  docs, so I do not act on outdated names.
- As a maintainer, I want the naming decision recorded, so a future rename does
  not have to repeat the survey.

## Acceptance criteria (BDD)

```gherkin
Scenario: Listing conveys the full scope
  Given a reader on the GitHub repository listing
  When they see the repository name, description and topics
  Then the name names the whole workstation, not only its configuration
  And the description mentions rerun-safe setup scripts and chezmoi dotfiles
  And the topics include ubuntu, linux, dotfiles and chezmoi

Scenario: Old links still reach the renamed repository
  Given a bookmark or documentation link to the former repository location
  When the link is opened
  Then GitHub resolves it to the renamed repository

Scenario: No stale self-references in active files
  Given a fresh checkout after the change
  When a reader searches active docs and configuration for the former name
  Then nothing that identifies the repository itself uses the former name
  And historical changelog, spec and decision records are left intact

Scenario: Consistent runtime identity
  Given an e2e run or a local dev iteration after the change
  When VMs, cache, logs, traces and working files are named
  Then active scripts, tests and dashboards use the same project name
  And the only differently named state is owned by the app it belongs to

Scenario: Existing install state survives the rename
  Given a machine with apps installed by an earlier version of the setup
  When the setup is rerun after the change
  Then already-installed apps are skipped as before
  And the version reported for each managed app is unchanged

Scenario: Previous version marker is understood
  Given a machine whose AnythingLLM version marker was written by the old setup
  When the version is queried after the change
  Then the reported version matches the one recorded before the rename
  And no reinstall is triggered

Scenario: CI image is available under the new name
  Given the published test image has moved to the new package name
  When the full gate runs in CI and locally
  Then every check passes using the new image reference
```

## Constraints

- [ ] Setup behavior, including rerun-safety, must not change.
- [ ] Public repository: the change must not add secrets.
- [ ] Integration points: GitHub repository metadata, the container package,
      CI, local state and cache, e2e VMs and observability.
- [ ] Out of scope: what the scripts install, the repository restructure in
      #190, and renaming existing branches or pull requests.

## Assumptions

- GitHub redirects repository URLs and git operations after a rename
  (source: GitHub "Renaming a repository" docs; verify by opening one old link
  after the rename is applied).
- A container package has no in-place rename and a first publish is private
  (source: GitHub Container registry docs; verify by publishing once and
  checking the package visibility).
