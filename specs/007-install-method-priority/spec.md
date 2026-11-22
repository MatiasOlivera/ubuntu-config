# spec.md - `007-install-method-priority`

## Context

Issue: [#7](https://github.com/MatiasOlivera/ubuntu-config/issues/7).

Setup installs applications through several different methods: Ubuntu apt,
vendor apt repositories, release artifacts, Homebrew, flatpak, snap and raw
vendor `.deb` downloads. Nothing tells a contributor which to pick for a new
application; the trigger was uv, whose docs offer several mutually exclusive
paths. The issue's proposed priority predates the accepted integrity decisions
and its audit table no longer matches the tree: several scripts it lists as
`curl … | sh` now install checksum-verified artifacts.

Online check, re-verified on 2026-11-20 (web search still failed with HTTP 402,
so the authoritative docs were fetched directly and the quoted lines confirmed):

- [Debian's reference](https://www.debian.org/doc/manuals/debian-reference/ch02.en.html)
  warns "Do not install random packages by `dpkg -i random_package`", and
  [Debian's FAQ](https://www.debian.org/doc/manuals/debian-faq/pkgtools.en.html)
  documents apt as the way to install and upgrade from configured sources.
- [Flatpak's introduction](https://docs.flatpak.org/en/latest/introduction.html)
  says it is "best suited for desktop applications" and lists stale distro
  packages as one of the problems it addresses.
- No universal ranking was found in the sources consulted. Since web search was
  unavailable, this is not an exhaustive survey.

Conclusion: keep the Ubuntu-first order from the issue, with the verified
release artifact as the third rung, and treat unverifiable remote installers as
exceptions rather than a rung. This matches distribution guidance and the
repository's accepted integrity decisions.

This change defines one public priority for install methods, resolves the
current deviations into tracked follow-up work, and makes the repo's agent
guidance point at the policy. It records a decision; it does not migrate
existing applications. Language-ecosystem managers are tracked separately in
#8.

## User stories

- As a contributor adding a new application, I want one ordered list of install
  methods, so that I can choose without re-litigating the decision each time.
- As a maintainer reviewing a new-app change, I want the chosen method stated in
  the pull request's Verification section, so that I can check it against the
  published policy at a glance.
- As a maintainer reviewing an older script, I want each confirmed deviation
  recorded in its own follow-up, so that the audit becomes actionable work
  instead of a mass rewrite.
- As a person trusting setup, I want the policy to exclude unverifiable remote
  execution except through the existing exception register, so that a new
  application cannot quietly bypass the integrity decisions.

## Acceptance criteria (BDD)

```gherkin
Scenario: The decision answers "which method?"
  Given the repository already holds accepted decision records 0001 through 0007
  When a contributor opens the decisions directory looking for install-method guidance
  Then one accepted record states the ordered install methods and the tie-breakers
  And it refers readers to the existing integrity decisions where relevant
  And the earlier records remain unchanged and readable

Scenario: Agent guidance points to the policy
  Given a contributor is about to add a new setup script
  When they read AGENTS.md and follow its install-package guidance
  Then they find a single install-method-priority section
  And that section lists the methods from most to least preferred
  And it directs unverifiable installers to the integrity-exception register

Scenario: A verified artifact wins over the lower-rung methods
  Given a new tool has no Ubuntu apt package and no vendor apt repository
  And the vendor publishes a checksum or signature for a release artifact
  When the contributor chooses its install method
  Then the priority selects the verified release artifact before Homebrew, flatpak or snap

Scenario: Fallback when no higher rung exists
  Given a new tool has no apt, vendor-repository or verified-artifact path
  When the contributor chooses its install method
  Then the priority falls back to the next available method in the published order
  And no rung offers execution of an unverifiable remote installer

Scenario: Each deviation becomes its own terse follow-up
  Given the audit against the current tree confirms a script sits below the priority
  And no accepted integrity exception already covers that script
  When a maintainer looks at the issue tracker
  Then exactly one open follow-up issue describes that deviation
  And the issue names only the install method currently used by that script

Scenario: Existing deviations are not silently rewritten
  Given an existing script's install method is below the priority
  When the policy lands
  Then that script's install behavior and source text are unchanged
  And no deviation is justified by editing the script

Scenario: A new application states its rung in the pull request
  Given a pull request adds an application after the policy is adopted
  When the author completes the Verification section
  Then a prompt asks which rung of the priority the install method uses
  And a reviewer can answer that question from the pull request body alone

Scenario: The policy change passes repository checks
  Given the change touches documentation and issue tracking only
  When the repository checks run
  Then the static checks pass
  And no e2e VM run is needed
```

## Constraints

- [ ] The priority must not authorize unverifiable remote-script execution;
      ADR 0003 and the integrity-exception register stay authoritative.
- [ ] ADR 0007 remains the source-priority rule for artifact integrity; the new
      decision records only the order of install methods.
- [ ] Existing setup scripts are not touched; deviations are tracked, not
      silently fixed or commented on in place.
- [ ] The refreshed audit is based on the live tree at base tip `bdfaaf8`, not
      on the table in issue #7.
- [ ] Follow-up issues are public and externally visible. Each one is terse:
      it names only the method currently used, with no recommendation or
      migration analysis. Scripts with an accepted exception entry are excluded.
- [ ] Out of scope: language package-manager policy (#8), implementing any
      per-package migration, reinstalling uv, renumbering existing decisions.

## Assumptions

- Base tip is `bdfaaf8687c6015daae599ccdd6e5feb5b847a3a` on the workspace
  branch. Source: `git rev-parse HEAD`. Verification: re-check before writing
  any file the plan depends on.
- Decision files `0001`–`0007` exist, so the next free number is `0008`.
  Source: `ls docs/decisions`. Verification: re-check immediately before
  creating the record.
- ADR 0003 rejects remote install-script execution and ADR 0007 prefers
  maintainer-published integrity material with a GitHub-digest fallback.
  Source: `docs/decisions/0003-remote-installer-integrity.md`,
  `docs/decisions/0007-artifact-integrity-source-priority.md`.
- No open pull request touches issue #7. Source: GitHub pull-request search for
  "install method priority" at planning time.
- uv, fnm, copilot, opencode, antigravity and anythingllm already install
  checksum-verified artifacts; ollama and cursor-cli have entries in the
  integrity-exception register. Source: the corresponding `setup/` scripts and
  `docs/integrity-exceptions.md`. Verification: the refreshed audit re-reads
  each script before any issue is filed.
- The 13 deviations to file are: raw `.deb` — chrome, discord, obsidian,
  gitkraken, handy, orca; snap — bw, postman; flatpak — obs; unverifiable
  script without an exception — chezmoi, openusage, oh-my-zsh, homebrew.
  Source: `grep` over `setup/*.sh` at the base tip. Verification: confirm each
  against the script before filing.
