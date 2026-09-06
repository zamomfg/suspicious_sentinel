"""Helpers and constants shared across detection tests."""

from __future__ import annotations

import re

# Widest interval we report; also the API Timespan bound (ISO 8601 duration).
MAX_TIMESPAN = "P30D"

# Tables whose time column is `TimeGenerated` (Microsoft Sentinel schema,
# queryable from advanced hunting in the unified Defender portal). Any table not
# listed here is assumed to use the Defender XDR `Timestamp` column.
SENTINEL_TABLES = {
    "AADNonInteractiveUserSignInLogs", "AuditLogs", "AWSCloudTrail",
    "AWSGuardDuty", "AzureActivity", "AzureDiagnostics", "CommonSecurityLog",
    "GCPAuditLogs", "MicrosoftGraphActivityLogs", "OfficeActivity", "SecurityAlert",
    "SecurityEvent", "SigninLogs", "Syslog",
}


def leading_table(query_text):
    """Return the query's first referenced table name, or None.

    Skips blank/comment lines and a `let` preamble, returning the identifier at
    the start of the first pipeline.
    """
    for line in query_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        match = re.match(r"\(*\s*([A-Za-z_][A-Za-z0-9_]*)", stripped)
        if match and match.group(1) != "let":
            return match.group(1)
    return None


def detect_time_column(query_text):
    """Time column for *query_text*: `TimeGenerated` for Sentinel tables,
    `Timestamp` for Defender XDR tables (the default)."""
    return "TimeGenerated" if leading_table(query_text) in SENTINEL_TABLES else "Timestamp"


def mermaid_label(text):
    """Sanitize a value for use as a Mermaid axis label (quoted string)."""
    label = str(text).replace('"', "'").replace("\n", " ").strip()
    if len(label) > 40:
        label = label[:37] + "..."
    return label or "(empty)"


def fmt(value):
    """Format a hit count for a Markdown table cell (⚠️ when missing)."""
    return f"{value:,}" if isinstance(value, int) else "⚠️"
