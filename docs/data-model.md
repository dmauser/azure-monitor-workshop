# Data Model: Custom Table Schemas

> **Last updated:** 2026-07-15  
> **Source of truth:** `.squad/decisions/inbox/mouse-kql-schema.md` (column names, types, semantics) + `.squad/decisions/inbox/tank-tables-dcr.md` (confirmed Bicep types)  
> All column names are **PascalCase**. No `_s` / `_d` / `_b` suffixes (Logs Ingestion API — not the legacy HTTP Data Collector API).

---

## Scenario Key Contract

Every scenario has three representations that must be consistent across Bicep, environment variables, and table/stream names.

| Bicep array key | `lab.env` UPPER_SNAKE | PascalCase (table) | Stream name | Table name |
|---|---|---|---|---|
| `virtualmachines` | `VIRTUAL_MACHINES` | `VirtualMachines` | `Custom-VirtualMachines_CL` | `VirtualMachines_CL` |
| `appservice` | `APP_SERVICE` | `AppService` | `Custom-AppService_CL` | `AppService_CL` |
| `aks` | `AKS` | `AKS` | `Custom-AKS_CL` | `AKS_CL` |
| `azuresql` | `AZURE_SQL` | `AzureSQL` | `Custom-AzureSQL_CL` | `AzureSQL_CL` |
| `apm` | `APM` | `APM` | `Custom-APM_CL` | `APM_CL` |

**Naming rule:**
- Bicep key: lowercase, no separator.
- `lab.env` key: `DCR_IMMUTABLE_ID_<UPPER_SNAKE>` and `STREAM_<UPPER_SNAKE>`.
- Table: PascalCase + `_CL` suffix.
- Stream: `Custom-` + PascalCase + `_CL`.

---

## Common Columns (all 5 tables)

Every table includes these five columns. They serve as the shared filtering and grouping dimensions.

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC injection timestamp; used by Log Analytics for time-range queries and retention | `2026-07-15T20:40:00Z` |
| `Resource` | `string` | Human-readable resource display name | `"vm-prod-01"`, `"aks-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/<sub>/resourceGroups/rg-amlab/providers/...` |
| `Environment` | `string` | Deployment environment: `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |

---

## Table: VirtualMachines_CL

**Row granularity:** one row per VM per ~1-minute metric sample.  
**KQL file:** `kql/virtual-machines.kql`  
**DCR:** `dcr-amlab-virtualmachines-<uid6>` | **Stream:** `Custom-VirtualMachines_CL`

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC injection timestamp | `2026-07-15T20:40:00Z` |
| `Resource` | `string` | VM display name | `"vm-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/.../virtualMachines/vm-prod-01` |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |
| `OSType` | `string` | `"Windows"` \| `"Linux"` | `"Linux"` |
| `CpuPercent` | `real` | CPU utilisation, 0–100 | `72.4` |
| `MemoryAvailableMB` | `real` | Available RAM in MB | `1024.0` |
| `MemoryTotalMB` | `real` | Total installed RAM in MB (constant per VM) | `8192.0` |
| `DiskName` | `string` | Volume label: `"C:"` (Windows) or `"/"` (Linux) | `"/"` |
| `DiskFreePercent` | `real` | Free disk space, 0–100 | `45.2` |
| `NetworkInBytes` | `long` | Bytes received in the sample interval | `1048576` |
| `NetworkOutBytes` | `long` | Bytes sent in the sample interval | `524288` |

### Alert-driving columns

| Column | Alert condition | Threshold |
|---|---|---|
| `CpuPercent` | CPU % sustained high | > 90 % over 5 min |
| `DiskFreePercent` | Disk nearly full | < 10 % |
| `TimeGenerated` | Heartbeat (absence of rows) | No rows for a given `Resource` for > 5 min |

---

## Table: AppService_CL

**Row granularity:** one row per App Service per ~1-minute aggregated metrics.  
**KQL file:** `kql/app-service.kql`  
**DCR:** `dcr-amlab-appservice-<uid6>` | **Stream:** `Custom-AppService_CL`

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC injection timestamp | `2026-07-15T20:40:00Z` |
| `Resource` | `string` | App Service resource name | `"app-prod-api"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/.../sites/app-prod-api` |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |
| `AppName` | `string` | Logical application name (may differ from slot name) | `"checkout-api"` |
| `RequestCount` | `long` | Total HTTP requests in the interval | `1200` |
| `ResponseTimeMs` | `real` | Mean response time (ms) in interval | `145.3` |
| `ResponseTimeP95Ms` | `real` | P95 response time (ms), pre-computed by generator | `890.0` |
| `Http2xxCount` | `long` | Count of 2xx responses in interval | `1180` |
| `Http4xxCount` | `long` | Count of 4xx responses in interval | `15` |
| `Http5xxCount` | `long` | Count of 5xx responses in interval | `5` |
| `RestartCount` | `int` | App restarts in the interval | `0` |
| `PlanCpuPercent` | `real` | App Service Plan CPU utilisation, 0–100 | `38.1` |
| `PlanMemoryPercent` | `real` | App Service Plan memory utilisation, 0–100 | `62.5` |

