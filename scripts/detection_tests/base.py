"""The interface every detection test implements."""

from __future__ import annotations

from abc import ABC, abstractmethod


class DetectionTest(ABC):
    """One check run against a detection rule's KQL.

    Subclasses implement two things — a ``run`` that performs the check and a
    ``markdown`` that renders it — and expose the raw result on ``data`` so a
    later test can reuse it (e.g. the trend test reads the interval test's
    30-day total to pick its bucket step).
    """

    # Unique key; also this test's slot in the shared `context`.
    name = ""

    def __init__(self, rule, client):
        self.rule = rule        # the discover_rules() dict for this rule
        self.client = client    # HuntingClient
        self.data = None        # raw output, populated by run()
        self.error = None       # human-readable failure string, or None

    @abstractmethod
    def run(self, context):
        """Perform the check; populate ``self.data`` (and ``self.error`` on failure).

        ``context`` maps each already-run test's ``name`` to its ``.data``, so a
        test can read a previous test's raw output.
        """

    @abstractmethod
    def markdown(self):
        """Return this test's Markdown fragment (``""`` if there's nothing to show)."""
