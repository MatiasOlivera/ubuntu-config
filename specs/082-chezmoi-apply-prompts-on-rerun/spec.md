# spec.md - `082-chezmoi-apply-prompts-on-rerun`

## Context

Issue: [#82](https://github.com/MatiasOlivera/ubuntu-config/issues/82), milestone
`v0.4.0 - reliability: honest verification`. Surfaced by the e2e audit in #30 when
reusing an already-configured VM.

This repository declares its shell configuration in `dotfiles/dot_zshrc` and applies
it to `~/.zshrc` at the end of `setup/install.sh`. `setup/post-install.sh` then
installs the zsh framework whose config that file is. The framework's own installer
treats an existing `~/.zshrc` as a file to back up and replace with its template.
After one full run the on-disk `~/.zshrc` therefore diverges from the declared
source. On the next `install.sh` the dotfile manager detects the divergence, asks
whether to overwrite it, and — when there is no terminal — fails with
`could not open a new TTY`, exiting 1 before the versions report.

Two layers configure the same environment fact, which conflicts with constitution
axiom 1 (one owner per fact). The second expected behavior in the issue — reruns
apply managed dotfiles without interactive confirmation — is broader than this one
file: any hand-edited managed dotfile would trigger the same prompt and failure.

Decisions settled with the issue owner:

- Keep the declarative config as the single owner of `~/.zshrc`; prevent the shell
  framework installer from writing it, rather than reordering the two scripts.
- Make the framework installer fully non-interactive as well, so it never prompts
  for a shell change or starts a new shell.
- Make the dotfile apply step non-interactive for all managed dotfiles, not just
  `~/.zshrc`.
- Do not move the dotfile step between scripts: both scripts keep their current
  responsibilities, and both version reports stay honest.
- Leave any `.zshrc.pre-oh-my-zsh` backups from earlier runs in place.

Rejected: reordering so the dotfiles are applied after the shell framework (larger
diff, doc/report churn, and the two layers still write the same file); letting the
framework own `~/.zshrc` and moving the curated config into its custom directory
(large dotfile refactor).

## User stories

- As a person setting up a fresh machine, I want the shell configuration I keep in
  this repository to be what ends up on disk, so my shell behaves the same on every
  rebuild.
- As a person rerunning setup, I want it to finish without any prompt, so I can run
  it unattended from a CI job or a script.
- As a person rerunning setup after tweaking a managed dotfile by hand, I want the
  repository's version reapplied automatically, so my machine converges to the
  declared state instead of failing.
- As a person who ran an older version of setup, I want my existing backups left
  alone, so I do not lose a config I may still need.

## Acceptance criteria (BDD)

```gherkin
Scenario: a fresh full run installs the curated shell configuration
  Given a machine where neither setup script has run and ~/.zshrc does not exist
  When install.sh and post-install.sh run in sequence
  Then ~/.zshrc contains the shell configuration declared in this repository
  And no pre-oh-my-zsh backup of ~/.zshrc is created
  And both scripts exit 0

Scenario: rerunning install.sh needs no terminal
  Given a machine configured by a previous full run
  When install.sh runs again with no terminal attached
  Then no step asks for confirmation
  And the dotfile step does not fail
  And the versions report and the total timing line still print
  And the script exits 0

Scenario: rerunning post-install.sh needs no terminal
  Given a machine configured by a previous full run
  When post-install.sh runs again with no terminal attached
  Then no step asks for confirmation or starts a new shell
  And the script exits 0

Scenario: an already-installed shell framework is left alone
  Given the shell framework is already installed
  When post-install.sh runs again
  Then its installer is not run again
  And any .zshrc.pre-oh-my-zsh backup left by an earlier run is still present

Scenario: a hand-edited managed dotfile is restored on rerun
  Given someone changed ~/.zshrc, or any other file managed by this repository, by hand
  When install.sh runs again with no terminal attached
  Then that file is restored to the repository's declared content
  And no confirmation is requested
  And the script exits 0
```

## Constraints

- [ ] `~/.zshrc` has one owner: the declarative dotfiles. No setup step replaces it
      with a framework template or asks to do so.
- [ ] The shell framework installer cannot prompt, change the login shell, or
      replace the current process with a new shell.
- [ ] The dotfile apply step never prompts or fails on a target it previously
      wrote, including a locally modified one.
- [ ] Both setup scripts keep their current step order, responsibilities, and
      version reports; the dotfile step is not moved between them.
- [ ] Existing `.zshrc.pre-oh-my-zsh` backups are neither deleted nor renamed.
- [ ] Tests are hermetic per `tests/AGENTS.md`: stubbed commands and per-test temp
      directories, no host changes, no network, and no real package installation.
- [ ] `tests/test.sh` contract, `bash -n`, and shellcheck stay green.

## Out of scope

- Changing the content of `dotfiles/dot_zshrc` or any other managed file.
- Reordering steps or scripts, or changing the two-script workflow.
- Adding a cleanup step for legacy `.zshrc.pre-oh-my-zsh` backups.
- Changing the install method of any tool or adding a decision record for it.
