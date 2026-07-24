# Scenario Walkthroughs

Guided tours of the **five telemetry scenarios** the lab ships. Each scenario deploys its own
Data Collection Rule (DCR), a custom `<Scenario>_CL` table, and an Azure Monitor workbook, and is
filled with realistic synthetic data by the Python generator.

Use this doc **after** you've completed [Step 1 of the Hands-On Lab](hands-on-lab.md#step-1--stand-up--confirm-a-central-log-analytics-workspace)
(deploy + seed). Every KQL query below runs as-is in **Log Analytics → Logs**, and every anomaly
command uses a **deterministic seed** so the break is reproducible.

> **Column reference:** full schemas live in [`data-model.md`](data-model.md).
> **Ingestion latency:** allow **5–15 min** after seeding/re-seeding before rows appear.

---

## How to use each walkthrough

Every scenario section has the same four parts:

1. **What it simulates** — the resources and signals modelled.
2. **Explore** — baseline KQL to see the data.
3. **Golden signals** — the aggregation query that powers the workbook.
4. **Break it on purpose** — inject the built-in anomaly, then the KQL that detects it.

### Injecting an anomaly

Re-seeding **appends** a fresh time window of data with one signal driven past its alert
threshold. Existing rows are retained (custom-log tables don't support selective delete).

```powershell
# PowerShell
.\scripts\reseed.ps1 -Scenario <scenario> -Anomaly <key> -Minutes 15
```

```bash
# bash
bash scripts/reseed.sh --scenario <scenario> --anomaly <key> --minutes 15
```

Valid `<scenario>` keys: `virtualmachines` · `appservice` · `aks` · `azuresql` · `apm`.
Anomaly `<key>` values are listed per scenario below.

---

## 1. Virtual Machines — `VirtualMachines_CL`

### What it simulates
Guest-OS metrics for five VMs (`vm-prod-01/02/03`, `vm-staging-01`, `vm-dev-01`), one row per VM
per ~1-minute sample: CPU, memory, disk free %, network I/O, and heartbeat.

| Anomaly key | Effect | Alert threshold |
|---|---|---|
| `cpu` | `CpuPercent` driven > 90 % on all VMs | CPU > 90 % sustained 5 min |
| `disk` | `DiskFreePercent` driven < 10 % | Disk free < 10 % |
| `heartbeat` | All rows for `vm-dev-01` suppressed | No rows for a VM > 5 min |

### Explore

```kql
VirtualMachines_CL
| where TimeGenerated > ago(1h)
| summarize AvgCpu = avg(CpuPercent), MinDiskFree = min(DiskFreePercent) by Resource, Environment
| order by AvgCpu desc
```

### Golden signals — CPU & disk trend

```kql
VirtualMachines_CL
| where TimeGenerated > ago(1h)
| summarize AvgCpu = avg(CpuPercent), P95Cpu = percentile(CpuPercent, 95),
            MinDiskFree = min(DiskFreePercent)
    by bin(TimeGenerated, 5m), Resource
| render timechart
```

### Break it on purpose

```powershell
.\scripts\reseed.ps1 -Scenario virtualmachines -Anomaly cpu -Minutes 15
```

**Detect the CPU breach** (mirrors the alert rule):

```kql
VirtualMachines_CL
| where TimeGenerated > ago(15m)
| summarize AvgCpu = avg(CpuPercent) by bin(TimeGenerated, 5m), Resource
| where AvgCpu > 90
```

**Detect a missing heartbeat** (after `-Anomaly heartbeat` — `vm-dev-01` goes silent):

```kql
VirtualMachines_CL
| where TimeGenerated > ago(15m)
| summarize LastSeen = max(TimeGenerated) by Resource
| extend SilentFor = now() - LastSeen
| where SilentFor > 5m
```

---

## 2. App Service / PaaS — `AppService_CL`

### What it simulates
HTTP + platform metrics for four App Services (`app-prod-api/web/worker`, `app-staging-api`), one
row per app per ~1-minute aggregation: request count, response time (mean + P95), HTTP status
buckets, restarts, and App Service Plan CPU/memory.

| Anomaly key | Effect | Alert threshold |
|---|---|---|
| `5xx` | `Http5xxCount` driven > 5 % of `RequestCount` | 5xx rate > 5 % over 5 min |
| `latency` | `ResponseTimeP95Ms` driven > 2 000 ms | P95 latency > 2 000 ms |

### Explore

```kql
AppService_CL
| where TimeGenerated > ago(1h)
| summarize Requests = sum(RequestCount), Errors5xx = sum(Http5xxCount),
            AvgP95 = avg(ResponseTimeP95Ms) by Resource, AppName
| order by Requests desc
```

### Golden signals — rate / errors / latency

```kql
AppService_CL
| where TimeGenerated > ago(1h)
| summarize Requests = sum(RequestCount), Errors5xx = sum(Http5xxCount),
            P95Ms = avg(ResponseTimeP95Ms) by bin(TimeGenerated, 5m), Resource
| extend ErrorRatePct = todouble(Errors5xx) / Requests * 100
| render timechart
```

### Break it on purpose

```powershell
.\scripts\reseed.ps1 -Scenario appservice -Anomaly 5xx -Minutes 15
```

**Detect the 5xx breach:**

```kql
AppService_CL
| where TimeGenerated > ago(15m)
| summarize Requests = sum(RequestCount), Errors5xx = sum(Http5xxCount)
    by bin(TimeGenerated, 5m), Resource
| extend ErrorRatePct = todouble(Errors5xx) / Requests * 100
| where ErrorRatePct > 5
```

**Detect the latency spike** (after `-Anomaly latency`):

```kql
AppService_CL
| where TimeGenerated > ago(15m)
| summarize MaxP95 = max(ResponseTimeP95Ms) by bin(TimeGenerated, 5m), Resource
| where MaxP95 > 2000
```

---

## 3. AKS / Containers — `AKS_CL`

### What it simulates
Kubernetes node- and pod-level metrics for `aks-prod-01` (nodes `aks-nodepool1-01..03`; pods across
`default` / `monitoring` / `ingress` namespaces). Node rows have `PodName=""`; pod rows have
`NodeName` populated. Includes CPU/mem, restarts, pod phase/reason, PV usage, and HPA replicas.

| Anomaly key | Effect | Alert threshold |
|---|---|---|
| `crashloop` | One prod pod → `PodPhase="Failed"`, `PodReason="CrashLoopBackOff"`, restarts > 5 | Any pod in CrashLoopBackOff in 5 min |
| `nodenotready` | One prod node → `NodeStatus="NotReady"` | Any node NotReady in 5 min |

### Explore

```kql
// Pod health snapshot (pod-level rows only)
AKS_CL
| where TimeGenerated > ago(1h) and isnotempty(PodName)
| summarize AvgPodCpu = avg(PodCpuPercent), MaxRestarts = max(PodRestartCount),
            LastPhase = arg_max(TimeGenerated, PodPhase, PodReason)
    by Namespace, PodName
| order by MaxRestarts desc
```

### Node & pod utilization

```kql
AKS_CL
| where TimeGenerated > ago(1h) and isempty(PodName)   // node-level rows
| summarize AvgNodeCpu = avg(NodeCpuPercent), AvgNodeMem = avg(NodeMemoryPercent)
    by bin(TimeGenerated, 5m), NodeName
| render timechart
```

### Break it on purpose

```powershell
.\scripts\reseed.ps1 -Scenario aks -Anomaly crashloop -Minutes 15
```

**Detect CrashLoopBackOff:**

```kql
AKS_CL
| where TimeGenerated > ago(15m)
| where PodReason == "CrashLoopBackOff"
| summarize Restarts = max(PodRestartCount) by Namespace, PodName, PodPhase
```

**Detect a NotReady node** (after `-Anomaly nodenotready`):

```kql
AKS_CL
| where TimeGenerated > ago(15m)
| where NodeStatus == "NotReady"
| distinct NodeName, NodeStatus, Resource
```

---

## 4. Azure SQL — `AzureSQL_CL`

### What it simulates
Database-level metrics for three logical servers (`sql-prod-01` with `db-main/analytics/reporting`,
`sql-prod-02` with `db-orders`, `sql-staging-01`), one row per database per ~1-minute snapshot:
DTU/CPU/worker %, connections, deadlocks, storage %, and query duration (mean + P95).

| Anomaly key | Effect | Alert threshold |
|---|---|---|
| `dtu` | `DtuPercent` driven > 85 % | DTU > 85 % over 5 min |
| `storage` | `StoragePercent` driven > 90 % | Storage > 90 % |
| `deadlock` | `DeadlockCount` driven > 0 | Deadlocks > 0 in 5 min |

### Explore

```kql
AzureSQL_CL
| where TimeGenerated > ago(1h)
| summarize AvgDtu = avg(DtuPercent), MaxStorage = max(StoragePercent),
            Deadlocks = sum(DeadlockCount), AvgP95Query = avg(QueryDurationP95Ms)
    by Resource, DatabaseName
| order by AvgDtu desc
```

### Golden signals — DTU & storage pressure

```kql
AzureSQL_CL
| where TimeGenerated > ago(1h)
| summarize AvgDtu = avg(DtuPercent), MaxStorage = max(StoragePercent)
    by bin(TimeGenerated, 5m), DatabaseName
| render timechart
```

### Break it on purpose

```powershell
.\scripts\reseed.ps1 -Scenario azuresql -Anomaly dtu -Minutes 15
```

**Detect DTU exhaustion:**

```kql
AzureSQL_CL
| where TimeGenerated > ago(15m)
| summarize AvgDtu = avg(DtuPercent) by bin(TimeGenerated, 5m), Resource, DatabaseName
| where AvgDtu > 85
```

**Detect deadlocks** (after `-Anomaly deadlock`):

```kql
AzureSQL_CL
| where TimeGenerated > ago(15m)
| where DeadlockCount > 0
| summarize Deadlocks = sum(DeadlockCount) by Resource, DatabaseName
```

---

## 5. Applications (APM) — `APM_CL`

### What it simulates
Application-performance telemetry for four services (`svc-checkout/orders/inventory/users`), **one
row per event** (~60 % requests · 25 % dependencies · 5 % exceptions · 10 % traces). Unlike the
other tables, this is **not pre-aggregated** — you derive the golden signals in KQL. This is the
scenario the [Hands-On Lab](hands-on-lab.md) uses end-to-end.

| Anomaly key | Effect | Alert threshold |
|---|---|---|
| `errorrate` | > 1 % of request rows get `IsSuccess=false` | Request failure rate > 1 % over 5 min |
| `latency` | request `DurationMs` P95 driven > 500 ms | P95 latency > 500 ms |

### Explore

```kql
APM_CL
| where TimeGenerated > ago(1h)
| summarize Events = count() by ItemType, Resource
| order by Events desc
```

### Golden signals — rate, errors, latency

```kql
APM_CL
| where TimeGenerated > ago(1h) and ItemType == "request"
| summarize
    Requests = count(),
    Failures = countif(IsSuccess == false),
    P95Ms = percentile(DurationMs, 95)
  by bin(TimeGenerated, 5m), Resource
| extend FailureRatePct = todouble(Failures) / Requests * 100
| render timechart
```

### Break it on purpose

```powershell
.\scripts\reseed.ps1 -Scenario apm -Anomaly errorrate -Minutes 15
```

**Detect the failure-rate breach** (drives `alert-amlab-apm-failure-rate`):

```kql
APM_CL
| where TimeGenerated > ago(15m) and ItemType == "request"
| summarize Requests = count(), Failures = countif(IsSuccess == false)
    by bin(TimeGenerated, 5m), Resource
| extend FailureRatePct = todouble(Failures) / Requests * 100
| where FailureRatePct > 1
```

**Detect the latency breach** (after `-Anomaly latency`):

```kql
APM_CL
| where TimeGenerated > ago(15m) and ItemType == "request"
| summarize P95Ms = percentile(DurationMs, 95) by bin(TimeGenerated, 5m), Resource
| where P95Ms > 500
```

> The APM scenario also has pre-built SLO alert rules and an end-to-end "fire a test" flow —
> see [Hands-On Lab Step 5](hands-on-lab.md#step-5--create-an-slo-based-alert--action-group-and-fire-a-test).

---

## Reset the environment

Re-seeding only appends data. To return to a clean baseline (no anomalies), tear down and redeploy:

```powershell
.\scripts\teardown.ps1           # deletes rg-amlab + config/lab.env (or: bash scripts/teardown.sh)
.\scripts\deploy.ps1             # or: bash scripts/deploy.sh
.\scripts\seed.ps1               # or: bash scripts/seed.sh
```

See the [Hands-On Lab](hands-on-lab.md) for the full deploy → seed → verify loop, and
[`troubleshooting.md`](troubleshooting.md) if a table stays empty.
