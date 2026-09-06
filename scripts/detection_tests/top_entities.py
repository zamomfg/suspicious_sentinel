"""Top entities (users / devices / IPs / senders ...) behind the hits.

A table can have several entities worth breaking down — e.g. sign-in logs by
both user and source IP — so each table maps to a *list* of columns, and each
gets its own bar chart nested under a single "Top entities" section.
"""

from __future__ import annotations

from .base import DetectionTest
from .client import HuntingError
from .common import leading_table, mermaid_label

# Entities to break the hits down by, per source table. Each entry is either a
# column name, or a (column, label) tuple when a friendlier label reads better
# than the raw column. The right columns differ per table — sign-in logs key on
# the user and the source IP, Device* tables on the device, and so on. Tables
# not listed here get no entity charts.
ENTITY_COLUMNS = {
    # Microsoft Sentinel tables — users / IPs / callers
    "SigninLogs": ["UserPrincipalName", ("IPAddress", "IP addresses")],
    "AADNonInteractiveUserSignInLogs": ["UserPrincipalName", ("IPAddress", "IP addresses")],
    "OfficeActivity": ["UserId"],
    "SecurityEvent": ["Account"],
    "CommonSecurityLog": ["SourceUserName"],
    "AzureActivity": ["Caller"],
    # Microsoft Defender XDR tables — devices
    "DeviceProcessEvents": ["DeviceName"],
    "DeviceFileEvents": ["DeviceName"],
    "DeviceNetworkEvents": ["DeviceName"],
    "DeviceRegistryEvents": ["DeviceName"],
    "DeviceImageLoadEvents": ["DeviceName"],
    "DeviceEvents": ["DeviceName"],
    "DeviceInfo": ["DeviceName"],
    "DeviceNetworkInfo": ["DeviceName"],
    # Microsoft Defender XDR tables — accounts
    "DeviceLogonEvents": ["AccountName"],
    "IdentityLogonEvents": ["AccountUpn"],
    "IdentityQueryEvents": ["AccountUpn"],
    "IdentityDirectoryEvents": ["AccountUpn"],
    "CloudAppEvents": ["AccountDisplayName"],
    "UrlClickEvents": ["AccountUpn"],
    # Microsoft Defender XDR tables — email senders
    "EmailEvents": ["SenderFromAddress"],
    "EmailAttachmentInfo": ["SenderFromAddress"],
    "EmailUrlInfo": ["SenderFromAddress"],
}

# How many top entities to plot per chart (capped so charts don't get cluttered).
ENTITY_TOP_N = 10


def entity_entries(query_text):
    """Return [(column, label), ...] to break down for the query's table."""
    entries = ENTITY_COLUMNS.get(leading_table(query_text), [])
    return [e if isinstance(e, tuple) else (e, e) for e in entries]


def entities_query(query_text, col):
    """Append a top-N summarize so we can chart which entities trigger the hits."""
    return (
        query_text.rstrip()
        + f"\n| summarize Hits = count() by Entity = tostring({col})"
        + "\n| where isnotempty(Entity)"
        + f"\n| top {ENTITY_TOP_N} by Hits"
    )


class TopEntitiesTest(DetectionTest):
    """Horizontal bar charts of the top entities, one per mapped column.

    Renders a collapsed "Top entities" section with each entity's chart nested
    in its own dropdown beneath it.
    """

    name = "top_entities"

    def run(self, context):
        # Skip unmapped tables, and skip if the base query already failed
        # (no point re-running a doomed query for the entity breakdown).
        entries = entity_entries(self.rule["query_text"])
        if not entries or context.get("hits_over_time") is None:
            return

        charts, errors = [], []
        for col, label in entries:
            try:
                rows = self.client.run(entities_query(self.rule["query_text"], col))
            except HuntingError as exc:
                errors.append(f"`{label}`: {exc}")
                continue
            if not rows:  # no hits for this breakdown — nothing to chart
                continue
            charts.append({
                "label": label,
                "rows": [(mermaid_label(r.get("Entity")), int(float(r.get("Hits") or 0)))
                         for r in rows],
            })

        if charts or errors:
            self.data = {"charts": charts, "errors": errors}

    def markdown(self):
        if not self.data:
            return ""
        lines = ["<details>", "<summary><b>Top entities</b></summary>", ""]
        for chart in self.data["charts"]:
            lines += _chart_dropdown(chart["label"], chart["rows"])
            lines.append("")
        for err in self.data["errors"]:
            lines.append(f"> ⚠️ top-entities chart unavailable for {err}")
            lines.append("")
        lines.append("</details>")
        return "\n".join(lines)


def _chart_dropdown(label, rows):
    """Render one entity's collapsed horizontal bar chart."""
    labels = ", ".join(f'"{entity}"' for entity, _ in rows)
    values = ", ".join(str(hits) for _, hits in rows)
    return [
        "<details>",
        f"<summary><b>Top {label}</b></summary>",
        "",
        "```mermaid",
        "---",
        "config:",
        "  xyChart:",
        "    chartOrientation: horizontal",
        "---",
        "xychart-beta",
        f'    title "Top {label}"',
        f"    x-axis [{labels}]",
        '    y-axis "Hits"',
        f"    bar [{values}]",
        "```",
        "",
        "</details>",
    ]
