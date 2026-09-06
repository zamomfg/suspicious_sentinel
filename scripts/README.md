# scripts

## `test_detection_rules.py`

Tests Microsoft Defender XDR custom detection rules **before** they are
deployed, by running each rule's KQL against the advanced ("threat") hunting
API instead of waiting for the scheduled rule to fire.

For every `detection_rule` module instance declared in `IaC/*.tf` it runs the
rule's `query_text` against the Microsoft Graph endpoint
[`POST /beta/security/runHuntingQuery`](https://learn.microsoft.com/en-us/graph/api/security-security-runhuntingquery?view=graph-rest-beta)
and produces a Markdown report, stamped with the UTC time it was queried, with
per rule:

- **Lookback window** — each rule's
  [lookback](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules#lookback)
  is fixed by its `schedule_period`:

  | `schedule_period` | Frequency        | Lookback |
  | ----------------- | ---------------- | -------- |
  | `24H`             | Every 24 hours   | 30 days  |
  | `12H`             | Every 12 hours   | 48 hours |
  | `3H`              | Every 3 hours    | 12 hours |
  | `1H`              | Every hour       | 4 hours  |
  | `0`               | Continuous (NRT) | n/a      |

- **Hits over time** — counts over the last 4 hours, 12 hours, 24 hours,
  48 hours, 7 days, 14 days, and 30 days.
- **Top entities** — a collapsed "Top entities" section with a nested dropdown
  per entity, each a horizontal Mermaid bar chart of the top 10 entities over
  the last 30 days. A table can break down by several columns (see the
  `ENTITY_COLUMNS` lookup in `detection_tests/top_entities.py`): e.g.
  `SigninLogs` → `UserPrincipalName` **and** `IPAddress`, `Device*` tables →
  `DeviceName`, `Identity*` → `AccountUpn`, `Email*` → `SenderFromAddress`.
  Tables with no mapping get no entity charts.
- **Trend** — a Mermaid line chart of an evenly-spaced `make-series` over the
  last 30 days. The bucket step is 1 day, or 7 days once the 30-day total
  exceeds 1000 hits (so a noisy rule doesn't produce 30 cramped points).

Each section above is produced by a separate **test**, and each test runs its
own hunting query (appending e.g. a `summarize` or `make-series` to the rule's
KQL), bounded to 30 days with the API's
[`Timespan` parameter](https://learn.microsoft.com/en-us/graph/api/security-security-runhuntingquery?view=graph-rest-beta#example-2-query-with-optional-the-timespan-parameter-specified).
The time column is `TimeGenerated` for Microsoft Sentinel tables and
`Timestamp` for Defender XDR tables, detected from the query's leading table.

### Structure

`test_detection_rules.py` is just the orchestrator: it discovers the rules,
renders the per-rule header, and runs the tests. The tests live in the
[`detection_tests/`](detection_tests) package:

| File | Contents |
| ---- | -------- |
| `base.py` | `DetectionTest` — the interface (`run`/`markdown`/`.data`). |
| `client.py` | `HuntingClient` and the hunting API call. |
| `common.py` | Shared helpers (table/time-column detection, label formatting). |
| `hits_over_time.py` | `HitsOverTimeTest` — the interval counts table. |
| `top_entities.py` | `TopEntitiesTest` — the top-entities bar chart. |
| `trend.py` | `TrendTest` — the trend line chart. |
| `__init__.py` | The ordered `TESTS` registry. |

Each test exposes its raw result on `.data`, and the orchestrator publishes that
into a `context` passed to later tests — so, for example, `TrendTest` reads
`HitsOverTimeTest`'s 30-day total to pick its bucket step.

### Adding a test

1. Create a module in `detection_tests/`.
2. Subclass `DetectionTest`; set a unique `name`; implement `run(self, context)`
   (call `self.client.run(<kql>)`, store the raw result on `self.data`, set
   `self.error` on failure) and `markdown(self)` (return the section, or `""`).
3. Append the class to `TESTS` in `detection_tests/__init__.py` — its position
   sets both run order and render order. Read another test's output via
   `context.get("<that test's name>")`.

### Run locally

```sh
pip install "python-hcl2==4.3.5"   # 5.x changes load() output; pin 4.x
export GRAPH_TOKEN="$(az account get-access-token \
  --resource https://graph.microsoft.com --query accessToken -o tsv)"
python scripts/test_detection_rules.py --output report.md
```

### In CI

[`.github/workflows/test-detection-rules.yaml`](../.github/workflows/test-detection-rules.yaml)
runs this on every pull request that touches `IaC/**.tf` and posts (or updates)
the report as a PR comment. It is **read-only** — it never deploys anything.

### Permissions

The identity used (the GitHub OIDC service principal from
[`init.sh`](../init.sh)) needs the **`ThreatHunting.Read.All`** Microsoft Graph
**application** permission with admin consent granted. This is separate from
the `CustomDetection.ReadWrite.All` permission the Terraform deploy uses — see
the [module README](../IaC/modules/detection_rule/README.md#prerequisites).
