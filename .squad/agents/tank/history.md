# Tank — History

## Seed Context
- **Project:** azure-monitor-workshop (requested by Daniel Mauser / @dmauser).
- **My scope:** per-scenario custom tables + DCRs + DCE + LA workspace + workbook/alert modules + alerts/*.alerts.bicep + deploy/validate/teardown scripts (bash + pwsh).
- **Ingestion path:** generator → DCE Logs Ingestion endpoint → DCR stream `Custom-<Scenario>_CL` → transformKql → `<Scenario>_CL` table.
- **Scenarios (deck slides 34–38):** virtual-machines, app-service, aks, azure-sql, apm. Signals/alerts per team.md Project Context.
- **Region:** southcentralus. All names surfaced via Bicep outputs (Trinity owns outputs).

## Learnings

### 2026-07-15 — infra-tables-dcr

**Module paths authored:**
- `infra/modules/custom-table.bicep` — `Microsoft.OperationalInsights/workspaces/tables@2023-09-01`, parent = existing workspace, Analytics plan, 30-day retention.
- `infra/modules/data-collection-rule.bicep` — `Microsoft.Insights/dataCollectionRules@2023-03-11`, wires DCE → stream → logAnalytics destination → dataFlow with `transformKql: 'source'`.

**Column → LA type mapping decisions:**
- `bool` (Mouse schema) → `boolean` (Log Analytics DCR API requirement)
- `int`, `long`, `real`, `string`, `datetime` pass through unchanged
- `TimeGenerated` (`datetime`) is mandatory in every table schema; included in both the table `columns` and the `streamDeclarations` columns (both required)

**How immutableIds surface to main outputs:**
- `dcrs[i].outputs.immutableId` collected via a loop output in `main.bicep`:
  `output dcrOutputs array = [for (scenario, i) in scenarioConfigs: { scenario, immutableId, dcrId }]`
- Trinity's `outputs.bicep` should iterate this array to emit `DCR_IMMUTABLE_ID_<UPPER_SNAKE>` into `config/lab.env`

**Bicep build result (infra-tables-dcr):**
- `az bicep build --file infra\main.bicep` → exit 0, no errors (az 2.83, bicep 0.42.1, 2026-07-15)
- Only output: version upgrade notice (v0.45.15 available), not an error

**Architecture notes:**
- `scenarioConfigs` var is defined inline in `main.bicep`; Dozer still uses `mouse-kql-schema.md` as its authoritative source
- DCR modules use `dependsOn: [customTables]` (all tables) so no DCR deploys before all tables exist

### 2026-07-15 — alerts-workbooks

**scheduledQueryRules API version:** `Microsoft.Insights/scheduledQueryRules@2022-06-15` (stable GA).
Validated at https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/2022-06-15/scheduledqueryrules.
The preview `2023-03-15-preview` also exists; GA `2022-06-15` chosen per risk preference.

**Workbooks API version:** `Microsoft.Insights/workbooks@2023-06-01` (stable GA).
Validated at https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/2023-06-01/workbooks.

**Known Bicep compiler quirk (v0.42.1):** Do NOT name a param `description` — Bicep parses `@description(...)` decorators as expression references to the `description` identifier and emits BCP062/BCP079 errors. Renamed to `alertDescription` in `scheduled-query-alert.bicep`.

**Alert list per scenario:**

| Scenario | Alert name (namePrefix=amlab) | Threshold | windowSize | KQL source |
|---|---|---|---|---|
| VM | `alert-amlab-vm-cpu-high` | avg CPU > 90% | PT5M | kql/virtual-machines.kql [5] |
| VM | `alert-amlab-vm-disk-low` | disk free < 10% | PT5M | kql/virtual-machines.kql [3] adapted |
| VM | `alert-amlab-vm-heartbeat-missing` | last seen > 5 min | PT1H | kql/virtual-machines.kql [4] adapted |
| App Service | `alert-amlab-app-5xx-high` | 5xx rate > 5% | PT5M | kql/app-service.kql [6] |
| App Service | `alert-amlab-app-p95-high` | P95 > 2000 ms | PT5M | kql/app-service.kql [7] |
| AKS | `alert-amlab-aks-crashloop` | CrashLoopBackOff any pod | PT5M | kql/aks.kql [7] |
| AKS | `alert-amlab-aks-node-notready` | NodeNotReady any node | PT5M | kql/aks.kql [8] |
| Azure SQL | `alert-amlab-sql-dtu-high` | avg DTU > 85% | PT5M | kql/azure-sql.kql [6] |
| Azure SQL | `alert-amlab-sql-storage-high` | storage > 90% | PT5M | kql/azure-sql.kql [7] |
| Azure SQL | `alert-amlab-sql-deadlocks` | deadlocks > 0 | PT5M | kql/azure-sql.kql [8] |
| APM | `alert-amlab-apm-failure-rate` | error rate > 1% | PT5M | kql/apm.kql [7] |
| APM | `alert-amlab-apm-p95-latency` | P95 > 500 ms | PT5M | kql/apm.kql [8] |
| APM | `alert-amlab-apm-error-budget-burn` | rolling 1h error > 2% | PT1H | kql/apm.kql [9] |

**Workbook module pattern (loadTextContent paths):**
- `workbook.bicep` takes `displayName`, `serializedData`, `sourceId`, `location`.
- `name = guid(displayName)` — deterministic across re-deployments.
- `infra/main.bicep` uses `loadTextContent('../workbooks/<name>.workbook.json')` (relative to `infra/`).
- Workbooks are deployed in a `for` loop over `var workbookConfigs` which holds 6 static `loadTextContent` entries.
- `loadTextContent` must be called statically in a `var` array (not dynamically in a loop body).

**`az bicep build` results:**
- `infra/main.bicep` → exit 0, no errors (az 2.83, bicep 0.42.1, 2026-07-15)
- All 5 `alerts/*.alerts.bicep` → exit 0, no errors

### 2026-07-15 — scripts

**Script inventory (all under `scripts/`):**

| File | Purpose |
|---|---|
| `common.ps1` | Dot-sourced helpers: RepoRoot, SubscriptionId/NamePrefix/Location defaults, `Assert-AzCli`, `Set-AzSubscription`, `Write-LabEnv` |
| `common.sh` | Sourced helpers: REPO_ROOT, same defaults, `assert_az_cli`, `set_az_subscription`, `write_lab_env` |
| `deploy.ps1` | Core deploy: clean artifacts, resolve principalId, `az deployment sub create`, extract all 22 outputs, write `config/lab.env` |
| `deploy.sh` | Same flow as deploy.ps1 for Linux/macOS |
| `validate.ps1` | Pre-deploy gate: clean artifacts, `az bicep build`, `az bicep lint`, optional what-if |
| `validate.sh` | Same flow as validate.ps1 |
| `teardown.ps1` | Delete RG (`--no-wait`), remove `config/lab.env`; `-Force` skips confirm prompt |
| `teardown.sh` | Same flow as teardown.ps1 |

**Deploy flow:**
1. `common.ps1` dot-sourced → sets `$script:RepoRoot`, defaults, functions.
2. `deploy.ps1` cleans stale `.json` artifacts (BCP037 prevention).
3. `az account set --subscription` called first.
4. `principalId` resolved: param → `$env:LAB_PRINCIPAL_ID` → `az ad signed-in-user show` → lab default OID `<PRINCIPAL_ID>`.
5. `az deployment sub create --name amlab-<timestamp>` runs against `infra/main.bicep` + `infra/main.bicepparam`.
6. All 22 Bicep outputs extracted via `az deployment sub show --query properties.outputs.<name>.value -o tsv`.
7. `Write-LabEnv` writes `config/lab.env` in the `lab.env.example` format.

**How config/lab.env is written:**
- `Write-LabEnv` in `common.ps1` (and `write_lab_env` in `common.sh`) takes a hashtable/env vars and writes a templated file matching `config/lab.env.example` format.
- Includes both `LAW_ID` (customer GUID, from `workspaceCustomerId`) and `LAW_RESOURCE_ID` (ARM ID, from `workspaceResourceId`) per trinity-roles-outputs.md contract.
- Static stream/table names are read from Bicep outputs (which return the hardcoded values) — no separate hardcoding in scripts.

**validate.ps1 result (2026-07-15):**
- All 4 checks PASS: az CLI present, stale .json cleaned, `az bicep build` exit 0, `az bicep lint` exit 0.
- Only output beyond PASS: version upgrade notice (v0.45.15 available) — not an error.

---

## Team Update: 2026-07-16T03:05:00Z

**Lab Status:** ✓ PRODUCTION DEPLOYED & VERIFIED  
**Deployment:** Azure Sub 00000000-0000-0000-0000-000000000000 / RG rg-amlab / Workspace law-amlab-<uid>  
**Infrastructure Health:** All 22 Bicep outputs extracted + config/lab.env populated correctly  
**Alerting:** 13/13 scheduled-query rules ENABLED; 9/9 anomaly types detected firing in live deployment  

Your infrastructure automation scripts (deploy.ps1, deploy.sh, validate.ps1, validate.sh, teardown.ps1, teardown.sh) have been successfully deployed to production. All 5 custom tables populated (2,400 rows), all DCRs wired, all alert rules active and firing on live anomalies. Lab is repeatable and documented.

---

## Learnings: 2026-07-16 — demo-vm module

### Module design

**File:** `infra/modules/demo-vm.bicep`  
**Scope:** resourceGroup. Entirely additive — does not reference any existing resource by name except the passed-in `workspaceResourceId`.

**Resources authored in one module:**
- `Microsoft.Network/networkSecurityGroups@2023-09-01` — zero inbound allow rules; DenyAllInBound default is the zero-trust posture.
- `Microsoft.Network/virtualNetworks@2023-09-01` — 10.10.0.0/24 / snet-vmguest 10.10.0.0/27 with NSG attached on subnet.
- `Microsoft.Network/networkInterfaces@2023-09-01` — private IP only, no PIP. `deleteOption: Delete` on the NIC so VM teardown removes it automatically.
- `Microsoft.Compute/virtualMachines@2024-07-01` — Ubuntu 22.04 LTS Gen2 (`Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest`, confirmed live in southcentralus 2026-07-16). Standard_LRS 30 GB OS disk with `deleteOption: Delete`. SSH-key-only auth.
- `Microsoft.Compute/virtualMachines/extensions@2024-07-01` (AzureMonitorLinuxAgent) — publisher `Microsoft.Azure.Monitor`, autoUpgradeMinorVersion + enableAutomaticUpgrade both true.
- `Microsoft.Insights/dataCollectionRules@2023-03-11` — kind `Linux`, 6 lean performance counters at 60 s, streams `Microsoft-InsightsMetrics` + `Microsoft-Perf` both to the lab workspace. No syslog, no data transform — minimum cost.
- `Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11` — scoped to the VM via `scope: vm`, `dependsOn: [amaExt]`.
- `Microsoft.DevTestLab/schedules@2018-09-15` — name pattern `shutdown-computevm-<vmName>` required by Azure portal. `taskType: ComputeVmShutdownTask`, `timeZoneId: Central Standard Time`, 19:00 daily, `notificationSettings.status: Disabled`.

### Chosen SKU and why

**Standard_B2ats_v2** (2 vCPU / 1 GiB RAM) — cheapest v2-series burstable available with no zone/quota restriction in southcentralus. B1s and B2s carry a "Zone" restriction confirmed at planning time. B2ats_v2 is verified unrestricted by coordinator.

### DCR stream set

`Microsoft-InsightsMetrics` — feeds `InsightsMetrics` table (VM Insights, KQL-queryable).  
`Microsoft-Perf` — feeds `Perf` table (classic performance counter table, KQL-queryable).  
Both on one performanceCounters data source, 6 counters, 60 s cadence. No syslog, no extra tables.

### Key file paths

```
infra/modules/demo-vm.bicep       — Bicep module
scripts/deploy-vm.sh              — bash deploy script
scripts/deploy-vm.ps1             — PowerShell deploy script (UTF-8 BOM)
scripts/teardown-vm.sh            — bash teardown (VM resources only)
scripts/teardown-vm.ps1           — PowerShell teardown (UTF-8 BOM)
docs/metrics-demo-vm.md           — deployment runbook + KQL demo
config/vm.env                     — generated on deploy, gitignored
config/keys/vm-amlab-ed25519      — SSH private key, gitignored
config/keys/vm-amlab-ed25519.pub  — SSH public key
```

### AMA requires system-assigned managed identity (live deployment finding)

During live deployment, AMA extension showed "Provisioning succeeded" but the agent failed to download DCR configuration. Root cause: `mdsd.err` showed repeated `Failed to get MSI token from IMDS endpoint: http://169.254.169.254 ErrorCode:-2146041343` — AMA could not authenticate because the VM had no managed identity.

**Fix:** Added `identity: { type: 'SystemAssigned' }` to the VM resource in `demo-vm.bicep`. The Bicep module is authoritative and now correct. For any existing VM missing this: `az vm identity assign -g rg-amlab -n <vmname> --identities '[system]'` followed by `systemctl restart azuremonitoragent` in-guest.

**Symptom checklist if AMA isn't collecting:**
1. `mdsd.err` shows MSI/IMDS errors → add system identity
2. `config-cache/configchunks/` is empty → identity missing or DCRA not linked
3. Once identity + DCRA are present, config chunk appears within ~2 min of AMA restart

### Live deployment results (2026-07-16)

- **VM:** `vm-amlab-<uid>`, private IP `10.10.0.4`, RG `rg-amlab`, southcentralus
- **DCR:** `dcr-amlab-vmguest-<uid>`
- **DCRA:** `dcra-vmguest-2yvzaw`
- **AMA state:** Provisioning succeeded ✅
- **Perf table:** ✅ all 6 counters flowing at T+20 min
- **InsightsMetrics table:** ✅ data from VM flowing (`_ResourceId` confirmed), `Namespace`/`Name` fields empty during first-collection schema initialization (self-resolves ~20–30 min)
- **Host Percentage CPU:** confirmed spike to 56.46% during `dd` stress run, 2.12–4.16% during `openssl` runs
- **Config/vm.env:** written; private key at `config/keys/vm-amlab-ed25519` (gitignored)


Bicep single-quoted strings interpret `\` as an escape character. Performance counter paths that use `\` (e.g. `Processor(*)\% Processor Time`) must be written as `'Processor(*)\\% Processor Time'` in Bicep source. The compiled ARM JSON has the single backslash as expected.

---

## Learnings: 2026-07-17 — service-health-alert

### Service Health alert pattern

**Service Health alerts = Activity Log alerts with `category == ServiceHealth`.**
- API versions validated against https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-bicep
  - Action group: `microsoft.insights/actionGroups@2019-06-01`
  - Activity log alert: `microsoft.insights/activityLogAlerts@2017-04-01`
- **Both resources MUST use `location: 'Global'`** — Service Health alerts are only supported in the global region (public cloud). Deploying at resourceGroup scope is still correct; the resource location is simply Global.
- Alert scope = `subscription().id` (the full subscription ARM path `/subscriptions/<guid>`).
- Condition: `allOf: [{ field: 'category', equals: 'ServiceHealth' }]` — single condition captures all ServiceHealth event types (Incidents, Maintenance, Advisories, Security advisories).
- Cost: **$0** — Activity Log alerts are free; email notifications via action groups are effectively free.

### Key file paths created

```
alerts/service-health.alerts.bicep              — Bicep module (action group + alert)
scripts/deploy-service-health-alert.ps1         — PowerShell deploy script
scripts/deploy-service-health-alert.sh          — Bash deploy script
scripts/teardown-service-health-alert.ps1       — PowerShell teardown (idempotent)
scripts/teardown-service-health-alert.sh        — Bash teardown (idempotent)
```

### Live deployment result (2026-07-17)

- **Subscription:** 00000000-0000-0000-0000-000000000000 (Your-Subscription)
- **Resource Group:** rg-amlab
- **Deployment name:** amlab-svc-health-20260717
- **provisioningState:** Succeeded
- **Activity Log Alert:** `alert-amlab-service-health`
  - ID: `/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-amlab/providers/microsoft.insights/activityLogAlerts/alert-amlab-service-health`
  - location: Global, enabled: true, scopes: [subscription id], condition: category=ServiceHealth
- **Action Group:** `ag-amlab-service-health`
  - ID: `/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-amlab/providers/microsoft.insights/actionGroups/ag-amlab-service-health`
  - location: Global, enabled: true, emailReceivers: [you@example.com], groupShortName: amlabSvcHlth

### az bicep build + lint results (2026-07-17)

- `az bicep build --file alerts\service-health.alerts.bicep` → exit 0, no errors
- `az bicep lint --file alerts\service-health.alerts.bicep` → exit 0, no errors
- Tool versions: az 2.83, bicep 0.42.1

