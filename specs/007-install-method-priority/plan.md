# plan.md - `007-install-method-priority`

## Architecture

Documentation and tracker work only. No file under `setup/`, `dotfiles/` or
`tests/` changes, and no new test harness is introduced. The base tip is
`bdfaaf8687c6015daae599ccdd6e5feb5b847a3a`; re-check it before the first edit.

Components, in dependency order:

1. `docs/decisions/0008-install-method-priority.md` — the decision record,
   created through `mo-recording-adrs` before the plan was written. It holds the
   ladder and tie-breakers; ADR 0003 and 0007 remain the integrity authority.
2. `.agents/skills/install-package/SKILL.md` — gains one "Install method
   priority" section listing the rungs in order, stating that integrity checks
   (0003/0007) apply to every artifact rung, that unverifiable installers go to
   `docs/integrity-exceptions.md`, and that a new-app PR names its rung in
   Verification. Placed beside the existing phase/contract sections so a
   contributor reads it before writing a script.
3. `AGENTS.md` — one pointer from the Skills list / "For changes" area to the
   priority section, without duplicating the rungs.
4. `README.md` — one pointer in "Adding a new app" to the same section, again
   without duplicating the rungs.
5. `.github/pull_request_template.md` — one Verification checkbox asking the
   author to name the rung (N/A when no application was added). This is the
   mechanism for the spec's "new application states its rung" scenario.
6. `specs/007-install-method-priority/{spec,plan,tasks}.md` — the SDD artifacts
   for this issue.
7. GitHub issues — 13 follow-ups, one per confirmed deviation, created through
   the GitHub MCP after the audit is re-checked against the base tip. Each has
   the `installation` label, a title naming the application, and a body that
   states only its current install method. ollama and cursor-cli are excluded:
   they already have entries in the integrity-exception register.

Confirmed deviation list (from a `grep` over `setup/` at the base tip;
re-check each before filing): chrome, discord, obsidian, gitkraken, handy, orca
(raw `.deb`); bw, postman (snap); obs (flatpak); chezmoi, openusage, oh-my-zsh,
homebrew (unverifiable script, no exception entry). No script is edited to carry
a justification comment.

Verification is docs-only: `./tests/test.sh` on this trusted checkout, plus a
read-back of every link and issue. No Docker or Multipass run is needed because
install behavior does not change.

## Data models

None. The spec, plan, tasks, decision record and tracker issues are plain
documents; no persisted format or migration is introduced.

## API contracts

Only the tracker contract for a follow-up issue:

- Title: `<application>: install method below priority`.
- Body: one line, `Current install method: <method>`, with no recommendation,
  higher-rung suggestion or migration analysis.
- Label: `installation`.

Each of the 13 issues maps to one "Each deviation becomes its own terse
follow-up" scenario in `spec.md`. No code interface changes.

## Decisions

- `docs/decisions/0008-install-method-priority.md` — created inline with
  `mo-recording-adrs`, next free number because 0003 and 0004 are taken. It
  records the distribution-first ladder, the verified-artifact rung, the
  exception path and the tie-breakers; it rejects the original `curl | sh`
  rung, a verified-artifact-first order, and case-by-case choice. Status stays
  `proposed` until the change is merged.
- Keeping the issue's Ubuntu-first order follows the human decision after the
  online check: no universal ranking was found in the sources consulted (web
  search was unavailable), Debian guidance favours repositories over downloaded
  `.deb` files, and Flatpak documents itself as desktop-oriented.
- The follow-up issues are intentionally terse and the existing scripts are
  untouched, following the human decision to draft issues abstractly and keep
  this change documentation-only.
- The PR-template checkbox is the chosen mechanism for the acceptance criterion
  about the first new application stating its rung; uv already landed under the
  verified-artifact rung and is not changed.

## Risks

- Filing 13 public issues is externally visible and cannot be undone quietly.
  The scope was approved explicitly; if a call fails midway, re-check the
  existing set before retrying so no duplicate is created.
- The decision number could drift if another record lands first. Re-list
  `docs/decisions/` immediately before creating the record.
- Three prose pointers (skill, AGENTS.md, README) can drift apart. Only the
  skill carries the rungs; the other two are one-line links.
- If any `setup/` file is touched by accident, the docs-only verification is no
  longer sufficient; run the full static, Docker and VM chain instead.
- Verified-artifact installs need publisher integrity material. If a publisher
  stops providing it, the step fails closed by the existing contract; that is
  unchanged by this policy.

## Assumptions

- Base tip is `bdfaaf8687c6015daae599ccdd6e5feb5b847a3a`. Source:
  `git rev-parse HEAD`. Verification: re-check before editing.
- ADR 0003 and 0007 already carry the integrity rules. Source: their files in
  `docs/decisions/`. Verification: the new record only refers to them.
- The 13 deviations are current at the base tip. Source: `grep` over `setup/`
  plus `docs/integrity-exceptions.md`. Verification: re-read each script before
  filing its issue.
- `tests/test.sh` discovers plain documentation changes safely on a trusted
  checkout. Source: `AGENTS.md` verification order and the script's contract
  checks. Verification: run it once after the edits.
