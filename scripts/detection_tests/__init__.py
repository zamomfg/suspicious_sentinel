"""Pluggable detection tests run against each rule's KQL.

Add a test by creating a module here, subclassing ``DetectionTest`` (implement
``run`` and ``markdown``), and appending it to ``TESTS`` below.
"""

from __future__ import annotations

from .base import DetectionTest
from .client import HuntingClient, HuntingError, run_hunting_query
from .hits_over_time import HitsOverTimeTest
from .top_entities import TopEntitiesTest
from .trend import TrendTest

# Order is both the run order and the render order. `hits_over_time` must run
# before `trend` (trend reads its 30-day total to choose the bucket step), and
# `top_entities` renders between the hits table and the trend chart.
TESTS = [HitsOverTimeTest, TopEntitiesTest, TrendTest]

__all__ = [
    "DetectionTest",
    "HuntingClient",
    "HuntingError",
    "run_hunting_query",
    "TESTS",
]
