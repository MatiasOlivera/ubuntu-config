# plan.md - `077-e2e-observability`

## Architecture

```text
host
  tests/test.sh --vm
    ├─ derive run id, host address, E2E_OBSERVABILITY_DIR (XDG fallback)
    ├─ tests/e2e-observability.sh <phase> multipass exec ... setup/install.sh
    │    ├─ tee transcript to host record dir (status preserved)
    │    ├─ VM writes spans.jsonl, logs/<span_id>.log, run.json, summary.tsv
    │    └─ copy VM record dir out after each phase and on failure trap
    └─ optional: report collector unreachable once, continue
  tests/observability/compose.yml (manual start, per AGENTS.md)
    OTel Collector ─┬─ OTLP/HTTP ← live spans from VM (best effort)
                    └─ filelog ← durable JSONL after the run
                         ├─ Tempo   (traces)
                         ├─ Loki    (logs correlated by span id)
                         ├─ Prometheus (duration/outcome/bytes metrics)
                         └─ Grafana (waterfall, logs, dashboards)

VM (only while e2e observability is enabled)
  setup/helpers/observability.sh  span/log/byte emitters + no-op defaults
  setup/helpers/steps.sh          guarded hooks around existing step timing
  PATH shims: curl, wget, git, sudo
    ├─ curl/wget/git → download child spans + /proc/net/dev delta
    └─ sudo apt|apt-get|snap|flatpak → package-manager child spans
  app-paths.tsv → du per declared path; dpkg-query diff per step
```

Instrumentation lives only in `setup/helpers/` (exempt from the sourced and
source-only contract checks) and in new `tests/observability/` assets; no new
setup library outside `helpers/` is added. When observability is not
initialized, every hook is a no-op and `step()`/`advisory_step()` take their
exact current code path, so normal setup runs and the existing spec 030/082
tests are unaffected.

Shims are generated in a VM temp dir and prepended to `PATH`; the real binary
paths are captured before that change so shims call them by absolute path and
cannot recurse. The sudo keepalive calls (`sudo -n true`) are excluded from
span emission.

