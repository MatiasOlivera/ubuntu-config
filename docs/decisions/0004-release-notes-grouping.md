# Release notes grouping

- Status: proposed
- Deciders: Matias Olivera
- Date: 2026-11-04

## Context and Problem Statement

Generated release notes are this repository's changelog. `v0.2.0` rendered as one flat list of merged pull requests, which answers neither "what does this release install?" nor "what changes on my machine?". Every pull request carries two label families — the change type inherited from its Conventional Commit title and the area inherited from the paths it touches — so any grouping rule must decide which family names the section. The labels exist; nothing makes them mean something to a reader.

## Decision Drivers

- Notes grouping is configured by an ordered list of label-driven sections: the platform supports no hierarchy.
- A pull request can belong to both label families, so a grouping rule either lists it twice, hides it, or routes it deterministically.
- The repository's dominant changes are installing a tool and changing managed configuration; its PR templates already split on that difference.
- Entry titles keep their commit prefix, so change type stays readable wherever an entry is placed.
- A release PR packages a release; it is not a change inside that release.
- Labels are applied by whoever opens the pull request, so a grouping rule must survive a missing label.

## Considered Options

| Option | Outcome | Cost |
| ------ | ------- | ---- |
| **Area routing leads, change type follows** | Won: the release reads as what it gives the machine, and the type survives in the title | Type-driven sections stay sparse whenever area work dominates |
| Change type leads, one area exception | Lost: the area the readers ask most about — installed tools — is the only exception, leaving configuration and credential work hidden in type sections | Balanced sections, weak area view |
| Both families as parallel sections | Lost: routing depends on which family is listed first, so area sections collect leftovers and identical changes split across views | Two axes, unpredictable placement |
| Hierarchical sections (area containing type) | Lost: unsupported, the grouping has one level | would have been the requested shape |
| Hand-written notes per release | Lost: labels stop carrying the changelog and the effort repeats every release | ongoing manual work |
| External changelog generator | Lost here: the need is label grouping, not commit-message reconstruction | a toolchain to install, pin, and keep current |

## Decision Outcome

Chosen option: **area routing leads, change type follows**, because the release should read as what a fresh machine gains, and each entry's title already carries its change type.

- Area labels route a pull request before change-type labels do; type grouping is the fallback, never the primary axis.
- Sections are disjoint: one merged pull request produces exactly one entry, whichever label families it carries.
- Packaging PRs and bot-authored changes stay out of the notes.
- Work carrying no routing label stays visible in a residual section rather than being dropped, so a labeling gap is loud instead of silent.
- The section list, its ordering, and the label mapping live only in the release-notes configuration; this record deliberately does not restate them, so the configuration stays the single authority and cannot drift from it.

### Positive Consequences

- Notes answer the install and configuration questions directly, which makes the label set load-bearing for the changelog.
- Regenerating a release's notes requires no writing and no reconciliation with a duplicated spec.
- The decision outlives the current section list because it is stated apart from its mapping.

### Negative Consequences

- Type-driven sections stay sparse in area-dominated releases; mitigation is the commit prefix carried by every entry title.
- Notes are only as correct as the labels present at merge time; mitigation is the residual section, plus the hub's convention for labeling pull requests at creation time.
- The exhaustive record remains the tag-comparison changelog, which is ungrouped.
