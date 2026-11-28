# plan.md - `192-explore-alternative-repository-names-description`

## Architecture

Three layers change in one coordinated pass:

1. GitHub metadata: repository name, description and topics.
2. Repository identity references: README, agent instructions, the
   constitution, generated changelog links and issue-template links.
3. Runtime identifiers: container image name, e2e VM prefix, state/cache/log
   locations, compose project, observability service name and their tests and
   dashboards.

The project name is reused for every project-owned identifier; no second
namespace is introduced. AnythingLLM's version marker moves out of the
project-named state directory to an application-owned location, because it is
app state rather than a project identifier. Its previous location is read once
when the new marker is absent, so an existing install keeps its recorded
version without a reinstall.

Sequencing: land the in-repository changes first, apply the GitHub rename and
metadata in one window immediately before merge, publish and make the new
container package public, then verify redirects and the full gate. The rename
is externally visible and needs explicit approval before it is executed.

## Data models

No schema changes. One persisted file moves: the AnythingLLM version marker.
Read the new location first; when it is absent and the legacy marker exists,
use the legacy value and write it to the new location on the next install. No
other persisted state is migrated — cache, logs and e2e records are disposable.

## API contracts

No application API changes. External surfaces are the GitHub REST calls for
repository metadata and container package publication, and the redirect
behavior that keeps old links and git remotes working. Each maps to
"Listing conveys the full scope", "Old links still reach the renamed
repository" and "CI image is available under the new name" in `spec.md`.

## Repository metadata

Name: `ubuntu-workstation`

Description:

```text
My Ubuntu workstation as code: bash scripts install the software I use; chezmoi dotfiles configure my development environment.
```

Topics: `ubuntu`, `linux`, `dotfiles`, `chezmoi`, `bash`, `workstation`,
`automation`, `infrastructure-as-code`.

## Decisions

- `docs/decisions/0019-repository-identity-naming.md` — project naming,
  description/topics, runtime identifier scope and the persisted-state
  boundary. Status moves from `proposed` to `accepted` when the plan is
  approved.

## Risks

- The new container package starts private and must be made public before fork
  PR checks can use it; the old package remains published but unreferenced.
- Rename redirects cover web and git traffic, but not GitHub Pages project-site
  URLs (this repository has none) or links outside the repository that we
  cannot edit.
- Local clones keep working through redirects; update their remotes to avoid
  confusion.
- The legacy AnythingLLM marker must stay readable while pre-rename installs
  exist; the version check must not fail when only the new marker exists.
- The grep-based check for stale names must exclude historical records and the
  deliberate legacy-state read, or it will report false positives.

## Assumptions

- The chosen name is free under the account and the token can rename the
  repository (source: `gh api` 404 for the candidate name; `gh auth status`
  shows `repo` scope). Verify by applying the rename.
- GitHub redirects after a rename and a first container publish is private
  (source: GitHub docs, recorded in `spec.md`). Verify after the mutation.