### Alert-driving columns

| Column | Alert condition | Threshold |
|---|---|---|
| `Http5xxCount` / `RequestCount` | 5xx error rate | > 5 % over 5 min |
| `ResponseTimeP95Ms` | P95 latency spike | > 2 000 ms |

---

## Table: AKS_CL

**Row granularity:** one row per pod **or** per node per ~1-minute sample.  
Node-level rows have `PodName` and `ContainerName` set to `""`. Pod-level rows have `NodeName` populated.  
**KQL file:** `kql/aks.kql`  
**DCR:** `dcr-amlab-aks-<uid6>` | **Stream:** `Custom-AKS_CL`

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC injection timestamp | `2026-07-15T20:40:00Z` |
| `Resource` | `string` | AKS cluster name | `"aks-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/.../managedClusters/aks-prod-01` |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |
| `Namespace` | `string` | Kubernetes namespace; `""` for node-level rows | `"default"` |
| `NodeName` | `string` | Node hostname; always populated | `"aks-nodepool1-12345-vmss000001"` |
| `PodName` | `string` | Pod name; `""` for node-only rows | `"checkout-7d6f9b-xk2pq"` |
| `ContainerName` | `string` | Container name; `""` for pod/node rows | `"checkout"` |
| `NodeCpuPercent` | `real` | Node CPU utilisation, 0–100 | `55.2` |
| `NodeMemoryPercent` | `real` | Node memory utilisation, 0–100 | `70.1` |
| `PodCpuPercent` | `real` | Pod CPU utilisation, 0–100; `0` for node-only rows | `12.4` |
| `PodMemoryPercent` | `real` | Pod memory utilisation, 0–100; `0` for node-only rows | `35.8` |
| `PodRestartCount` | `int` | Cumulative pod restart count; `0` for node-only rows | `3` |
| `PodPhase` | `string` | `"Running"` \| `"Pending"` \| `"Failed"` \| `"Succeeded"` \| `"Unknown"` | `"Running"` |
| `PodReason` | `string` | Detailed status reason; `""` if healthy | `"CrashLoopBackOff"` |
| `NodeStatus` | `string` | `"Ready"` \| `"NotReady"` \| `"Unknown"` | `"Ready"` |
| `PVName` | `string` | PersistentVolume name; `""` if no PV | `"pvc-data-01"` |
| `PVUsagePercent` | `real` | PV disk usage, 0–100; `0` if no PV | `48.3` |
| `HpaName` | `string` | HPA name; `""` if not HPA-managed | `"checkout-hpa"` |
| `HpaCurrentReplicas` | `int` | Current replica count; `0` if no HPA | `3` |
| `HpaMaxReplicas` | `int` | Configured max replicas; `0` if no HPA | `10` |

### Alert-driving columns

| Column | Alert condition | Threshold |
|---|---|---|
| `PodReason` | CrashLoopBackOff detected | Any pod with `PodReason == "CrashLoopBackOff"` in 5 min |
| `NodeStatus` | Node not ready | Any node with `NodeStatus == "NotReady"` in 5 min |

---

## Table: AzureSQL_CL

**Row granularity:** one row per database per ~1-minute metric snapshot.  
**KQL file:** `kql/azure-sql.kql`  
**DCR:** `dcr-amlab-azuresql-<uid6>` | **Stream:** `Custom-AzureSQL_CL`

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC injection timestamp | `2026-07-15T20:40:00Z` |
| `Resource` | `string` | Logical SQL server name | `"sql-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/.../servers/sql-prod-01` |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |
| `DatabaseName` | `string` | Database name within the server | `"orders-db"` |
| `DtuPercent` | `real` | DTU consumption, 0–100 (use `0` for vCore models) | `82.3` |
| `CpuPercent` | `real` | CPU utilisation, 0–100 | `77.5` |
| `WorkerPercent` | `real` | Worker thread utilisation, 0–100 | `40.0` |
| `ActiveConnections` | `int` | Current active connection count | `45` |
| `FailedConnections` | `int` | Failed connection attempts in interval | `2` |
| `DeadlockCount` | `int` | Deadlocks detected in interval | `0` |
| `StoragePercent` | `real` | Storage used, 0–100 | `68.4` |
| `StorageUsedMB` | `long` | Storage used in MB | `34816` |
| `StorageLimitMB` | `long` | Storage limit in MB | `51200` |
| `QueryDurationMs` | `real` | Mean query duration (ms) | `23.4` |
| `QueryDurationP95Ms` | `real` | P95 query duration (ms), pre-computed by generator | `180.0` |

### Alert-driving columns

| Column | Alert condition | Threshold |
|---|---|---|
| `DtuPercent` | DTU exhaustion | > 85 % over 5 min |
| `StoragePercent` | Storage nearly full | > 90 % |
| `DeadlockCount` | Deadlocks detected | > 0 in 5 min |

---

## Table: APM_CL

