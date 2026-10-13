---
name: Install application
about: Add or update a tool installed by setup/ scripts
title: ''
labels: installation
---

<!-- Title: free text, imperative, no prefix. -->

## Application

<!-- Name and upstream project URL. -->

## Install method

<!-- apt, apt repository (.sources + key), tarball/script, flatpak, other.
  Heavy or network-bound installs need a <stem>_version() guard — say which. -->

## Phase & location

<!-- essentials / desktop-apps / development / security → setup/<dir>/; tools needing zsh/curl from install.sh → setup/post-install.sh.
  Flat script or a directory grouping related scripts? -->

## Dependencies

<!-- apt packages beyond what other scripts manage (→ <pkg>_dependencies()). -->

## Wiring

- [ ] `setup/install.sh` — `source` next to its neighbors + `step install_<pkg>` / `step config_<pkg>` in the right phase
- [ ] `reports/versions.sh` — `src <path>` line **and** `chk "<label>" <pkg>_version` row
- [ ] `README.md` structure tree (only when a new category/script needs listing)

## Verification

<!-- ./tests/test.sh (static). Install-path changes: seed ./tests/test.sh --vm --keep, iterate ./tests/test.sh --vm --reuse. -->

## Out of scope

<!-- What this deliberately does not touch. -->
