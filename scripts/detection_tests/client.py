"""Microsoft Graph advanced ("threat") hunting API client."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

from .common import MAX_TIMESPAN

GRAPH_HUNTING_URL = "https://graph.microsoft.com/beta/security/runHuntingQuery"


class HuntingError(Exception):
    """A query could not be evaluated by the hunting API."""


def run_hunting_query(kql, token, timespan):
    """POST *kql* (bounded to *timespan*) to the hunting API; return result rows.

    *timespan* is an ISO 8601 duration (e.g. ``P30D``) measured back from now,
    passed verbatim as the API's Timespan parameter.
    """
    body = {"Query": kql}
    if timespan is not None:
        body["Timespan"] = timespan
    payload = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        GRAPH_HUNTING_URL,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        try:
            detail = json.loads(detail)["error"]["message"]
        except Exception:  # noqa: BLE001
            pass
        raise HuntingError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise HuntingError(str(exc.reason)) from exc

    return data.get("results", [])


class HuntingClient:
    """Runs hunting queries for one report, bounded to a fixed timespan.

    Sleeps ``throttle`` seconds after each call to stay under the hunting API
    rate limit (10 requests/minute), so individual tests don't manage pacing.
    """

    def __init__(self, token, timespan=MAX_TIMESPAN, throttle=1.0):
        self.token = token
        self.timespan = timespan
        self.throttle = throttle

    def run(self, kql):
        """Run *kql* and return its result rows. Raises HuntingError on failure."""
        rows = run_hunting_query(kql, self.token, self.timespan)
        if self.throttle:
            time.sleep(self.throttle)
        return rows