**Row granularity:** one row per individual telemetry event (request, dependency call, exception, or trace).  
This is **NOT** a pre-aggregated table — KQL queries must aggregate to derive golden signals.  
**KQL file:** `kql/apm.kql`  
**DCR:** `dcr-amlab-apm-<uid6>` | **Stream:** `Custom-APM_CL`

| Column | Type | Description | Example |
|---|---|---|---|
| `TimeGenerated` | `datetime` | UTC event timestamp | `2026-07-15T20:40:00.123Z` |
| `Resource` | `string` | Service/app name | `"svc-checkout"` |
| `ResourceId` | `string` | Full ARM resource ID | `/subscriptions/.../components/svc-checkout` |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` | `"prod"` |
| `Region` | `string` | Azure region slug | `"southcentralus"` |
| `ItemType` | `string` | `"request"` \| `"dependency"` \| `"exception"` \| `"trace"` | `"request"` |
| `OperationName` | `string` | HTTP route or function name | `"GET /api/orders"` |
| `DurationMs` | `real` | End-to-end duration (ms); `0` for exceptions/traces | `142.8` |
| `IsSuccess` | `boolean` | `true` = 2xx/success; `false` = 4xx/5xx/failure | `true` |
| `ExceptionType` | `string` | Exception class name; `""` if not an exception row | `"NullReferenceException"` |
| `ExceptionMessage` | `string` | Exception message text; `""` if not an exception row | `"Object reference not set..."` |
| `DependencyType` | `string` | `"HTTP"` \| `"SQL"` \| `"ServiceBus"` \| `"Redis"` \| `""` | `"SQL"` |
| `DependencyTarget` | `string` | Dependency endpoint/host; `""` if not a dependency row | `"sql-prod-01.database.windows.net"` |
| `DependencySuccess` | `boolean` | Dependency call succeeded; `true` for non-dependency rows | `true` |
| `DependencyDurationMs` | `real` | Dependency call duration (ms); `0` for non-dependency rows | `18.3` |
| `SeverityLevel` | `int` | `0`=verbose `1`=info `2`=warning `3`=error `4`=critical | `0` |
| `TraceId` | `string` | W3C trace-id (16-byte hex); `""` if not traced | `"4bf92f3577b34da6a3ce929d0e0e4736"` |
| `SpanId` | `string` | W3C span-id (8-byte hex); `""` if not traced | `"00f067aa0ba902b7"` |

> **Note on types:** `IsSuccess` and `DependencySuccess` are stored as `boolean` in Log Analytics (DCR Bicep type). In KQL queries use `== true` / `== false`. In the Python generator models (`generator/models.py`) these are native `bool`.

### Alert-driving columns

| Column | Alert condition | Threshold |
|---|---|---|
| `IsSuccess` / `ItemType` | Request failure rate | `IsSuccess == false` rate > 1 % of `ItemType == "request"` rows over 5 min |
| `DurationMs` / `ItemType` | P95 latency | P95 of `DurationMs` where `ItemType == "request"` > 500 ms |
| `IsSuccess` / `ItemType` | Error-budget burn | Rolling 1 h failure rate > 2 % of requests |

---

## `config/lab.env` Variable Map

These variables are written by `scripts/deploy` from Bicep outputs and consumed by the generator and scripts.

| Variable | Description | Example value |
|---|---|---|
| `LAB_LOCATION` | Azure region | `southcentralus` |
| `LAB_RESOURCE_GROUP` | Resource group name | `rg-amlab` |
| `LAB_SUBSCRIPTION_ID` | Active subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `LAW_NAME` | Log Analytics Workspace name | `law-amlab-a1b2c3` |
| `LAW_ID` | Workspace ARM resource ID | `/subscriptions/.../workspaces/law-amlab-a1b2c3` |
| `DCE_LOGS_INGESTION_ENDPOINT` | DCE ingestion URL | `https://dce-amlab-a1b2c3-xxxx.southcentralus-1.ingest.monitor.azure.com` |
| `DCR_IMMUTABLE_ID_VIRTUAL_MACHINES` | DCR immutable ID for VMs scenario | `dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `DCR_IMMUTABLE_ID_APP_SERVICE` | DCR immutable ID for App Service scenario | `dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `DCR_IMMUTABLE_ID_AKS` | DCR immutable ID for AKS scenario | `dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `DCR_IMMUTABLE_ID_AZURE_SQL` | DCR immutable ID for Azure SQL scenario | `dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `DCR_IMMUTABLE_ID_APM` | DCR immutable ID for APM scenario | `dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `STREAM_VIRTUAL_MACHINES` | Stream name for VMs | `Custom-VirtualMachines_CL` |
| `STREAM_APP_SERVICE` | Stream name for App Service | `Custom-AppService_CL` |
| `STREAM_AKS` | Stream name for AKS | `Custom-AKS_CL` |
| `STREAM_AZURE_SQL` | Stream name for Azure SQL | `Custom-AzureSQL_CL` |
| `STREAM_APM` | Stream name for APM | `Custom-APM_CL` |
