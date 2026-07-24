# Ghost — History

## Seed Context
- **Project:** azure-monitor-lab (requested by Daniel Mauser / @dmauser).
- **My scope:** pytest suite (config, time_window, scenarios, thresholds, payload_schema), seed/reseed/smoke-test scripts, and the two validation gates.
- **Gate 1 (local):** az bicep build all modules, bicep lint, pytest, shellcheck (.sh), PSScriptAnalyzer (.ps1).
- **Gate 2 (cloud):** what-if → deploy → seed → smoke-test confirms rows per `<Scenario>_CL` table + alert firing.
- Tests must be hermetic (use generator `--dry-run`, no Azure creds).

## Learnings

### 2026-07-15 — Seed / Reseed / Smoke-Test scripts authored

**Script inventory:**

| File | Purpose |
|---|---|
| `scripts/seed.ps1` | Primary Windows script — loads lab.env, sets PYTHONPATH, runs baseline pass + 12 anomaly passes |
| `scripts/seed.sh` | Bash equivalent for portability |
| `scripts/reseed.ps1` | Parameterised re-run: `-Minutes N`, `-Anomaly KEY`, `-Scenario`, `-Seed N` |
| `scripts/reseed.sh` | Bash equivalent; flags: `--minutes`, `--anomaly`, `--scenario`, `--seed` |
| `scripts/smoke-test.ps1` | Post-deploy gate: table row-count retry loop + alert rule provisioning check + PASS/FAIL table |
| `scripts/smoke-test.sh` | Bash equivalent; uses Python (project dep) for JSON parsing — avoids jq requirement |

All scripts dot-source/source `scripts/common.{ps1,sh}` if present (Tank owns it) and degrade gracefully by parsing `config/lab.env` directly when common is absent.

**Smoke-test retry strategy:**
Custom-log ingestion into Log Analytics typically lags 5–15 minutes after the Logs Ingestion API call returns success. The smoke-test polls every 60 s for up to 20 min (configurable via `-MaxWaitMinutes` / `--max-wait-minutes`). Each pending table is queried independently so fast-ingesting tables stop being re-queried once they pass. If any table still has 0 rows after the retry window expires, the script exits non-zero.

**Alert-verification approach:**
`az monitor scheduled-query list -g <RG>` retrieves all scheduledQueryRules and their `enabled` status. The smoke-test checks all 13 expected rule names (from tank-alerts-workbooks.md) exist in the RG and are not disabled. Fired-alert history is NOT accessible via az CLI for scheduledQueryRules — the script documents a portal path (Monitor → Alerts → Alert history) and a REST call to `Microsoft.AlertsManagement/alerts?alertState=Fired` as the manual verification step.

**Generator dry-run validation (2026-07-15):**
- `python generator/main.py --scenario all --dry-run --backfill-minutes 5 --seed 42` → exit 0, all 5 scenarios generated correctly.
- `python generator/main.py --scenario virtualmachines --anomaly cpu --dry-run --backfill-minutes 5 --seed 42` → exit 0, CpuPercent=96.44 (>90% threshold confirmed).



### 2026-07-15 — PS5.1 compatibility fix in smoke-test.ps1

**Bug:** `if`-as-expression inside `(...)` in argument position is PS7-only.
`Add-Member ... -NotePropertyValue (if ($val) { $val } else { ... })` threw
`"The term 'if' is not recognized"` on Windows PowerShell 5.1.

**Rule (PS5.1):** `$x = if (...) { ... }` (statement-assignment) is valid.
`SomeCmdlet -Param (if (...) { ... })` (argument-position sub-expression) is NOT.

**Fix:** Hoist the conditional into a statement-assigned variable first, then pass the variable:
```powershell
$tn = if ($val) { $val } else { $tableDefaults[$t.EnvVar] }
$t | Add-Member -NotePropertyName 'TableName' -NotePropertyValue $tn
```

**Lesson for future PS scripts:** Never wrap `if` directly inside `(...)` when the expression
is used as a cmdlet argument. Always hoist to a named variable first. This pattern
can bite anywhere `if`/`switch`/`foreach` would be used inline as a value in PS5.1.

**Verification:** `[System.Management.Automation.PSParser]::Tokenize(...)` → 0 errors;
`[System.Management.Automation.Language.Parser]::ParseFile(...)` → 0 AST errors.



**Final pytest result:** 163 passed, 2 xfailed — exit code 0.

**conftest.py approach:** Single `tests/conftest.py` at the tests/ root inserts the
repo root (`Path(__file__).parent.parent`) into `sys.path[0]`.  This lets
`import generator.*` resolve from any working directory without needing
`PYTHONPATH` pre-set.  No `tests/__init__.py` needed.

**Generator quirks found:**

1. **APM errorrate — probabilistic injection failure (seed-specific):**
   `apm.py` uses `rng.random() > 0.02` for `is_success` under `errorrate` anomaly.
   With `seed=42` and only 70 request rows (5-min window, 20 events/tick),
   all 70 draws exceed 0.02 → 0 failures, 0.0% rate — below the 1% alert threshold.
   A 60-min window (703 requests, seed=42) yields 18 failures (2.56%).
   Tests covering the small-window case are marked `xfail(strict=True)` and routed
   to Dozer.  Additional large-window tests provide green coverage of the feature.

2. **AzureSQL StorageUsedMB vs StoragePercent rounding drift:**
   `azure_sql.py` computes `StorageUsedMB = int(limit_mb * raw_pct / 100)` from the
   raw (unrounded) `storage_pct`, but `to_dict()` emits `StoragePercent = round(storage_pct, 2)`.
   Recomputing `StorageUsedMB` from the rounded percent can differ by up to
   `limit_mb * 0.005 / 100` ≈ 5 MB for the largest server (102 400 MB limit).
   Test was fixed to allow ±6 MB tolerance (this is a test authoring issue, not a
   generator bug — the math is correct at generation time).

---

## Team Update: 2026-07-16T03:05:00Z

**Lab Status:** ✓ PRODUCTION DEPLOYED & VERIFIED  
**Deployment:** Azure Sub 00000000-0000-0000-0000-000000000000 / RG rg-amlab / Workspace law-amlab-<uid>  
**Test Status:** 165 passed, 0 xfailed (2 APM errorrate xfail tests converted to passing after Dozer fix)  
**QA Smoke-Test:** PASS (exit 0) — all 5 custom tables ingested (2,400 rows), all 13 alerts ENABLED, 9 alerts fired on live anomalies  

Your QA automation scripts (seed.ps1, reseed.ps1, smoke-test.ps1 + Bash equivalents) have executed successfully against live infrastructure. PS 5.1 UTF-8 BOM compatibility bug is documented for future maintainers. End-to-end data ingestion → alert firing chain verified working.

## Cross-Agent Note: Tank Service Health Alert Module (2026-07-17)

**From:** Scribe (via Coordinator Tank manifest)  
**Date:** 2026-07-17T15:23:48-05:00  
**Note:** Tank has authored `alerts/service-health.alerts.bicep` + deploy/teardown scripts. New subscription-level Service Health alert IaC module (ADDITIVE ONLY). Live deployed to rg-amlab (Succeeded @ 2026-07-17T21:04:59Z). Includes activity log alert filtering on `category=ServiceHealth` (all Service Health event types). Relevant to Ghost's smoke-test gate 2 (cloud deploy): this new module does NOT require custom-table seeding or validation — it is monitoring subscription-level Service Health events, independent of the 5-scenario generators.