# constitution.md

> Binding charter for coding agents working in this repository. The SDD flow
> and every spec, plan, and task inherit it. When `AGENTS.md`, skills, or any
> other file conflicts with this constitution, this constitution wins and the
> conflicting file is corrected; when they merely disagree on specifics, the
> more concrete operational rule applies as long as it honors the axioms below.

## Identity — what this project is

`ubuntu-config` is one person's development environment expressed as code:
bash scripts that turn a fresh Ubuntu machine into that person's working
workstation (`setup/`), and chezmoi dotfiles that declaratively own its
configuration (`dotfiles/`). The beneficiary is the machines the author owns;
general portability to other people's environments is a non-goal. The
repository is public, so it must never contain secrets.

## Goals

- Reproducibility: one clone and one command rebuild the environment.
- Safety: every step is rerun-safe; running the setup never damages an
  already-configured machine.
- Trust: the setup executes only what it can hold accountable; it degrades to
  loud failure, never to silent partial action.
- Verifiability: changes are provable hermetically — without touching the host
  or the network — before they are trusted.

## Axioms

1. **Reproduce, don't mutate.** Declarative state and imperative action each
   have exactly one owner; no environment fact is configured twice by
   different layers.
2. **Least surprise.** Reruns converge; failures stop loudly and leave the
   machine inspectable.
3. **No unverifiable execution.** The setup path never runs code it cannot
   hold to a publisher's integrity material.
4. **Decisions are durable artifacts.** Non-trivial trade-offs become decision
   records; issue work becomes a spec before it becomes code.