Rejected: changing each installer to emit its own spans (wide diff, duplicated
logic); a PATH shim for `apt` itself (sudo's `secure_path` bypasses it); running
the collector inside the VM (Docker is not installed until late in the run).

## Data models

- `spans.jsonl` — one object per span: `trace_id`, `span_id`,
  `parent_span_id`, `name` (step label), `kind` (`step` / `download` /
  `package-manager`), `phase` (`install` / `post-install`), `start_ns`,
  `end_ns`, `duration_ms`, `status`, `exit_code`, `log_ref`, and attributes
  `run_id`, `git_sha`, `git_branch`, `vm_name`, `ubuntu_image`, `url_host`,
  `bytes_net_approx`, `bytes_disk_approx`, `disk_basis`. Appending is
  sequential; no migration path (new artifact).
- `logs/<span_id>.log` — raw step output; the filename carries the span id used
  as the Loki correlation label. No new structured log format.
- `run.json` — run id, UTC timestamp, git commit/branch, VM name, Ubuntu image.
  No host metadata.
- `summary.tsv` — one row per step: label, phase, status, duration, network
  bytes, approximate disk bytes, log reference. This is the human-readable
  durable artifact and the input for run-to-run comparison.
- `app-paths.tsv` — static label → declared install paths map for `du`; shipped
  in the repo, read-only in the VM, covered by a drift test.

## Interface contracts

- `observability_init <run_id> <collector_endpoint>` — idempotent; creates VM record
  dirs, records real binary paths, installs shims. Emits nothing to stdout.
- `observability_step_begin <label>` / `observability_step_end <status>` — no-op when uninitialized;
  otherwise open/close a step span and emit its log reference.
- `observability_span <kind> <name> <start_ns> <end_ns> <attrs...>` — appends one span to
  `spans.jsonl` and posts the same OTLP/HTTP JSON to the collector with a short
  timeout; forwarding failure prints one warning and is never fatal.
- `tests/e2e-observability.sh <phase> <cmd...>` — replacement for the deleted
  whole-run log helper: prints `log:` and `exit:`, tees the command live, copies
  VM records out after completion, and shows a short tail only after the
  command has finished (never a pipe into `head`/`tail`). Returns the wrapped
  command's status. No new option flags on `tests/test.sh`.
- `tests/test.sh` passes `E2E_OBSERVABILITY_DIR`, `OBSERVABILITY_COLLECTOR`, `run_id`,
  git metadata, VM name and image into both `multipass exec` calls; default
  host path is `${E2E_OBSERVABILITY_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability}/<run-id>/`.
- Compose stack exposes OTLP/HTTP to the VM and reads the durable directory
  read-only; starting it is a documented manual step in `AGENTS.md`, `README.md`
  and the run-tests skill. `./tests/test.sh` has no Docker dependency.
- Acceptance mapping: durable records → "completed e2e run leaves durable
  per-app records"; shim spans → "download and install are distinguishable" and
  "package-manager time is visible"; manifest → "disk footprint is recorded per
  app"; log refs + Loki labels → "a failed app's logs are reachable"; best-effort
  forward → "live delivery is best effort"; compose → "stack exposes traces logs
  and metrics"; helper removal → "one logging workflow"; hermetic tests →
  "static checks stay green".

## Decisions

- `docs/decisions/0009-e2e-run-observability.md` — accepted; records the choice
  of a file-first local observability stack, best-effort live delivery,
  approximate disk accounting, and the rejected alternatives.

## Evidence

- e2e runs two opaque install commands and only prints per-phase times:
  `tests/test.sh:57-65`, `tests/test.sh:200-214`, total at `tests/test.sh:224`.
- Per-step timing and failure output already exists and must be preserved:
  `setup/helpers/steps.sh:8-23`, `setup/helpers/steps.sh:26-33`; format declared
  stable in `specs/030-surface-failed-install-steps/plan.md:64-66` and
  `specs/082-chezmoi-apply-prompts-on-rerun/plan.md:49`.
- Existing whole-run log helper and its sole agent-facing references:
  `tests/run-with-logging.sh:19-27`, `tests/run-with-logging-test.sh`,
  `.agents/skills/run-tests/SKILL.md:8-18`. Historical spec references in
  `specs/080-*` are left untouched as records of past work.
- Static check coverage: `tests/test.sh:82-141` builds `ALL_SCRIPTS` from
  `setup/**/*.sh`; helpers are exempt from the sourced/source-only checks but
  included in `bash -n` and shellcheck. Functional checks auto-run every
  `tests/**/*-test.sh` at `tests/test.sh:143-151`.
- XDG variables are already used in this repo:
  `setup/desktop-apps/anythingllm.sh:8`, `dotfiles/dot_zshrc:4`.
- No shared download helper exists; download patterns are per-installer
  (`curl | sh`, `.deb` + apt, verified artifacts, keys, fonts, git clone) and
  apt/snap/flatpak bundle download and install internally (exploration of
  `setup/`). Shims at the common command boundary avoid editing ~30 installers.
- Disk snapshot spike: `dpkg-query` ~19.6 ms, `du` over real roots ~7.2 s;
  manifest `du` ~3.5-14.4 ms in a controlled sandbox. Source: read-only spike
  run during specification; reproducible from the recorded commands.
- Host tooling present: Docker Compose v5.8.0, Multipass, GNU `time`,
  `systemd-run`, `strace` (`command -v`); only Compose and Multipass are used.

## Verification

- `bash tests/observability/*-test.sh` — hermetic span, shim, manifest and
  wrapper tests with stubbed commands and fixture records.
- `./tests/test.sh` — phases 1-5 stay green; removed helper's test is gone.
- `docker compose -f tests/compose.yml run --rm test` — isolated static check.
- `docker compose -f tests/observability/compose.yml config` — stack config
  parses; manual fixture ingest then inspect Grafana traces/logs/metrics.
- `./tests/test.sh --vm --reuse` — e2e; verify per-app summary, copy-out even
  with a failed step, and live spans when the stack is up. Use `--keep` to
  inspect a failing VM.

## Sequencing

1. Red hermetic tests for step spans and no-op behavior; green helper plus
   guarded hooks in `steps.sh`.
2. Red tests for shims, byte counters and path manifest; green shims and
   manifest wiring.
3. Host-side e2e wrapper tests; green wrapper and `tests/test.sh` wiring,
   including copy-out on failure.
4. Compose stack, collector config and Grafana provisioning; manual ingest
   check with fixture records.
5. ADR, docs and skill updates; delete the old whole-run log helper and test.
6. Full verification chain and e2e review against acceptance scenarios.

## Risks

- Piping step output to `tee` changes stdout from a TTY to a pipe; apt progress
  and colors may differ, but prompts read stdin and the e2e run is
  non-interactive. Detect with the full e2e; if a step regresses, fall back to
  transcript-only logs for that step.
- Shims may intercept unintended `curl`/`sudo` calls (e.g. keepalive). Filter
  by arguments and assert in hermetic tests that only install commands produce
  child spans.
- Live forwarding can block a step if the collector is unreachable; use a
  short curl timeout and a one-time warning, and assert in a test that an
  unreachable endpoint does not change the wrapped status.
- Copy-out failure must not mask the e2e result; report it as a warning and
  leave `--keep` available for VM inspection.
- Manifest drift silently loses disk bytes; the drift test fails when a label
  or path no longer exists.
- The collector's filelog receiver may re-read records on restart; accept
  duplicate spans after an explicit restart rather than adding stateful
  de-duplication.
- Records can be large across many runs; retention is manual by design, and
  the directory is gitignored outside the repo by default.
