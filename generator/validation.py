"""validation — validate a record dict against the expected column contract.

Returns a list of human-readable error strings (empty list = valid).
Used by tests and as a pre-send gate in ingestion_client.py.
"""

from __future__ import annotations

from typing import Any, Dict, List, Tuple, Type

# ---------------------------------------------------------------------------
# Column contracts: (name, python_type, range_check_fn | None)
# range_check_fn(value) returns an error string or "" if OK.
# ---------------------------------------------------------------------------

def _pct(col: str):
    def check(v: Any) -> str:
        try:
            f = float(v)
        except (TypeError, ValueError):
            return f"{col}: cannot coerce '{v}' to float"
        if not (0.0 <= f <= 100.0):
            return f"{col}: value {f} is outside [0, 100]"
        return ""
    return check


def _nonneg(col: str, typ: Type):
    def check(v: Any) -> str:
        try:
            n = typ(v)
        except (TypeError, ValueError):
            return f"{col}: cannot coerce '{v}' to {typ.__name__}"
        if n < 0:
            return f"{col}: value {n} is negative"
        return ""
    return check


def _severity(col: str):
    def check(v: Any) -> str:
        try:
            i = int(v)
        except (TypeError, ValueError):
            return f"{col}: cannot coerce '{v}' to int"
        if i not in (0, 1, 2, 3, 4):
            return f"{col}: severity {i} not in {{0,1,2,3,4}}"
        return ""
    return check


def _coercible(col: str, typ: Type):
    def check(v: Any) -> str:
        try:
            typ(v)
        except (TypeError, ValueError):
            return f"{col}: cannot coerce '{v}' to {typ.__name__}"
        return ""
    return check


# Schema: list of (column_name, type, validator_fn | None)
_SCHEMA: Dict[str, List[Tuple[str, Type, Any]]] = {
    "virtualmachines": [
        ("TimeGenerated", str, _coercible("TimeGenerated", str)),
        ("Resource", str, None),
        ("ResourceId", str, None),
        ("Environment", str, None),
        ("Region", str, None),
        ("OSType", str, None),
        ("CpuPercent", float, _pct("CpuPercent")),
        ("MemoryAvailableMB", float, _nonneg("MemoryAvailableMB", float)),
        ("MemoryTotalMB", float, _nonneg("MemoryTotalMB", float)),
        ("DiskName", str, None),
        ("DiskFreePercent", float, _pct("DiskFreePercent")),
        ("NetworkInBytes", int, _nonneg("NetworkInBytes", int)),
        ("NetworkOutBytes", int, _nonneg("NetworkOutBytes", int)),
    ],
    "appservice": [
        ("TimeGenerated", str, None),
        ("Resource", str, None),
        ("ResourceId", str, None),
        ("Environment", str, None),
        ("Region", str, None),
        ("AppName", str, None),
        ("RequestCount", int, _nonneg("RequestCount", int)),
        ("ResponseTimeMs", float, _nonneg("ResponseTimeMs", float)),
        ("ResponseTimeP95Ms", float, _nonneg("ResponseTimeP95Ms", float)),
        ("Http2xxCount", int, _nonneg("Http2xxCount", int)),
        ("Http4xxCount", int, _nonneg("Http4xxCount", int)),
        ("Http5xxCount", int, _nonneg("Http5xxCount", int)),
        ("RestartCount", int, _nonneg("RestartCount", int)),
        ("PlanCpuPercent", float, _pct("PlanCpuPercent")),
        ("PlanMemoryPercent", float, _pct("PlanMemoryPercent")),
    ],
    "aks": [
        ("TimeGenerated", str, None),
        ("Resource", str, None),
        ("ResourceId", str, None),
        ("Environment", str, None),
        ("Region", str, None),
        ("Namespace", str, None),
        ("NodeName", str, None),
        ("PodName", str, None),
        ("ContainerName", str, None),
        ("NodeCpuPercent", float, _pct("NodeCpuPercent")),
        ("NodeMemoryPercent", float, _pct("NodeMemoryPercent")),
        ("PodCpuPercent", float, _pct("PodCpuPercent")),
        ("PodMemoryPercent", float, _pct("PodMemoryPercent")),
        ("PodRestartCount", int, _nonneg("PodRestartCount", int)),
        ("PodPhase", str, None),
        ("PodReason", str, None),
        ("NodeStatus", str, None),
        ("PVName", str, None),
        ("PVUsagePercent", float, _pct("PVUsagePercent")),
        ("HpaName", str, None),
        ("HpaCurrentReplicas", int, _nonneg("HpaCurrentReplicas", int)),
        ("HpaMaxReplicas", int, _nonneg("HpaMaxReplicas", int)),
    ],
    "azuresql": [
        ("TimeGenerated", str, None),
        ("Resource", str, None),
        ("ResourceId", str, None),
        ("Environment", str, None),
        ("Region", str, None),
        ("DatabaseName", str, None),
        ("DtuPercent", float, _pct("DtuPercent")),
        ("CpuPercent", float, _pct("CpuPercent")),
        ("WorkerPercent", float, _pct("WorkerPercent")),
        ("ActiveConnections", int, _nonneg("ActiveConnections", int)),
        ("FailedConnections", int, _nonneg("FailedConnections", int)),
        ("DeadlockCount", int, _nonneg("DeadlockCount", int)),
        ("StoragePercent", float, _pct("StoragePercent")),
        ("StorageUsedMB", int, _nonneg("StorageUsedMB", int)),
        ("StorageLimitMB", int, _nonneg("StorageLimitMB", int)),
        ("QueryDurationMs", float, _nonneg("QueryDurationMs", float)),
        ("QueryDurationP95Ms", float, _nonneg("QueryDurationP95Ms", float)),
    ],
    "apm": [
        ("TimeGenerated", str, None),
        ("Resource", str, None),
        ("ResourceId", str, None),
        ("Environment", str, None),
        ("Region", str, None),
        ("ItemType", str, None),
        ("OperationName", str, None),
        ("DurationMs", float, _nonneg("DurationMs", float)),
        ("IsSuccess", bool, _coercible("IsSuccess", bool)),
        ("ExceptionType", str, None),
        ("ExceptionMessage", str, None),
        ("DependencyType", str, None),
        ("DependencyTarget", str, None),
        ("DependencySuccess", bool, _coercible("DependencySuccess", bool)),
        ("DependencyDurationMs", float, _nonneg("DependencyDurationMs", float)),
        ("SeverityLevel", int, _severity("SeverityLevel")),
        ("TraceId", str, None),
        ("SpanId", str, None),
    ],
}


def validate_record(scenario_key: str, record: Dict[str, Any]) -> List[str]:
    """Validate *record* against the schema for *scenario_key*.

    Returns a list of error strings (empty = valid).
    """
    schema = _SCHEMA.get(scenario_key)
    if schema is None:
        return [f"Unknown scenario key: '{scenario_key}'"]

    errors: List[str] = []
    for col, _typ, checker in schema:
        if col not in record:
            errors.append(f"Missing column: '{col}'")
            continue
        if checker is not None:
            msg = checker(record[col])
            if msg:
                errors.append(msg)
    return errors


def required_columns(scenario_key: str) -> List[str]:
    """Return the ordered list of required column names for a scenario."""
    schema = _SCHEMA.get(scenario_key, [])
    return [col for col, _, _ in schema]
