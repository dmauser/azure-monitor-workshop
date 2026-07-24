"""Dataclass models for each scenario table.

Column names and types match mouse-kql-schema.md exactly (PascalCase, KQL types
mapped to Python: datetime→datetime, string→str, real→float, int/long→int,
bool→bool).  Each model's .to_dict() emits the JSON record expected by the DCE
Logs Ingestion API, with TimeGenerated serialised as ISO-8601 UTC.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    """Return dt as ISO-8601 UTC string."""
    return dt.astimezone(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# VirtualMachines_CL
# ---------------------------------------------------------------------------

@dataclass
class VirtualMachineRecord:
    Resource: str
    ResourceId: str
    Environment: str
    Region: str
    OSType: str
    CpuPercent: float
    MemoryAvailableMB: float
    MemoryTotalMB: float
    DiskName: str
    DiskFreePercent: float
    NetworkInBytes: int
    NetworkOutBytes: int
    TimeGenerated: datetime = field(default_factory=_now_utc)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "TimeGenerated": _iso(self.TimeGenerated),
            "Resource": self.Resource,
            "ResourceId": self.ResourceId,
            "Environment": self.Environment,
            "Region": self.Region,
            "OSType": self.OSType,
            "CpuPercent": float(self.CpuPercent),
            "MemoryAvailableMB": float(self.MemoryAvailableMB),
            "MemoryTotalMB": float(self.MemoryTotalMB),
            "DiskName": self.DiskName,
            "DiskFreePercent": float(self.DiskFreePercent),
            "NetworkInBytes": int(self.NetworkInBytes),
            "NetworkOutBytes": int(self.NetworkOutBytes),
        }


# ---------------------------------------------------------------------------
# AppService_CL
# ---------------------------------------------------------------------------

@dataclass
class AppServiceRecord:
    Resource: str
    ResourceId: str
    Environment: str
    Region: str
    AppName: str
    RequestCount: int
    ResponseTimeMs: float
    ResponseTimeP95Ms: float
    Http2xxCount: int
    Http4xxCount: int
    Http5xxCount: int
    RestartCount: int
    PlanCpuPercent: float
    PlanMemoryPercent: float
    TimeGenerated: datetime = field(default_factory=_now_utc)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "TimeGenerated": _iso(self.TimeGenerated),
            "Resource": self.Resource,
            "ResourceId": self.ResourceId,
            "Environment": self.Environment,
            "Region": self.Region,
            "AppName": self.AppName,
            "RequestCount": int(self.RequestCount),
            "ResponseTimeMs": float(self.ResponseTimeMs),
            "ResponseTimeP95Ms": float(self.ResponseTimeP95Ms),
            "Http2xxCount": int(self.Http2xxCount),
            "Http4xxCount": int(self.Http4xxCount),
            "Http5xxCount": int(self.Http5xxCount),
            "RestartCount": int(self.RestartCount),
            "PlanCpuPercent": float(self.PlanCpuPercent),
            "PlanMemoryPercent": float(self.PlanMemoryPercent),
        }


# ---------------------------------------------------------------------------
# AKS_CL
# ---------------------------------------------------------------------------

@dataclass
class AKSRecord:
    Resource: str
    ResourceId: str
    Environment: str
    Region: str
    Namespace: str
    NodeName: str
    PodName: str
    ContainerName: str
    NodeCpuPercent: float
    NodeMemoryPercent: float
    PodCpuPercent: float
    PodMemoryPercent: float
    PodRestartCount: int
    PodPhase: str
    PodReason: str
    NodeStatus: str
    PVName: str
    PVUsagePercent: float
    HpaName: str
    HpaCurrentReplicas: int
    HpaMaxReplicas: int
    TimeGenerated: datetime = field(default_factory=_now_utc)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "TimeGenerated": _iso(self.TimeGenerated),
            "Resource": self.Resource,
            "ResourceId": self.ResourceId,
            "Environment": self.Environment,
            "Region": self.Region,
            "Namespace": self.Namespace,
            "NodeName": self.NodeName,
            "PodName": self.PodName,
            "ContainerName": self.ContainerName,
            "NodeCpuPercent": float(self.NodeCpuPercent),
            "NodeMemoryPercent": float(self.NodeMemoryPercent),
            "PodCpuPercent": float(self.PodCpuPercent),
            "PodMemoryPercent": float(self.PodMemoryPercent),
            "PodRestartCount": int(self.PodRestartCount),
            "PodPhase": self.PodPhase,
            "PodReason": self.PodReason,
            "NodeStatus": self.NodeStatus,
            "PVName": self.PVName,
            "PVUsagePercent": float(self.PVUsagePercent),
            "HpaName": self.HpaName,
            "HpaCurrentReplicas": int(self.HpaCurrentReplicas),
            "HpaMaxReplicas": int(self.HpaMaxReplicas),
        }


# ---------------------------------------------------------------------------
# AzureSQL_CL
# ---------------------------------------------------------------------------

@dataclass
class AzureSQLRecord:
    Resource: str
    ResourceId: str
    Environment: str
    Region: str
    DatabaseName: str
    DtuPercent: float
    CpuPercent: float
    WorkerPercent: float
    ActiveConnections: int
    FailedConnections: int
    DeadlockCount: int
    StoragePercent: float
    StorageUsedMB: int
    StorageLimitMB: int
    QueryDurationMs: float
    QueryDurationP95Ms: float
    TimeGenerated: datetime = field(default_factory=_now_utc)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "TimeGenerated": _iso(self.TimeGenerated),
            "Resource": self.Resource,
            "ResourceId": self.ResourceId,
            "Environment": self.Environment,
            "Region": self.Region,
            "DatabaseName": self.DatabaseName,
            "DtuPercent": float(self.DtuPercent),
            "CpuPercent": float(self.CpuPercent),
            "WorkerPercent": float(self.WorkerPercent),
            "ActiveConnections": int(self.ActiveConnections),
            "FailedConnections": int(self.FailedConnections),
            "DeadlockCount": int(self.DeadlockCount),
            "StoragePercent": float(self.StoragePercent),
            "StorageUsedMB": int(self.StorageUsedMB),
            "StorageLimitMB": int(self.StorageLimitMB),
            "QueryDurationMs": float(self.QueryDurationMs),
            "QueryDurationP95Ms": float(self.QueryDurationP95Ms),
        }


# ---------------------------------------------------------------------------
# APM_CL
# ---------------------------------------------------------------------------

@dataclass
class APMRecord:
    Resource: str
    ResourceId: str
    Environment: str
    Region: str
    ItemType: str
    OperationName: str
    DurationMs: float
    IsSuccess: bool
    ExceptionType: str
    ExceptionMessage: str
    DependencyType: str
    DependencyTarget: str
    DependencySuccess: bool
    DependencyDurationMs: float
    SeverityLevel: int
    TraceId: str
    SpanId: str
    TimeGenerated: datetime = field(default_factory=_now_utc)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "TimeGenerated": _iso(self.TimeGenerated),
            "Resource": self.Resource,
            "ResourceId": self.ResourceId,
            "Environment": self.Environment,
            "Region": self.Region,
            "ItemType": self.ItemType,
            "OperationName": self.OperationName,
            "DurationMs": float(self.DurationMs),
            "IsSuccess": bool(self.IsSuccess),
            "ExceptionType": self.ExceptionType,
            "ExceptionMessage": self.ExceptionMessage,
            "DependencyType": self.DependencyType,
            "DependencyTarget": self.DependencyTarget,
            "DependencySuccess": bool(self.DependencySuccess),
            "DependencyDurationMs": float(self.DependencyDurationMs),
            "SeverityLevel": int(self.SeverityLevel),
            "TraceId": self.TraceId,
            "SpanId": self.SpanId,
        }
