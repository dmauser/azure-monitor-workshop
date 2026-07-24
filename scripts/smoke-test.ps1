#Requires -Version 5.1
<#
.SYNOPSIS
    Post-deploy verification gate — confirms rows in all 5 tables and alert rules provisioned.
.DESCRIPTION
    1. Loads config/lab.env.
    2. For each of the 5 custom-log tables, polls Log Analytics until rows appear
       (up to MaxWaitMinutes; custom-log ingestion can lag 5-15 min after upload).
    3. Lists all scheduled-query alert rules in the resource group and confirms
       all 13 expected rules exist and are enabled.
    4. Prints a PASS/FAIL summary table.
    5. Exits non-zero if any table has 0 rows after retries, or any alert rule
       is missing or disabled.

    NOTE on fired-alert state: az CLI does not expose scheduled-query-rule fire
    history directly.  After this script passes, verify fired alerts via:
      Azure Portal → Monitor → Alerts → Alert history (filter by RG)
    Or via REST:
      az rest --method get \
        --url 'https://management.azure.com/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG>/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01&alertState=Fired'
#>
[CmdletBinding()]
param(
    [int] $MaxWaitMinutes      = 20,
    [int] $PollIntervalSeconds = 60
)

$ErrorActionPreference = 'Stop'

# ── Paths ─────────────────────────────────────────────────────────────────────
$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LabEnvPath = Join-Path $RepoRoot 'config\lab.env'
$CommonPath = Join-Path $PSScriptRoot 'common.ps1'

# ── Load common helpers (Tank owns this; provides helpers, not lab.env vars) ──
if (Test-Path $CommonPath) {
    . $CommonPath
}

# ── Always load config/lab.env (common.ps1 does not expose lab vars) ─────────
if (-not (Test-Path $LabEnvPath)) {
    Write-Error "config\lab.env not found at '$LabEnvPath'. Run scripts\deploy first."
}
Get-Content $LabEnvPath | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)\s*$') {
        [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim(), 'Process')
    }
}

# ── Set subscription ──────────────────────────────────────────────────────────
if ($env:LAB_SUBSCRIPTION_ID) {
    Write-Host "→ Setting subscription $env:LAB_SUBSCRIPTION_ID"
    az account set --subscription $env:LAB_SUBSCRIPTION_ID
}
if ($LASTEXITCODE -ne 0) { exit 1 }

# ── Resolve key env vars ──────────────────────────────────────────────────────
$LawId = $env:LAW_ID
$Rg    = $env:LAB_RESOURCE_GROUP

if (-not $LawId) { Write-Error "LAW_ID is empty in config\lab.env." }
if (-not $Rg)    { Write-Error "LAB_RESOURCE_GROUP is empty in config\lab.env." }

# Table name map — fall back to static defaults when lab.env values are absent
$tableDefaults = @{
    TABLE_VIRTUAL_MACHINES = 'VirtualMachines_CL'
    TABLE_APP_SERVICE      = 'AppService_CL'
    TABLE_AKS              = 'AKS_CL'
    TABLE_AZURE_SQL        = 'AzureSQL_CL'
    TABLE_APM              = 'APM_CL'
}

$tables = @(
    [pscustomobject]@{ Label = 'VirtualMachines'; EnvVar = 'TABLE_VIRTUAL_MACHINES' }
    [pscustomobject]@{ Label = 'AppService';       EnvVar = 'TABLE_APP_SERVICE'       }
    [pscustomobject]@{ Label = 'AKS';              EnvVar = 'TABLE_AKS'              }
    [pscustomobject]@{ Label = 'AzureSQL';         EnvVar = 'TABLE_AZURE_SQL'         }
    [pscustomobject]@{ Label = 'APM';              EnvVar = 'TABLE_APM'              }
)

foreach ($t in $tables) {
    $val = [System.Environment]::GetEnvironmentVariable($t.EnvVar)
    $tn  = if ($val) { $val } else { $tableDefaults[$t.EnvVar] }
    $t | Add-Member -NotePropertyName 'TableName' -NotePropertyValue $tn
    $t | Add-Member -NotePropertyName 'RowCount'  -NotePropertyValue 0
}

# Expected alert rules (13 total) — names from tank-alerts-workbooks.md
$expectedAlerts = @(
    'alert-amlab-vm-cpu-high'
    'alert-amlab-vm-disk-low'
    'alert-amlab-vm-heartbeat-missing'
    'alert-amlab-app-5xx-high'
    'alert-amlab-app-p95-high'
    'alert-amlab-aks-crashloop'
    'alert-amlab-aks-node-notready'
    'alert-amlab-sql-dtu-high'
    'alert-amlab-sql-storage-high'
    'alert-amlab-sql-deadlocks'
    'alert-amlab-apm-failure-rate'
    'alert-amlab-apm-p95-latency'
    'alert-amlab-apm-error-budget-burn'
)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Table row counts with retry loop
# Custom-log ingestion can lag 5-15 min after the generator uploads data.
# We poll every PollIntervalSeconds until all tables report >=1 row, or
# MaxWaitMinutes is exhausted.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 65)
Write-Host 'STEP 1 — Table row counts'
Write-Host "  Retry window : $MaxWaitMinutes min  |  Poll interval : ${PollIntervalSeconds}s"
Write-Host '  Custom-log ingestion latency is typically 5-15 min after upload.'
Write-Host ('═' * 65)

