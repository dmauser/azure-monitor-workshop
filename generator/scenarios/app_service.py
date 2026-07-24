"""app_service — telemetry generator for the AppService_CL table.

Supported anomaly keys
----------------------
5xx      : Inject Http5xxCount > 5 % of RequestCount (threshold > 5 % over 5 min)
latency  : Inject ResponseTimeP95Ms > 2 000 ms (threshold > 2 000 ms)
"""

from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.models import AppServiceRecord

# ---------------------------------------------------------------------------
# Static resource catalogue
# ---------------------------------------------------------------------------

_APPS = [
    {"resource": "app-prod-api",     "app_name": "api-service",   "env": "prod"},
    {"resource": "app-prod-web",     "app_name": "web-frontend",  "env": "prod"},
    {"resource": "app-prod-worker",  "app_name": "background-worker", "env": "prod"},
    {"resource": "app-staging-api",  "app_name": "api-service",   "env": "staging"},
]


def _arm_id(sub: str, rg: str, name: str) -> str:
    return (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Web/sites/{name}"
    )


def generate(
    config: LabConfig,
    time_window: List[datetime],
    *,
    anomaly: Optional[str] = None,
    seed: Optional[int] = None,
    count_per_tick: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Generate AppService_CL records.

    One row per App Service per tick in *time_window*.  Anomaly keys: 5xx, latency.
    """
    rng = random.Random(seed)
    sub = config.subscription_id or "00000000-0000-0000-0000-000000000000"
    rg = config.resource_group or "rg-amlab"
    region = config.location or "southcentralus"

    records: List[Dict[str, Any]] = []

    for ts in time_window:
        for app in _APPS:
            request_count = rng.randint(80, 600)

            if anomaly == "latency":
                p95_ms = rng.uniform(2100.0, 4000.0)
                mean_ms = p95_ms * rng.uniform(0.35, 0.55)
            else:
                mean_ms = rng.uniform(40.0, 250.0)
                p95_ms = mean_ms * rng.uniform(1.5, 2.8)

            if anomaly == "5xx":
                rate_5xx = rng.uniform(0.06, 0.12)
            else:
                rate_5xx = rng.uniform(0.001, 0.008)

            rate_4xx = rng.uniform(0.01, 0.04)
            count_5xx = max(0, int(request_count * rate_5xx))
            count_4xx = max(0, int(request_count * rate_4xx))
            count_2xx = max(0, request_count - count_4xx - count_5xx)
            restart = 1 if rng.random() < 0.02 else 0

            rec = AppServiceRecord(
                TimeGenerated=ts,
                Resource=app["resource"],
                ResourceId=_arm_id(sub, rg, app["resource"]),
                Environment=app["env"],
                Region=region,
                AppName=app["app_name"],
                RequestCount=request_count,
                ResponseTimeMs=round(mean_ms, 2),
                ResponseTimeP95Ms=round(p95_ms, 2),
                Http2xxCount=count_2xx,
                Http4xxCount=count_4xx,
                Http5xxCount=count_5xx,
                RestartCount=restart,
                PlanCpuPercent=round(rng.uniform(8.0, 45.0), 2),
                PlanMemoryPercent=round(rng.uniform(15.0, 55.0), 2),
            )
            records.append(rec.to_dict())

    return records
