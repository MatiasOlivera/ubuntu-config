# Infrastructure as code

This repository keeps one person's Ubuntu workstation in versioned scripts under
`setup/` and chezmoi dotfiles under `dotfiles/`: the definition is versioned, the
configuration is declarative, setup converges on rerun, and a fresh clone
rebuilds the machine. These are the principles it implements:

- **Versioned source of truth** — the environment definition lives in git with its
  history, so changes are reviewable and reversible; e.g. adding an app is a commit
  you can review and revert before it reaches any machine.
- **Declarative configuration** — desired config is stated once and applied by
  chezmoi instead of being re-issued as imperative commands every run; e.g. shell
  configuration lives as a file whose desired state is applied, not as commands
  repeated by hand.
- **Rerun-safe, idempotent setup** — repeat runs skip work already done and leave
  an already-configured machine intact; e.g. a second run skips an app that is
  already installed.
- **Reproducible from a fresh clone** — the documented setup commands rebuild the
  workstation, and the end-to-end check repeats them on a clean machine; e.g. a
  clean machine plus those steps ends up with the same apps and configuration.

The choice to name these principles is recorded in
[ADR 0015](decisions/0015-infrastructure-as-code-principles.md).
