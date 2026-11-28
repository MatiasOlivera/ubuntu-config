# Repository identity naming

- Status: proposed
- Deciders: MatiasOlivera
- Date: 2026-11-27

## Context and Problem Statement

The repository name and GitHub listing describe only part of what the project
contains, and the name is also reused as an identifier in scripts, tests and
published artifacts. Choosing a new identity therefore affects discovery,
existing links, app-owned state and CI. The choice and the boundary between
changing identity and preserving behavior need one durable rule.

## Decision Drivers

- A visitor should be able to judge the project's scope from the listing alone.
- Humans and coding agents should encounter one identity, not two competing
  names in active files.
- The target is a fresh install, so no upgrade path is needed.
- Existing external links and local clones must keep working.
- Republishing work should be paid once, not on every future rename.

## Considered Options

| Option                                              | Outcome                                                                 | Cost                                              |
| --------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------- |
| Keep the current name, improve description/topics   | The name still understates the scope                                    | Lowest, but leaves the core problem in place      |
| Rename everything, keep app state app-owned         | One identity everywhere; app state independent of the name              | New package publication and a marker path change  |
| Rename the repository only, keep runtime identifiers | Small diff, but two names remain in active files                        | Agents and readers can follow stale identifiers   |
| Give each artifact a role-specific name             | No shared name to grep and no coupling to the repo                      | Several unrelated names to learn and maintain     |

## Decision Outcome

Chosen option: **rename everything, keep app state app-owned**, because a single
identity is the point of the change and a fresh install needs no upgrade path.

The project identity is the new name in all active references. The same name is
used for every project-owned identifier; no second namespace is introduced.
Persisted state whose meaning belongs to an application rather than to the
repository is kept in an application-owned location, so a later repository
rename does not need to move it again. Historical records keep the name they
were written under.

### Positive Consequences

- The GitHub listing describes the whole workstation, not only configuration.
- Active code, docs and artifacts have one unambiguous identity.
- Fresh installs record app state independently of the project name.
- Future renames do not need to move application-owned state again.

### Negative Consequences

- A container package must be published under the new name and made public;
  the old package remains as an unreferenced artifact.
- Machines set up before the rename are out of scope: their next rerun treats
  the app as newly installed.
- External links rely on GitHub's rename redirects, and historical records
  intentionally retain the old name.
- A future rebrand repeats the identifier rename, because project-owned names
  carry the repository name.
