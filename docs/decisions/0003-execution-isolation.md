# Execution isolation: host for none, sandbox for untrusted, VM for system mutation

- Status: proposed
- Deciders: Matias Olivera
- Date: 2026-10-13

## Context and Problem Statement

The verification chain mixes checks that never execute repo code (`bash -n`,
shellcheck, the grep-based contract checks, `reports/gaps.sh`) with checks that
source — and therefore execute — repo code (`tests/test.sh`'s source-only check,
the functional tests, `reports/versions.sh`). Running all of them on the host by
default treats contributor-controlled code as trusted: the source-only check
runs each library script's top-level commands before any declaration is
validated, so on an untrusted checkout the "validation" executes the very code
it is meant to vet (CWE-829). Docker shares the host kernel, so it is
containment, not a security boundary.

## Decision Drivers

- Fork and branch PRs are the untrusted-code source.
- Local and CI loops must stay fast.
- Public repository: exfiltration is low-value, but LAN reachability is not.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Host for everything | Lost: executes untrusted code with the user's authority | Zero |
| **Three tiers by what a check executes** | Won: isolation follows whether, and on what, code executes | Policy text to maintain |
| Docker for everything | Lost: no kernel boundary for system-mutating scripts | Confusing half-failures in containers |
| VM for everything | Lost: minutes-versus-seconds loop cost | Slow iteration |

## Decision Outcome

Chosen option: **three tiers keyed on whether a check executes code**, because
every check's required isolation is derivable from one rule.

- **No execution** (`bash -n`, shellcheck, the grep-based checks, `gaps.sh`):
  host is fine on any checkout.
- **Execution of untrusted code** (source-only check, functional tests,
  `versions.sh`): Docker only, hardened (read-only mount, no network, dropped
  capabilities); never on the host.
- **Execution that mutates the system** (`install.sh`, `post-install.sh`):
  Multipass VM only; never Docker, never the host.

`tests/test.sh` Phase 1 spans the first two tiers; `--vm` runs the third; the
docker-isolated CI job is the hardened reference implementation.

### Positive Consequences

- Untrusted code is verified without executing it on a maintainer's host.
- CI and local flows are explainable by one rule, with the reasoning kept in
  this record.

### Negative Consequences

- The hardened Docker tier keeps a shared-kernel residual risk, accepted as
  proportionate to the threat model.
- Upgrading that tier to a VM-strength runtime (sandboxes, GVisor, Firecracker)
  remains a separate decision.
