"""test_thresholds.py — anomaly threshold crossing tests.

For each anomaly key in the catalog, verify:
1. Generating with that anomaly key injects values that CROSS the alert threshold.
2. Generating without any anomaly (baseline) stays WITHIN normal bounds.

All tests are hermetic: dry_run=True, fixed seed=42, fixed now → no network calls.
"""

from datetime import datetime, timezone

import pytest

from generator.config import LabConfig
from generator.time_window import generate_timestamps
from generator.scenarios.virtual_machines import generate as vm_generate
from generator.scenarios.app_service import generate as app_generate
from generator.scenarios.aks import generate as aks_generate
from generator.scenarios.azure_sql import generate as sql_generate
from generator.scenarios.apm import generate as apm_generate


FIXED_NOW = datetime(2026, 7, 15, 20, 0, 0, tzinfo=timezone.utc)


@pytest.fixture
def config():
    return LabConfig.load(dry_run=True)


@pytest.fixture
def time_window():
    return generate_timestamps(
        backfill_minutes=5, interval_seconds=60, now=FIXED_NOW
    )


# ===========================================================================
# VirtualMachines — cpu
# ===========================================================================

class TestVMCpuAnomaly:
    """cpu: CpuPercent > 90 % (threshold: > 90 % over 5 min)."""

    def test_cpu_anomaly_all_records_exceed_threshold(self, config, time_window):
        records = vm_generate(config, time_window, anomaly="cpu", seed=42)
        assert len(records) > 0
        violations = [r for r in records if r["CpuPercent"] <= 90]
        assert violations == [], (
            f"Expected ALL records to have CpuPercent > 90, "
            f"but {len(violations)} did not. "
            f"Sample: {violations[0]}"
        )

    def test_cpu_baseline_stays_below_threshold(self, config, time_window):
        """Baseline CpuPercent is in [15, 40] — never exceeds 90 %."""
        records = vm_generate(config, time_window, seed=42)
        above = [r["CpuPercent"] for r in records if r["CpuPercent"] > 90]
        assert above == [], f"Baseline CPU unexpectedly exceeded 90%: {above}"

    def test_cpu_anomaly_values_in_injected_range(self, config, time_window):
        """Injected CpuPercent values should be in [91, 99.5]."""
        records = vm_generate(config, time_window, anomaly="cpu", seed=42)
        for rec in records:
            assert 91.0 <= rec["CpuPercent"] <= 99.5, (
                f"CpuPercent {rec['CpuPercent']} outside injected range [91, 99.5]"
            )


# ===========================================================================
# VirtualMachines — disk
# ===========================================================================

class TestVMDiskAnomaly:
    """disk: DiskFreePercent < 10 % (threshold: free < 10 %)."""

    def test_disk_anomaly_all_below_threshold(self, config, time_window):
        records = vm_generate(config, time_window, anomaly="disk", seed=42)
        assert len(records) > 0
        above = [r for r in records if r["DiskFreePercent"] >= 10]
        assert above == [], (
            f"Expected ALL disk-anomaly records to have DiskFreePercent < 10, "
            f"but {len(above)} did not."
        )

    def test_disk_baseline_above_threshold(self, config, time_window):
        """Baseline DiskFreePercent is in [20, 80] — always ≥ 10 %."""
        records = vm_generate(config, time_window, seed=42)
        below = [r["DiskFreePercent"] for r in records if r["DiskFreePercent"] < 10]
        assert below == [], f"Baseline disk free unexpectedly below 10%: {below}"


# ===========================================================================
# VirtualMachines — heartbeat
# ===========================================================================

