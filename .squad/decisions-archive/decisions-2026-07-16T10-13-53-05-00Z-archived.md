# Squad Decisions

## Active Decisions

No decisions recorded yet.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction


### 2026-07-16T03:05:00Z: Deployment verification + PS 5.1 encoding hardening
**By:** Daniel Mauser (@dmauser) session — coordinator operational execution
**What:**
1. Smoke-test initially FAILED due to a transient Azure CLI tenant/token flip: CLI context rolled to personal@example.com (tenant <tenant-a>) and target sub 00000000 (Your-Subscription, tenant <tenant-b>) dropped out of az account list, causing InvalidAuthenticationTokenTenant + ResourceGroupNotFound. Fix: re-select with 'az account set --subscription 00000000-0000-0000-0000-000000000000' (token still cached) — access restored, RG rg-amlab present.
2. All scripts/*.ps1 were UTF-8 WITHOUT BOM. Launched via Windows PowerShell 5.1 ('powershell -File'), the Unicode glyphs (box-drawing, arrows, checkmarks) were misread as ANSI, corrupting the tokenizer and breaking string quoting on the REST-URL line (bare '&'). Fix: re-saved every scripts/*.ps1 as UTF-8 WITH BOM so 5.1 detects encoding correctly.
**Verified live (sub 00000000 / rg-amlab / workspace law-amlab-<uid>):**
- Row counts: VirtualMachines_CL=304, AppService_CL=192, AKS_CL=624, AzureSQL_CL=320, APM_CL=960 (2,400 total).
- 13/13 scheduled-query alerts ENABLED. Smoke-test OVERALL RESULT: PASS (exit 0).
- 9 alerts actually FIRED from injected anomalies (VM heartbeat-missing, APM error-budget-burn, SQL deadlocks, App Service P95 = Fired; AKS crashloop/node-notready, SQL storage, VM disk-low, APM P95 = fired-then-resolved) — end-to-end telemetry to detection to alerting proven.
**Why:** Records the two environment gotchas (tenant flip recovery, PS 5.1 UTF-8 BOM requirement) and the final verified working state so the lab can be re-run reliably.

# Decision: Dozer — APM errorrate Determinism Fix

**Date:** 2026-07-15  
**Author:** Dozer (Backend / Data Dev)  
**Status:** COMPLETE — 165 passed, 0 xfailed, exit 0  
**Consumers:** Ghost (QA re-validation) · live deploy pipeline

---

## Problem

`generator/scenarios/apm.py` injected failures for the `errorrate` anomaly using:

```python
is_success = rng.random() > 0.02  # ~2 % failure rate
```

With `seed=42` and a 5-minute window (5 ticks × 20 events/tick ≈ 70 request rows), all 70
random draws happened to exceed 0.02, producing **0 failures** → 0.0% failure rate.  The Azure
Monitor APM failure-rate alert (threshold: > 1% over 5 min) would not fire.

Ghost documented this as BUG-1 in `ghost-tests.md`, marked 2 tests `xfail(strict=True)` in
`tests/test_thresholds.py::TestAPMErrorRateAnomaly`, and routed it to Dozer for fixing.

---

## What Changed

### `generator/scenarios/apm.py`

1. Added `import math` at the top.
2. The probabilistic injection comment updated (line is kept as the initial probabilistic
   pass — the floor below corrects any shortfall).
3. **Added a deterministic floor pass after the main generation loop:**

```python
# Deterministic floor for errorrate anomaly: guarantee >= ceil(max(1, 3%)) failures
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
```

### `tests/test_thresholds.py`

- Removed `@pytest.mark.xfail(strict=True)` from both small-window tests in
  `TestAPMErrorRateAnomaly`.
- Updated the class docstring to describe the deterministic guarantee instead of the bug.
- Test method docstrings updated (removed "(xfail)" prefix and bug language).
- Large-window tests kept unchanged — they still pass.

---

## Guaranteed-Failure Formula

```
n_required = ceil(max(1, 0.03 × request_row_count))
```

| Window  | Request rows | n_required | Actual failures | Failure rate |
|---------|-------------|------------|-----------------|--------------|
| 5 min   | 70          | 3          | 3               | 4.29%        |
| 60 min  | ~703        | 22         | ≥22             | ≥3.13%       |

Both values are strictly above the >1% alert threshold.  The baseline (no anomaly) stays at
~0.2% (`rng.random() > 0.002`) — unaffected by this change.

---

## Why This Approach

- **RNG sequence preserved:** The fix runs *after* the main loop, so seed-driven choices for
  service, operation, ItemType, duration, and TraceId/SpanId are identical to before.  Only
  `IsSuccess` is overridden on a small subset of already-generated request rows.
- **Zero probability of missing the threshold:** With `max(1, …)` the guarantee holds even if
  there is a single request row in the window.
- **3% target vs 1% threshold:** The 3% target leaves a ×3 margin above the alert threshold,
  matching a ~real-world SLA-breach signal level.

---

## Final pytest Result

```
165 passed in 0.33s
```

(Previously: 163 passed, 2 xfailed)

No regressions.  All 5 scenarios, all anomaly/baseline combinations pass.


# Decision: Dozer — Generator Contract

**Date:** 2026-07-15  
**Author:** Dozer (Backend / Data Dev)  
**Status:** COMPLETE — all generator files authored and dry-run validated  
**Consumers:** Ghost (tests) · Mouse (docs / scripts)

---

## 1. CLI Contract

Entry point: `generator/main.py`  
Run from repo root with `PYTHONPATH=C:\path\to\azure-monitor-workshop` set.

```
python generator/main.py [OPTIONS]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--scenario {all,virtualmachines,appservice,aks,azuresql,apm}` | `all` | Scenario(s) to generate |
| `--backfill-minutes N` | `15` | Minutes of history to generate on each pass |
| `--interval-seconds N` | `60` | Tick spacing in seconds (row timestamp granularity) |
| `--anomaly KEY` | _(none)_ | Inject alert-triggering values for the named anomaly key |
| `--seed N` | _(none)_ | Integer seed for reproducible random output |
| `--dry-run` | _(off)_ | Skip Azure upload; print counts + sample record to stdout |
| `--once` | _(default)_ | Run one pass then exit |
| `--loop` | _(off)_ | Run continuously, one pass per `--interval-seconds` |

**Exit codes:** `0` = success, `1` = config/upload failure.

**Dry-run hermetic invocation** (no Azure credentials required):
```powershell
$env:PYTHONPATH = "C:\path\to\azure-monitor-workshop"
python generator/main.py --scenario all --dry-run --backfill-minutes 5 --seed 42
```

---

## 2. Anomaly Key Catalog

The `--anomaly KEY` flag applies to the single scenario specified by `--scenario`.
Passing `--scenario all --anomaly <key>` propagates the key to all generators;
generators that do not recognise the key treat it as no-op (normal baseline).

| Scenario | Anomaly Key | Injected condition | Alert threshold matched |
|----------|-------------|--------------------|------------------------|
| `virtualmachines` | `cpu` | `CpuPercent` > 90 % | CPU % > 90 % over 5 min |
| `virtualmachines` | `disk` | `DiskFreePercent` < 10 % | Disk free < 10 % |
| `virtualmachines` | `heartbeat` | All rows suppressed for one VM | Heartbeat silence > 5 min |
| `appservice` | `5xx` | `Http5xxCount` > 5 % of `RequestCount` | 5xx error rate > 5 % over 5 min |
| `appservice` | `latency` | `ResponseTimeP95Ms` > 2 000 ms | P95 latency > 2 000 ms |
| `aks` | `crashloop` | `PodPhase=Failed`, `PodReason=CrashLoopBackOff`, `PodRestartCount` > 5 | Any CrashLoopBackOff pod in 5 min |
| `aks` | `nodenotready` | `NodeStatus=NotReady` for one node | Any node NotReady in 5 min |
| `azuresql` | `dtu` | `DtuPercent` > 85 % | DTU % > 85 % over 5 min |
| `azuresql` | `storage` | `StoragePercent` > 90 % | Storage % > 90 % |
| `azuresql` | `deadlock` | `DeadlockCount` > 0 | Deadlocks > 0 in 5 min |
| `apm` | `errorrate` | ~2 % of request rows have `IsSuccess=false` | Failure rate > 1 % over 5 min |
| `apm` | `latency` | Request `DurationMs` > 500 ms (P95 injected high) | P95 latency > 500 ms |

---

## 3. Model-to-Schema Alignment Confirmation

All Python dataclass fields in `generator/models.py` match `mouse-kql-schema.md` exactly:
column names are PascalCase, types mapped as `datetime→datetime`, `string→str`,
`real→float`, `int/long→int`, `bool→bool`.

### VirtualMachines_CL → `VirtualMachineRecord`
`TimeGenerated` `Resource` `ResourceId` `Environment` `Region` `OSType`
`CpuPercent` `MemoryAvailableMB` `MemoryTotalMB` `DiskName` `DiskFreePercent`
`NetworkInBytes` `NetworkOutBytes`

### AppService_CL → `AppServiceRecord`
`TimeGenerated` `Resource` `ResourceId` `Environment` `Region` `AppName`
`RequestCount` `ResponseTimeMs` `ResponseTimeP95Ms` `Http2xxCount` `Http4xxCount`
`Http5xxCount` `RestartCount` `PlanCpuPercent` `PlanMemoryPercent`

### AKS_CL → `AKSRecord`
`TimeGenerated` `Resource` `ResourceId` `Environment` `Region` `Namespace`
`NodeName` `PodName` `ContainerName` `NodeCpuPercent` `NodeMemoryPercent`
`PodCpuPercent` `PodMemoryPercent` `PodRestartCount` `PodPhase` `PodReason`
`NodeStatus` `PVName` `PVUsagePercent` `HpaName` `HpaCurrentReplicas` `HpaMaxReplicas`

### AzureSQL_CL → `AzureSQLRecord`
`TimeGenerated` `Resource` `ResourceId` `Environment` `Region` `DatabaseName`
`DtuPercent` `CpuPercent` `WorkerPercent` `ActiveConnections` `FailedConnections`
`DeadlockCount` `StoragePercent` `StorageUsedMB` `StorageLimitMB`
`QueryDurationMs` `QueryDurationP95Ms`

### APM_CL → `APMRecord`
`TimeGenerated` `Resource` `ResourceId` `Environment` `Region` `ItemType`
`OperationName` `DurationMs` `IsSuccess` `ExceptionType` `ExceptionMessage`
`DependencyType` `DependencyTarget` `DependencySuccess` `DependencyDurationMs`
`SeverityLevel` `TraceId` `SpanId`

---

## 4. Module Layout (for Ghost / tests)

```
generator/
  __init__.py
  config.py          # LabConfig.load(dry_run=False)
  models.py          # VirtualMachineRecord, AppServiceRecord, AKSRecord,
                     # AzureSQLRecord, APMRecord — each with .to_dict()
  time_window.py     # generate_timestamps(backfill_minutes, interval_seconds, seed, now)
  validation.py      # validate_record(scenario_key, record) -> List[str]
                     # required_columns(scenario_key) -> List[str]
  ingestion_client.py# IngestionClient(config, dry_run).upload(scenario_key, records) -> int
  main.py            # argparse CLI entry point
  scenarios/
    __init__.py
    virtual_machines.py  # generate(config, time_window, *, anomaly, seed, count_per_tick)
    app_service.py
    aks.py
    azure_sql.py
    apm.py
```

### Key contracts for Ghost (tests)

- `validate_record(scenario_key, record)` returns `[]` for valid records, list of strings for errors.
- All `generate()` functions accept `seed=42` for deterministic output.
- `--dry-run` requires no environment variables and no Azure credentials.
- `LabConfig.load(dry_run=True)` uses safe defaults (`rg-amlab`, `southcentralus`, empty DCR IDs).
- ARM resource IDs use placeholder sub/RG when config values are empty.
- `TimeGenerated` is serialised as `datetime.isoformat()` with UTC timezone offset.


# Decision: Ghost — Seed / Reseed / Smoke-Test Script Contract

**Date:** 2026-07-15  
**Author:** Ghost (Tester / QA)  
**Status:** COMPLETE — scripts authored and generator invocations dry-run validated  
**Consumers:** Coordinator (post-deploy run order) · Tank (common.ps1/sh contract) · Mouse (docs)

---

## 1. Script Inventory

| Script | Platform | Description |
|---|---|---|
| `scripts/seed.ps1` | PowerShell (Windows primary) | Baseline + 12 anomaly generator passes |
| `scripts/seed.sh` | Bash (portability) | Same as seed.ps1 |
| `scripts/reseed.ps1` | PowerShell | Parameterised re-run (append rows, no delete) |
| `scripts/reseed.sh` | Bash | Same as reseed.ps1 |
| `scripts/smoke-test.ps1` | PowerShell | Post-deploy verification gate |
| `scripts/smoke-test.sh` | Bash | Same as smoke-test.ps1 |

All scripts:
- Dot-source / source `scripts/common.{ps1,sh}` if present (Tank's module); degrade to direct `config/lab.env` parse if absent.
- Set `az account set --subscription 00000000-0000-0000-0000-000000000000` on every run.
- Set `PYTHONPATH=<repo-root>` before invoking the generator.
- Exit non-zero on any upload failure (seed) or verification failure (smoke-test).

---

## 2. Exact Invocations

### seed (PowerShell — primary)
```powershell
cd C:\path\to\azure-monitor-workshop
.\scripts\seed.ps1
```

### seed (Bash)
```bash
cd /path/to/azure-monitor-workshop
bash scripts/seed.sh
```

### reseed (PowerShell — default: baseline, 15 min, all scenarios)
```powershell
.\scripts\reseed.ps1
# With options:
.\scripts\reseed.ps1 -Minutes 30
.\scripts\reseed.ps1 -Scenario virtualmachines -Anomaly cpu -Minutes 15
```

### reseed (Bash)
```bash
bash scripts/reseed.sh
bash scripts/reseed.sh --minutes 30
bash scripts/reseed.sh --scenario virtualmachines --anomaly cpu --minutes 15
```

### smoke-test (PowerShell — primary, default: 20 min max wait, 60 s poll)
```powershell
.\scripts\smoke-test.ps1
# Shorter wait for quick re-check:
.\scripts\smoke-test.ps1 -MaxWaitMinutes 5 -PollIntervalSeconds 30
```

### smoke-test (Bash)
```bash
bash scripts/smoke-test.sh
bash scripts/smoke-test.sh --max-wait-minutes 5 --poll-interval-seconds 30
```

---

## 3. Coordinator Post-Deploy Run Order

After `scripts/deploy` completes and `config/lab.env` is populated:

```
Step 1 — Seed data
  Windows:  .\scripts\seed.ps1
  Linux/Mac: bash scripts/seed.sh

Step 2 — Wait for ingestion (5-15 min typical)
  The seed script prints a reminder. No manual action needed.

Step 3 — Run smoke-test
  Windows:  .\scripts\smoke-test.ps1
  Linux/Mac: bash scripts/smoke-test.sh

  Expected: OVERALL RESULT: ✓  PASS
  On failure, the script prints which table(s) / rule(s) failed.
```

---

## 4. Ingestion Latency Handling (Smoke-Test Retry)

Custom-log ingestion via the Logs Ingestion API typically takes **5–15 minutes** before rows appear in Log Analytics queries. The smoke-test handles this with a configurable retry loop:

| Parameter | PS1 flag | SH flag | Default |
|---|---|---|---|
| Max wait | `-MaxWaitMinutes` | `--max-wait-minutes` | 20 min |
| Poll interval | `-PollIntervalSeconds` | `--poll-interval-seconds` | 60 s |

The loop polls each table independently. Once a table returns ≥1 row it is removed from the retry set. If any table still has 0 rows when the window expires, the script exits 1.

KQL used per table:
```kql
<TableName> | where TimeGenerated > ago(1h) | summarize RowCount=count()
```
`--workspace` receives `LAW_ID` (workspace customer GUID, not ARM resource ID).

---

## 5. Alert Rule Verification (Smoke-Test)

### Provisioning check (automated)
```
az monitor scheduled-query list -g <LAB_RESOURCE_GROUP> --output json
```
The smoke-test confirms all **13 expected rules** exist and are `enabled=true`:

| Alert Rule Name | Scenario |
|---|---|
| `alert-amlab-vm-cpu-high` | Virtual Machines |
| `alert-amlab-vm-disk-low` | Virtual Machines |
| `alert-amlab-vm-heartbeat-missing` | Virtual Machines |
| `alert-amlab-app-5xx-high` | App Service |
| `alert-amlab-app-p95-high` | App Service |
| `alert-amlab-aks-crashloop` | AKS |
| `alert-amlab-aks-node-notready` | AKS |
| `alert-amlab-sql-dtu-high` | Azure SQL |
| `alert-amlab-sql-storage-high` | Azure SQL |
| `alert-amlab-sql-deadlocks` | Azure SQL |
| `alert-amlab-apm-failure-rate` | APM |
| `alert-amlab-apm-p95-latency` | APM |
| `alert-amlab-apm-error-budget-burn` | APM |

### Fired-state check (manual — az CLI limitation)
`az` CLI does not expose scheduledQueryRule fire history. After the smoke-test passes, verify alerts FIRED via:

**Portal:**
> Azure Portal → Monitor → Alerts → Alert history
> Filter: Resource group = `<LAB_RESOURCE_GROUP>`

**REST (az CLI):**
```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<RG>/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01&alertState=Fired"
```

Alert evaluation runs every PT5M. After seed, allow **5–10 minutes** for the first evaluation cycle before checking fired state.

---

## 6. Anomaly Key Catalog (used by seed + reseed)

| Scenario | Key | Alert threshold triggered |
|---|---|---|
| `virtualmachines` | `cpu` | CpuPercent > 90 % |
| `virtualmachines` | `disk` | DiskFreePercent < 10 % |
| `virtualmachines` | `heartbeat` | Heartbeat silence > 5 min |
| `appservice` | `5xx` | 5xx error rate > 5 % |
| `appservice` | `latency` | P95 latency > 2 000 ms |
| `aks` | `crashloop` | CrashLoopBackOff pod in 5 min |
| `aks` | `nodenotready` | NodeNotReady in 5 min |
| `azuresql` | `dtu` | DTU % > 85 % |
| `azuresql` | `storage` | Storage % > 90 % |
| `azuresql` | `deadlock` | Deadlocks > 0 |
| `apm` | `errorrate` | Error rate > 1 % |
| `apm` | `latency` | P95 latency > 500 ms |

---

## 7. Notes

- **No delete:** Custom logs in Log Analytics cannot be selectively deleted. Reseed always appends rows.  
- **Seed reproducibility:** Anomaly passes use `--seed 42`. Baseline pass uses no seed (random per run) — this is intentional to vary the baseline time-series data.  
- **Python dependency:** `smoke-test.sh` uses `python3` (already a project dependency) to parse `az monitor scheduled-query list` JSON output — avoids requiring `jq`.  
- **common.{ps1,sh}:** Tank's `common.{ps1,sh}` provide helpers (`Assert-AzCli`, `Set-AzSubscription`, etc.) but do NOT load `config/lab.env`. All scripts therefore always source `config/lab.env` directly after optionally sourcing common.

# Decision: Tank — Demo VM Module

**Date:** 2026-07-16  
**Author:** Tank (Infra / IaC Dev)  
**Status:** DEPLOYED AND VERIFIED  
**Consumers:** All team members, @dmauser

---

## What Was Deployed

A minimal-cost Ubuntu demo VM was deployed to the existing `rg-amlab` resource group. All resources are **additive only** — no existing lab resources were modified.

### Resources created (actual names)

| Resource | Name | Notes |
|---|---|---|
| NSG | `nsg-amlab-vmguest-2yvzaw` | Zero inbound allow rules; DenyAllInBound default |
| VNet | `vnet-amlab-2yvzaw` | 10.10.0.0/24, subnet snet-vmguest 10.10.0.0/27 |
| NIC | `nic-amlab-2yvzaw` | Private IP `10.10.0.4`; no public IP |
| VM | `vm-amlab-<uid>` | Ubuntu 22.04 LTS Gen2, Standard_B2ats_v2, 30 GB Standard_LRS; **system-assigned identity** |
| AMA extension | (child of VM) | AzureMonitorLinuxAgent, auto-upgrade enabled; provisioning state: Succeeded |
| Guest DCR | `dcr-amlab-vmguest-<uid>` | kind Linux; 6 lean perf counters → InsightsMetrics + Perf |
| DCRA | `dcra-vmguest-2yvzaw` | Associates guest DCR with the VM |
| Auto-shutdown | `shutdown-computevm-vm-amlab-<uid>` | Daily 19:00 CST, deallocates VM |

Live credentials in `config/vm.env` (gitignored).

---

## SKU Choice and Rationale

**Chosen:** `Standard_B2ats_v2` (2 vCPU / 1 GiB RAM)

- Cheapest v2-series burstable with no zone/quota restriction in southcentralus.
- B1s and B2s carry a "Zone" restriction; the `_v2 ats` variant is confirmed clean.
- Cost estimate: ~$14/mo running 24×7; ~$5/mo with auto-shutdown (8 h/day).

---

## Cost Posture

| Scenario | Est. monthly |
|---|---|
| 24×7 running | ~$15.30 (compute + disk + minimal ingestion) |
| Auto-shutdown (8 h/day workdays) | ~$6.24 |

Auto-shutdown is **enabled by default** at 19:00 CST. Storage billed regardless; run teardown-vm when done.

---

## DCR Design: Lean Counter Set

Six Linux performance counters at 60-second sampling. No syslog. No custom tables.

- `Microsoft-InsightsMetrics` → `InsightsMetrics` table (VM Insights queries)
- `Microsoft-Perf` → `Perf` table (classic counter table)

Platform/host metrics (CPU %, disk, network) are **free** without any agent — always available in Metrics Explorer.

---

## Critical Finding: AMA Requires System-Assigned Managed Identity

During live deployment: AMA extension provisioned but agent failed to collect. `mdsd.err` showed IMDS MSI token failures. Root cause: VM had no managed identity.

**Resolution:** Added `identity: { type: 'SystemAssigned' }` to the VM resource in `demo-vm.bicep`. This is now in the module.

**Lesson for team:** Any Bicep module that installs AMA must include `identity: { type: 'SystemAssigned' }` on the VM resource — otherwise AMA extension provisions successfully but collection never starts.

---

## Additive-Only Guarantee

The Bicep module accepts `workspaceResourceId` as a parameter and references no other existing lab resources. It creates a fresh VNet/NSG isolated from other lab resources. The teardown script deletes only what was created by this module.

---

## Files Authored

```
infra/modules/demo-vm.bicep
scripts/deploy-vm.sh
scripts/deploy-vm.ps1
scripts/teardown-vm.sh
scripts/teardown-vm.ps1
docs/metrics-demo-vm.md
.gitignore (additive edit: config/vm.env, config/keys/, *.pem, id_ed25519*)
```

## 8. PS5.1 Compatibility — `if`-as-expression Fix (2026-07-15)

**Root cause:** `smoke-test.ps1` originally used `if` inline inside `(...)` in cmdlet argument position:
```powershell
$t | Add-Member -NotePropertyName 'TableName' -NotePropertyValue (
    if ($val) { $val } else { $tableDefaults[$t.EnvVar] }
)
```
This pattern is **PS7-only**. On Windows PowerShell 5.1 (the lab runtime) it throws:
> `"The term 'if' is not recognized as a name of a cmdlet"`

**Fix applied:** Hoist to a statement-assigned variable first (valid in 5.1):
```powershell
$tn = if ($val) { $val } else { $tableDefaults[$t.EnvVar] }
$t | Add-Member -NotePropertyName 'TableName' -NotePropertyValue $tn
```

**General rule for all future PS scripts targeting PS5.1:**
- `$x = if (...) { ... }` — ✓ valid in PS5.1 (statement assignment)
- `Cmdlet -Param (if (...) { ... })` — ✗ **invalid in PS5.1**, PS7-only

**Verified clean** with both `PSParser::Tokenize` (0 errors) and
`Language.Parser::ParseFile` (0 AST errors) on Windows PowerShell 5.1.


# Decision: Ghost — Test Suite Inventory

**Date:** 2026-07-15  
**Author:** Ghost (Tester / QA)  
**Status:** COMPLETE — 163 passed, 2 xfailed (expected), 0 failures  
**Consumers:** Dozer (bug fix for errorrate anomaly) · all team members running CI

---

## How to Run

```powershell
# From repo root — no PYTHONPATH required (conftest.py sets sys.path automatically)
cd C:\path\to\azure-monitor-workshop
C:\Users\<user>\AppData\Local\Programs\Python\Python312\python.exe -m pytest tests/ -q
```

Expected output: `163 passed, 2 xfailed`  
Exit code: `0` (xfail does not fail the suite)

---

## Test File Inventory

| File | Tests | What it covers |
|------|-------|----------------|
| `tests/conftest.py` | — | Inserts repo root into `sys.path[0]` so `import generator.*` works from any cwd |
| `tests/test_config.py` | 23 | `LabConfig.load(dry_run=True)` safe defaults; env-var overrides; `_read_env_file` dotenv parsing |
| `tests/test_time_window.py` | 18 | `generate_timestamps` — count, spacing, UTC-aware, determinism, seed acceptance, live-clock path |
| `tests/test_scenarios.py` | 32 | Per-scenario row counts (baseline + anomaly variants), determinism, required columns, ISO-8601 UTC serialisation, record types |
| `tests/test_thresholds.py` | 40 | Each anomaly key crosses alert threshold (anomaly ON); baseline stays within normal bounds (anomaly OFF). Two small-window APM errorrate tests are `xfail`. Two large-window tests cover the same feature with green results. |
| `tests/test_payload_schema.py` | 50 | `required_columns()` column-set match vs `mouse-kql-schema.md`; `validate_record()` returns `[]` for valid; errors for missing cols / out-of-range / bad severity; all generator records pass live validation |

**Total: 163 collected (163 passed, 2 xfailed)**

---

## Pass Count by File

```
test_config.py          23 passed
test_time_window.py     18 passed
test_scenarios.py       32 passed   (1 fixed — storage rounding tolerance)
test_thresholds.py      40 passed + 2 xfailed
test_payload_schema.py  50 passed
─────────────────────────────────
TOTAL                  163 passed, 2 xfailed
```

---

## Bugs Routed Back to Dozer

### BUG-1: APM `errorrate` anomaly — probabilistic injection may produce zero failures in small windows

**Severity:** Medium  
**Scenario:** `apm`  
**Anomaly key:** `errorrate`  
**Root cause:** `apm.py` uses `is_success = rng.random() > 0.02` for request rows under
`errorrate` anomaly. With `seed=42` and only 70 request records (5-min window, 20 events/tick),
all 70 random draws happen to return values > 0.02 → 0 failures → 0.0% failure rate, which
does NOT trigger the > 1% alert threshold.

**Observed:**
```
seed=42, backfill=5min, interval=60s, count_per_tick=20
→ 120 total records, 70 requests, 0 failures, rate = 0.0%  (threshold: > 1%)
```

**Workaround in tests:** Large-window tests (60-min, 703 requests, 18 failures, 2.56%) prove
the feature works.  Small-window tests are marked `xfail(strict=True)` in
`test_thresholds.py::TestAPMErrorRateAnomaly`.

**Recommended fix:** In `apm.py`, guarantee at least N failed requests per tick when
`anomaly="errorrate"` (e.g., deterministically mark the first request of each tick as
`IsSuccess=False` rather than relying on `rng.random()`), OR increase the baseline
`count_per_tick` under anomaly mode to 100+ so the probabilistic floor is reliable.

**Test status:** `xfail(strict=True)` — tests auto-promote to `XPASS` (error) when bug is fixed.

---

## Notes / No-Bug Findings

- **AzureSQL StorageUsedMB rounding:** `StorageUsedMB` is computed from the raw (unrounded)
  `storage_pct` but `StoragePercent` is rounded to 2 dp in `to_dict()`.  The recomputed
  value from the rounded percent can differ by up to `limit_mb × 0.005 / 100` ≈ 5 MB.
  This is **not a bug** — the math is correct at generation time.  Test adjusted to allow
  ±6 MB tolerance.

- All 5 scenario generators produce records that pass `validate_record()` for both baseline
  and anomaly modes (including values like CpuPercent=95 which are within [0,100] range).

- `LabConfig.load(dry_run=True)` works cleanly with no env vars and no `config/lab.env`.
  `resource_group` returns `""` in dry_run mode (scenarios fall back to `"rg-amlab"` internally).

- APM `latency` anomaly: all request `DurationMs` values are reliably ≥ 500ms with seed=42
  (range injected: [500, 3000]).

- AKS `crashloop` anomaly: first pod of prod cluster gets `PodPhase="Failed"`,
  `PodReason="CrashLoopBackOff"`, `PodRestartCount` in [6, 20] — confirmed.

- All tests are hermetic: no Azure credentials, no network calls, no live `config/lab.env`.


# Decision: Mouse — Docs Inventory

**Date:** 2026-07-15  
**Author:** Mouse (Content & Docs)  
**Status:** COMPLETE

---

## Summary

Four documentation files have been authored under `docs/`. They are ready to be linked from `README.md`.

---

## Docs Inventory

| File | Purpose | Key contents |
|---|---|---|
| `docs/architecture.md` | Ingestion architecture reference | Mermaid + ASCII ingestion-path diagram; resource hierarchy; API version table; 5-scenario deck alignment; Bicep deployment model; generator → lab.env integration |
| `docs/design-decisions.md` | WHY rationale | 9 decisions: Logs Ingestion API over legacy HTTP Data Collector; one DCR/table per scenario; Monitoring Metrics Publisher least-privilege; `uniqueString` naming; `transformKql='source'`; PascalCase schema choices; `southcentralus` default; `lab.env` output contract; subscription-scope Bicep |
| `docs/data-model.md` | Custom table schemas (full column reference) | Scenario key contract (Bicep key → UPPER_SNAKE → PascalCase → stream → table); common columns; per-table column tables with type, description, example; alert-driving columns per table; `lab.env` variable map |
| `docs/troubleshooting.md` | Operational troubleshooting | 10 issues with fixes; ingestion latency (5–15 min); DCR immutableId mismatch; RBAC propagation delay; `DefaultAzureCredential`; Bicep API-version errors; PYTHONPATH; lab.env not found; schema mismatch; deployment scope; `az monitor log-analytics query` examples |

---

## README Cross-References Needed

The following links should be added to `README.md` under a `## Docs` or `## Learn More` section:

```markdown
| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Ingestion path, resource map, API versions, scenario–deck alignment |
| [Design Decisions](docs/design-decisions.md) | Why Logs Ingestion API, one DCR/table per scenario, RBAC, naming |
| [Data Model](docs/data-model.md) | Full column schemas for all 5 custom tables, lab.env variable map |
| [Troubleshooting](docs/troubleshooting.md) | Common issues, CLI query examples, auth fixes |
```

The existing `README.md` already references `docs/` generically on line 102 (`See docs/ for workshop slide deck and datasheet`). The above table should replace or supplement that line.

---

## Cross-References Between Docs

- `architecture.md` → references `data-model.md` (column types), `design-decisions.md` (naming decision), `dozer-generator.md` (anomaly catalog).
- `design-decisions.md` → references `trinity-scaffold-infra.md` and `tank-tables-dcr.md` (accepted decisions).
- `data-model.md` → references `mouse-kql-schema.md` (source of truth) and `tank-tables-dcr.md` (Bicep type confirmation).
- `troubleshooting.md` → references `architecture.md`, `data-model.md`, `design-decisions.md`, and `dozer-generator.md`.


# Schema: KQL Column Contracts (Schema Source of Truth)

> **Authored by:** Mouse (Content & Docs)  
> **Date:** 2026-07-15  
> **Status:** ✅ Approved for DCR + Generator alignment  
> **Consumers:** Tank (DCR schema / Bicep) · Dozer (Python generator models)

---

## Purpose

This document is the **single source of truth** for the per-scenario custom table schemas used by the azure-monitor-workshop. Every column name, type, and semantic defined here must be reflected exactly in:

1. **Tank's DCR/table definitions** — `outputStream` column declarations in Bicep/JSON
2. **Dozer's generator models** — Python dataclass / Pydantic fields that emit rows to the DCE endpoint

Column names are **PascalCase**. Log Analytics DCR-based custom tables preserve declared types without renaming (no `_s`, `_d` suffix appended). Use the types exactly as listed.

---

## Table: VirtualMachines_CL

**Row granularity:** one row per VM per ~1-minute sample interval (metric snapshot)

| Column | Type | Constraints / Notes |
|--------|------|---------------------|
| `TimeGenerated` | `datetime` | Log Analytics injection timestamp; must be UTC |
| `Resource` | `string` | VM display name, e.g. `"vm-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` |
| `Region` | `string` | Azure region slug, e.g. `"southcentralus"` |
| `OSType` | `string` | `"Windows"` \| `"Linux"` |
| `CpuPercent` | `real` | 0–100; CPU utilisation |
| `MemoryAvailableMB` | `real` | Available RAM in MB; ≥ 0 |
| `MemoryTotalMB` | `real` | Total installed RAM in MB; constant per VM |
| `DiskName` | `string` | Volume label: `"C:"` (Windows) or `"/"` (Linux) |
| `DiskFreePercent` | `real` | 0–100; free space on this volume |
| `NetworkInBytes` | `long` | Bytes received in the sample interval; ≥ 0 |
| `NetworkOutBytes` | `long` | Bytes sent in the sample interval; ≥ 0 |

**KQL file:** `kql/virtual-machines.kql`

---

## Table: AppService_CL

**Row granularity:** one row per App Service per ~1-minute sample interval (aggregated metrics)

| Column | Type | Constraints / Notes |
|--------|------|---------------------|
| `TimeGenerated` | `datetime` | Log Analytics injection timestamp; UTC |
| `Resource` | `string` | App Service resource name, e.g. `"app-prod-api"` |
| `ResourceId` | `string` | Full ARM resource ID |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` |
| `Region` | `string` | Azure region slug |
| `AppName` | `string` | Logical application name (may differ from slot name) |
| `RequestCount` | `long` | Total HTTP requests in interval; ≥ 0 |
| `ResponseTimeMs` | `real` | Mean response time (ms) in interval; ≥ 0 |
| `ResponseTimeP95Ms` | `real` | P95 response time (ms) — pre-computed by generator; ≥ 0 |
| `Http2xxCount` | `long` | Count of 2xx responses in interval; ≥ 0 |
| `Http4xxCount` | `long` | Count of 4xx responses in interval; ≥ 0 |
| `Http5xxCount` | `long` | Count of 5xx responses in interval; ≥ 0 |
| `RestartCount` | `int` | App restarts in interval; ≥ 0 |
| `PlanCpuPercent` | `real` | App Service Plan CPU %; 0–100 |
| `PlanMemoryPercent` | `real` | App Service Plan memory %; 0–100 |

**KQL file:** `kql/app-service.kql`

---

## Table: AKS_CL

**Row granularity:** one row per pod **or** per node per ~1-minute sample interval.  
Node-level rows have `PodName` and `ContainerName` empty. Pod-level rows have `NodeName` populated.

| Column | Type | Constraints / Notes |
|--------|------|---------------------|
| `TimeGenerated` | `datetime` | Log Analytics injection timestamp; UTC |
| `Resource` | `string` | AKS cluster name, e.g. `"aks-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` |
| `Region` | `string` | Azure region slug |
| `Namespace` | `string` | Kubernetes namespace; `""` for node-level rows |
| `NodeName` | `string` | Node hostname; always populated |
| `PodName` | `string` | Pod name; `""` for node-only rows |
| `ContainerName` | `string` | Container name; `""` for pod/node rows |
| `NodeCpuPercent` | `real` | Node CPU utilisation; 0–100 |
| `NodeMemoryPercent` | `real` | Node memory utilisation; 0–100 |
| `PodCpuPercent` | `real` | Pod CPU utilisation; 0–100; 0 for node-only rows |
| `PodMemoryPercent` | `real` | Pod memory utilisation; 0–100; 0 for node-only rows |
| `PodRestartCount` | `int` | Cumulative pod restart count; 0 for node-only rows |
| `PodPhase` | `string` | `"Running"` \| `"Pending"` \| `"Failed"` \| `"Succeeded"` \| `"Unknown"` |
| `PodReason` | `string` | Detailed status reason, e.g. `"CrashLoopBackOff"`; `""` if healthy |
| `NodeStatus` | `string` | `"Ready"` \| `"NotReady"` \| `"Unknown"` |
| `PVName` | `string` | PersistentVolume name; `""` if no PV |
| `PVUsagePercent` | `real` | PV disk usage; 0–100; 0 if no PV |
| `HpaName` | `string` | HPA name; `""` if not HPA-managed |
| `HpaCurrentReplicas` | `int` | Current replica count; 0 if no HPA |
| `HpaMaxReplicas` | `int` | Configured max replicas; 0 if no HPA |

**KQL file:** `kql/aks.kql`

---

## Table: AzureSQL_CL

**Row granularity:** one row per database per ~1-minute sample interval (metric snapshot)

| Column | Type | Constraints / Notes |
|--------|------|---------------------|
| `TimeGenerated` | `datetime` | Log Analytics injection timestamp; UTC |
| `Resource` | `string` | Logical server name, e.g. `"sql-prod-01"` |
| `ResourceId` | `string` | Full ARM resource ID |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` |
| `Region` | `string` | Azure region slug |
| `DatabaseName` | `string` | Database name within the server |
| `DtuPercent` | `real` | DTU consumption; 0–100 (use 0 for vCore models) |
| `CpuPercent` | `real` | CPU utilisation; 0–100 |
| `WorkerPercent` | `real` | Worker thread utilisation; 0–100 |
| `ActiveConnections` | `int` | Current active connection count; ≥ 0 |
| `FailedConnections` | `int` | Failed connection attempts in interval; ≥ 0 |
| `DeadlockCount` | `int` | Deadlocks detected in interval; ≥ 0 |
| `StoragePercent` | `real` | Storage used; 0–100 |
| `StorageUsedMB` | `long` | Storage used in MB; ≥ 0 |
| `StorageLimitMB` | `long` | Storage limit in MB; > 0 |
| `QueryDurationMs` | `real` | Mean query duration (ms); ≥ 0 |
| `QueryDurationP95Ms` | `real` | P95 query duration (ms) — pre-computed by generator; ≥ 0 |

**KQL file:** `kql/azure-sql.kql`

---

## Table: APM_CL

**Row granularity:** one row per individual telemetry event (request, dependency call, exception, or trace).  
This is **NOT** a pre-aggregated table — KQL queries must aggregate to derive golden signals.

| Column | Type | Constraints / Notes |
|--------|------|---------------------|
| `TimeGenerated` | `datetime` | Event timestamp; UTC |
| `Resource` | `string` | Service/app name, e.g. `"svc-checkout"` |
| `ResourceId` | `string` | Full ARM resource ID |
| `Environment` | `string` | `"prod"` \| `"staging"` \| `"dev"` |
| `Region` | `string` | Azure region slug |
| `ItemType` | `string` | `"request"` \| `"dependency"` \| `"exception"` \| `"trace"` |
| `OperationName` | `string` | HTTP route or function, e.g. `"GET /api/orders"` |
| `DurationMs` | `real` | End-to-end duration (ms); 0 for exceptions/traces |
| `IsSuccess` | `bool` | `true`=2xx/success; `false`=4xx/5xx/failure |
| `ExceptionType` | `string` | Exception class name; `""` if not an exception row |
| `ExceptionMessage` | `string` | Exception message text; `""` if not an exception row |
| `DependencyType` | `string` | `"HTTP"` \| `"SQL"` \| `"ServiceBus"` \| `"Redis"` \| `""`|
| `DependencyTarget` | `string` | Dependency endpoint/host; `""` if not a dependency row |
| `DependencySuccess` | `bool` | Dependency call succeeded; `true` for non-dependency rows |
| `DependencyDurationMs` | `real` | Dependency call duration (ms); 0 for non-dependency rows |
| `SeverityLevel` | `int` | `0`=verbose `1`=info `2`=warning `3`=error `4`=critical |
| `TraceId` | `string` | W3C trace-id (16-byte hex); `""` if not traced |
| `SpanId` | `string` | W3C span-id (8-byte hex); `""` if not traced |

**KQL file:** `kql/apm.kql`

---

## Alert thresholds (defaults, may be overridden per environment)

| Scenario | Alert condition | Default threshold |
|----------|----------------|-------------------|
| VMs | CPU % sustained | > 90% over 5 min |
| VMs | Disk free | < 10% |
| VMs | Heartbeat missing | > 5 min silence |
| App Service | 5xx error rate | > 5% over 5 min |
| App Service | P95 latency | > 2 000 ms |
| AKS | CrashLoopBackOff | any pod in 5 min |
| AKS | Node NotReady | any node in 5 min |
| Azure SQL | DTU % | > 85% over 5 min |
| Azure SQL | Storage % | > 90% |
| Azure SQL | Deadlocks | > 0 in 5 min |
| APM | Failure rate | > 1% over 5 min |
| APM | P95 latency | > 500 ms |
| APM | Error-budget burn | rolling 1 h failure rate > 2% |

---

## Cross-scenario overview

**KQL file:** `kql/overview.kql`  
Uses `union` across all five tables for:
- Table freshness / row-count roll-up (Panel A)
- Headline signal per scenario in the last 1 h (Panel B)  
- Active issues — rows currently in alert state (Panel C)


# Decision: Mouse — Deck Update (Per-Scenario Live Demo Slides)

**Date:** 2026-07-15
**Author:** Mouse (Content & Docs)
**Status:** DONE — 5 slides added, content + visual QA passed, deck + PDF exported
**Deck:** `docs\Azure-Monitor-Observability-Workshop.pptx`

---

## 1. Summary

Added **5 per-scenario "Live Demo" slides** to the existing workshop deck — one per
workload scenario. The existing theme (fonts, palette, title-icon motif, footer) was
preserved; nothing in the original 38 slides was rebuilt or altered.

| Metric | Before | After |
|---|---|---|
| Total slides | 38 | **43** |
| New slides | — | 5 (positions **39–43**) |
| Original slides changed | — | 0 (visible text identical) |

## 2. Slides added (append-at-end "Live Demo" sequence)

| Pos | Scenario | Table | Reseed anomaly | Alert rule (threshold) |
|---|---|---|---|---|
| 39 | Virtual Machines | `VirtualMachines_CL` | `cpu` | `alert-amlab-vm-cpu-high` — avg CpuPercent > 90% / 5 min (Sev 2) |
| 40 | App Service | `AppService_CL` | `5xx` | `alert-amlab-app-5xx-high` — 5xx rate > 5% / 5 min (Sev 2) |
| 41 | AKS / Containers | `AKS_CL` | `crashloop` | `alert-amlab-aks-crashloop` — any CrashLoopBackOff pod / 5 min (Sev 1) |
| 42 | Azure SQL | `AzureSQL_CL` | `dtu` | `alert-amlab-sql-dtu-high` — avg DtuPercent > 85% / 5 min (Sev 2) |
| 43 | Applications (APM) | `APM_CL` | `errorrate` | `alert-amlab-apm-failure-rate` — request error rate > 1% / 5 min (Sev 2) |

## 3. Insertion point & rationale

Appended all 5 as a **grouped "Live Demo" sequence at the end** (after slide 38, the APM
appendix), rather than interleaving each demo after its scenario blueprint. Rationale:
- Keeps the appendix reference block (slides 33–38) intact and unchanged.
- The 5 demos form one continuous runnable block that maps to the single **2:00–3:30
  hands-on lab** slot, matching how the workshop actually runs.

## 4. Each demo slide contains (theme-matched, not text-only)

- Scenario title + **"· Live Demo"** label, with the matching scenario title-icon reused
  from its appendix slide; blue eyebrow "LIVE DEMO · <SUBTITLE>".
- **① Reseed** command chip (dark, monospace), exact anomaly key from `ghost-scripts.md` §6,
  e.g. `.\scripts\reseed.ps1 -Scenario virtualmachines -Anomaly cpu -Minutes 15`
  (split with a backtick continuation so it fits cleanly and stays runnable).
- **② Run this KQL** — dark code panel with the flagship alert query copied from the real
  `kql\<scenario>.kql`; references only real `<Scenario>_CL` columns.
- **③ Alert fires** — exact rule name (from `tank-alerts-workbooks.md`) + severity + threshold
  + "→ Action Group notifies on-call".
- **What to watch** — full-width navy strip tying the anomaly to the specific workbook tile.

## 5. QA performed

- **Content QA:** `python -m markitdown` — all 5 slides present, no placeholder/lorem text,
  KQL columns verified against `mouse-kql-schema.md`, commands + rule names exact.
- **Visual QA:** rendered to PNG (PowerPoint COM) and inspected by a fresh-eyes subagent.
  One issue found (awkward command wrap) → fixed (backtick continuation) → re-verified clean.
- **Regression:** original slides 1–38 confirmed unchanged (whitespace-normalized diff);
  final deck = 43 slides, 143 media files, appendix icons render correctly.

## 6. Output

- **Deck (overwritten):** `docs\Azure-Monitor-Observability-Workshop.pptx` (43 slides)
- **PDF (for review):** `docs\Azure-Monitor-Observability-Workshop.pdf`

> Note: `scripts\office\soffice.py` fails on Windows (no `socket.AF_UNIX`); rendering + PDF
> export were done via PowerPoint COM (`POWERPNT.EXE`).


# Decision: Tank — Alerts + Workbooks Wiring

**Date:** 2026-07-15  
**Author:** Tank (Infra / IaC Dev)  
**Status:** DONE — az bicep build exits 0, all files lint-clean

---

## 1. New Modules

| File | API version | Scope | Notes |
|---|---|---|---|
| `infra/modules/scheduled-query-alert.bicep` | `Microsoft.Insights/scheduledQueryRules@2022-06-15` | resourceGroup | GA stable; skipQueryValidation=true |
| `infra/modules/workbook.bicep` | `Microsoft.Insights/workbooks@2023-06-01` | resourceGroup | name=guid(displayName) for idempotency |

---

## 2. Alert Rules Created (13 total)

> Alert names below assume default `namePrefix = 'amlab'`.
> Names follow pattern: `alert-{namePrefix}-{scenario}-{condition}`.
> All rules: `threshold=0`, `operator=GreaterThan`, `timeAggregation=Count`,
> `autoMitigate=true`, `skipQueryValidation=true`, scope=workspaceResourceId.

### Virtual Machines (`alerts/virtual-machines.alerts.bicep`)

| Alert name | Severity | evaluationFrequency | windowSize | Threshold | KQL source |
|---|---|---|---|---|---|
| `alert-amlab-vm-cpu-high` | 2 (Warning) | PT5M | PT5M | avg CPU > 90% | kql/virtual-machines.kql [5] verbatim |
| `alert-amlab-vm-disk-low` | 2 (Warning) | PT5M | PT5M | disk free < 10% | kql/virtual-machines.kql [3] adapted |
| `alert-amlab-vm-heartbeat-missing` | 1 (Error) | PT5M | PT1H | last seen > 5 min | kql/virtual-machines.kql [4] adapted |

### App Service (`alerts/app-service.alerts.bicep`)

| Alert name | Severity | evaluationFrequency | windowSize | Threshold | KQL source |
|---|---|---|---|---|---|
| `alert-amlab-app-5xx-high` | 2 (Warning) | PT5M | PT5M | 5xx rate > 5% | kql/app-service.kql [6] verbatim |
| `alert-amlab-app-p95-high` | 2 (Warning) | PT5M | PT5M | P95 > 2000 ms | kql/app-service.kql [7] verbatim |

### AKS (`alerts/aks.alerts.bicep`)

| Alert name | Severity | evaluationFrequency | windowSize | Threshold | KQL source |
|---|---|---|---|---|---|
| `alert-amlab-aks-crashloop` | 1 (Error) | PT5M | PT5M | CrashLoopBackOff any pod | kql/aks.kql [7] verbatim |
| `alert-amlab-aks-node-notready` | 1 (Error) | PT5M | PT5M | NodeNotReady any node | kql/aks.kql [8] verbatim |

### Azure SQL (`alerts/azure-sql.alerts.bicep`)

| Alert name | Severity | evaluationFrequency | windowSize | Threshold | KQL source |
|---|---|---|---|---|---|
| `alert-amlab-sql-dtu-high` | 2 (Warning) | PT5M | PT5M | avg DTU > 85% | kql/azure-sql.kql [6] verbatim |
| `alert-amlab-sql-storage-high` | 2 (Warning) | PT5M | PT5M | storage > 90% | kql/azure-sql.kql [7] verbatim |
| `alert-amlab-sql-deadlocks` | 2 (Warning) | PT5M | PT5M | deadlocks > 0 | kql/azure-sql.kql [8] verbatim |

### APM (`alerts/apm.alerts.bicep`)

| Alert name | Severity | evaluationFrequency | windowSize | Threshold | KQL source |
|---|---|---|---|---|---|
| `alert-amlab-apm-failure-rate` | 2 (Warning) | PT5M | PT5M | error rate > 1% | kql/apm.kql [7] verbatim |
| `alert-amlab-apm-p95-latency` | 2 (Warning) | PT5M | PT5M | P95 > 500 ms | kql/apm.kql [8] verbatim |
| `alert-amlab-apm-error-budget-burn` | 1 (Error) | PT5M | PT1H | rolling 1h error > 2% | kql/apm.kql [9] verbatim |

---

## 3. Workbook Module Wiring

Six workbooks are deployed via `infra/modules/workbook.bicep` from `infra/main.bicep`:

| Workbook key | displayName | JSON file |
|---|---|---|
| `overview` | Azure Monitor Lab — Overview | `workbooks/overview.workbook.json` |
| `virtual-machines` | Azure Monitor Lab — Virtual Machines | `workbooks/virtual-machines.workbook.json` |
| `app-service` | Azure Monitor Lab — App Service | `workbooks/app-service.workbook.json` |
| `aks` | Azure Monitor Lab — AKS | `workbooks/aks.workbook.json` |
| `azure-sql` | Azure Monitor Lab — Azure SQL | `workbooks/azure-sql.workbook.json` |
| `apm` | Azure Monitor Lab — APM | `workbooks/apm.workbook.json` |

**Pattern:** `var workbookConfigs` in `main.bicep` holds static `loadTextContent('../workbooks/<name>.workbook.json')` entries. A `for` loop over this var with `if (deployWorkbooks)` condition deploys all six.

---

## 4. main.bicep Toggle Parameters

Two new `param` declarations added (after `param scenarios array`):

```bicep
param deployWorkbooks bool = true   // set false to skip all workbook deployments
param deployAlerts    bool = true   // set false to skip all alert rule deployments
```

Deploy with alerts disabled: `az deployment sub create ... --parameters deployAlerts=false`  
Deploy with workbooks disabled: `az deployment sub create ... --parameters deployWorkbooks=false`

---

## 5. Bicep Build Validation

```
az bicep build --file infra\main.bicep   → exit 0, no errors (2026-07-15, bicep 0.42.1)
az bicep build --file alerts\*.alerts.bicep → exit 0 each (all 5 files)
```

---

## 6. Notes for Ghost (smoke-test)

Alert rule names in Azure Monitor (resourceGroup `rg-amlab`) — use these to verify firing:
- `alert-amlab-vm-cpu-high`
- `alert-amlab-vm-disk-low`
- `alert-amlab-vm-heartbeat-missing`
- `alert-amlab-app-5xx-high`
- `alert-amlab-app-p95-high`
- `alert-amlab-aks-crashloop`
- `alert-amlab-aks-node-notready`
- `alert-amlab-sql-dtu-high`
- `alert-amlab-sql-storage-high`
- `alert-amlab-sql-deadlocks`
- `alert-amlab-apm-failure-rate`
- `alert-amlab-apm-p95-latency`
- `alert-amlab-apm-error-budget-burn`

All rules use `Count` aggregation against `workspaceResourceId` scope. Trigger each by ensuring Dozer emits rows that breach the KQL `where` conditions listed in Section 2.


# Decision: Tank — Scripts Contract

**Date:** 2026-07-15  
**Author:** Tank (Infra / IaC Dev)  
**Status:** COMPLETE — all 8 scripts authored and validate.ps1 verified exit 0

---

## 1. Summary

Eight scripts authored under `scripts/`:

| File | Primary OS | Purpose |
|---|---|---|
| `common.ps1` | Windows | Dot-sourced helpers: RepoRoot, defaults, Assert-AzCli, Set-AzSubscription, Write-LabEnv |
| `common.sh` | Linux/macOS | Sourced helpers: same as common.ps1 |
| `deploy.ps1` | Windows | Core deploy: bicep build artifacts clean, az deploy, output extraction, lab.env write |
| `deploy.sh` | Linux/macOS | Same deploy flow |
| `validate.ps1` | Windows | Pre-deploy gate: bicep build + lint; optional what-if |
| `validate.sh` | Linux/macOS | Same validate flow |
| `teardown.ps1` | Windows | Delete RG + remove lab.env; -Force skips confirmation |
| `teardown.sh` | Linux/macOS | Same teardown flow |

---

## 2. Invocation Reference

### common.ps1 / common.sh

These are **library files** — not invoked directly. Dot-sourced/sourced at the top of every other script:

```powershell
# PowerShell
. (Join-Path $PSScriptRoot 'common.ps1')
```

```bash
# bash
source "$(dirname "$0")/common.sh"
```

Environment overrides (set before dot-sourcing/sourcing):

| Env var | Default | Description |
|---|---|---|
| `LAB_SUBSCRIPTION_ID` | `00000000-0000-0000-0000-000000000000` | Azure subscription |
| `LAB_NAME_PREFIX` | `amlab` | Bicep namePrefix |
| `LAB_LOCATION` | `southcentralus` | Azure region |
| `LAB_PRINCIPAL_ID` | _(empty — resolved at runtime)_ | Override principalId resolution |

---

### validate.ps1 (PowerShell — run before deploy)

```powershell
# From repo root:
.\scripts\validate.ps1

# With what-if (requires az login):
.\scripts\validate.ps1 -WhatIfMode

# With explicit subscription for what-if:
.\scripts\validate.ps1 -WhatIfMode -SubscriptionId 00000000-0000-0000-0000-000000000000
```

**Verified:** exits 0, all 4 checks PASS (2026-07-15, az-cli 2.83.0, bicep 0.42.1).

### validate.sh (bash)

```bash
# From repo root:
chmod +x scripts/validate.sh
./scripts/validate.sh

# With what-if:
./scripts/validate.sh --what-if
```

---

### deploy.ps1 — THE deploy command for the Coordinator

```powershell
# Standard deploy (from repo root, logged in to Azure):
.\scripts\deploy.ps1

# Full explicit invocation:
.\scripts\deploy.ps1 `
  -SubscriptionId 00000000-0000-0000-0000-000000000000 `
  -PrincipalId 11111111-1111-1111-1111-111111111111 `
  -NamePrefix amlab `
  -Location southcentralus

# What-if only (no actual deploy):
.\scripts\deploy.ps1 -WhatIfMode

# Skip alerts and workbooks (faster deploy for testing):
.\scripts\deploy.ps1 -SkipAlerts -SkipWorkbooks
```

**Prerequisites:**
1. `az login` (or device code flow)
2. `az bicep upgrade` (optional — build works on current 0.42.1)
3. Run validate.ps1 first (recommended)

### deploy.sh (bash)

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Full explicit:
./scripts/deploy.sh \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --principal-id 11111111-1111-1111-1111-111111111111 \
  --name-prefix amlab \
  --location southcentralus

# What-if only:
./scripts/deploy.sh --what-if
```

---

### teardown.ps1 (PowerShell)

```powershell
# Interactive confirmation prompt:
.\scripts\teardown.ps1

# Non-interactive (CI / forced teardown):
.\scripts\teardown.ps1 -Force

# Explicit RG (if lab.env is already removed):
.\scripts\teardown.ps1 -Force -ResourceGroup rg-amlab
```

### teardown.sh (bash)

```bash
chmod +x scripts/teardown.sh

# Interactive:
./scripts/teardown.sh

# Non-interactive:
./scripts/teardown.sh --force

# Explicit RG:
./scripts/teardown.sh --force --resource-group rg-amlab
```

---

## 3. Deploy Flow (step-by-step)

1. **dot-source common.ps1** → sets `$script:RepoRoot`, `$script:SubscriptionId`, `$script:NamePrefix`, `$script:Location`, loads helper functions.
2. **Assert-AzCli** → verifies `az` is in PATH and `az account show` returns 0.
3. **Set-AzSubscription** → `az account set --subscription 00000000-…`.
4. **Resolve principalId**: `-PrincipalId` param → `$env:LAB_PRINCIPAL_ID` → `az ad signed-in-user show --query id -o tsv` → fallback to lab OID `11111111-1111-1111-1111-111111111111`.
5. **Clean stale .json artifacts**: `Get-ChildItem infra/**/*.json, alerts/**/*.json -Recurse | Remove-Item` (prevents BCP037 false positives).
6. **az deployment sub create**:
   ```
   --name amlab-<yyyyMMddHHmmss>
   --location southcentralus
   --template-file infra\main.bicep
   --parameters infra\main.bicepparam
   --parameters principalId=<oid>
   --parameters deployAlerts=true
   --parameters deployWorkbooks=true
   ```
7. **Extract 22 Bicep outputs** via `az deployment sub show --query properties.outputs.<name>.value -o tsv`.
8. **Write-LabEnv** → writes `config/lab.env` in `lab.env.example` format.
9. **Print summary**: RG name, workspace name, DCE endpoint, lab.env path.

---

## 4. Output → lab.env Variable Mapping

Exact output names per `trinity-roles-outputs.md` §3:

| Bicep output | lab.env variable |
|---|---|
| `location` | `LAB_LOCATION` |
| `resourceGroupName` | `LAB_RESOURCE_GROUP` |
| _(az account show)_ | `LAB_SUBSCRIPTION_ID` |
| `workspaceName` | `LAW_NAME` |
| `workspaceCustomerId` | `LAW_ID` |
| `workspaceResourceId` | `LAW_RESOURCE_ID` |
| `dceLogsIngestionEndpoint` | `DCE_LOGS_INGESTION_ENDPOINT` |
| `dcrImmutableIdVirtualMachines` | `DCR_IMMUTABLE_ID_VIRTUAL_MACHINES` |
| `dcrImmutableIdAppService` | `DCR_IMMUTABLE_ID_APP_SERVICE` |
| `dcrImmutableIdAks` | `DCR_IMMUTABLE_ID_AKS` |
| `dcrImmutableIdAzureSql` | `DCR_IMMUTABLE_ID_AZURE_SQL` |
| `dcrImmutableIdApm` | `DCR_IMMUTABLE_ID_APM` |
| `streamVirtualMachines` | `STREAM_VIRTUAL_MACHINES` |
| `streamAppService` | `STREAM_APP_SERVICE` |
| `streamAks` | `STREAM_AKS` |
| `streamAzureSql` | `STREAM_AZURE_SQL` |
| `streamApm` | `STREAM_APM` |
| `tableVirtualMachines` | `TABLE_VIRTUAL_MACHINES` |
| `tableAppService` | `TABLE_APP_SERVICE` |
| `tableAks` | `TABLE_AKS` |
| `tableAzureSql` | `TABLE_AZURE_SQL` |
| `tableApm` | `TABLE_APM` |

---

## 5. Coordinator: Live Deploy Command

Run after merging all infra/scripts work:

```powershell
# 1. Login
az login