$maxIter    = [Math]::Ceiling($MaxWaitMinutes * 60 / $PollIntervalSeconds)
$iteration  = 0
$pending    = [System.Collections.Generic.List[object]]($tables)

while ($pending.Count -gt 0 -and $iteration -lt $maxIter) {
    $elapsedSec = $iteration * $PollIntervalSeconds
    Write-Host ''
    Write-Host "[Poll $($iteration + 1)/$maxIter | ${elapsedSec}s elapsed] Querying $($pending.Count) table(s)..."

    $stillPending = [System.Collections.Generic.List[object]]::new()

    foreach ($t in $pending) {
        $kql = "$($t.TableName) | where TimeGenerated > ago(1h) | summarize RowCount=count()"
        try {
            $raw = az monitor log-analytics query `
                --workspace $LawId `
                --analytics-query $kql `
                --output json 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [$($t.Label)] Query error (will retry): $raw"
                $stillPending.Add($t)
                continue
            }
            $result = $raw | ConvertFrom-Json
            $count  = 0
            if ($result -and $result.Count -gt 0) {
                $row   = $result[0]
                $count = if ($null -ne $row.PSObject.Properties['RowCount']) { [int]$row.RowCount } else { 0 }
            }
            if ($count -ge 1) {
                $t.RowCount = $count
                Write-Host "  [$($t.Label)] ✓  $count row(s)"
            }
            else {
                Write-Host "  [$($t.Label)] 0 rows — ingestion pending, will retry"
                $stillPending.Add($t)
            }
        }
        catch {
            Write-Host "  [$($t.Label)] Parse error (will retry): $_"
            $stillPending.Add($t)
        }
    }

    $pending = $stillPending
    $iteration++

    if ($pending.Count -gt 0 -and $iteration -lt $maxIter) {
        Write-Host "  Waiting ${PollIntervalSeconds}s …"
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

# Any tables still pending after timeout have RowCount = 0 (already initialised)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Alert rule provisioning
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 65)
Write-Host "STEP 2 — Alert rule provisioning (resource group: $Rg)"
Write-Host ('═' * 65)

$alertStatus = @{}
foreach ($name in $expectedAlerts) { $alertStatus[$name] = 'MISSING' }

try {
    $raw = az monitor scheduled-query list -g $Rg --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Could not list scheduled-query rules: $raw"
        foreach ($name in $expectedAlerts) { $alertStatus[$name] = 'QUERY_ERROR' }
    }
    else {
        $rules = $raw | ConvertFrom-Json
        foreach ($r in $rules) {
            if (-not $alertStatus.ContainsKey($r.name)) { continue }
            # 'enabled' may surface at top level or under properties
            $enabled = $true
            if ($null -ne $r.PSObject.Properties['enabled']) {
                $enabled = [bool]$r.enabled
            }
            elseif ($null -ne $r.PSObject.Properties['properties'] `
                    -and $null -ne $r.properties.PSObject.Properties['enabled']) {
                $enabled = [bool]$r.properties.enabled
            }
            $alertStatus[$r.name] = if ($enabled) { 'ENABLED' } else { 'DISABLED' }
        }
    }
}
catch {
    Write-Host "  ERROR querying alert rules: $_"
    foreach ($name in $expectedAlerts) { $alertStatus[$name] = 'ERROR' }
}

Write-Host ''
Write-Host '  NOTE — Verifying FIRED state requires the Azure Portal or REST API.'
Write-Host "  Portal : Monitor → Alerts → Alert history  (filter RG = '$Rg')"
Write-Host '  REST   : az rest --method get \'
Write-Host "           --url 'https://management.azure.com/subscriptions/$($env:LAB_SUBSCRIPTION_ID)/resourceGroups/$Rg/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01&alertState=Fired'"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PASS/FAIL report
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 65)
Write-Host 'SMOKE-TEST RESULTS'
Write-Host ('═' * 65)

Write-Host ''
Write-Host '┌─ Table Row Counts ──────────────────────────────────────────'
$anyTableFail = $false
foreach ($t in $tables) {
    $pass   = $t.RowCount -ge 1
    $status = if ($pass) { 'PASS' } else { 'FAIL'; $anyTableFail = $true }
    $icon   = if ($pass) { '✓' } else { '✗' }
    Write-Host ('│  {0,-25} {1,6} rows   [{2}] {3}' -f "$($t.TableName):", $t.RowCount, $status, $icon)
}
Write-Host '└─────────────────────────────────────────────────────────────'

Write-Host ''
Write-Host '┌─ Alert Rule Provisioning ───────────────────────────────────'
$anyAlertFail = $false
foreach ($name in $expectedAlerts) {
    $st   = $alertStatus[$name]
    $pass = $st -eq 'ENABLED'
    if (-not $pass) { $anyAlertFail = $true }
    $icon = if ($pass) { '✓' } else { '✗' }
    Write-Host ('│  {0,-47} [{1,-12}] {2}' -f $name, $st, $icon)
}
Write-Host '└─────────────────────────────────────────────────────────────'

Write-Host ''
if ($anyTableFail -or $anyAlertFail) {
    Write-Host 'OVERALL RESULT: ✗  FAIL'
    if ($anyTableFail)  { Write-Host "  → One or more tables had 0 rows after $MaxWaitMinutes-minute wait." }
    if ($anyAlertFail)  { Write-Host '  → One or more alert rules are missing or disabled.' }
    exit 1
}
else {
    Write-Host 'OVERALL RESULT: ✓  PASS'
}
