"""test_scenarios.py — scenario generator tests.

Covers per-scenario:
- Row counts (baseline and with anomaly variants)
- Determinism: same seed → identical records list
- Required columns present in every emitted record
- TimeGenerated serialised as ISO-8601 UTC string in to_dict() output
"""

from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List

import pytest

from generator.config import LabConfig
from generator.time_window import generate_timestamps
from generator.validation import required_columns
from generator.scenarios.virtual_machines import generate as vm_generate
from generator.scenarios.app_service import generate as app_generate
from generator.scenarios.aks import generate as aks_generate
from generator.scenarios.azure_sql import generate as sql_generate
from generator.scenarios.apm import generate as apm_generate


# Deterministic test constants
FIXED_NOW = datetime(2026, 7, 15, 20, 0, 0, tzinfo=timezone.utc)
BACKFILL_MIN = 5
INTERVAL_SEC = 60
# 6 ticks: now-5min, now-4min, …, now (inclusive, step 60s)
N_TICKS = 6


@pytest.fixture
def config():
    return LabConfig.load(dry_run=True)


@pytest.fixture
def time_window():
    return generate_timestamps(
        backfill_minutes=BACKFILL_MIN,
        interval_seconds=INTERVAL_SEC,
        now=FIXED_NOW,
    )


def _assert_iso8601_utc(records: List[Dict[str, Any]]) -> None:
    """Assert every record's TimeGenerated is an ISO-8601 UTC string."""
    for rec in records:
        tg = rec["TimeGenerated"]
        assert isinstance(tg, str), f"TimeGenerated is not a string: {type(tg)}"
        # fromisoformat handles '+00:00'; replace 'Z' for compat
        dt = datetime.fromisoformat(tg.replace("Z", "+00:00"))
        assert dt.tzinfo is not None, f"TimeGenerated has no timezone: {tg}"
        assert dt.utcoffset() == timedelta(0), f"TimeGenerated is not UTC: {tg}"


def _assert_required_columns(scenario_key: str, records: List[Dict[str, Any]]) -> None:
    req = required_columns(scenario_key)
    for i, rec in enumerate(records):
        for col in req:
            assert col in rec, (
                f"Record #{i} for '{scenario_key}' missing required column '{col}'"
            )


# ---------------------------------------------------------------------------
# VirtualMachines
# ---------------------------------------------------------------------------

class TestVirtualMachines:
    # 5 VMs in catalogue × 6 ticks = 30 baseline records

    def test_row_count_baseline(self, config, time_window):
        records = vm_generate(config, time_window, seed=42)
        assert len(records) == 5 * N_TICKS  # 30

    def test_row_count_heartbeat_anomaly(self, config, time_window):
        """heartbeat silences 1 VM → 4 VMs × 6 ticks = 24 records."""
        records = vm_generate(config, time_window, anomaly="heartbeat", seed=42)
        assert len(records) == 4 * N_TICKS  # 24

    def test_row_count_cpu_anomaly(self, config, time_window):
        """cpu anomaly keeps full VM set (5 × 6 = 30)."""
        records = vm_generate(config, time_window, anomaly="cpu", seed=42)
        assert len(records) == 5 * N_TICKS

    def test_deterministic(self, config, time_window):
        r1 = vm_generate(config, time_window, seed=42)
        r2 = vm_generate(config, time_window, seed=42)
        assert r1 == r2

    def test_different_seeds_produce_different_values(self, config, time_window):
        r1 = vm_generate(config, time_window, seed=42)
        r2 = vm_generate(config, time_window, seed=99)
        assert r1 != r2

    def test_required_columns_present(self, config, time_window):
        records = vm_generate(config, time_window, seed=42)
        _assert_required_columns("virtualmachines", records)

    def test_time_generated_iso8601_utc(self, config, time_window):
        records = vm_generate(config, time_window, seed=42)
        _assert_iso8601_utc(records)

    def test_record_types(self, config, time_window):
        """CpuPercent is float, NetworkInBytes is int, Resource is str."""
        records = vm_generate(config, time_window, seed=42)
        for rec in records:
            assert isinstance(rec["CpuPercent"], float)
            assert isinstance(rec["NetworkInBytes"], int)
            assert isinstance(rec["Resource"], str)


