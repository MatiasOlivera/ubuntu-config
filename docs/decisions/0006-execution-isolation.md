# Execution isolation for repository checks

- Status: proposed
- Deciders: Matias Olivera
- Date: 2026-10-13

## Context and Problem Statement

Repository checks vary in whether they execute checkout-controlled code and
whether that code can mutate the system. Without a clear isolation rule,
contributors may run untrusted code with the authority of their host account.
Containerization limits some effects but shares the host kernel, so it is not
equivalent to a virtual machine boundary.

## Decision Drivers

- Forks and branches from other contributors must be treated as untrusted.
- Local and CI verification must remain fast.
- Host network reachability matters even when the repository contains no
  valuable secrets.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Host for all checks | Lost: untrusted code runs with host account authority | Lowest setup cost |
| **Isolation based on execution and impact** | Won: boundary follows what the check executes and can change | Policy must be maintained |
| Container for all checks | Lost: shares the host kernel and is unsuitable for system mutation | Container limitations |
| Virtual machine for all checks | Lost: strongest boundary, but slows routine verification | Highest runtime cost |

## Decision Outcome

Chosen option: **isolation based on execution and impact**, because it balances
the risk of running untrusted code with the need for fast routine checks.

- Checks that inspect code without executing it may run on the host.
- Checks that execute code from an untrusted checkout must run in a hardened,
  network-isolated container environment; they must not run on the host.
- Checks that mutate the system must run in a virtual machine; they must not
  run on the host or in a container.

### Positive Consequences

- Untrusted code is not given the host account's direct authority.
- Isolation requirements follow a consistent rule across local and CI checks.

### Negative Consequences

- Hardened containers still share the host kernel, leaving residual escape risk.
- Stronger isolation for code-executing checks can add setup and runtime cost.