# 2. Pre-deploy gate
.\scripts\validate.ps1

# 3. Deploy (creates config/lab.env on success)
.\scripts\deploy.ps1

# 4. Verify lab.env was written
Get-Content config\lab.env
```

The deploy command does NOT need `-PrincipalId` if running interactively — it resolves via `az ad signed-in-user show`.


# Decision: Tank — Custom Tables + DCR Wiring

**Date:** 2026-07-15  
**Author:** Tank (Infra / IaC Dev)  
**Status:** ACCEPTED  

---

## 1. Summary

Custom table and DCR modules are authored and wired into `infra/main.bicep` as a 5-scenario loop. `az bicep build` exits 0 (no errors, az 2.83 / bicep 0.42.1).

---

## 2. DCR Output Structure (for Trinity's outputs.bicep)

`main.bicep` now exposes:

```bicep
output dcrOutputs array = [for (scenario, i) in scenarioConfigs: {
  scenario: scenario.key          // e.g. 'virtualmachines'
  immutableId: dcrs[i].outputs.immutableId
  dcrId: dcrs[i].outputs.dcrId
}]
```

**Resulting array shape (5 elements):**

```json
[
  { "scenario": "virtualmachines", "immutableId": "<dcr-immutable-id>", "dcrId": "<arm-id>" },
  { "scenario": "appservice",      "immutableId": "<dcr-immutable-id>", "dcrId": "<arm-id>" },
  { "scenario": "aks",             "immutableId": "<dcr-immutable-id>", "dcrId": "<arm-id>" },
  { "scenario": "azuresql",        "immutableId": "<dcr-immutable-id>", "dcrId": "<arm-id>" },
  { "scenario": "apm",             "immutableId": "<dcr-immutable-id>", "dcrId": "<arm-id>" }
]
```

**How Trinity should surface this in `lab.env`:**  
Iterate `dcrOutputs` and map each `scenario` key to UPPER_SNAKE using Trinity's convention:

| scenario key | lab.env variable |
|---|---|
| `virtualmachines` | `DCR_IMMUTABLE_ID_VIRTUAL_MACHINES` |
| `appservice` | `DCR_IMMUTABLE_ID_APP_SERVICE` |
| `aks` | `DCR_IMMUTABLE_ID_AKS` |
| `azuresql` | `DCR_IMMUTABLE_ID_AZURE_SQL` |
| `apm` | `DCR_IMMUTABLE_ID_APM` |

---

## 3. Column Set Confirmation (vs mouse-kql-schema.md)

All columns from `mouse-kql-schema.md` are present. Type mapping applied: `bool` → `boolean`.

### VirtualMachines_CL (13 columns)

| Column | LA Type |
|---|---|
| TimeGenerated | datetime |
| Resource | string |
| ResourceId | string |
| Environment | string |
| Region | string |
| OSType | string |
| CpuPercent | real |
| MemoryAvailableMB | real |
| MemoryTotalMB | real |
| DiskName | string |
| DiskFreePercent | real |
| NetworkInBytes | long |
| NetworkOutBytes | long |

### AppService_CL (15 columns)

| Column | LA Type |
|---|---|
| TimeGenerated | datetime |
| Resource | string |
| ResourceId | string |
| Environment | string |
| Region | string |
| AppName | string |
| RequestCount | long |
| ResponseTimeMs | real |
| ResponseTimeP95Ms | real |
| Http2xxCount | long |
| Http4xxCount | long |
| Http5xxCount | long |
| RestartCount | int |
| PlanCpuPercent | real |
| PlanMemoryPercent | real |

### AKS_CL (22 columns)

| Column | LA Type |
|---|---|
| TimeGenerated | datetime |
| Resource | string |
| ResourceId | string |
| Environment | string |
| Region | string |
| Namespace | string |
| NodeName | string |
| PodName | string |
| ContainerName | string |
| NodeCpuPercent | real |
| NodeMemoryPercent | real |
| PodCpuPercent | real |
| PodMemoryPercent | real |
| PodRestartCount | int |
| PodPhase | string |
| PodReason | string |
| NodeStatus | string |
| PVName | string |
| PVUsagePercent | real |
| HpaName | string |
| HpaCurrentReplicas | int |
| HpaMaxReplicas | int |

### AzureSQL_CL (17 columns)

| Column | LA Type |
|---|---|
| TimeGenerated | datetime |
| Resource | string |
| ResourceId | string |
| Environment | string |
| Region | string |
| DatabaseName | string |
| DtuPercent | real |
| CpuPercent | real |
| WorkerPercent | real |
| ActiveConnections | int |
| FailedConnections | int |
| DeadlockCount | int |
| StoragePercent | real |
| StorageUsedMB | long |
| StorageLimitMB | long |
| QueryDurationMs | real |
| QueryDurationP95Ms | real |

### APM_CL (18 columns)

| Column | LA Type |
|---|---|
| TimeGenerated | datetime |
| Resource | string |
| ResourceId | string |
| Environment | string |
| Region | string |
| ItemType | string |
| OperationName | string |
| DurationMs | real |
| IsSuccess | **boolean** ← mapped from `bool` |
| ExceptionType | string |
| ExceptionMessage | string |
| DependencyType | string |
| DependencyTarget | string |
| DependencySuccess | **boolean** ← mapped from `bool` |
| DependencyDurationMs | real |
| SeverityLevel | int |
| TraceId | string |
| SpanId | string |

---

## 4. Stream / Table Contract Summary

| Bicep key | tableName | streamName | DCR name pattern |
|---|---|---|---|
| `virtualmachines` | `VirtualMachines_CL` | `Custom-VirtualMachines_CL` | `dcr-amlab-virtualmachines-<uid6>` |
| `appservice` | `AppService_CL` | `Custom-AppService_CL` | `dcr-amlab-appservice-<uid6>` |
| `aks` | `AKS_CL` | `Custom-AKS_CL` | `dcr-amlab-aks-<uid6>` |
| `azuresql` | `AzureSQL_CL` | `Custom-AzureSQL_CL` | `dcr-amlab-azuresql-<uid6>` |
| `apm` | `APM_CL` | `Custom-APM_CL` | `dcr-amlab-apm-<uid6>` |

---

## 5. Modules Authored

| File | API version | Scope |
|---|---|---|
| `infra/modules/custom-table.bicep` | `Microsoft.OperationalInsights/workspaces/tables@2023-09-01` | resourceGroup |
| `infra/modules/data-collection-rule.bicep` | `Microsoft.Insights/dataCollectionRules@2023-03-11` | resourceGroup |


# Decision: Trinity — Role Assignments + Outputs Contract

**Date:** 2026-07-15  
**Author:** Trinity (Lead / Architect)  
**Status:** ACCEPTED

---

## 1. Summary

`infra/modules/role-assignment.bicep` and `infra/modules/outputs.bicep` are authored and wired into `infra/main.bicep`. `az bicep build` and `az bicep lint` both exit 0 (az-cli 2.83.0 / bicep 0.42.1).

This document is the **deploy-script contract** that Tank (scripts/deploy) and Ghost (smoke-test) must read to populate `config/lab.env`.

---

## 2. Role-Assignment Wiring

### Module: `infra/modules/role-assignment.bicep`

| Param | Type | Default | Description |
|---|---|---|---|
| `dcrName` | string | — | Existing DCR name in the RG |
| `principalId` | string | — | AAD object ID to grant the role |
| `roleDefinitionId` | string | `3913510d-42f4-4e42-8a64-420c390055eb` | Monitoring Metrics Publisher |
| `principalType` | string | `User` | AAD principal type |

- **Scope:** `resourceGroup` — creates one `Microsoft.Authorization/roleAssignments@2022-04-01` scoped to the specified DCR via `resource dcr existing`.
- **Assignment name:** `guid(dcr.id, principalId, roleDefinitionId)` — deterministic, idempotent.
- **Role:** Monitoring Metrics Publisher (`3913510d-42f4-4e42-8a64-420c390055eb`) — least-privilege for Logs Ingestion API.

### Loop in `main.bicep`

```bicep
module roleAssignments './modules/role-assignment.bicep' = [for (scenario, i) in scenarioConfigs: if (!empty(principalId)) {
  name: 'deploy-role-${scenario.key}'
  scope: resourceGroup(rgName)
  dependsOn: [dcrs]
  params: {
    dcrName: 'dcr-${namePrefix}-${scenario.key}-${uniqueSuffix}'
    principalId: principalId
  }
}]
```

- Skipped entirely when `principalId` is empty (CI/no-auth runs).
- `principalId` passed at deploy time: `--parameters principalId=$(az ad signed-in-user show --query id -o tsv)`.

---

## 3. Outputs Contract — Deploy Script Must Read These

The deploy script reads outputs from `az deployment sub show --name <deployment> --query properties.outputs`.

### Base Infrastructure (7 outputs)

| Bicep output name | lab.env variable | Description |
|---|---|---|
| `location` | `LAB_LOCATION` | Azure region |
| `resourceGroupName` | `LAB_RESOURCE_GROUP` | Resource group name |
| `workspaceName` | `LAW_NAME` | Log Analytics Workspace name |
| `workspaceCustomerId` | `LAW_ID` | Workspace customer GUID (for KQL `workspace()` calls) |
| `workspaceResourceId` | `LAW_RESOURCE_ID` | Workspace ARM resource ID |
| `dceLogsIngestionEndpoint` | `DCE_LOGS_INGESTION_ENDPOINT` | DCE ingestion URL |
| `dceId` | *(internal, not in lab.env)* | DCE ARM resource ID |

> ⚠️ **Breaking rename:** Previous output `workspaceId` (ARM ID) is now `workspaceResourceId`. Any script referencing `workspaceId` must be updated.

### Per-Scenario DCR Immutable IDs (5 outputs)

| Bicep output name | lab.env variable |
|---|---|
| `dcrImmutableIdVirtualMachines` | `DCR_IMMUTABLE_ID_VIRTUAL_MACHINES` |
| `dcrImmutableIdAppService` | `DCR_IMMUTABLE_ID_APP_SERVICE` |
| `dcrImmutableIdAks` | `DCR_IMMUTABLE_ID_AKS` |
| `dcrImmutableIdAzureSql` | `DCR_IMMUTABLE_ID_AZURE_SQL` |
| `dcrImmutableIdApm` | `DCR_IMMUTABLE_ID_APM` |

### Per-Scenario Stream Names (5 outputs — static)

| Bicep output name | lab.env variable | Value |
|---|---|---|
| `streamVirtualMachines` | `STREAM_VIRTUAL_MACHINES` | `Custom-VirtualMachines_CL` |
| `streamAppService` | `STREAM_APP_SERVICE` | `Custom-AppService_CL` |
| `streamAks` | `STREAM_AKS` | `Custom-AKS_CL` |
| `streamAzureSql` | `STREAM_AZURE_SQL` | `Custom-AzureSQL_CL` |
| `streamApm` | `STREAM_APM` | `Custom-APM_CL` |

### Per-Scenario Table Names (5 outputs — static)

| Bicep output name | lab.env variable | Value |
|---|---|---|
| `tableVirtualMachines` | `TABLE_VIRTUAL_MACHINES` | `VirtualMachines_CL` |
| `tableAppService` | `TABLE_APP_SERVICE` | `AppService_CL` |
| `tableAks` | `TABLE_AKS` | `AKS_CL` |
| `tableAzureSql` | `TABLE_AZURE_SQL` | `AzureSQL_CL` |
| `tableApm` | `TABLE_APM` | `APM_CL` |

### Convenience Aggregate (not a lab.env var)

`dcrOutputs` — array of objects `{ scenario, immutableId, dcrId, streamName, tableName }` in `scenarioConfigs` order. Deploy script may iterate this instead of reading individual named outputs.

---

## 4. `LAB_SUBSCRIPTION_ID` — Not a Bicep Output

`LAB_SUBSCRIPTION_ID` is obtained by the deploy script from `az account show --query id -o tsv`, not from Bicep outputs.

---

## 5. Suggested Deploy Script Snippet

```bash
DEPLOYMENT_NAME="amlab-$(date +%Y%m%d%H%M%S)"