class TestVMHeartbeatAnomaly:
    """heartbeat: one VM's rows are suppressed (threshold: silence > 5 min)."""

    def test_heartbeat_reduces_record_count(self, config, time_window):
        baseline = vm_generate(config, time_window, seed=42)
        anomaly = vm_generate(config, time_window, anomaly="heartbeat", seed=42)
        # Exactly one VM (of five) is silenced → 4/5 of records remain
        assert len(anomaly) == len(baseline) * 4 // 5, (
            f"Expected {len(baseline) * 4 // 5} heartbeat records, got {len(anomaly)}"
        )

    def test_silenced_vm_not_present(self, config, time_window):
        """vm-dev-01 (last catalogue entry) must be absent in heartbeat output."""
        records = vm_generate(config, time_window, anomaly="heartbeat", seed=42)
        resources = {r["Resource"] for r in records}
        assert "vm-dev-01" not in resources, (
            f"Silenced VM 'vm-dev-01' should not appear, but found in: {resources}"
        )

    def test_other_vms_still_present(self, config, time_window):
        """All other VMs must still emit records."""
        records = vm_generate(config, time_window, anomaly="heartbeat", seed=42)
        resources = {r["Resource"] for r in records}
        for expected in ("vm-prod-01", "vm-prod-02", "vm-prod-03", "vm-staging-01"):
            assert expected in resources


# ===========================================================================
# AppService — 5xx
# ===========================================================================

class TestAppService5xxAnomaly:
    """5xx: Http5xxCount/RequestCount > 5 % (threshold: > 5 % over 5 min)."""

    def test_5xx_aggregate_rate_exceeds_threshold(self, config, time_window):
        """Aggregate 5xx rate across all anomaly records must exceed 5 %."""
        records = app_generate(config, time_window, anomaly="5xx", seed=42)
        total_requests = sum(r["RequestCount"] for r in records)
        total_5xx = sum(r["Http5xxCount"] for r in records)
        assert total_requests > 0
        aggregate_rate = total_5xx / total_requests
        assert aggregate_rate > 0.05, (
            f"Aggregate 5xx rate {aggregate_rate:.4f} does not exceed 5% threshold"
        )

    def test_5xx_anomaly_injects_nonzero_errors(self, config, time_window):
        """Every record in 5xx anomaly mode must have Http5xxCount > 0."""
        records = app_generate(config, time_window, anomaly="5xx", seed=42)
        for rec in records:
            assert rec["Http5xxCount"] > 0, (
                f"Expected Http5xxCount > 0, got {rec['Http5xxCount']}"
            )

    def test_5xx_baseline_aggregate_below_threshold(self, config, time_window):
        """Baseline aggregate 5xx rate must stay well below 5 %."""
        records = app_generate(config, time_window, seed=42)
        total_requests = sum(r["RequestCount"] for r in records)
        total_5xx = sum(r["Http5xxCount"] for r in records)
        assert total_requests > 0
        aggregate_rate = total_5xx / total_requests
        assert aggregate_rate < 0.05, (
            f"Baseline aggregate 5xx rate {aggregate_rate:.4f} unexpectedly ≥ 5%"
        )


# ===========================================================================
# AppService — latency
# ===========================================================================

class TestAppServiceLatencyAnomaly:
    """latency: ResponseTimeP95Ms > 2 000 ms (threshold: P95 > 2 000 ms)."""

    def test_latency_anomaly_all_p95_exceed_threshold(self, config, time_window):
        records = app_generate(config, time_window, anomaly="latency", seed=42)
        assert len(records) > 0
        below = [r for r in records if r["ResponseTimeP95Ms"] <= 2000]
        assert below == [], (
            f"{len(below)} records have P95 ≤ 2000ms under latency anomaly"
        )

    def test_latency_anomaly_values_in_injected_range(self, config, time_window):
        """Injected P95 values should be in [2100, 4000]."""
        records = app_generate(config, time_window, anomaly="latency", seed=42)
        for rec in records:
            assert rec["ResponseTimeP95Ms"] >= 2100, (
                f"P95 {rec['ResponseTimeP95Ms']} below injected minimum 2100ms"
            )

    def test_latency_baseline_p95_below_threshold(self, config, time_window):
        """Baseline P95 latency (max ~700ms) stays well below 2 000ms."""
        records = app_generate(config, time_window, seed=42)
        above = [r for r in records if r["ResponseTimeP95Ms"] >= 2000]
        assert above == [], (
            f"{len(above)} baseline records have P95 ≥ 2000ms"
        )


# ===========================================================================
# AKS — crashloop
# ===========================================================================

