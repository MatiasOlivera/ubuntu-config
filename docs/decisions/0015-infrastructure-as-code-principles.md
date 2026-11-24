# Infrastructure as code principles

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-24

## Context and Problem Statement

The repository already manages a workstation the way infrastructure as code is
managed: the environment definition is versioned, configuration is declarative,
setup steps converge on rerun, and a fresh clone rebuilds the machine. None of the
human- or agent-facing documentation names that model. The README described what
the scripts do, and the agent guidance stated the declarative/imperative split as
a bare rule, so a reader had to infer the contract from the implementation. The
choice is whether to make the model explicit and, if so, how far to take it.

## Decision Drivers

- The contract should be readable without reverse-engineering the implementation.
- Agent guidance should derive placement rules from a stated principle.
- The statement must remain true as the repository changes.
- No runtime behaviour or tooling change is warranted for a documentation gap.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Name the principles the project already implements | Won: makes the contract explicit without changing behaviour | Small |
| Adopt external infrastructure-as-code tooling | Lost: adds tooling and runtime change for a documentation problem | Large |
| Leave the contract implicit in the implementation | Lost: readers and agents must infer it, and the rules look arbitrary | None |

## Decision Outcome

Chosen option: **name the principles the project already implements**, because the
practices are already in place and only the statement is missing.

- Only principles that hold today are named; each is described by the behaviour a
  reader can observe, not by the file or command that happens to implement it.
- Agent-facing guidance states the principle alongside the placement rule, so
  the rule has a stated rationale.
- The statement changes no setup behaviour and adds no tooling or enforcement.

### Positive Consequences

- Readers can see the model without reading the implementation.
- Agent guidance has a named principle behind the declarative/imperative split.
- Evidence is described at the level of observable behaviour, so the statement
  stays accurate through refactors.

### Negative Consequences

- The statement can still drift if a named principle stops holding; periodic
  verification against the repository is required.
- Naming only implemented principles leaves aspirational practices undocumented
  until they are real.
