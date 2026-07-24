"""time_window — helpers to generate a series of UTC timestamps for backfill.

Usage::

    from generator.time_window import generate_timestamps
    ticks = generate_timestamps(backfill_minutes=60, interval_seconds=60)
    # returns a list of datetime objects from (now-60m) to now, spaced 60s apart

When seed is provided the function is deterministic (seed affects any
per-tick jitter; the base timestamps are always evenly-spaced regardless).
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone
from typing import List, Optional


def generate_timestamps(
    backfill_minutes: int = 15,
    interval_seconds: int = 60,
    seed: Optional[int] = None,
    now: Optional[datetime] = None,
) -> List[datetime]:
    """Return evenly-spaced UTC datetimes covering a backfill window.

    Args:
        backfill_minutes: How many minutes back from *now* the window starts.
        interval_seconds: Spacing between ticks in seconds.
        seed: Optional RNG seed for reproducibility (currently unused by this
              function but accepted for API consistency; callers may pass the
              same seed to scenarios for joint reproducibility).
        now: Override "now" (useful in tests). Defaults to
             ``datetime.now(timezone.utc)``.

    Returns:
        Sorted list of UTC-aware datetimes, oldest first.  The last element
        is always ≤ *now*.
    """
    if now is None:
        now = datetime.now(timezone.utc)

    start = now - timedelta(minutes=backfill_minutes)
    ticks: List[datetime] = []
    current = start
    while current <= now:
        ticks.append(current)
        current += timedelta(seconds=interval_seconds)

    return ticks
