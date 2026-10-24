"""NRT (Continuous) detection rules may only use the tables and KQL features Microsoft supports."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

import nrt_compat
from test_detection_rules import discover_rules

IAC_DIR = os.environ.get("IAC_DIR", str(Path(__file__).resolve().parents[2] / "IaC"))

NRT_RULES = [
    rule for rule in discover_rules(IAC_DIR)
    if rule["schedule_frequency"] in nrt_compat.NRT_FREQUENCIES
]


@pytest.mark.parametrize("rule", NRT_RULES, ids=[r["name"] for r in NRT_RULES])
def test_nrt_rule_uses_supported_table(rule):
    tables = nrt_compat.tables(rule["query_text"])
    assert len(tables) == 1, f"expected exactly one source table, found {tables}"
    assert tables[0] in nrt_compat.NRT_TABLES, f"table `{tables[0]}` is not supported for NRT"


@pytest.mark.parametrize("rule", NRT_RULES, ids=[r["name"] for r in NRT_RULES])
def test_nrt_rule_uses_supported_kql(rule):
    assert nrt_compat.violations(rule["query_text"]) == []


@pytest.mark.parametrize("query", [
    'DeviceLogonEvents\n| where RemoteIP startswith "10."\n| project Timestamp, ReportId, DeviceId',
    'DeviceEvents\n| where ingestion_time() > ago(1d)\n| summarize (Timestamp, ReportId)=arg_max(Timestamp, ReportId), count() by DeviceId',
    'DeviceLogonEvents\n| where InitiatingProcessFileName in~ ("sshd", "sshd-session")\n| where not(isempty(RemoteIP))',
    'SigninLogs\n| where UserPrincipalName has "admin"\n| extend Upn = tolower(UserPrincipalName)',
])
def test_checker_accepts_supported_query(query):
    assert nrt_compat.violations(query) == []


@pytest.mark.parametrize("query, expected", [
    ("DeviceLogonEvents\n| where not(ipv4_is_private(RemoteIP))", "function `ipv4_is_private()`"),
    ("ASimNetworkSessionLogs\n| where DvcAction == \"Allow\"", "table `ASimNetworkSessionLogs`"),
    ("DeviceEvents\n| join (DeviceInfo) on DeviceId", "`join`"),
    ("DeviceEvents\n| union DeviceInfo", "`union`"),
    ("DeviceEvents\n| sort by Timestamp desc", "tabular operator `sort`"),
    ("let Ranges = toscalar(_GetWatchlist('Vlans'));\nDeviceEvents", "function `toscalar()`"),
])
def test_checker_rejects_unsupported_query(query, expected):
    assert any(expected in problem for problem in nrt_compat.violations(query))


def test_checker_ignores_strings_and_comments():
    query = 'DeviceEvents\n// ipv4_is_private(x) | join\n| where ActionType == "join(union)"'
    assert nrt_compat.violations(query) == []
