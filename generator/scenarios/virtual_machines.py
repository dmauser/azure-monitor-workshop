"""virtual_machines — telemetry generator for the VirtualMachines_CL table.

Supported anomaly keys
----------------------
cpu        : Inject CpuPercent > 90 % for all VMs (threshold > 90 % over 5 min)
disk       : Inject DiskFreePercent < 10 % for all VMs (threshold < 10 %)
heartbeat  : Suppress all rows for one VM, simulating a missing heartbeat
             (threshold > 5 min silence)
"""

from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.models import VirtualMachineRecord

# ---------------------------------------------------------------------------
# Static resource catalogue
# ---------------------------------------------------------------------------

_VMS = [
    {"name": "vm-prod-01",   "os": "Linux",   "env": "prod",    "mem_total": 16384.0},
    {"name": "vm-prod-02",   "os": "Linux",   "env": "prod",    "mem_total": 16384.0},
    {"name": "vm-prod-03",   "os": "Windows", "env": "prod",    "mem_total": 32768.0},
    {"name": "vm-staging-01","os": "Linux",   "env": "staging", "mem_total": 8192.0},
    {"name": "vm-dev-01",    "os": "Linux",   "env": "dev",     "mem_total": 4096.0},
]


def _arm_id(sub: str, rg: str, name: str) -> str:
    return (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Compute/virtualMachines/{name}"
    )


def generate(
    config: LabConfig,
    time_window: List[datetime],
    *,
    anomaly: Optional[str] = None,
    seed: Optional[int] = None,
    count_per_tick: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Generate VirtualMachines_CL records.

    One row per VM per tick in *time_window*.  Anomaly keys: cpu, disk, heartbeat.
    """
    rng = random.Random(seed)
    sub = config.subscription_id or "00000000-0000-0000-0000-000000000000"
    rg = config.resource_group or "rg-amlab"
    region = config.location or "southcentralus"

    # heartbeat anomaly: silence the last VM in the list
    silenced: str = _VMS[-1]["name"] if anomaly == "heartbeat" else ""

    records: List[Dict[str, Any]] = []

    for ts in time_window:
        for vm in _VMS:
            if vm["name"] == silenced:
                continue  # simulate missing heartbeat

            mem_total: float = vm["mem_total"]

            if anomaly == "cpu":
                cpu = rng.uniform(91.0, 99.5)
            else:
                cpu = rng.uniform(15.0, 40.0)

            if anomaly == "disk":
                disk_free = rng.uniform(1.0, 9.5)
            else:
                disk_free = rng.uniform(20.0, 80.0)

            mem_used_pct = rng.uniform(0.30, 0.65)
            mem_available = round(mem_total * (1.0 - mem_used_pct), 1)

            rec = VirtualMachineRecord(
                TimeGenerated=ts,
                Resource=vm["name"],
                ResourceId=_arm_id(sub, rg, vm["name"]),
                Environment=vm["env"],
                Region=region,
                OSType=vm["os"],
                CpuPercent=round(cpu, 2),
                MemoryAvailableMB=mem_available,
                MemoryTotalMB=mem_total,
                DiskName="C:" if vm["os"] == "Windows" else "/",
                DiskFreePercent=round(disk_free, 2),
                NetworkInBytes=rng.randint(100_000, 5_000_000),
                NetworkOutBytes=rng.randint(50_000, 2_000_000),
            )
            records.append(rec.to_dict())

    return records