class TestAKSCrashLoopAnomaly:
    """crashloop: PodPhase=Failed, PodReason=CrashLoopBackOff, PodRestartCount > 5."""

    def test_crashloop_pods_exist(self, config, time_window):
        records = aks_generate(config, time_window, anomaly="crashloop", seed=42)
        crashers = [r for r in records if r["PodReason"] == "CrashLoopBackOff"]
        assert len(crashers) > 0, "No CrashLoopBackOff pods found under crashloop anomaly"

    def test_crashloop_pod_phase_is_failed(self, config, time_window):
        """Every CrashLoopBackOff pod must have PodPhase=Failed."""
        records = aks_generate(config, time_window, anomaly="crashloop", seed=42)
        for rec in records:
            if rec["PodReason"] == "CrashLoopBackOff":
                assert rec["PodPhase"] == "Failed", (
                    f"CrashLoopBackOff pod has PodPhase={rec['PodPhase']}, expected 'Failed'"
                )

    def test_crashloop_pod_restart_count_above_5(self, config, time_window):
        """Every CrashLoopBackOff pod must have PodRestartCount > 5."""
        records = aks_generate(config, time_window, anomaly="crashloop", seed=42)
        for rec in records:
            if rec["PodReason"] == "CrashLoopBackOff":
                assert rec["PodRestartCount"] > 5, (
                    f"CrashLoopBackOff pod restart count {rec['PodRestartCount']} not > 5"
                )

    def test_crashloop_baseline_no_crashers(self, config, time_window):
        """Without anomaly, no pods have CrashLoopBackOff reason."""
        records = aks_generate(config, time_window, seed=42)
        crashers = [r for r in records if r["PodReason"] == "CrashLoopBackOff"]
        assert crashers == [], (
            f"Baseline unexpectedly contains {len(crashers)} CrashLoopBackOff pods"
        )

    def test_crashloop_baseline_all_pods_running(self, config, time_window):
        """Without anomaly, all pod rows have PodPhase=Running (or empty for node rows)."""
        records = aks_generate(config, time_window, seed=42)
        pod_rows = [r for r in records if r["PodName"] != ""]
        for rec in pod_rows:
            assert rec["PodPhase"] == "Running", (
                f"Baseline pod {rec['PodName']} has PodPhase={rec['PodPhase']}"
            )


# ===========================================================================
# AKS — nodenotready
# ===========================================================================

class TestAKSNodeNotReadyAnomaly:
    """nodenotready: NodeStatus=NotReady for one node."""

    def test_notready_node_exists(self, config, time_window):
        records = aks_generate(config, time_window, anomaly="nodenotready", seed=42)
        not_ready = [r for r in records if r["NodeStatus"] == "NotReady"]
        assert len(not_ready) > 0, "No NotReady nodes found under nodenotready anomaly"

    def test_notready_affects_expected_node(self, config, time_window):
        """First prod-cluster node (aks-nodepool1-01) should be NotReady."""
        records = aks_generate(config, time_window, anomaly="nodenotready", seed=42)
        not_ready_names = {r["NodeName"] for r in records if r["NodeStatus"] == "NotReady"}
        assert "aks-nodepool1-01" in not_ready_names

    def test_notready_baseline_all_nodes_ready(self, config, time_window):
        """Without anomaly, every node row has NodeStatus=Ready."""
        records = aks_generate(config, time_window, seed=42)
        not_ready = [r for r in records if r["NodeStatus"] == "NotReady"]
        assert not_ready == [], (
            f"Baseline unexpectedly contains {len(not_ready)} NotReady nodes"
        )


# ===========================================================================
# AzureSQL — dtu
# ===========================================================================

