"""apm — telemetry generator for the APM_CL table.

Row granularity: one row per individual telemetry event (not pre-aggregated).
Event mix per tick: ~60 % requests · ~25 % dependencies · ~5 % exceptions · ~10 % traces.

Supported anomaly keys
----------------------
errorrate  : > 1 % of request rows have IsSuccess=False
             (threshold > 1 % failure rate over 5 min)
latency    : DurationMs P95 > 500 ms for request rows
             (threshold P95 > 500 ms)
"""

from __future__ import annotations

import math
import random
import secrets
from datetime import datetime
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.models import APMRecord

# ---------------------------------------------------------------------------
# Static resource catalogue
# ---------------------------------------------------------------------------

_SERVICES = [
    {"name": "svc-checkout",  "env": "prod"},
    {"name": "svc-orders",    "env": "prod"},
    {"name": "svc-inventory", "env": "prod"},
    {"name": "svc-users",     "env": "staging"},
]

_OPERATIONS = [
    "GET /api/orders",
    "POST /api/orders",
    "GET /api/users/{id}",
    "PUT /api/users/{id}",
    "GET /api/products",
    "POST /api/checkout",
    "DELETE /api/cart/{id}",
    "GET /api/inventory",
    "POST /api/payments",
]

_EXCEPTION_TYPES = [
    "System.NullReferenceException",
    "System.TimeoutException",
    "System.InvalidOperationException",
    "Microsoft.Data.SqlClient.SqlException",
    "System.Net.Http.HttpRequestException",
]

_DEP_TYPES = ["HTTP", "SQL", "ServiceBus", "Redis"]
_DEP_TARGETS: Dict[str, List[str]] = {
    "HTTP":        ["https://api.partner.com", "https://auth.internal"],
    "SQL":         ["sql-prod-01.database.windows.net", "sql-prod-02.database.windows.net"],
    "ServiceBus":  ["sb-prod.servicebus.windows.net"],
    "Redis":       ["redis-prod.redis.cache.windows.net"],
}

_DEFAULT_COUNT_PER_TICK = 20


def _arm_id(sub: str, rg: str, name: str) -> str:
    return (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Web/sites/{name}"
    )


def _trace_id(rng: random.Random) -> str:
    return "".join(f"{rng.randint(0, 255):02x}" for _ in range(16))


def _span_id(rng: random.Random) -> str:
    return "".join(f"{rng.randint(0, 255):02x}" for _ in range(8))


def generate(
    config: LabConfig,
    time_window: List[datetime],
    *,
    anomaly: Optional[str] = None,
    seed: Optional[int] = None,
    count_per_tick: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Generate APM_CL records.

    *count_per_tick* events are emitted per timestamp (default 20), spread
    across the configured services.  Anomaly keys: errorrate, latency.
    """
    rng = random.Random(seed)
    sub = config.subscription_id or "00000000-0000-0000-0000-000000000000"
    rg = config.resource_group or "rg-amlab"
    region = config.location or "southcentralus"
    n_per_tick = count_per_tick or _DEFAULT_COUNT_PER_TICK

    records: List[Dict[str, Any]] = []

    for ts in time_window:
        for _ in range(n_per_tick):
            svc = rng.choice(_SERVICES)
            arm_id = _arm_id(sub, rg, svc["name"])
            operation = rng.choice(_OPERATIONS)

            # Choose event type by weighted random
            roll = rng.random()
            if roll < 0.60:
                item_type = "request"
            elif roll < 0.85:
                item_type = "dependency"
            elif roll < 0.90:
                item_type = "exception"
            else:
                item_type = "trace"

            # Defaults (overridden per type below)
            duration_ms = 0.0
            is_success = True
            exc_type = ""
            exc_msg = ""
            dep_type = ""
            dep_target = ""
            dep_success = True
            dep_duration_ms = 0.0
            severity = 1
            trace_id = _trace_id(rng)
            span_id = _span_id(rng)

            if item_type == "request":
                if anomaly == "latency":
                    duration_ms = rng.uniform(500.0, 3000.0)
                else:
                    duration_ms = rng.uniform(10.0, 350.0)

                if anomaly == "errorrate":
                    # Probabilistic pass; deterministic floor applied after the loop.
                    is_success = rng.random() > 0.02
                else:
                    is_success = rng.random() > 0.002  # ~0.2 % normal
                severity = 1

            elif item_type == "dependency":
                dep_type = rng.choice(_DEP_TYPES)
                dep_target = rng.choice(_DEP_TARGETS[dep_type])
                dep_duration_ms = round(rng.uniform(2.0, 80.0), 2)
                dep_success = rng.random() > 0.005
                is_success = dep_success
                severity = 1

            elif item_type == "exception":
                exc_type = rng.choice(_EXCEPTION_TYPES)
                exc_msg = f"Unhandled exception in {operation}: {exc_type.split('.')[-1]}"
                is_success = False
                severity = 3

            else:  # trace
                severity = rng.choice([0, 1, 2])
                is_success = True

            rec = APMRecord(
                TimeGenerated=ts,
                Resource=svc["name"],
                ResourceId=arm_id,
                Environment=svc["env"],
                Region=region,
                ItemType=item_type,
                OperationName=operation,
                DurationMs=round(duration_ms, 2),
                IsSuccess=is_success,
                ExceptionType=exc_type,
                ExceptionMessage=exc_msg,
                DependencyType=dep_type,
                DependencyTarget=dep_target,
                DependencySuccess=dep_success,
                DependencyDurationMs=dep_duration_ms,
                SeverityLevel=severity,
                TraceId=trace_id,
                SpanId=span_id,
            )
            records.append(rec.to_dict())

    # Deterministic floor for errorrate anomaly: guarantee ≥ ceil(max(1, 3%)) failures
    # so the >1% alert threshold is reliably crossed even in small windows.
    if anomaly == "errorrate":
        request_rows = [r for r in records if r["ItemType"] == "request"]
        actual_failures = sum(1 for r in request_rows if not r["IsSuccess"])
        n_required = math.ceil(max(1, 0.03 * len(request_rows)))
        if actual_failures < n_required:
            deficit = n_required - actual_failures
            for r in request_rows:
                if deficit == 0:
                    break
                if r["IsSuccess"]:
                    r["IsSuccess"] = False
                    deficit -= 1

    return records
