"""azure_sql — telemetry generator for the AzureSQL_CL table.

Supported anomaly keys
----------------------
dtu       : Inject DtuPercent > 85 % (threshold > 85 % over 5 min)
storage   : Inject StoragePercent > 90 % (threshold > 90 %)
deadlock  : Inject DeadlockCount > 0 (threshold > 0 in 5 min)
"""

from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.models import AzureSQLRecord

# ---------------------------------------------------------------------------
# Static resource catalogue
# ---------------------------------------------------------------------------

_SERVERS = [
    {
        "name": "sql-prod-01",
        "env": "prod",
        "databases": ["db-main", "db-analytics", "db-reporting"],
        "storage_limit_mb": 102_400,
    },
    {
        "name": "sql-prod-02",
        "env": "prod",
        "databases": ["db-orders"],
        "storage_limit_mb": 51_200,
    },
    {
        "name": "sql-staging-01",
        "env": "staging",
        "databases": ["db-main"],
        "storage_limit_mb": 20_480,
    },
]


def _arm_id(sub: str, rg: str, server: str) -> str:
    return (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Sql/servers/{server}"
    )


def generate(
    config: LabConfig,
    time_window: List[datetime],
    *,
    anomaly: Optional[str] = None,
    seed: Optional[int] = None,
    count_per_tick: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Generate AzureSQL_CL records.

    One row per database per tick in *time_window*.  Anomaly keys: dtu, storage, deadlock.
    """
    rng = random.Random(seed)
    sub = config.subscription_id or "00000000-0000-0000-0000-000000000000"
    rg = config.resource_group or "rg-amlab"
    region = config.location or "southcentralus"

    records: List[Dict[str, Any]] = []

    for ts in time_window:
        for server in _SERVERS:
            arm_id = _arm_id(sub, rg, server["name"])
            env = server["env"]
            limit_mb: int = server["storage_limit_mb"]

            for db_name in server["databases"]:

                if anomaly == "dtu":
                    dtu = rng.uniform(86.0, 99.0)
                else:
                    dtu = rng.uniform(15.0, 65.0)

                if anomaly == "storage":
                    storage_pct = rng.uniform(91.0, 99.0)
                else:
                    storage_pct = rng.uniform(20.0, 70.0)

                deadlock_count = rng.randint(1, 4) if anomaly == "deadlock" else 0

                storage_used_mb = int(limit_mb * storage_pct / 100.0)
                mean_q = rng.uniform(8.0, 120.0)
                p95_q = mean_q * rng.uniform(1.8, 4.0)

                rec = AzureSQLRecord(
                    TimeGenerated=ts,
                    Resource=server["name"],
                    ResourceId=arm_id,
                    Environment=env,
                    Region=region,
                    DatabaseName=db_name,
                    DtuPercent=round(dtu, 2),
                    CpuPercent=round(rng.uniform(10.0, 45.0), 2),
                    WorkerPercent=round(rng.uniform(3.0, 30.0), 2),
                    ActiveConnections=rng.randint(3, 60),
                    FailedConnections=rng.randint(0, 3),
                    DeadlockCount=deadlock_count,
                    StoragePercent=round(storage_pct, 2),
                    StorageUsedMB=storage_used_mb,
                    StorageLimitMB=limit_mb,
                    QueryDurationMs=round(mean_q, 2),
                    QueryDurationP95Ms=round(p95_q, 2),
                )
                records.append(rec.to_dict())

    return records
