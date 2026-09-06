"""Trend line chart of hits over the last 30 days."""

from __future__ import annotations

from .base import DetectionTest
from .client import HuntingError
from .common import detect_time_column

# The trend chart is built from a make-series query over the last 30 days. The
# bucket step widens to 7 days once a rule is noisy enough that a daily series
# would be unwieldy; otherwise it is 1 day.
SERIES_RANGE = "30d"
SERIES_THRESHOLD = 1000
SERIES_STEP_BUSY = "7d"
SERIES_STEP_QUIET = "1d"

# Font size for the x-axis labels. Kept small so a daily (30-point) series fits
# without the date labels overlapping.
X_LABEL_FONT_SIZE = 8


def series_step(counts):
    """7-day buckets for busy rules, 1-day buckets otherwise (by 30-day total)."""
    if counts and counts.get("Last30D", 0) > SERIES_THRESHOLD:
        return SERIES_STEP_BUSY
    return SERIES_STEP_QUIET


def make_series_query(query_text, step):
    """Build a make-series query yielding one tabular row per evenly-spaced bin.

    make-series returns the timestamps and counts as parallel dynamic arrays in
    a single row, which the hunting API can serialize awkwardly. `mv-expand`
    flattens them (in lock-step) into one row per bin with scalar `Bin`/`Hits`
    columns, which parse predictably.
    """
    time_col = detect_time_column(query_text)
    return (
        query_text.rstrip()
        + f"\n| make-series Hits = count() on {time_col} "
          f"from ago({SERIES_RANGE}) to now() step {step}"
        + f"\n| mv-expand {time_col} to typeof(datetime), Hits to typeof(long)"
        + f"\n| project Bin = {time_col}, Hits"
        + "\n| order by Bin asc"
    )


class TrendTest(DetectionTest):
    """A Mermaid line chart of an evenly-spaced make-series over 30 days.

    Reads the interval test's 30-day total from the shared context to choose the
    bucket step — the cross-test dependency that motivates exposing raw data.
    """

    name = "trend"

    def run(self, context):
        counts = context.get("hits_over_time")
        if counts is None:  # base query failed; the interval test reports it
            return
        step = series_step(counts)
        try:
            rows = self.client.run(make_series_query(self.rule["query_text"], step))
        except HuntingError as exc:
            self.error = str(exc)
            return
        if not rows:
            self.error = "make-series returned no rows"
            return

        labels, values = [], []
        for row in rows:
            bin_value = row.get("Bin")
            if bin_value is None:
                continue
            # ISO timestamp -> "MM-DD" axis label.
            labels.append(str(bin_value).split("T")[0][5:])
            values.append(int(float(row.get("Hits") or 0)))
        if not labels:
            self.error = "make-series rows missing Bin/Hits columns"
            return
        self.data = {"step": step, "labels": labels, "values": values}

    def markdown(self):
        if not self.data:
            if self.error:
                return f"> ⚠️ trend chart unavailable: {self.error}"
            return ""
        step = self.data["step"]
        labels = ", ".join(f'"{label}"' for label in self.data["labels"])
        values = ", ".join(str(v) for v in self.data["values"])
        return "\n".join([
            f"**Trend** — hits per {step} over the last 30 days",
            "",
            "```mermaid",
            # Shrink the x-axis labels so a daily (30-point) series doesn't
            # overlap; Mermaid neither rotates nor thins labels on its own.
            "---",
            "config:",
            "  xyChart:",
            "    xAxis:",
            f"      labelFontSize: {X_LABEL_FONT_SIZE}",
            "---",
            "xychart-beta",
            '    title "Hits over time"',
            f"    x-axis [{labels}]",
            '    y-axis "Hits"',
            f"    line [{values}]",
            "```",
        ])
