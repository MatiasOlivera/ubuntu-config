---
name: Release
about: Track a release from develop to main
title: "Release vX.Y.Z"
labels: release
---

<!-- Title: Release vX.Y.Z. The version is computed from commits by
     scripts/release.sh prepare, not chosen here. Automation: #121. -->

## Version

<!-- Filled from the computed version in the promotion pull request. -->

## Range

<!-- Latest tag .. the prepared develop commit. -->

## Release notes

<!-- Generated notes use .github/release.yml at the release target (main), not
     the committed changelog; a config change still on develop has no effect.
     Review the preview and grouped sections before merging. -->

- Added: …
- Changed: …
- Fixed: …
- Removed: …

## Verification

Pre-merge checks:

- [ ] `sh scripts/release.sh preview` was reviewed from a clean `develop`
- [ ] `sh scripts/release.sh prepare` computed the version and regenerated
      `CHANGELOG.md`
- [ ] All checks green on develop
- [ ] Pull requests in range carry the labels their sections need (ADR 0004)
- [ ] Promotion PR is labelled `release` so it stays out of its own notes

## Post-release

The promotion merge triggers automatic publication; verify:

- [ ] Tag created and pushed on the merge commit
- [ ] GitHub release published with generated notes from `main`
- [ ] `main` merged back into `develop`; tag reachable from `develop`
- [ ] Fixed issues closed
