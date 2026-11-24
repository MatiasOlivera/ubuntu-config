---
name: Release
about: Track a release from develop to main
title: "Release vX.Y.Z"
labels: release
---

<!-- Title: Release vX.Y.Z. Automation: #121. -->

## Version

<!-- Version and tag (e.g., v1.2.0). -->

## Range

<!-- Commits included in this release (e.g., "develop commits since v1.1.0"). -->

## Release notes

<!-- Generated notes use .github/release.yml at the release target (main), not
     a committed changelog; a config change still on develop has no effect.
     Review the grouped sections before merging. -->

- Added: …
- Changed: …
- Fixed: …
- Removed: …

## Verification

Pre-merge checks:

- [ ] All checks green on develop
- [ ] Pull requests in range carry the labels their sections need (ADR 0004)
- [ ] Promotion PR is labelled `release` so it stays out of its own notes

## Post-release

After merge to main:

- [ ] Version tag created and pushed on the merge commit
- [ ] GitHub release published with generated notes from `main`
- [ ] Fixed issues closed
