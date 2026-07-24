# Trinity — History

## Seed Context
- **Project:** azure-monitor-lab — Azure Monitor Observability Demo Lab (requested by Daniel Mauser / @dmauser).
- **Stack:** Bicep (subscription scope), Python 3.11+ generator (azure-monitor-ingestion + DefaultAzureCredential), KQL, Azure Workbooks, scheduled-query alerts, bash + PowerShell scripts, pytest.
- **Decisions:** live deploy · per-scenario custom tables (5) · region `southcentralus` · names from Bicep outputs.
- **Source of truth:** `docs/Azure-Monitor-Observability-Workshop.pptx`, appendix slides 34–38 (5 scenarios).

## Learnings

### Session: 2026-07-15 — Scaffold + Core Infra (Tasks A & B)

**Files created:**
```
README.md
LICENSE
.gitignore                          (extended — was squad-only)
requirements.txt
config/lab.env.example
generator/__init__.py
generator/scenarios/__init__.py
infra/main.bicep                    (subscription-scoped entry point)
infra/main.bicepparam
infra/modules/resource-group.bicep  (subscription-scoped module)
infra/modules/log-analytics.bicep   (RG-scoped module)
infra/modules/data-collection-endpoint.bicep  (RG-scoped module)
.squad/decisions/inbox/trinity-scaffold-infra.md
```

**Naming convention chosen:**
- RG:        `rg-<namePrefix>`                       → `rg-amlab`
- Workspace: `law-<namePrefix>-<uid6>`               → `law-amlab-<uid>`
- DCE:       `dce-<namePrefix>-<uid6>`               → `dce-amlab-<uid>`
- DCRs:      `dcr-<namePrefix>-<scenario>-<uid6>`    → `dcr-amlab-virtualmachines-<uid>`
- `<uid6>` = `take(uniqueString(subscription().id, namePrefix), 6)` — stable, deterministic

**Scenario keys (Bicep array) → UPPER_SNAKE env vars → PascalCase table names:**
| Bicep key       | Env key         | Table              | Stream                      |
|----------------|-----------------|--------------------|-----------------------------|
| virtualmachines | VIRTUAL_MACHINES | VirtualMachines_CL | Custom-VirtualMachines_CL  |
| appservice      | APP_SERVICE      | AppService_CL      | Custom-AppService_CL       |
| aks             | AKS              | AKS_CL             | Custom-AKS_CL              |
| azuresql        | AZURE_SQL        | AzureSQL_CL        | Custom-AzureSQL_CL         |
| apm             | APM              | APM_CL             | Custom-APM_CL              |

**API versions (docs-validated via learn.microsoft.com, 2026-07-15):**
| Resource type | API version used | Notes |
|---|---|---|
| `Microsoft.Resources/resourceGroups` | `2022-09-01` | Stable |
| `Microsoft.OperationalInsights/workspaces` | `2023-09-01` | ✅ Confirmed |
| `Microsoft.Insights/dataCollectionEndpoints` | `2023-03-11` | Task requested 2023-09-01 but that version doesn't exist; 2023-03-11 is latest pre-2024 GA |
| `Microsoft.Insights/dataCollectionRules` | `2023-03-11` | Tank's module — same note as DCE |
| `Microsoft.OperationalInsights/workspaces/tables` | `2023-09-01` | Tank's module; task said 2022-06-01 but that doesn't exist |

**Bicep build:** `az bicep build --file infra\main.bicep` → exit 0, no errors, no warnings.

**Decision file:** `.squad/decisions/inbox/trinity-scaffold-infra.md`

### Session: 2026-07-15 — Roles + Outputs (Task: infra-roles-outputs)

**Files created/updated:**
```
infra/modules/role-assignment.bicep   (new — single-DCR role assignment module)
infra/modules/outputs.bicep           (new — canonical lab.env contract module)
infra/main.bicep                      (updated — role-assignment loop + outputs rewired)
.squad/decisions/inbox/trinity-roles-outputs.md  (new — deploy-script contract)
```

**Role-assignment approach:**
- `role-assignment.bicep` is RG-scoped; takes `dcrName`, `principalId`, `roleDefinitionId` (default = Monitoring Metrics Publisher), `principalType` (default = `User`).
- References the target DCR via `resource dcr existing`, then creates `Microsoft.Authorization/roleAssignments@2022-04-01` scoped directly to that DCR.
- Assignment name = `guid(dcr.id, principalId, roleDefinitionId)` — idempotent.
- Wired in `main.bicep` as a loop over 5 `scenarioConfigs` with `if (!empty(principalId))` guard; `scope: resourceGroup(rgName)`.

**Final `main.bicep` top-level output list (exact names the deploy script must read):**

