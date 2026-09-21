---
name: reports
description: Use when working with the report scripts reports/versions.sh and reports/gaps.sh — reading version tables, adding a <stem>_version()/src/chk row, refreshing the apt manifest baseline after an Ubuntu bump, or adding a new report script.
---

# Reports

`reports/versions.sh` and `reports/gaps.sh` are report-only: always exit 0, install nothing. Never gate installs on them, never let them fail a run.

## versions.sh

Sources every library script and calls its `<stem>_version()` (the single source of truth also used by install guards). A missing `src <path>` or `chk "<label>" <pkg>_version` row shows up as a MISSING row in the table. When adding a package, add both rows — see the `install-package` skill for the full workflow.

Excludes manually installed apps (see `setup/manual-installation.md`).

## gaps.sh

Flags host apps (apt/snap/flatpak/AppImage) not tracked by the repo. The apt baseline comes from the vendored names-only manifest `reports/baselines/ubuntu-<release>-desktop-manifest.txt` — no network at audit time. Expect ~10 residual lines on a real host (hardware/locale drift); near-empty on a fresh VM.

## Baseline refresh (after a Ubuntu version bump)

Refetch from the exact point-release desktop manifest and update the filename referenced in `gaps.sh`:

```sh
curl -sL https://releases.ubuntu.com/<release>/ubuntu-<release>-desktop-amd64.manifest \
  | awk '{print $1}' | sort -u > reports/baselines/ubuntu-<release>-desktop-manifest.txt
```

Full bump procedure (plus `UBUNTU_IMAGE` in `tests/test.sh`, compose/Dockerfile images) lives in `README.md` under `Updating to a new Ubuntu version`.

## New report scripts

New top-level report scripts belong in `reports/` (`versions.sh`, `gaps.sh`); `tests/` holds `test.sh` and e2e assets only.