"""Interval hit counts (4h / 12h / 24h / 48h / 7d / 14d / 30d)."""

from __future__ import annotations

from .base import DetectionTest
from .client import HuntingError
from .common import detect_time_column, fmt

# Time intervals reported in "Hits over time". Other tests read this test's raw
# data by these aliases (e.g. the trend test keys on "Last30D").
# (display label, KQL summarize column/alias, KQL ago() argument)
TIME_INTERVALS = [
    ("Last 4 hours", "Last4H", "4h"),
    ("Last 12 hours", "Last12H", "12h"),
    ("Last 24 hours", "Last24H", "24h"),
    ("Last 48 hours", "Last48H", "48h"),
    ("Last 7 days", "Last7D", "7d"),
    ("Last 14 days", "Last14D", "14d"),
    ("Last 30 days", "Last30D", "30d"),
]


def counts_query(query_text):
    """Append a summarize row bucketing the result into every TIME_INTERVAL."""
    time_col = detect_time_column(query_text)
    buckets = ", ".join(
        f"{alias} = countif({time_col} > ago({ago}))"
        for _, alias, ago in TIME_INTERVALS
    )
    return query_text.rstrip() + f"\n| summarize {buckets}"


class HitsOverTimeTest(DetectionTest):
    """Counts hits across every interval in a single summarize pass.

    Its raw data (``{alias: count}``) is the foundation other tests build on.
    """

    name = "hits_over_time"

    def run(self, context):
        try:
            rows = self.client.run(counts_query(self.rule["query_text"]))
        except HuntingError as exc:
            self.error = str(exc)
            return
        # A summarize with no `by` returns a single row holding every bucket; an
        # empty result set means the query produced no rows, so every bucket is 0.
        row = rows[0] if rows else {}
        self.data = {alias: int(row.get(alias, 0)) for _, alias, _ in TIME_INTERVALS}

    def markdown(self):
        lines = ["**Hits over time**", "", "| Window | Hits |", "|---|---:|"]
        for label, alias, _ in TIME_INTERVALS:
            value = self.data.get(alias) if self.data else None
            lines.append(f"| {label} | {fmt(value)} |")
        if self.error:
            lines.append(f"\n> ⚠️ query failed: {self.error}")
        return "\n".join(lines)
