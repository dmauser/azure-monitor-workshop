"""aks — telemetry generator for the AKS_CL table.

Row granularity: one row per pod OR per node per tick.
Node-level rows: PodName="" ContainerName="" Namespace=""
Pod-level rows:  NodeName populated, PodName populated

Supported anomaly keys
----------------------
crashloop    : One pod emits PodPhase="Failed", PodReason="CrashLoopBackOff",
               PodRestartCount > 5  (threshold: any pod in 5 min)
nodenotready : One node emits NodeStatus="NotReady"
               (threshold: any node in 5 min)
"""

from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.models import AKSRecord

# ---------------------------------------------------------------------------
# Static resource catalogue
# ---------------------------------------------------------------------------

_CLUSTERS = [
    {
        "name": "aks-prod-01",
        "env": "prod",
        "nodes": ["aks-nodepool1-01", "aks-nodepool1-02", "aks-nodepool1-03"],
        "pods": [
            {"namespace": "default",    "pod": "api-deployment-abc12", "container": "api"},
            {"namespace": "default",    "pod": "api-deployment-def34", "container": "api"},
            {"namespace": "default",    "pod": "worker-deployment-gh56", "container": "worker"},
            {"namespace": "monitoring", "pod": "prometheus-0",          "container": "prometheus"},
            {"namespace": "monitoring", "pod": "grafana-6789",          "container": "grafana"},
            {"namespace": "ingress",    "pod": "nginx-ingress-abc12",   "container": "controller"},
        ],
    },
    {
        "name": "aks-staging-01",
        "env": "staging",
        "nodes": ["aks-nodepool1-01", "aks-nodepool1-02"],
        "pods": [
            {"namespace": "default",    "pod": "api-deployment-xy01",  "container": "api"},
            {"namespace": "default",    "pod": "worker-deployment-yz02","container": "worker"},
        ],
    },
]


def _arm_id(sub: str, rg: str, name: str) -> str:
    return (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.ContainerService/managedClusters/{name}"
    )


def generate(
    config: LabConfig,
    time_window: List[datetime],
    *,
    anomaly: Optional[str] = None,
    seed: Optional[int] = None,
    count_per_tick: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Generate AKS_CL records (mix of node + pod rows per tick).

    Anomaly keys: crashloop, nodenotready.
    """
    rng = random.Random(seed)
    sub = config.subscription_id or "00000000-0000-0000-0000-000000000000"
    rg = config.resource_group or "rg-amlab"
    region = config.location or "southcentralus"

    records: List[Dict[str, Any]] = []

    for ts in time_window:
        for cluster in _CLUSTERS:
            arm_id = _arm_id(sub, rg, cluster["name"])
            env = cluster["env"]

            # --- Node rows ---------------------------------------------------
            for i, node_name in enumerate(cluster["nodes"]):
                # nodenotready anomaly: first node of prod cluster is NotReady
                if anomaly == "nodenotready" and env == "prod" and i == 0:
                    node_status = "NotReady"
                else:
                    node_status = "Ready"

                rec = AKSRecord(
                    TimeGenerated=ts,
                    Resource=cluster["name"],
                    ResourceId=arm_id,
                    Environment=env,
                    Region=region,
                    Namespace="",
                    NodeName=node_name,
                    PodName="",
                    ContainerName="",
                    NodeCpuPercent=round(rng.uniform(10.0, 55.0), 2),
                    NodeMemoryPercent=round(rng.uniform(20.0, 65.0), 2),
                    PodCpuPercent=0.0,
                    PodMemoryPercent=0.0,
                    PodRestartCount=0,
                    PodPhase="Running",
                    PodReason="",
                    NodeStatus=node_status,
                    PVName="",
                    PVUsagePercent=0.0,
                    HpaName="",
                    HpaCurrentReplicas=0,
                    HpaMaxReplicas=0,
                )
                records.append(rec.to_dict())

            # --- Pod rows ----------------------------------------------------
            nodes = cluster["nodes"]
            for j, pod_info in enumerate(cluster["pods"]):
                node_name = nodes[j % len(nodes)]

                # crashloop anomaly: first pod of prod cluster is crashing
                if anomaly == "crashloop" and env == "prod" and j == 0:
                    pod_phase = "Failed"
                    pod_reason = "CrashLoopBackOff"
                    restart_count = rng.randint(6, 20)
                else:
                    pod_phase = "Running"
                    pod_reason = ""
                    restart_count = rng.randint(0, 1)

                has_pv = pod_info["namespace"] == "monitoring"
                pv_name = f"pvc-{pod_info['pod']}" if has_pv else ""
                pv_usage = round(rng.uniform(20.0, 70.0), 2) if has_pv else 0.0

                has_hpa = pod_info["container"] == "api"
                hpa_name = f"hpa-{pod_info['container']}" if has_hpa else ""
                hpa_current = rng.randint(2, 5) if has_hpa else 0
                hpa_max = 10 if has_hpa else 0

                rec = AKSRecord(
                    TimeGenerated=ts,
                    Resource=cluster["name"],
                    ResourceId=arm_id,
                    Environment=env,
                    Region=region,
                    Namespace=pod_info["namespace"],
                    NodeName=node_name,
                    PodName=pod_info["pod"],
                    ContainerName=pod_info["container"],
                    NodeCpuPercent=round(rng.uniform(10.0, 55.0), 2),
                    NodeMemoryPercent=round(rng.uniform(20.0, 65.0), 2),
                    PodCpuPercent=round(rng.uniform(1.0, 30.0), 2),
                    PodMemoryPercent=round(rng.uniform(5.0, 40.0), 2),
                    PodRestartCount=restart_count,
                    PodPhase=pod_phase,
                    PodReason=pod_reason,
                    NodeStatus="Ready",
                    PVName=pv_name,
                    PVUsagePercent=pv_usage,
                    HpaName=hpa_name,
                    HpaCurrentReplicas=hpa_current,
                    HpaMaxReplicas=hpa_max,
                )
                records.append(rec.to_dict())

    return records