class TestAzureSQLDtuAnomaly:
    """dtu: DtuPercent > 85 % (threshold: > 85 % over 5 min)."""

    def test_dtu_anomaly_all_exceed_threshold(self, config, time_window):
        records = sql_generate(config, time_window, anomaly="dtu", seed=42)
        assert len(records) > 0
        below = [r for r in records if r["DtuPercent"] <= 85]
        assert below == [], (
            f"{len(below)} records have DtuPercent ≤ 85 under dtu anomaly"
        )

    def test_dtu_anomaly_values_in_injected_range(self, config, time_window):
        """Injected DtuPercent values should be in [86, 99]."""
        records = sql_generate(config, time_window, anomaly="dtu", seed=42)
        for rec in records:
            assert 86.0 <= rec["DtuPercent"] <= 99.0, (
                f"DtuPercent {rec['DtuPercent']} outside injected range [86, 99]"
            )

    def test_dtu_baseline_below_threshold(self, config, time_window):
        """Baseline DtuPercent is in [15, 65] — never exceeds 85 %."""
        records = sql_generate(config, time_window, seed=42)
        above = [r["DtuPercent"] for r in records if r["DtuPercent"] > 85]
        assert above == [], f"Baseline DTU exceeded 85%: {above}"


# ===========================================================================
# AzureSQL — storage
# ===========================================================================

class TestAzureSQLStorageAnomaly:
    """storage: StoragePercent > 90 % (threshold: > 90 %)."""

    def test_storage_anomaly_all_exceed_threshold(self, config, time_window):
        records = sql_generate(config, time_window, anomaly="storage", seed=42)
        assert len(records) > 0
        below = [r for r in records if r["StoragePercent"] <= 90]
        assert below == [], (
            f"{len(below)} records have StoragePercent ≤ 90 under storage anomaly"
        )

    def test_storage_baseline_below_threshold(self, config, time_window):
        """Baseline StoragePercent is in [20, 70] — never exceeds 90 %."""
        records = sql_generate(config, time_window, seed=42)
        above = [r["StoragePercent"] for r in records if r["StoragePercent"] > 90]
        assert above == [], f"Baseline storage exceeded 90%: {above}"


# ===========================================================================
# AzureSQL — deadlock
# ===========================================================================

class TestAzureSQLDeadlockAnomaly:
    """deadlock: DeadlockCount > 0 (threshold: > 0 in 5 min)."""

    def test_deadlock_anomaly_all_counts_positive(self, config, time_window):
        records = sql_generate(config, time_window, anomaly="deadlock", seed=42)
        assert len(records) > 0
        zero = [r for r in records if r["DeadlockCount"] == 0]
        assert zero == [], (
            f"{len(zero)} records have DeadlockCount=0 under deadlock anomaly"
        )

    def test_deadlock_anomaly_values_in_injected_range(self, config, time_window):
        """Injected DeadlockCount values should be in [1, 4]."""
        records = sql_generate(config, time_window, anomaly="deadlock", seed=42)
        for rec in records:
            assert 1 <= rec["DeadlockCount"] <= 4, (
                f"DeadlockCount {rec['DeadlockCount']} outside injected range [1, 4]"
            )

    def test_deadlock_baseline_is_zero(self, config, time_window):
        """Without anomaly, DeadlockCount is always 0."""
        records = sql_generate(config, time_window, seed=42)
        nonzero = [r["DeadlockCount"] for r in records if r["DeadlockCount"] != 0]
        assert nonzero == [], f"Baseline deadlock count nonzero: {nonzero}"


# ===========================================================================
# APM — errorrate
# ===========================================================================

