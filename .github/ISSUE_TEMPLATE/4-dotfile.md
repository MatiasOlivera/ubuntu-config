---
name: Dotfile change
about: Add or change a chezmoi-managed config under dotfiles/
title: ''
labels: dotfiles
---

<!-- Title: free text, imperative, no prefix. -->

## Application

<!-- Name and upstream project URL. -->

## Dotfile

<!-- Source path (dot_* / dot_config/<app>/…) → destination ($HOME/…). -->

## Rendered values

<!-- Needs .tmpl? Which values vary (name/email from chezmoi.toml [data])? Static otherwise. -->

## Declarative vs imperative

<!-- File content → dotfiles/. Actions (chsh, gsettings, clones, git config writes) → setup/ bash. -->

## Secrets

<!-- Matches a deny pattern? A new secret-equivalent pattern goes in BOTH .gitignore and dotfiles/.chezmoiignore. Public repo — never commit secrets. -->

## Verification

- [ ] `chezmoi apply --source dotfiles/` applies cleanly
- [ ] `./tests/test.sh` passes
- [ ] `reports/versions.sh` row renders (if the dotfile feeds a script's config)

## Out of scope

<!-- What this deliberately does not touch. -->
