# plan.md - `06-copilot-integrity-check`

## Architecture

One script changes: `setup/development/copilot.sh`. Everything else in the
install pipeline (`setup/install.sh` step wiring at `:79`/`:144`, the
dispatcher contract, `reports/versions.sh` `src`/`chk` rows at `:80`/`:131`)
is untouched and must keep working unchanged.

Install flow (replacing `copilot.sh:11`):

```
skip guard (copilot_version)          — unchanged
  └─ mktemp -d private workdir
      ├─ map uname -s/-m  → platform ∈ {linux,darwin}, arch ∈ {x64,arm64}
      ├─ HEAD …/releases/latest → one release tag (curl -fsSI, fail-closed)
      ├─ GET …/releases/download/<tag>/SHA256SUMS.txt          (curl -fsSL)
      ├─ GET …/releases/download/<tag>/copilot-<plat>-<arch>.tar.gz
      ├─ extract the asset's checksum line (grep -F; absent → fail)
      ├─ sha256sum -c the line in the workdir (mismatch → fail)
      ├─ tar -x into the workdir; require ./copilot at archive root
      └─ install -m 0755 only the verified copilot binary → ${PREFIX:-/usr/local}/bin
  └─ rm -rf workdir (caller-side cleanup, no traps set here)
```

Design properties:

- No remote bytes are ever parsed as shell. The only executed artifact is the
  binary that passed `sha256sum -c` against the publisher's own sums file.
- Every step is fail-closed with an `error: copilot: …` stderr line naming the
  failed stage; partial state is never installed.
- Workdir cleanup is explicit caller-side code, not an EXIT trap:
  `setup/install.sh` owns the process EXIT trap for the sudo keepalive
  (`install.sh:3-13`) and must not have it overwritten. The heavy lifting runs
  in a disposable subshell so `exit 1` aborts only the copilot step (spec:
  "failure is contained to its step").
- Only the `copilot` member of the verified archive is installed; extra
  archive members never leave the private temp dir.

## Data models

None persisted. Wire format consumed (verified live, see Assumptions):

- `SHA256SUMS.txt`: standard `sha256sum -c` lines,
  `<64-hex>␣␣<asset-name>`, one line per release asset.
- Asset naming: `copilot-<linux|linuxmusl|darwin|win3>-<x64|arm64>.(tar.gz|zip|msi|tgz)`;
  this change consumes only the four glibc/macOS tarballs.

## API contracts

Publisher contract (outbound):

- `HEAD https://github.com/github/copilot-cli/releases/latest` → the 302
  Location yields the tag once; both files below are fetched under that one
  tag, so a mid-run publish cannot mix releases.
- `https://github.com/github/copilot-cli/releases/download/<tag>/SHA256SUMS.txt`
- `https://github.com/github/copilot-cli/releases/download/<tag>/copilot-<platform>-<arch>.tar.gz`
- Requires on the host: `curl`, `sha256sum`, `tar` (explicit pre-checks; the
  test stubs `curl`). `sudo` only when the target dir is not writable (kept
  alive by `install.sh`; standalone runs authenticate normally).

Repo contract (inbound, unchanged by design):

- Defines exactly `install_copilot`, `copilot_version`, and one private helper
  that matches no dispatcher pattern (`install_*` / `config_*` / `*_version`),
  so `tests/test.sh` phases 2-4 stay green and `dispatch_command` cannot route
  to it accidentally.
- Env knob: `PREFIX` (destination bin dir = `$PREFIX/bin`), mirroring the
  upstream installer's documented knob; unset → `/usr/local`.
- stdout markers (asserted by the functional test):
  - `skip: copilot already installed (<ver>)`
  - `installed: copilot <version-output> to <path>`
- stderr markers: `error: copilot: <stage-specific message>` for unsupported
  OS, unsupported architecture, missing curl/sha256sum, unresolvable latest
  release tag, checksums download failure, asset download failure, missing
  checksum line, checksum mismatch, invalid archive, missing binary in
  archive, install-dir creation/copy failure, installed binary that fails to
  run.