# ---------------------------------------------------------------------------
# AppService
# ---------------------------------------------------------------------------

class TestAppService:
    # 4 apps in catalogue × 6 ticks = 24 baseline records

    def test_row_count_baseline(self, config, time_window):
        records = app_generate(config, time_window, seed=42)
        assert len(records) == 4 * N_TICKS  # 24

    def test_deterministic(self, config, time_window):
        r1 = app_generate(config, time_window, seed=42)
        r2 = app_generate(config, time_window, seed=42)
        assert r1 == r2

    def test_required_columns_present(self, config, time_window):
        records = app_generate(config, time_window, seed=42)
        _assert_required_columns("appservice", records)

    def test_time_generated_iso8601_utc(self, config, time_window):
        records = app_generate(config, time_window, seed=42)
        _assert_iso8601_utc(records)

    def test_http_counts_sum_to_request_count(self, config, time_window):
        """Http2xx + Http4xx + Http5xx should equal RequestCount."""
        records = app_generate(config, time_window, seed=42)
        for rec in records:
            total = rec["Http2xxCount"] + rec["Http4xxCount"] + rec["Http5xxCount"]
            assert total == rec["RequestCount"], (
                f"HTTP count mismatch: 2xx+4xx+5xx={total} != RequestCount={rec['RequestCount']}"
            )

    def test_record_types(self, config, time_window):
        records = app_generate(config, time_window, seed=42)
        for rec in records:
            assert isinstance(rec["RequestCount"], int)
            assert isinstance(rec["ResponseTimeMs"], float)
            assert isinstance(rec["RestartCount"], int)


# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

class TestAKS:
    # prod cluster: 3 nodes + 6 pods = 9 rows/tick
    # staging cluster: 2 nodes + 2 pods = 4 rows/tick
    # total: 13 rows/tick × 6 ticks = 78 records

    def test_row_count_baseline(self, config, time_window):
        records = aks_generate(config, time_window, seed=42)
        assert len(records) == 13 * N_TICKS  # 78

    def test_deterministic(self, config, time_window):
        r1 = aks_generate(config, time_window, seed=42)
        r2 = aks_generate(config, time_window, seed=42)
        assert r1 == r2

    def test_required_columns_present(self, config, time_window):
        records = aks_generate(config, time_window, seed=42)
        _assert_required_columns("aks", records)

    def test_time_generated_iso8601_utc(self, config, time_window):
        records = aks_generate(config, time_window, seed=42)
        _assert_iso8601_utc(records)

    def test_node_rows_have_empty_pod_fields(self, config, time_window):
        """Node-level rows: PodName="" and ContainerName=""."""
        records = aks_generate(config, time_window, seed=42)
        node_rows = [r for r in records if r["PodName"] == ""]
        # 3 prod nodes + 2 staging nodes = 5 per tick × 6 ticks = 30
        assert len(node_rows) == 5 * N_TICKS  # 30
        for row in node_rows:
            assert row["ContainerName"] == ""

    def test_pod_rows_have_pod_name(self, config, time_window):
        """Pod-level rows: PodName is non-empty."""
        records = aks_generate(config, time_window, seed=42)
        pod_rows = [r for r in records if r["PodName"] != ""]
        # 6 prod pods + 2 staging pods = 8 per tick × 6 ticks = 48
        assert len(pod_rows) == 8 * N_TICKS  # 48
        for row in pod_rows:
            assert row["NodeName"] != ""


# ---------------------------------------------------------------------------
# AzureSQL
# ---------------------------------------------------------------------------