# Deploy
az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location southcentralus \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam \
  --parameters principalId="$(az ad signed-in-user show --query id -o tsv)"

# Extract outputs
LAB_LOCATION=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.location.value -o tsv)
LAB_RESOURCE_GROUP=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.resourceGroupName.value -o tsv)
LAB_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LAW_NAME=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.workspaceName.value -o tsv)
LAW_ID=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.workspaceCustomerId.value -o tsv)
LAW_RESOURCE_ID=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.workspaceResourceId.value -o tsv)
DCE_LOGS_INGESTION_ENDPOINT=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dceLogsIngestionEndpoint.value -o tsv)

# Per-scenario DCR IDs
DCR_IMMUTABLE_ID_VIRTUAL_MACHINES=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dcrImmutableIdVirtualMachines.value -o tsv)
DCR_IMMUTABLE_ID_APP_SERVICE=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dcrImmutableIdAppService.value -o tsv)
DCR_IMMUTABLE_ID_AKS=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dcrImmutableIdAks.value -o tsv)
DCR_IMMUTABLE_ID_AZURE_SQL=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dcrImmutableIdAzureSql.value -o tsv)
DCR_IMMUTABLE_ID_APM=$(az deployment sub show -n "$DEPLOYMENT_NAME" --query properties.outputs.dcrImmutableIdApm.value -o tsv)