Test contract: `tests/setup/development/copilot-test.sh` is hermetic — stub
`curl` serves a fixture release built with `tar` + real `sha256sum`;
`PREFIX` points into the temp dir; no network, no system writes; picked up
automatically by `tests/test.sh` phase 6 (`find tests -name '*-test.sh'`).
Conventions follow `deja-vu-test.sh` (STUB_DIR, black-box assertions on rc /
stdout markers / filesystem state). Scenario coverage maps 1:1 to spec
scenarios (tamper, missing line, interrupted download via stub exit ≠ 0,
unsupported arch, skip-without-network, success) plus PR-review additions:
parent-run containment (sourced, caller EXIT trap intact), un-runnable
installed binary, and a failing `copilot` stub that keeps host installs
from skewing the fresh-install cases.

## Sequencing

1. ADR `0003-remote-installer-integrity` (broadened: the repo-wide rule, this
   issue as first application) — records the approach chosen in the spec phase.
2. Functional test (red): all six scenarios fail against the current
   `curl | bash` script.
3. `copilot.sh` rewrite (green).
4. Verify chain per AGENTS.md (static → shellcheck → functional → VM e2e).
5. PR onto `develop`; two commits: fix+test, then docs (ADR + specs/).

## Decisions

- `docs/decisions/0003-remote-installer-integrity.md` — checksum-verified
  release artifacts instead of executing publisher install scripts.
  Rejected: TOFU hash-pin of `install.sh` (no publisher hash exists; upstream
  edits the installer weekly, pin churn = audit fatigue, and matched pins
  still execute remote-origin code); `gh attestation verify` (attestation
  publication for copilot-cli releases unconfirmed — the release's asset list
  shows no attestation/signature artifacts, see Assumptions); Homebrew/npm
  (brew PATH unavailable mid-`install.sh`; npm adds the fnm post-install step;
  casks carry no sha256 — moving parts with no integrity gain).
  Residual risk accepted: artifact and sums share one delivery path, so
  publisher-side compromise is not covered (axiom 3 bounds the goal: remove
  unverifiable execution, not achieve full supply-chain security).

## Risks

- Upstream stops publishing `SHA256SUMS.txt` or renames assets → install fails
  closed with a named error (loud, spec-conformant); repair = update contract,
  not weaken it.
- Upstream moves the binary inside the archive → explicit `./copilot` presence
  check fails closed with a named error.
- `releases/latest/download` semantics (redirects to newest non-prerelease) —
  matches today's "latest stable" behavior; no new drift introduced.
- Rollback: revert two commits; nothing persisted, no state to migrate.
- VM e2e pays the same ~115 MB asset download as today.

## Assumptions

All load-bearing facts verified against live sources on 2026-11-04; no
open assumptions remain.

- `SHA256SUMS.txt` published with the four needed assets for the current
  latest release, standard line format. Evidence: `gh release view --repo
  github/copilot-cli` (tag `v1.0.105`) asset list + downloaded sums file
  (`grep -F ' copilot-linux-x64.tar.gz'` hit).
- `gh.io/copilot-install` serves mutable-branch content. Evidence:
  `curl -sIL` resolves to
  `raw.githubusercontent.com/github/copilot-cli/refs/heads/main/install.sh`.
- Upstream verifies tarballs against `SHA256SUMS.txt` only best-effort
  (`sha256sum -c --ignore-missing`; "skipping checksum validation" when no
  sha tool exists) — this change makes the check mandatory. Evidence:
  upstream `install.sh` lines 101-116 (fetched from the redirect target).
- Tarball holds `copilot` at its archive root; `PREFIX` is the upstream
  installer's documented knob. Evidence: upstream `install.sh` lines 8-9 and
  143-145 (`tar -xz -C "$INSTALL_DIR"`, `chmod +x "$INSTALL_DIR/copilot"`).
- Release carries no signature/attestation assets (sums/zip/msi/tgz only).
  Evidence: v1.0.105 asset list.
- Upstream installer reads `GITHUB_TOKEN` from the environment — quoted in
  the ADR threat model as the exfiltration-target argument. Evidence:
  upstream `install.sh` line 46.
