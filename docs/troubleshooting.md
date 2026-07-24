# Troubleshooting Guide: Azure Monitor Observability Demo Lab

> **Last updated:** 2026-07-15  
> For generator CLI reference see `docs/architecture.md` and `.squad/decisions/inbox/dozer-generator.md`.

---

## Quick Diagnostics Checklist

Before diving into specific issues, run through this checklist:

1. `az account show` — confirm the correct subscription is active.
2. Check `config/lab.env` exists and is populated (non-empty `DCE_LOGS_INGESTION_ENDPOINT`).
3. `az bicep build --file infra\main.bicep` — confirm zero errors.
4. Try a dry-run to confirm the generator itself works: see [Generator dry-run](#generator-dry-run-no-azure-required).

---

## Issue 1 — Empty Query Results (No Rows Returned)

**Symptom:** KQL queries against `VirtualMachines_CL`, `AppService_CL`, `AKS_CL`, `AzureSQL_CL`, or `APM_CL` return no rows.

### Cause A: Custom-log ingestion latency

The Logs Ingestion API has an **end-to-end latency of 5–15 minutes** from the time the generator POSTs records to the time they are queryable in Log Analytics. This is normal and documented behavior.

**Fix:** Wait 10–15 minutes after the first generator run, then re-run your query with a wider time range (`TimeRange = Last 1 hour`).

### Cause B: Time range too narrow

The default workbook time range may be shorter than the ingestion lag.

**Fix:** In the workbook or Log Analytics query editor, set the time range to **Last 1 hour** or **Last 4 hours**.

### Cause C: Generator was run in `--dry-run` mode

Dry-run prints records to stdout but does **not** upload to Azure.

**Fix:** Run without `--dry-run`:

```powershell
$env:PYTHONPATH = "C:\path\to\azure-monitor-workshop"
python generator/main.py --scenario all --backfill-minutes 15
```

### Cause D: Custom table not yet created

If Bicep deployment did not complete successfully, the table may not exist.

**Fix:**

```powershell
# Check if the table exists
az monitor log-analytics workspace table show `
  --resource-group rg-amlab `
  --workspace-name <LAW_NAME> `
  --name VirtualMachines_CL
```

If this returns a `ResourceNotFound` error, re-run the Bicep deployment.

---

## Issue 2 — DCR `immutableId` Mismatch

**Symptom:** Generator exits with `1` and logs an error like `The stream 'Custom-VirtualMachines_CL' was not found in the DCR` or `403 Forbidden`.

**Cause:** The `DCR_IMMUTABLE_ID_<SCENARIO>` in `config/lab.env` does not match the deployed DCR. This happens when:
- The lab was redeployed and `config/lab.env` was not refreshed.
- `config/lab.env` was manually edited with an incorrect value.
- The generator is pointing at a different subscription than the one where the DCR was deployed.

**Fix:**

```powershell
# Re-read the DCR immutable IDs from the deployment
az deployment sub show `
  --name deploy-rg `
  --query "properties.outputs.dcrOutputs.value" `
  --output json

# Or list DCRs in the resource group
az monitor data-collection rule list `
  --resource-group rg-amlab `
  --query "[].{name:name, immutableId:immutableId}" `
  --output table
```

Update `config/lab.env` with the correct values, or re-run `scripts/deploy` to regenerate it.

---

## Issue 3 — Role Assignment Propagation Delay

**Symptom:** Generator fails with `AuthorizationFailed` or `403` immediately after deployment.

**Cause:** Azure RBAC role assignments can take **1–5 minutes** to propagate. The generator's principal may not yet have the **Monitoring Metrics Publisher** role on the DCRs and DCE.

**Fix:** Wait 2–5 minutes and retry. To verify the role assignment exists:

```powershell
# Check role assignments on a specific DCR
az role assignment list `
  --scope <DCR_ARM_ID> `
  --query "[?roleDefinitionName=='Monitoring Metrics Publisher']" `
  --output table
```

If the assignment is missing, re-run the deployment with the correct `principalId` parameter, or assign manually:

```powershell
az role assignment create `
  --assignee <principalId> `
  --role "Monitoring Metrics Publisher" `
  --scope <DCR_ARM_ID>
```

Repeat for the DCE resource ID and for each of the 5 DCRs.

---

## Issue 4 — `DefaultAzureCredential` Authentication Failure

**Symptom:** Generator fails with `CredentialUnavailableError` or `ClientAuthenticationError`.

**Cause:** The `azure-identity` SDK's `DefaultAzureCredential` tries several credential sources in order (environment variables → managed identity → Azure CLI → etc.). If none are available, it raises an error.

**Fix — Interactive (workshop use):**

```powershell
# Log in with the Azure CLI (easiest for workshop attendees)
az login
az account set --subscription <SUBSCRIPTION_ID>
```

`DefaultAzureCredential` will pick up the CLI token automatically.

**Fix — CI/CD or automation:**

Set these environment variables before running the generator:

```powershell
$env:AZURE_TENANT_ID     = "<tenant-id>"
$env:AZURE_CLIENT_ID     = "<service-principal-app-id>"
$env:AZURE_CLIENT_SECRET = "<service-principal-secret>"
```

**Verify credential works:**

```powershell
python -c "from azure.identity import DefaultAzureCredential; t = DefaultAzureCredential().get_token('https://monitor.azure.com/.default'); print('OK', t.expires_on)"
```

---

## Issue 5 — Bicep API-Version Errors

**Symptom:** `az bicep build` or `az deployment sub create` fails with `InvalidApiVersionParameter` or `NoRegisteredProviderFound`.

**Cause:** An incorrect API version was used in a module. The validated versions for this lab are:

| Resource | Correct API version |
|---|---|
| `Microsoft.Resources/resourceGroups` | `2022-09-01` |
| `Microsoft.OperationalInsights/workspaces` | `2023-09-01` |
| `Microsoft.OperationalInsights/workspaces/tables` | `2023-09-01` |
| `Microsoft.Insights/dataCollectionEndpoints` | `2023-03-11` |
| `Microsoft.Insights/dataCollectionRules` | `2023-03-11` |

**Fix:** Correct the `@<version>` suffix in the affected `.bicep` file. Run `az bicep build --file infra\main.bicep` to validate before deploying.

---

## Issue 6 — `PYTHONPATH` Error (Generator Not Found)

**Symptom:** `python generator/main.py` fails with `ModuleNotFoundError: No module named 'generator'`.

**Cause:** The `generator/` package requires the repo root to be on `PYTHONPATH`.

**Fix:**

```powershell
# PowerShell
$env:PYTHONPATH = "C:\path\to\azure-monitor-workshop"
python generator/main.py --scenario all --dry-run
```

```bash
# Bash
export PYTHONPATH=/path/to/azure-monitor-workshop
python generator/main.py --scenario all --dry-run
```

---

## Issue 7 — Generator `config/lab.env` Not Found

**Symptom:** Generator exits with `FileNotFoundError: config/lab.env not found` or prints `LabConfig: using safe defaults (dry_run=True forced)`.

**Cause:** `config/lab.env` has not been created yet (deployment has not been run), or the generator is being run from a directory other than the repo root.

**Fix:**

```powershell
# Ensure you are in the repo root
Set-Location C:\path\to\azure-monitor-workshop

# Deploy first (creates config/lab.env)
bash scripts/deploy   # or: pwsh scripts/deploy.ps1

# Or use dry-run mode (no lab.env needed)
python generator/main.py --scenario all --dry-run --seed 42
```

---

## Generator Dry-Run (No Azure Required)

Use `--dry-run` to validate generator output without any Azure credentials or deployed infrastructure. This is safe to run in any environment:

```powershell
$env:PYTHONPATH = "C:\path\to\azure-monitor-workshop"
python generator/main.py --scenario all --dry-run --backfill-minutes 5 --seed 42
```

Expected output: row counts per scenario and a sample record printed to stdout. Exit code `0`.

To test a specific anomaly injection:

```powershell
# Inject a CrashLoopBackOff anomaly for AKS
python generator/main.py --scenario aks --anomaly crashloop --dry-run --seed 42

# Inject high CPU for VMs
python generator/main.py --scenario virtualmachines --anomaly cpu --dry-run --seed 42
```

See the full anomaly key catalog in `docs/architecture.md` or `.squad/decisions/inbox/dozer-generator.md`.

---

## Issue 8 — Table Schema Mismatch on Ingestion

**Symptom:** Generator exits `1` with an error like `Column 'SomeColumn' not found in table schema` or rows are silently dropped.

**Cause:** The DCR `outputColumns` definition does not match the `<Scenario>_CL` table columns, **or** the generator is emitting a column name that differs from the declared schema.

**Fix:**

1. Compare the table columns in the workspace against `docs/data-model.md`:

```powershell
az monitor log-analytics workspace table show `
  --resource-group rg-amlab `
  --workspace-name <LAW_NAME> `
  --name APM_CL `
  --query "properties.schema.columns[].{name:name,type:type}" `
  --output table
```

2. Compare against the exact column list in `docs/data-model.md`.  
3. If there is a mismatch, re-deploy the custom-table Bicep module (which will add/update columns) and restart the generator.

---

## Verifying Data Ingestion with `az monitor log-analytics query`

Use these commands to query each table from the CLI (useful for automation and smoke tests):

```powershell
# Source lab.env
# (PowerShell equivalent of bash source)
Get-Content config\lab.env | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim())
  }
}

# Row count per table (last 1 hour)
az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "VirtualMachines_CL | where TimeGenerated > ago(1h) | count" `
  --output table

az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "AppService_CL | where TimeGenerated > ago(1h) | count" `
  --output table

az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "AKS_CL | where TimeGenerated > ago(1h) | count" `
  --output table

az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "AzureSQL_CL | where TimeGenerated > ago(1h) | count" `
  --output table

az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "APM_CL | where TimeGenerated > ago(1h) | count" `
  --output table
```

```powershell
# Check for CrashLoopBackOff events (last 1 hour)
az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "AKS_CL | where TimeGenerated > ago(1h) and PodReason == 'CrashLoopBackOff' | project TimeGenerated, Resource, PodName, PodRestartCount" `
  --output table

# Check for high CPU on VMs
az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "VirtualMachines_CL | where TimeGenerated > ago(1h) and CpuPercent > 90 | summarize max(CpuPercent) by Resource" `
  --output table

# APM failure rate (last 1 hour)
az monitor log-analytics query `
  --workspace $env:LAW_ID `
  --analytics-query "APM_CL | where TimeGenerated > ago(1h) and ItemType == 'request' | summarize total=count(), failed=countif(IsSuccess == false) | extend failureRate = round(100.0 * failed / total, 2)" `
  --output table
```

---

## Issue 9 — Bicep Deployment Scope Error

**Symptom:** `az deployment sub create` fails with `InvalidDeploymentLevel` or `Deployment at scope 'resourceGroup' not allowed`.

**Cause:** `infra/main.bicep` uses `targetScope = 'subscription'` and must be deployed at the subscription level.

**Fix:** Use `az deployment sub create`, **not** `az deployment group create`:

```powershell
az deployment sub create `
  --location southcentralus `
  --template-file infra\main.bicep `
  --parameters infra\main.bicepparam
```

---

## Issue 10 — `az bicep` Not Installed

**Symptom:** `'bicep' is not recognized` or `ERROR: The command requires the extension bicep`.

**Fix:**

```powershell
az bicep install
# Verify
az bicep version
```

---

## Getting More Help

- Architecture and ingestion path: [`docs/architecture.md`](architecture.md)
- Table column reference: [`docs/data-model.md`](data-model.md)
- Design rationale: [`docs/design-decisions.md`](design-decisions.md)
- Generator CLI options: `python generator/main.py --help`
- Azure Monitor Logs Ingestion API docs: <https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview>
