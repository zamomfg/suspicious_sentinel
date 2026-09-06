#!/usr/bin/env python3
"""Test Microsoft Defender XDR custom detection rules via the advanced hunting API.

For every `detection_rule` module instance declared in the Terraform under
``IaC/`` this script runs a suite of read-only checks against the rule's KQL
query — using the Microsoft Graph advanced ("threat") hunting endpoint
(``POST /beta/security/runHuntingQuery``) — and renders a Markdown report meant
to be posted as a pull-request comment.

Each check is a pluggable `DetectionTest` (see the `detection_tests` package):
it runs a query, exposes its raw result, and renders a Markdown fragment. The
shipped tests cover hit counts over several intervals, the top entities behind
the hits, and a trend line chart. Add one by dropping a module in
`detection_tests/` and listing it in `detection_tests.TESTS`.

Environment:
  GRAPH_TOKEN   Bearer token for https://graph.microsoft.com (required).
  IAC_DIR       Directory to scan for *.tf rule definitions (default: IaC).

Usage:
  python test_detection_rules.py --output report.md
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
from datetime import datetime, timezone

import hcl2

from detection_tests import TESTS, HuntingClient

# Lookback window per schedule frequency, for display.
# https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules#lookback
LOOKBACK_LABEL = {
    "24H": "30 days",   # runs every 24h, looks back 30 days
    "12H": "48 hours",  # runs every 12h, looks back 48 hours
    "3H": "12 hours",   # runs every  3h, looks back 12 hours
    "1H": "4 hours",    # runs every  1h, looks back  4 hours
    "0": None,          # Continuous (NRT) — no lookback window
}

# Human-readable schedule labels for the report.
SCHEDULE_LABEL = {
    "24H": "Every 24 hours",
    "12H": "Every 12 hours",
    "3H": "Every 3 hours",
    "1H": "Every hour",
    "0": "Continuous (NRT)",
}

# Normalize a schedule value to the canonical token used by the label maps above.
# Accepts the current module's ISO 8601 `schedule_frequency` (PT24H, ..., PT0S)
# as well as the deprecated `schedule_period` (24H, ..., 0).
FREQUENCY_ALIASES = {
    "PT24H": "24H", "P1D": "24H", "24H": "24H",
    "PT12H": "12H", "12H": "12H",
    "PT3H": "3H", "3H": "3H",
    "PT1H": "1H", "1H": "1H",
    "PT0S": "0", "0": "0",
}

COMMENT_MARKER = "<!-- defender-detection-test -->"


def discover_rules(iac_dir):
    """Return a list of detection-rule module instances found under *iac_dir*.

    Each entry is a dict with keys: file, name, display_name, query_text,
    schedule_frequency. Only root-level *.tf files are scanned; the module's own
    implementation under modules/ is skipped.
    """
    rules = []
    pattern = os.path.join(iac_dir, "*.tf")
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = hcl2.load(fh)
        except Exception as exc:  # noqa: BLE001 - surface parse errors, keep going
            print(f"warning: could not parse {path}: {exc}", file=sys.stderr)
            continue

        for module_block in data.get("module", []):
            for name, body in module_block.items():
                source = str(body.get("source", ""))
                if "modules/detection_rule" not in source:
                    continue
                query = body.get("query_text")
                if not query:
                    print(f"warning: module {name} has no query_text; skipping",
                          file=sys.stderr)
                    continue
                rules.append({
                    "file": os.path.basename(path),
                    "name": name,
                    "display_name": body.get("display_name", name),
                    "query_text": str(query),
                    "schedule_frequency": str(
                        body.get("schedule_frequency")
                        or body.get("schedule_period")
                        or "PT24H"
                    ),
                })
    return rules


def rule_header(rule):
    """Render the fixed header for a rule: metadata bullets + collapsed KQL."""
    frequency = rule["schedule_frequency"]
    token = FREQUENCY_ALIASES.get(frequency, frequency)
    schedule_label = SCHEDULE_LABEL.get(token, f"`{frequency}`")
    lookback = LOOKBACK_LABEL.get(token)
    return "\n".join([
        f"### `{rule['name']}` — {rule['display_name']}",
        "",
        f"- **Source:** `IaC/{rule['file']}`",
        f"- **Schedule:** {schedule_label} (`frequency = \"{frequency}\"`)",
        f"- **Lookback window:** {lookback or 'n/a (Continuous / NRT)'}",
        "",
        "<details>",
        "<summary><b>KQL query</b></summary>",
        "",
        "```kql",
        rule["query_text"].rstrip(),
        "```",
        "",
        "</details>",
    ])


def build_rule_section(rule, client):
    """Run every test for *rule* and assemble its Markdown section.

    Each test's raw output is published into `context` under its `name` so a
    later test can read it (e.g. the trend test reads the 30-day total).
    """
    parts = [rule_header(rule)]
    context = {}
    for test_cls in TESTS:
        test = test_cls(rule, client)
        test.run(context)
        context[test.name] = test.data
        fragment = test.markdown()
        if fragment:
            parts.append(fragment)
    return "\n\n".join(parts) + "\n"


def build_report(rules, token):
    queried_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    header = [
        COMMENT_MARKER,
        "## 🛡️ Defender XDR detection rule test",
        "",
        "Each rule's KQL was run against the Microsoft Graph advanced "
        "hunting API (`POST /beta/security/runHuntingQuery`).",
        "",
        f"_Queried at {queried_at}._",
        "",
    ]
    if not rules:
        header.append("_No `detection_rule` modules found to test._")
        return "\n".join(header) + "\n"

    client = HuntingClient(token)
    sections = [build_rule_section(rule, client) for rule in rules]
    return "\n".join(header + sections) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iac-dir", default=os.environ.get("IAC_DIR", "IaC"))
    parser.add_argument("--output", default="-",
                        help="File to write the Markdown report to (default: stdout).")
    args = parser.parse_args()

    token = os.environ.get("GRAPH_TOKEN")
    if not token:
        print("error: GRAPH_TOKEN is not set", file=sys.stderr)
        return 1

    rules = discover_rules(args.iac_dir)
    print(f"Discovered {len(rules)} detection rule(s) in {args.iac_dir}",
          file=sys.stderr)

    report = build_report(rules, token)

    if args.output == "-":
        sys.stdout.write(report)
    else:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(report)
        print(f"Wrote report to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
