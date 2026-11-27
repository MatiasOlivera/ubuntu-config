# ubuntu-config

> Opinionated infrastructure-as-code setup for a fresh Ubuntu workstation: versioned
> bash scripts install apt, Flatpak and Snap apps plus dev tools; chezmoi dotfiles
> declaratively own the configuration.

## Description

`ubuntu-config` turns one clone and a couple of commands into a working Ubuntu
workstation. `setup/` holds versioned, rerun-safe bash scripts for packages and
tools; `dotfiles/` holds declarative chezmoi source state for the shell, Git,
editor and coding-agent configuration. Changes are reviewable and reversible
before they reach a machine, and a fresh clone rebuilds the same environment.

The four principles behind that design — versioned source of truth, declarative
configuration, rerun-safe setup and reproducibility from a fresh clone — are
explained in [Infrastructure as code](docs/infrastructure-as-code.md).

## Installation

The target is Ubuntu 26.04 LTS.

```sh
git clone https://github.com/MatiasOlivera/ubuntu-config ubuntu-config
cd ubuntu-config
./setup/install.sh
# restart here so the new login shell and group memberships take effect
./setup/post-install.sh
```

Some setup steps are manual — one-time MCP sign-in and apps the scripts cannot
install; see [manual steps](setup/manual-steps.md).

## Usage

Run a package script directly to install or check one app without re-running setup:

```sh
bash setup/development/github-cli.sh install
bash setup/development/github-cli.sh version
```

`./reports/versions.sh` reports the versions of everything the scripts manage.

## Support

- Bugs and questions: [open an issue](https://github.com/MatiasOlivera/ubuntu-config/issues).
- [Dotfiles](docs/dotfiles.md) — secrets and chezmoi apply.
- [Agent credentials runbook](docs/runbooks/agent-credentials-runbook.md) — vault → keyring bridge and troubleshooting.

## License

MIT — see [LICENSE](LICENSE).
