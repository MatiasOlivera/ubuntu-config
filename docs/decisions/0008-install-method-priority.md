# Install method priority

- Status: proposed
- Deciders: Matias Olivera
- Date: 2026-11-20

## Context and Problem Statement

Setup installs applications through a mix of distribution packages, vendor
repositories, standalone tools, universal package formats and downloaded
installer files, with no rule deciding which a new application should use.
Some of those paths are not covered by the system upgrade, and the choice is
re-litigated for every new tool. Since the question was raised, several tools
have moved to checksum-verified release artifacts, which makes the original
standalone-installer rung obsolete.

## Decision Drivers

- Distribution repositories integrate an application with the system's own
  update path.
- Delivery must be verifiable; an accepted decision already forbids executing
  code for which no publisher integrity material exists.
- Desktop and command-line tools have different viable channels, and a rule
  should prefer the least privilege that still works.
- A single short, reviewable order is worth more than case-by-case discretion.
- Existing installations must keep working; this decision should not require a
  mass migration.
- Installs must stay rerun-safe and non-interactive on a fresh machine.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Keep the original ladder, with an executable vendor installer as its third rung | Rejected — contradicts the accepted integrity decision, and several tools have already moved past it. | Reopens a settled question and gives reviewers conflicting guidance. |
| Put verified release artifacts ahead of distribution repositories | Rejected — gives up integration with the system update path, and no upstream guidance supports that order. | Weaker update story; more review friction. |
| Leave the choice case by case with no order | Rejected — does not answer the question that prompted the decision. | Every new application re-litigates the same trade-off. |
| Distribution-first ladder with a verified-artifact rung and a separate exception path for unverifiable installers | **Chosen** — one ordered answer that keeps system updates where possible and leaves integrity decisions authoritative. | Some existing applications remain below the order until separate follow-up work. |

## Decision Outcome

Chosen option: **distribution-first ladder with a verified-artifact rung and a
separate exception path**, because it gives one predictable answer while
preserving the update and integrity properties the setup already relies on.

Install methods are preferred in this order: Ubuntu apt; vendor apt repository;
checksum-verified vendor release artifact; Homebrew for command-line tools;
flatpak for desktop applications; snap; raw vendor `.deb` download.

A release artifact qualifies for its rung only through the existing integrity
source priority; that decision stays authoritative and is not restated here.
Remote install scripts are not a rung: execution of unverifiable remote code is
permitted only through the documented exception path.

Ties are broken by, in order: staying idempotent and non-interactive; choosing a
verifiable source; keeping updates on a path the setup actually runs; and using
the least privilege that is equally correct.

A deviation is tracked as separate work. This decision does not rewrite or
annotate existing scripts.

### Positive Consequences

- Contributors have one answer to "how do I install this?" and reviewers can
  ask which rung a change uses.
- The system update path remains the default where it is available.
- The integrity decisions remain authoritative; no new unverifiable route is
  introduced.
- Existing installations are unaffected; deviations become their own work.

### Negative Consequences

- A verified-artifact install needs more setup work than a repository install,
  and its updates are vendor-native rather than apt-managed.
- Applications currently below the order stay that way until their follow-ups
  are acted on; the decision records the debt rather than clearing it.
- Two lower universal formats remain in the order even though this setup does
  not run their upgrade commands directly.