class TestAzureSQL:
    # sql-prod-01: 3 DBs; sql-prod-02: 1 DB; sql-staging-01: 1 DB = 5 total
    # 5 DBs × 6 ticks = 30 records

    def test_row_count_baseline(self, config, time_window):
        records = sql_generate(config, time_window, seed=42)
        assert len(records) == 5 * N_TICKS  # 30

    def test_deterministic(self, config, time_window):
        r1 = sql_generate(config, time_window, seed=42)
        r2 = sql_generate(config, time_window, seed=42)
        assert r1 == r2

    def test_required_columns_present(self, config, time_window):
        records = sql_generate(config, time_window, seed=42)
        _assert_required_columns("azuresql", records)

    def test_time_generated_iso8601_utc(self, config, time_window):
        records = sql_generate(config, time_window, seed=42)
        _assert_iso8601_utc(records)

    def test_storage_used_consistent_with_percent(self, config, time_window):
        """StorageUsedMB is proportional to StorageLimitMB × StoragePercent / 100.

        Note: StorageUsedMB is computed from the raw (pre-rounded) StoragePercent
        but to_dict() rounds StoragePercent to 2 decimal places, so an exact
        recomputation from rec["StoragePercent"] may differ by up to
        limit_mb * 0.005 / 100 ≈ 5 MB for the largest limit.  Allow ±6 MB.
        """
        records = sql_generate(config, time_window, seed=42)
        for rec in records:
            rough_expected = rec["StorageLimitMB"] * rec["StoragePercent"] / 100.0
            tolerance = max(6, rec["StorageLimitMB"] // 20000 + 1)
            assert abs(rec["StorageUsedMB"] - rough_expected) <= tolerance, (
                f"StorageUsedMB={rec['StorageUsedMB']} differs from "
                f"expected≈{rough_expected:.1f} by more than {tolerance} MB"
            )

    def test_record_types(self, config, time_window):
        records = sql_generate(config, time_window, seed=42)
        for rec in records:
            assert isinstance(rec["DtuPercent"], float)
            assert isinstance(rec["ActiveConnections"], int)
            assert isinstance(rec["DeadlockCount"], int)


# ---------------------------------------------------------------------------
# APM
# ---------------------------------------------------------------------------

class TestAPM:
    # Default 20 events per tick × 6 ticks = 120 records

    def test_row_count_default(self, config, time_window):
        records = apm_generate(config, time_window, seed=42)
        assert len(records) == 20 * N_TICKS  # 120

    def test_row_count_custom_count_per_tick(self, config, time_window):
        """count_per_tick override is honoured."""
        records = apm_generate(config, time_window, seed=42, count_per_tick=10)
        assert len(records) == 10 * N_TICKS  # 60

    def test_deterministic(self, config, time_window):
        r1 = apm_generate(config, time_window, seed=42)
        r2 = apm_generate(config, time_window, seed=42)
        assert r1 == r2

    def test_required_columns_present(self, config, time_window):
        records = apm_generate(config, time_window, seed=42)
        _assert_required_columns("apm", records)

    def test_time_generated_iso8601_utc(self, config, time_window):
        records = apm_generate(config, time_window, seed=42)
        _assert_iso8601_utc(records)

    def test_item_type_values_are_valid(self, config, time_window):
        """ItemType must be one of the four defined event types."""
        valid = {"request", "dependency", "exception", "trace"}
        records = apm_generate(config, time_window, seed=42)
        for rec in records:
            assert rec["ItemType"] in valid, f"Unexpected ItemType: {rec['ItemType']}"

    def test_is_success_is_bool(self, config, time_window):
        records = apm_generate(config, time_window, seed=42)
        for rec in records:
            assert isinstance(rec["IsSuccess"], bool)

    def test_severity_level_in_valid_range(self, config, time_window):
        """SeverityLevel must be in {0, 1, 2, 3, 4}."""
        records = apm_generate(config, time_window, seed=42)
        for rec in records:
            assert rec["SeverityLevel"] in {0, 1, 2, 3, 4}

    def test_exception_rows_have_exception_type(self, config, time_window):
        """Exception-type rows must have non-empty ExceptionType."""
        records = apm_generate(config, time_window, seed=42)
        for rec in records:
            if rec["ItemType"] == "exception":
                assert rec["ExceptionType"] != "", (
                    f"Exception row missing ExceptionType: {rec}"
                )

    def test_request_rows_have_duration(self, config, time_window):
        """Request rows should have DurationMs > 0."""
        records = apm_generate(config, time_window, seed=42)
        request_rows = [r for r in records if r["ItemType"] == "request"]
        # With 120 records at 60% probability, we expect ~72 request rows
        assert len(request_rows) > 0
        for rec in request_rows:
            assert rec["DurationMs"] >= 0.0
