# ubuntu-config

## Description

This is my environment setup: one clone and a couple of commands rebuild my Ubuntu
workstation. `setup/` holds versioned, rerun-safe bash scripts for the applications
I use; `dotfiles/` holds declarative chezmoi source state for my shell, Git, editor
and coding-agent configuration. Changes are reviewable and reversible before they
reach a machine.

The four principles behind that design — versioned source of truth, declarative
configuration, rerun-safe setup and reproducibility from a fresh clone — are
explained in [Infrastructure as code](docs/infrastructure-as-code.md).

## Installation

Designed for Ubuntu 26.04 LTS. The first run asks for your Git name and email once.
Restart the shell after `install.sh` so the new login shell and group memberships
take effect.

```sh
git clone https://github.com/MatiasOlivera/ubuntu-config ubuntu-config
cd ubuntu-config
./setup/install.sh
./setup/post-install.sh
```

Some setup steps are manual — one-time MCP sign-in and apps the scripts cannot
install; see [manual steps](setup/manual-steps.md).

## Usage

Re-run `./setup/install.sh` after pulling changes; it skips work already done.
`./reports/versions.sh` reports the versions of everything the scripts manage.

## Support

- Bugs and questions: [open an issue](https://github.com/MatiasOlivera/ubuntu-config/issues).
- [Dotfiles](docs/dotfiles.md) — secrets and chezmoi apply.
- [Agent credentials runbook](docs/runbooks/agent-credentials-runbook.md) — vault → keyring bridge and troubleshooting.

## License

MIT — see [LICENSE](LICENSE).
