# Dozer — History

## Seed Context
- **Project:** azure-monitor-workshop (requested by Daniel Mauser / @dmauser).
- **My scope:** the Python telemetry generator + 5 scenario emitters + CLI.
- **Auth:** DefaultAzureCredential via azure-identity; upload via azure-monitor-ingestion LogsIngestionClient.
- **Scenarios (deck slides 34–38):** VM, App Service, AKS, Azure SQL, APM — each with baseline metrics + injectable alert-triggering anomalies.
- **Config source:** config/lab.env (written by deploy from Bicep outputs). `--dry-run` must work with no cloud creds.

## Learnings

### 2026-07-15 — gen-foundation + gen-scenarios complete

**Module layout** (`C:\path\to\azure-monitor-workshop\generator\`):
- `config.py` — `LabConfig.load(dry_run=False)`: dotenv parser + env-var overrides; safe defaults in dry-run mode.
- `models.py` — one `@dataclass` per table (`VirtualMachineRecord`, `AppServiceRecord`, `AKSRecord`, `AzureSQLRecord`, `APMRecord`); each has `.to_dict()` emitting ISO-8601 UTC `TimeGenerated`.
- `time_window.py` — `generate_timestamps(backfill_minutes, interval_seconds, seed, now)` → sorted list of UTC datetimes.
- `validation.py` — `validate_record(scenario_key, record)` → list of error strings; also `required_columns(scenario_key)`.
- `ingestion_client.py` — `IngestionClient(config, dry_run)` with `.upload(scenario_key, records)` → int count.
- `scenarios/virtual_machines.py`, `app_service.py`, `aks.py`, `azure_sql.py`, `apm.py` — each exposes `generate(config, time_window, *, anomaly, seed, count_per_tick)`.
- `main.py` — argparse CLI entry point.

**Anomaly key catalog per scenario:**
| Scenario       | Anomaly key   | Injected condition                              |
|----------------|---------------|-------------------------------------------------|
| virtualmachines| `cpu`         | CpuPercent > 90 %                               |
| virtualmachines| `disk`        | DiskFreePercent < 10 %                          |
| virtualmachines| `heartbeat`   | Suppress all rows for one VM                    |
| appservice     | `5xx`         | Http5xxCount > 5 % of RequestCount             |
| appservice     | `latency`     | ResponseTimeP95Ms > 2 000 ms                    |
| aks            | `crashloop`   | PodReason=CrashLoopBackOff, PodPhase=Failed     |
| aks            | `nodenotready`| NodeStatus=NotReady for one node                |
| azuresql       | `dtu`         | DtuPercent > 85 %                               |
| azuresql       | `storage`     | StoragePercent > 90 %                           |
| azuresql       | `deadlock`    | DeadlockCount > 0                               |
| apm            | `errorrate`   | >=ceil(max(1,3%)) of request rows have IsSuccess=False (deterministic floor) |
| apm            | `latency`     | Request DurationMs > 500 ms (P95 injected)      |

**Dry-run invocation** (no Azure creds required):
```
$env:PYTHONPATH = "C:\path\to\azure-monitor-workshop"
python C:\path\to\azure-monitor-workshop\generator\main.py --scenario all --dry-run --backfill-minutes 5 --seed 42
```

**Key file paths:**
- Schema source of truth: `.squad/decisions/inbox/mouse-kql-schema.md`
- Infrastructure contract: `.squad/decisions/inbox/trinity-scaffold-infra.md`
- Config template: `config/lab.env.example`
- Generator decision doc: `.squad/decisions/inbox/dozer-generator.md`

**Windows note:** Always set `PYTHONPATH=C:\path\to\azure-monitor-workshop` before running generator scripts; avoid Unicode non-ASCII characters in print statements (cp1252 encoding on Windows terminal).

### 2026-07-15 — errorrate determinism fix

**Bug:** `apm.py` used `rng.random() > 0.02` (probabilistic ~2% failure injection) for the
`errorrate` anomaly.  With `seed=42` and a 5-minute window (~70 request rows), all 70 random
draws happened to be > 0.02 → 0 failures → 0.0% failure rate.  The >1% alert threshold would
never fire for short windows with this seed.

**Fix approach:** After the main generation loop, a deterministic floor pass runs whenever
`anomaly == "errorrate"`.  It counts actual failures among request rows and computes
`n_required = math.ceil(max(1, 0.03 * request_row_count))`.  If actual failures < n_required,
the first `deficit` unfailed request rows are flipped to `IsSuccess=False`.  This guarantees
≥3% failure rate (well above the >1% threshold) for any window size and any seed, without
touching the RNG sequence used by everything else.

**Formula:** `n_required = ceil(max(1, 0.03 × request_row_count))`
- 5-min window, seed=42: 70 requests → n_required=3, actual post-fix=3 (4.29%) ✓
- 60-min window, seed=42: ~703 requests → n_required=22 (already had ~18 probabilistic
  failures, floor bumps to 22, ~3.13%) ✓

**Final pytest count:** `165 passed, 0 xfailed, exit 0`  (was: 163 passed, 2 xfailed)

---

## Team Update: 2026-07-16T03:05:00Z

**Lab Status:** ✓ PRODUCTION DEPLOYED & VERIFIED  
**Deployment:** Azure Sub 00000000-0000-0000-0000-000000000000 / RG rg-amlab / Workspace law-amlab-<uid>  
**Test Status:** 165 passed, 0 xfailed (all APM tests passing post-errorrate fix)  
**Alerting:** 9/9 anomaly types firing correctly in live deployment  

Your APM error-rate determinism fix is now verified working in production. The end-to-end telemetry→detection→alerting chain confirmed all alert rules firing as expected. Workshop deck (43 slides) includes your work in the observability demonstration.
