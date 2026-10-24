"""Static checks that a KQL query can run as a Continuous (NRT) custom detection.

Allow-lists mirror the Microsoft documentation:
- Tables: https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules#tables-that-support-continuous-nrt-frequency
- KQL features: https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure#supported-kql-features
"""

from __future__ import annotations

import re

NRT_FREQUENCIES = {"NRT", "PT0S", "0"}

DEFENDER_TABLES = {
    "AlertEvidence", "CloudAppEvents", "DeviceEvents", "DeviceFileCertificateInfo",
    "DeviceFileEvents", "DeviceImageLoadEvents", "DeviceLogonEvents",
    "DeviceNetworkEvents", "DeviceNetworkInfo", "DeviceInfo", "DeviceProcessEvents",
    "DeviceRegistryEvents", "EmailAttachmentInfo", "EmailEvents",
    "EmailPostDeliveryEvents", "EmailUrlInfo", "IdentityDirectoryEvents",
    "IdentityLogonEvents", "IdentityQueryEvents", "UrlClickEvents",
}

SENTINEL_TABLES = {
    "ABAPAuditLog_C", "ABAPChangeDocsLog_CL", "AuditLogs", "AWSCloudTrail",
    "AWSGuardDuty", "AzureActivity", "CommonSecurityLog", "GCPAuditLogs",
    "MicrosoftGraphActivityLogs", "OfficeActivity", "Okta_CL", "OktaV2_CL",
    "ProofpointPOD", "ProofPointTAPClicksPermitted_CL",
    "ProofPointTAPMessagesDelivered_CL", "SecurityAlert", "SecurityEvent",
    "SigninLogs",
}

NRT_TABLES = DEFENDER_TABLES | SENTINEL_TABLES

TABULAR_OPERATORS = {
    "extend", "project", "print", "where", "parse", "project-away",
    "project-rename", "datatable",
    # The Defender docs' own NRT-compatible example aggregates with summarize/arg_max/count.
    "summarize",
}

FUNCTIONS = {
    # Bitwise
    "binary_and", "binary_or", "binary_not", "binary_shift_left",
    "binary_shift_right", "binary_xor",
    # Conversion
    "tobool", "todatetime", "todouble", "toreal", "toguid", "toint", "tolong",
    "tostring", "totimespan",
    # DateTime and TimeSpan
    "ago", "datetime_add", "datetime_diff", "datetime_part", "dayofmonth",
    "dayofweek", "dayofyear", "endofday", "endofmonth", "endofweek", "endofyear",
    "getmonth", "monthofyear", "getyear", "hourofday", "make_datetime",
    "make_timespan", "now", "startofday", "startofmonth", "startofweek",
    "startofyear", "weekofyear",
    # Dynamic and array
    "array_concat", "array_length", "pack", "pack_array", "parse_json",
    "parse_xml", "zip",
    # Mathematical
    "abs", "bin", "floor", "ceiling", "exp", "exp10", "exp2", "isfinite", "isinf",
    "isnan", "log", "log10", "log2", "pow", "round", "sign",
    # Conditional
    "case", "iif", "max_of", "min_of",
    # String
    "base64_encodestring", "base64_decodestring", "countof", "extract",
    "extract_all", "indexof", "isempty", "isnotempty", "replace", "split",
    "strcat", "strcat_delim", "strlen", "substring", "tolower", "toupper",
    "hash_sha256",
    # Type
    "gettype", "isnotnull", "isnull",
    # Transformation-only specials and columnifexists
    "parse_cef_dictionary", "geo_location", "columnifexists",
    # Used by the Defender docs' NRT-compatible example
    "arg_max", "count", "ingestion_time",
    # Logical negation
    "not",
    # Scalar literals
    "datetime", "timespan", "time",
}

FORBIDDEN_OPERATORS = {"join", "union", "lookup", "externaldata"}

_STRING_LITERAL = re.compile(r'@"[^"]*"|@\'[^\']*\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
_COMMENT = re.compile(r"//[^\n]*")
_PIPE_OPERATOR = re.compile(r"\|\s*([A-Za-z][A-Za-z0-9_-]*)")
_FUNCTION_CALL = re.compile(r"(?<![\w.$-])([A-Za-z_][A-Za-z0-9_]*)\s*\(")
_LET = re.compile(r"^\s*let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", re.M)
_KEYWORDS_BEFORE_PARENS = {"in", "kind"}


def _normalise(query_text):
    without_strings = _STRING_LITERAL.sub('""', query_text)
    return _COMMENT.sub("", without_strings)


def _body(query):
    statements = [s for s in query.split(";") if s.strip()]
    return statements[-1] if statements else ""


def tables(query_text):
    """Tables referenced as pipeline sources (the final statement's source)."""
    match = re.match(r"\s*\(*\s*([A-Za-z_][A-Za-z0-9_]*)", _body(_normalise(query_text)))
    return [match.group(1)] if match else []


def tabular_operators(query_text):
    query = _normalise(query_text)
    return [match.group(1) for match in _PIPE_OPERATOR.finditer(query)]


def functions(query_text):
    query = _normalise(query_text)
    let_function_names = set(_LET.findall(query))
    query = _PIPE_OPERATOR.sub("|", query)
    called_names = (match.group(1) for match in _FUNCTION_CALL.finditer(query))
    return [
        function_name for function_name in called_names
        if function_name not in _KEYWORDS_BEFORE_PARENS and function_name not in let_function_names
    ]


def violations(query_text):
    """Return human-readable reasons *query_text* can't run as an NRT detection."""
    problems = []
    query = _normalise(query_text)

    found_tables = tables(query_text)
    if not found_tables:
        problems.append("no source table found")
    for table in found_tables:
        if table not in NRT_TABLES:
            problems.append(f"table `{table}` is not supported for NRT")

    for forbidden_operator in sorted(FORBIDDEN_OPERATORS):
        if re.search(rf"(?<![\w-]){forbidden_operator}(?![\w-])", query):
            problems.append(f"`{forbidden_operator}` is not allowed in NRT queries")

    for operator in sorted(set(tabular_operators(query_text))):
        if operator not in TABULAR_OPERATORS and operator not in FORBIDDEN_OPERATORS:
            problems.append(f"tabular operator `{operator}` is not supported for NRT")

    for function_name in sorted(set(functions(query_text))):
        if function_name not in FUNCTIONS:
            problems.append(f"function `{function_name}()` is not supported for NRT")

    return problems
