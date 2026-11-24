# Grafana query cookbook

Start the local stack first (`docker compose -f tests/observability/compose.yml up -d`). These links open Explore with a query and a 24-hour range already filled in; log in with `admin`/`admin` if prompted. The `{exporter="OTLP"}` selector matches records replayed by the collector, and `| json` exposes their fields as `attributes_*` labels.

## Ready-made queries

| Question | Datasource | Query | Explore |
|---|---|---|---|
| Which steps ran, and how long did they take? | Loki | `{exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl"` | [step spans](http://localhost:3000/explore?schemaVersion=1&panes=%7B%22map%22%3A%7B%22datasource%22%3A%22loki%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22loki%22%2C%22uid%22%3A%22loki%22%7D%2C%22expr%22%3A%22%7Bexporter%3D%5C%22OTLP%5C%22%7D%20%7C%20json%20%7C%20attributes_log_file_name%3D%5C%22spans.jsonl%5C%22%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-24h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1) |
| Which steps failed? | Loki | `{exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| attributes_status="error"` | [failed steps](http://localhost:3000/explore?schemaVersion=1&panes=%7B%22map%22%3A%7B%22datasource%22%3A%22loki%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22loki%22%2C%22uid%22%3A%22loki%22%7D%2C%22expr%22%3A%22%7Bexporter%3D%5C%22OTLP%5C%22%7D%20%7C%20json%20%7C%20attributes_log_file_name%3D%5C%22spans.jsonl%5C%22%20%7C%20attributes_status%3D%5C%22error%5C%22%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-24h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1) |
| What were the slowest steps? | Loki | `topk(5, avg by (attributes_name) (avg_over_time({exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| unwrap attributes_duration_ms [5m])))` | [slowest steps](http://localhost:3000/explore?schemaVersion=1&panes=%7B%22map%22%3A%7B%22datasource%22%3A%22loki%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22loki%22%2C%22uid%22%3A%22loki%22%7D%2C%22expr%22%3A%22topk(5%2C%20avg%20by%20(attributes_name)%20(avg_over_time(%7Bexporter%3D%5C%22OTLP%5C%22%7D%20%7C%20json%20%7C%20attributes_log_file_name%3D%5C%22spans.jsonl%5C%22%20%7C%20unwrap%20attributes_duration_ms%20%5B5m%5D)))%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-24h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1) |
| Which traces were recorded? | Tempo | `{ resource.service.name = "ubuntu-config-e2e" }` | [traces](http://localhost:3000/explore?schemaVersion=1&panes=%7B%22map%22%3A%7B%22datasource%22%3A%22tempo%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22tempo%22%2C%22uid%22%3A%22tempo%22%7D%2C%22queryType%22%3A%22traceql%22%2C%22query%22%3A%22%7B%20resource.service.name%20%3D%20%5C%22ubuntu-config-e2e%5C%22%20%7D%22%2C%22limit%22%3A20%2C%22tableType%22%3A%22traces%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-24h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1) |
| What is the p95 step latency? | Prometheus | `histogram_quantile(0.95, sum by (le, app) (rate(traces_spanmetrics_latency_bucket[5m])))` | [p95 latency](http://localhost:3000/explore?schemaVersion=1&panes=%7B%22map%22%3A%7B%22datasource%22%3A%22prometheus%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22datasource%22%3A%7B%22type%22%3A%22prometheus%22%2C%22uid%22%3A%22prometheus%22%7D%2C%22expr%22%3A%22histogram_quantile(0.95%2C%20sum%20by%20(le%2C%20app)%20(rate(traces_spanmetrics_latency_bucket%5B5m%5D)))%22%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-24h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1) |
| What is each run's total install time? | Loki | `sum by (attributes_run_id) (sum_over_time({exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| attributes_kind="phase" \| attributes_phase="install" \| unwrap attributes_duration_ms [5m]))` | [E2E runs](http://localhost:3000/d/e2e-runs/e2e-runs) |
| Where does the time go — downloads or package managers? | Loki | `sum by (attributes_kind) (sum_over_time({exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| attributes_kind=~"download\|package-manager" \| unwrap attributes_duration_ms [5m]))` | [E2E runs](http://localhost:3000/d/e2e-runs/e2e-runs) |
| Which package manager is slowest? | Loki | `sum by (attributes_name) (sum_over_time({exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| attributes_kind="package-manager" \| unwrap attributes_duration_ms [5m]))` | [E2E runs](http://localhost:3000/d/e2e-runs/e2e-runs) |
| Which download host is slowest? | Loki | `sum by (attributes_url_host) (sum_over_time({exporter="OTLP"} \| json \| attributes_log_file_name="spans.jsonl" \| attributes_kind="download" \| unwrap attributes_duration_ms [5m]))` | [E2E runs](http://localhost:3000/d/e2e-runs/e2e-runs) |

The four new queries are the all-runs form. The matching dashboard panels are
scoped by the **Run** variable. The per-run total is a sortable table; the
slowest-steps and download-host panels are bar gauges limited to the top
fifteen in descending order. Their sort comes from a reduce → sort by value →
rows-to-fields transform chain, which keeps the gauge styling and labels while
ordering the bars. Download spans carry `url_host` as a top-level field, which
is why the host query can group by it. Always filter on `attributes_kind`:
phase spans cover whole phases and step spans include their child calls, so
summing all kinds together double-counts time.

The [E2E runs dashboard](http://localhost:3000/d/e2e-runs/e2e-runs) links into these queries from its app and run panels: click a series in a legend or tooltip to open Explore with that label pre-filled.

## Trace to logs

Verified with trace `2609402a6ef92f4c47d84af73bd44674` from an end-to-end run:

1. Open the [traces link](#ready-made-queries) and paste a trace ID into the TraceQL query box, or click a trace in the table.
2. Select a span such as `install_github_cli` in the trace view.
3. Click **Logs for this span**. Grafana opens a second Explore pane with a Loki query filtered by the trace ID and the span's time range.
4. Replayed records are ingested when the stack starts, not when the step ran, so widen the pane's time picker (for example to **Last 24 hours**) to see their logs.

The Loki datasource uses structured metadata: `| json` exposes `attributes_trace_id`, `attributes_span_id` and the other step fields. The reverse link (log line to trace) relies on the `span_id` derived field, which is less reliable for replayed lines because their raw bodies contain escaped quotes; navigate by trace ID instead.

Split the Explore pane with **Split** to compare two runs' traces or queries side by side.