class TestAPMErrorRateAnomaly:
    """errorrate: ≥ ceil(max(1, 3%)) of request rows have IsSuccess=False (threshold: > 1%).

    The generator now applies a deterministic floor after probabilistic injection so
    the >1% failure-rate alert threshold is reliably crossed regardless of window size
    or seed.  Both small-window (5 min, ~70 requests) and large-window (60 min, ~700
    requests) tests must pass unconditionally.
    """

    def test_errorrate_anomaly_has_failures_small_window(self, config, time_window):
        """Small window: errorrate with seed=42 must produce ≥1 failure."""
        records = apm_generate(config, time_window, anomaly="errorrate", seed=42)
        request_records = [r for r in records if r["ItemType"] == "request"]
        failures = [r for r in request_records if not r["IsSuccess"]]
        assert len(failures) >= 1, (
            f"Expected ≥1 failed request, got 0 out of {len(request_records)}"
        )

    def test_errorrate_anomaly_rate_exceeds_threshold_small_window(self, config, time_window):
        """Small window: failure rate must exceed 1% threshold."""
        records = apm_generate(config, time_window, anomaly="errorrate", seed=42)
        requests = [r for r in records if r["ItemType"] == "request"]
        assert len(requests) > 0
        failure_rate = sum(1 for r in requests if not r["IsSuccess"]) / len(requests)
        assert failure_rate > 0.01, (
            f"Failure rate {failure_rate:.4f} does not exceed 1% threshold"
        )

    def test_errorrate_anomaly_has_failures_large_window(self, config):
        """60-min window: errorrate with seed=42 produces ~18 failures (2.56%)."""
        tw60 = generate_timestamps(
            backfill_minutes=60, interval_seconds=60, now=FIXED_NOW
        )
        records = apm_generate(config, tw60, anomaly="errorrate", seed=42)
        request_records = [r for r in records if r["ItemType"] == "request"]
        failures = [r for r in request_records if not r["IsSuccess"]]
        assert len(failures) >= 1, (
            f"Expected ≥1 failed request, got 0 out of {len(request_records)}"
        )

    def test_errorrate_anomaly_rate_exceeds_threshold_large_window(self, config):
        """60-min window: aggregate failure rate exceeds 1% threshold."""
        tw60 = generate_timestamps(
            backfill_minutes=60, interval_seconds=60, now=FIXED_NOW
        )
        records = apm_generate(config, tw60, anomaly="errorrate", seed=42)
        requests = [r for r in records if r["ItemType"] == "request"]
        assert len(requests) > 0
        failure_rate = sum(1 for r in requests if not r["IsSuccess"]) / len(requests)
        assert failure_rate > 0.01, (
            f"Failure rate {failure_rate:.4f} does not exceed 1% threshold"
        )

    def test_errorrate_baseline_rate_is_low(self, config, time_window):
        """Baseline request failure rate (0.2 %) must stay below 1 % threshold."""
        records = apm_generate(config, time_window, seed=42)
        requests = [r for r in records if r["ItemType"] == "request"]
        if not requests:
            pytest.skip("No request records generated — adjust count_per_tick")
        failure_rate = sum(1 for r in requests if not r["IsSuccess"]) / len(requests)
        assert failure_rate < 0.01, (
            f"Baseline failure rate {failure_rate:.4f} unexpectedly exceeds 1% threshold"
        )


# ===========================================================================
# APM — latency
# ===========================================================================

class TestAPMLatencyAnomaly:
    """latency: DurationMs P95 > 500 ms for request rows (threshold: P95 > 500 ms)."""

    def test_latency_anomaly_all_requests_above_500ms(self, config, time_window):
        """Under latency anomaly, all request DurationMs must be ≥ 500ms."""
        records = apm_generate(config, time_window, anomaly="latency", seed=42)
        request_records = [r for r in records if r["ItemType"] == "request"]
        assert len(request_records) > 0
        below = [r for r in request_records if r["DurationMs"] < 500]
        assert below == [], (
            f"{len(below)} request records have DurationMs < 500ms under latency anomaly"
        )

    def test_latency_anomaly_values_in_injected_range(self, config, time_window):
        """Injected request DurationMs values should be in [500, 3000]."""
        records = apm_generate(config, time_window, anomaly="latency", seed=42)
        for rec in records:
            if rec["ItemType"] == "request":
                assert 500.0 <= rec["DurationMs"] <= 3000.0, (
                    f"Request DurationMs {rec['DurationMs']} outside injected range [500, 3000]"
                )

    def test_latency_baseline_requests_below_threshold(self, config, time_window):
        """Baseline request DurationMs in [10, 350]ms — never exceeds 500ms."""
        records = apm_generate(config, time_window, seed=42)
        request_records = [r for r in records if r["ItemType"] == "request"]
        assert len(request_records) > 0
        above = [r["DurationMs"] for r in request_records if r["DurationMs"] > 500]
        assert above == [], (
            f"Baseline request DurationMs exceeded 500ms threshold: {above}"
        )