# Stream and table names are static (can be hardcoded or read from outputs)
STREAM_VIRTUAL_MACHINES="Custom-VirtualMachines_CL"
TABLE_VIRTUAL_MACHINES="VirtualMachines_CL"
# ... (repeat for all 5 scenarios)
```

---

## 6. outputs.bicep Design Note

`infra/modules/outputs.bicep` (`targetScope = 'subscription'`) is the **canonical lab.env contract document** in Bicep form. It uses `in`-prefixed parameter names (`inLocation`, `inWorkspaceName`, etc.) to avoid identifier conflicts with same-named outputs. No resources are deployed — it is a pure data pass-through.

Ghost (smoke-test) should validate the above output names are non-empty after a deploy.

---

## 7. Important: Stale `.json` Build Artifact Warning

Pre-compiled `*.json` artifacts co-located with `.bicep` source files (e.g., `alerts/*.json`, `infra/modules/scheduled-query-alert.json`) cause BCP037 false-positive errors in `az bicep build`. Always delete generated JSON artifacts before running the build:

```bash
# Clean stale artifacts before building
Remove-Item infra/**/*.json, alerts/*.json -ErrorAction SilentlyContinue
az bicep build --file infra\main.bicep
```


# Decision: Trinity — Scaffold & Core Infra
**Date:** 2026-07-15  
**Author:** Trinity (Lead / Architect)  
**Status:** ACCEPTED

---

## 1. Naming Convention

All resource names are deterministic and idempotent.  
`<uid6>` = `take(uniqueString(subscription().id, namePrefix), 6)` (stable across re-deployments).

| Resource | Name pattern | Default |
|---|---|---|
| Resource Group | `rg-<namePrefix>` | `rg-amlab` |
| Log Analytics Workspace | `law-<namePrefix>-<uid6>` | `law-amlab-<uid>` |
| Data Collection Endpoint | `dce-<namePrefix>-<uid6>` | `dce-amlab-<uid>` |
| Data Collection Rule (per scenario) | `dcr-<namePrefix>-<scenarioKey>-<uid6>` | `dcr-amlab-virtualmachines-<uid>` |
| Custom Table (per scenario) | `<PascalCase>_CL` | `VirtualMachines_CL` |

Default `namePrefix = 'amlab'`, `location = 'southcentralus'`.

---

## 2. Scenario Key Contract

Five scenarios, three representations each — must be consistent across Bicep, scripts, generator, and tests.

| Bicep array key | env UPPER_SNAKE | PascalCase (table) | Stream name | Table name |
|---|---|---|---|---|
| `virtualmachines` | `VIRTUAL_MACHINES` | `VirtualMachines` | `Custom-VirtualMachines_CL` | `VirtualMachines_CL` |
| `appservice` | `APP_SERVICE` | `AppService` | `Custom-AppService_CL` | `AppService_CL` |
| `aks` | `AKS` | `AKS` | `Custom-AKS_CL` | `AKS_CL` |
| `azuresql` | `AZURE_SQL` | `AzureSQL` | `Custom-AzureSQL_CL` | `AzureSQL_CL` |
| `apm` | `APM` | `APM` | `Custom-APM_CL` | `APM_CL` |

**Rule:** Bicep key = lowercase no-separator. Env key = UPPER_SNAKE. Table = PascalCase + `_CL`. Stream = `Custom-` + PascalCase + `_CL`.

---

## 3. `config/lab.env` Variable Contract

The file `config/lab.env` is **generated** by `scripts/deploy` from Bicep outputs. It is gitignored.  
`config/lab.env.example` is the committed template (all vars shown, empty values).

| Variable | Source | Description |
|---|---|---|
| `LAB_LOCATION` | param | Azure region (`southcentralus`) |
| `LAB_RESOURCE_GROUP` | output `resourceGroupName` | RG name |
| `LAB_SUBSCRIPTION_ID` | `az account show` | Active subscription |
| `LAW_NAME` | output `workspaceName` | Workspace name |
| `LAW_ID` | output `workspaceId` | Full ARM resource ID |
| `DCE_LOGS_INGESTION_ENDPOINT` | output `dceLogsIngestionEndpoint` | Ingestion URL |
| `DCR_IMMUTABLE_ID_<SCENARIO>` | DCR module output `immutableId` | Used by generator |
| `STREAM_<SCENARIO>` | static per table above | Stream name (hardcoded from convention) |
| `TABLE_<SCENARIO>` | static per table above | Table name (hardcoded from convention) |

**Alignment requirement:** Dozer (generator), Mouse (scripts/docs), and Tank (DCR modules) must read these exact variable names.

---

## 4. API Versions (docs-validated)

| Resource | API version | Validated URL |
|---|---|---|
| `Microsoft.Resources/resourceGroups` | `2022-09-01` | learn.microsoft.com |
| `Microsoft.OperationalInsights/workspaces` | `2023-09-01` | [link](https://learn.microsoft.com/en-us/azure/templates/microsoft.operationalinsights/workspaces) |
| `Microsoft.Insights/dataCollectionEndpoints` | `2023-03-11` | [link](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/datacollectionendpoints) |
| `Microsoft.Insights/dataCollectionRules` | `2023-03-11` | [link](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/datacollectionrules) |
| `Microsoft.OperationalInsights/workspaces/tables` | `2023-09-01` | [link](https://learn.microsoft.com/en-us/azure/templates/microsoft.operationalinsights/workspaces/tables) |

> ⚠️ Corrections from task spec: `2023-09-01` does NOT exist for DCE or DCR (no such version in docs); `2022-06-01` does NOT exist for custom tables.  Using nearest stable GA versions above.

---

## 5. Module-Hook TODO Map

The following modules are **Trinity placeholders** for Tank to author:

| Module path | Scope | Key inputs | Key outputs | Depends on |
|---|---|---|---|---|
| `infra/modules/custom-table.bicep` | resourceGroup | `workspaceId`, `tableName` | `tableName` | `log-analytics` |
| `infra/modules/data-collection-rule.bicep` | resourceGroup | `workspaceId`, `dceId`, `dcrName`, `streamName`, `tableName` | `immutableId`, `dcrId` | `custom-table`, `dce` |
| `infra/modules/workbook.bicep` | resourceGroup | `workspaceId`, `location` | `workbookId` | `log-analytics` |
| `infra/modules/scheduled-query-alert.bicep` | resourceGroup | `workspaceId`, scenario alert defs | `alertIds` | `log-analytics` |

Wire points in `infra/main.bicep` are marked with `// TODO(tank): ...` comments at the correct dependency positions.

Role assignment (`// TODO(trinity):`) will be authored by Trinity once DCR outputs are available from Tank.

---

## 6. Bicep Build Validation

```
az bicep build --file infra\main.bicep
```
Result: **exit 0, no errors** (verified 2026-07-15 with az-cli 2.83.0, bicep 0.42.1).



# Decision: Mouse — Observability Agent Walkthrough + Deck (Cost & Agent slides)

**Date:** 2026-07-16
**Author:** Mouse (Content & Docs)
**Status:** DONE — 1 new doc + README link, 2 slides appended, content + visual QA passed, deck + PDF exported
**Deck:** `docs\Azure-Monitor-Observability-Workshop.pptx`
**Doc:** `docs\observability-agent-walkthrough.md`

---

## 1. Summary

Added a hands-on **Observability Agent (preview)** walkthrough doc and appended **2 new slides**
to the workshop deck (an Observability Agent overview + a Monitoring Cost & Best Practices slide).
The existing theme was preserved; nothing in the original 43 slides was rebuilt or altered.

| Metric | Before | After |
|---|---|---|
| Total slides | 43 | **45** |
| New slides | — | 2 (positions **44–45**) |
| Original slides changed | — | 0 (whitespace-normalized text identical) |
| Docs under `docs/` | 4 + deck/pdf | **5** + deck/pdf |

## 2. Deliverables

| # | Deliverable | Path |
|---|---|---|
| 1 | Walkthrough doc | `docs\observability-agent-walkthrough.md` |
| 1 | README link (1 line, near existing `See docs/` note) | `README.md` |
| 2 | Deck slide 44 — Observability Agent (preview) overview | `docs\Azure-Monitor-Observability-Workshop.pptx` |
| 3 | Deck slide 45 — Monitoring Cost & Best Practices | same deck |
| — | Updated PDF export (45 pages) | `docs\Azure-Monitor-Observability-Workshop.pdf` |

## 3. Slide 44 — Observability Agent (append)

Placed right after the Live Demo sequence (slides 39–43) as a "what's next / AI-assisted ops"
beat. Layout: title-icon motif (reused the **slide-25 people+gear** white icon in the blue
`0F6CBD` circle), blue eyebrow "WHAT'S NEXT · AI-ASSISTED OPERATIONS", four numbered concept cards
(What it does / How it fits this workshop / Investigation flow / Roles required), a navy
"PREVIEW LIMITATIONS" strip, and a Microsoft Learn source footnote. Covers: investigates Azure
Monitor alerts via Copilot agent mode; create Azure Monitor issue → AIOps investigation →
summary/findings/remediation; roles = Contributor / Monitoring Contributor / Issue Contributor;
limits = App-Insights alerts only today, recommends but can't remediate, tenant preview access.

## 4. Slide 45 — Monitoring Cost & Best Practices (append)

Mirrored **slide 27** (Common Pitfalls) exactly: red `D1495B` "Pitfall" band, green `3C9D57`
"Do this instead" band with green left-accent bars, 6 alternating-fill rows, reused the
**slide-28 coins** white icon in the blue title circle, and a Microsoft Learn source footnote.
Content (verified): data volume is the #1 cost driver; AMA agent is free — pay for ingested data,
scope the DCR (standard counter set + sampling), avoid duplicate collection, ingestion-time
transformations; Basic/Auxiliary table plans for high-volume debug/audit; commitment tiers /
dedicated cluster; retention tuning + archive; daily cap guardrail; alert on high collection +
workspace insights.

## 5. QA performed

- **Content QA:** python-pptx text extraction — both new slides present, no placeholder/lorem;
  exact strings verified against coordinator's repo facts (reseed command
  `.\scripts\reseed.ps1 -Scenario apm -Anomaly errorrate -Minutes 15`, anomaly keys
  `errorrate`/`latency`, alert rule `alert-amlab-apm-failure-rate` Sev 2, table `APM_CL`,
  roles trio, App-Insights-only limitation).
- **Visual QA:** rendered slides 44 & 45 to PNG via **PowerPoint COM** and inspected fresh-eyes.
  Both clean — icons render, cards/strip aligned, row-2 "Do" text wraps within its card, no
  overflow. No fixes required.
- **Regression:** original slides 1–43 confirmed **unchanged** (whitespace-normalized text diff,
  0 mismatches); final deck = **45** slides.

## 6. Output

- **Deck (overwritten):** `docs\Azure-Monitor-Observability-Workshop.pptx` (45 slides)
- **PDF (overwritten):** `docs\Azure-Monitor-Observability-Workshop.pdf` (45 pages)
- **Doc (new):** `docs\observability-agent-walkthrough.md`
- **README:** +1 link line near the existing `docs/` reference

> Note: `scripts\office\soffice.py` fails on Windows (no `socket.AF_UNIX`); PNG rendering + PDF
> export were done via PowerPoint COM (`POWERPNT.EXE`), consistent with the prior deck update.

## 7. Flags

- The lab's APM alerts are **Log Analytics scheduled-query rules**, but the Observability Agent's
  documented paste-the-ID pattern targets an **Application Insights component**
  (`microsoft.insights/components/COMPONENT_NAME`). The walkthrough makes `COMPONENT_NAME` /
  `ALERT_ID` explicit placeholders and recommends prompt form (a) — "investigate this alert" while
  viewing it in the portal — as the reliable path for this lab. No fact could not be reconciled.