| Output name                      | lab.env variable                   |
|----------------------------------|------------------------------------|
| `location`                       | `LAB_LOCATION`                     |
| `resourceGroupName`              | `LAB_RESOURCE_GROUP`               |
| `workspaceName`                  | `LAW_NAME`                         |
| `workspaceCustomerId`            | `LAW_ID`                           |
| `workspaceResourceId`            | `LAW_RESOURCE_ID`                  |
| `dceLogsIngestionEndpoint`       | `DCE_LOGS_INGESTION_ENDPOINT`      |
| `dcrImmutableIdVirtualMachines`  | `DCR_IMMUTABLE_ID_VIRTUAL_MACHINES`|
| `dcrImmutableIdAppService`       | `DCR_IMMUTABLE_ID_APP_SERVICE`     |
| `dcrImmutableIdAks`              | `DCR_IMMUTABLE_ID_AKS`             |
| `dcrImmutableIdAzureSql`         | `DCR_IMMUTABLE_ID_AZURE_SQL`       |
| `dcrImmutableIdApm`              | `DCR_IMMUTABLE_ID_APM`             |
| `streamVirtualMachines`          | `STREAM_VIRTUAL_MACHINES`          |
| `streamAppService`               | `STREAM_APP_SERVICE`               |
| `streamAks`                      | `STREAM_AKS`                       |
| `streamAzureSql`                 | `STREAM_AZURE_SQL`                 |
| `streamApm`                      | `STREAM_APM`                       |
| `tableVirtualMachines`           | `TABLE_VIRTUAL_MACHINES`           |
| `tableAppService`                | `TABLE_APP_SERVICE`                |
| `tableAks`                       | `TABLE_AKS`                        |
| `tableAzureSql`                  | `TABLE_AZURE_SQL`                  |
| `tableApm`                       | `TABLE_APM`                        |
| `dcrOutputs` (array)             | (convenience aggregate)            |
| `dceId`                          | (internal)                         |

**Key design choices:**
- `outputs.bicep` uses `in`-prefixed param names (`inLocation`, etc.) to avoid name conflicts with output identifiers of the same name.
- `LAW_ID` = `workspaceCustomerId` (the GUID, not the ARM resource ID) — used for KQL queries. `LAW_RESOURCE_ID` = `workspaceResourceId` (full ARM ID).
- Old `workspaceId` output renamed to `workspaceResourceId`; consumers must update.
- `dcrOutputs` array extended to include `streamName` and `tableName` per element.

**Bicep build/lint:** `az bicep build --file infra\main.bicep` → exit 0. `az bicep lint --file infra\main.bicep` → exit 0. (az-cli 2.83.0 / bicep 0.42.1)

**Important: stale `.json` artifact issue.** Pre-compiled `*.json` files co-located with `.bicep` modules (e.g. `alerts/*.json`, `infra/modules/scheduled-query-alert.json`) caused BCP037 false-positive errors during `bicep build` of the outer main.bicep. Deleting the stale artifacts resolved the issue. **Rule:** delete `infra/**/*.json` and `alerts/*.json` before running `az bicep build --file infra\main.bicep` to ensure clean compilation from source.

**Decision file:** `.squad/decisions/inbox/trinity-roles-outputs.md`

## Cross-Agent Note: Tank Demo VM Module (2026-07-16)

**From:** Scribe (via Coordinator Tank manifest)  
**Date:** 2026-07-16T10:13:53-05:00  
**Note:** Tank has authored `infra/modules/demo-vm.bicep` — a new reusable IaC module for deploying standalone Linux demo VMs with guest metrics collection. The module accepts `workspaceResourceId` as a parameter and creates isolated VNet/NSG/VM/AMA/DCR/DCRA/auto-shutdown (no dependencies on other lab resources). Key lesson: AMA requires `identity: { type: 'SystemAssigned' }` on the VM resource for IMDS MSI token flow. Can be reused for future guest-metrics scenarios.

## Cross-Agent Note: Tank Service Health Alert Module (2026-07-17)

**From:** Scribe (via Coordinator Tank manifest)  
**Date:** 2026-07-17T15:23:48-05:00  
**Note:** Tank has authored `alerts/service-health.alerts.bicep` — a new Bicep IaC module for deploying subscription-level Service Health alerts. Resources: `microsoft.insights/actionGroups@2019-06-01` (Global, email receiver) + `microsoft.insights/activityLogAlerts@2017-04-01` (Global, category=ServiceHealth, subscription-scoped). Live deployed to rg-amlab (provisioningState Succeeded @ 2026-07-17T21:04:59Z). Cost: $0 (free tier). Schema source: learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-bicep. Includes deploy/teardown scripts (PS1 + Bash).
