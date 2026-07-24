"""test_time_window.py — generate_timestamps contract tests.

Covers:
- Returns evenly-spaced UTC-aware datetimes
- Correct tick count for various backfill/interval combinations
- Last tick ≤ now; first tick = now - backfill
- Accepts seed without error (seed is a no-op for timestamps, affects per-tick jitter)
- Deterministic: same now → same timestamps regardless of seed
"""

from datetime import datetime, timedelta, timezone

import pytest

from generator.time_window import generate_timestamps


# Fixed reference "now" for deterministic assertions
FIXED_NOW = datetime(2026, 7, 15, 20, 0, 0, tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Basic contract
# ---------------------------------------------------------------------------

class TestBasicContract:
    def test_returns_list(self):
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        assert isinstance(ticks, list)

    def test_all_tz_aware_utc(self):
        """Every returned datetime must be UTC-aware (offset == 0)."""
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        for t in ticks:
            assert t.tzinfo is not None, "Timestamp is not tz-aware"
            assert t.utcoffset() == timedelta(0), "Timestamp is not UTC"

    def test_sorted_oldest_first(self):
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        assert ticks == sorted(ticks), "Timestamps are not sorted oldest-first"

    def test_last_tick_lte_now(self):
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        assert ticks[-1] <= FIXED_NOW

    def test_first_tick_equals_start(self):
        """First tick must equal now - backfill_minutes."""
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        expected_start = FIXED_NOW - timedelta(minutes=5)
        assert ticks[0] == expected_start

    def test_non_empty(self):
        ticks = generate_timestamps(backfill_minutes=1, interval_seconds=60, now=FIXED_NOW)
        assert len(ticks) >= 1


# ---------------------------------------------------------------------------
# Tick count
# ---------------------------------------------------------------------------

class TestTickCount:
    @pytest.mark.parametrize("backfill_min,interval_sec,expected_count", [
        (5,  60, 6),   # 0,60,120,180,240,300 s → 6 ticks
        (1,  30, 3),   # 0,30,60 s              → 3 ticks
        (15, 60, 16),  # 0..900 s step 60       → 16 ticks
        (2,  60, 3),   # 0,60,120 s             → 3 ticks
        (0,  60, 1),   # start==now             → 1 tick
    ])
    def test_count(self, backfill_min, interval_sec, expected_count):
        ticks = generate_timestamps(
            backfill_minutes=backfill_min,
            interval_seconds=interval_sec,
            now=FIXED_NOW,
        )
        assert len(ticks) == expected_count, (
            f"Expected {expected_count} ticks for "
            f"backfill={backfill_min}m interval={interval_sec}s, got {len(ticks)}"
        )


# ---------------------------------------------------------------------------
# Even spacing
# ---------------------------------------------------------------------------

class TestEvenSpacing:
    def test_spacing_60s(self):
        """Consecutive ticks must be exactly interval_seconds apart."""
        ticks = generate_timestamps(backfill_minutes=5, interval_seconds=60, now=FIXED_NOW)
        for i in range(1, len(ticks)):
            delta = (ticks[i] - ticks[i - 1]).total_seconds()
            assert delta == 60.0, f"Unexpected gap at index {i}: {delta}s"

    def test_spacing_30s(self):
        ticks = generate_timestamps(backfill_minutes=2, interval_seconds=30, now=FIXED_NOW)
        for i in range(1, len(ticks)):
            delta = (ticks[i] - ticks[i - 1]).total_seconds()
            assert delta == 30.0

    def test_spacing_90s(self):
        ticks = generate_timestamps(backfill_minutes=6, interval_seconds=90, now=FIXED_NOW)
        for i in range(1, len(ticks)):
            delta = (ticks[i] - ticks[i - 1]).total_seconds()
            assert delta == 90.0


# ---------------------------------------------------------------------------
# Determinism / seed contract
# ---------------------------------------------------------------------------

class TestDeterminism:
    def test_seed_kwarg_accepted(self):
        """Function accepts seed kwarg without raising."""
        ticks = generate_timestamps(
            backfill_minutes=5, interval_seconds=60, seed=42, now=FIXED_NOW
        )
        assert len(ticks) == 6

    def test_same_now_same_timestamps_regardless_of_seed(self):
        """Timestamps are evenly spaced and seed does NOT change them."""
        t_seed42 = generate_timestamps(backfill_minutes=5, interval_seconds=60, seed=42, now=FIXED_NOW)
        t_seed99 = generate_timestamps(backfill_minutes=5, interval_seconds=60, seed=99, now=FIXED_NOW)
        assert t_seed42 == t_seed99

    def test_repeated_calls_same_result(self):
        """Two calls with same args return identical lists."""
        t1 = generate_timestamps(backfill_minutes=5, interval_seconds=60, seed=42, now=FIXED_NOW)
        t2 = generate_timestamps(backfill_minutes=5, interval_seconds=60, seed=42, now=FIXED_NOW)
        assert t1 == t2


# ---------------------------------------------------------------------------
# Live-clock path (no now= override)
# ---------------------------------------------------------------------------

class TestLiveClock:
    def test_no_now_uses_real_utc_clock(self):
        """Without now=, returned ticks are recent UTC datetimes."""
        ticks = generate_timestamps(backfill_minutes=1, interval_seconds=60)
        assert len(ticks) >= 1
        for t in ticks:
            assert t.tzinfo is not None
            assert t.utcoffset() == timedelta(0)

    def test_last_tick_not_in_future(self):
        """Without now=, last tick should not be more than 1 minute in the future."""
        from datetime import datetime, timezone
        ticks = generate_timestamps(backfill_minutes=1, interval_seconds=60)
        now = datetime.now(timezone.utc)
        # Allow a small tolerance for clock resolution
        assert ticks[-1] <= now + timedelta(seconds=2)
