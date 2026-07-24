#Requires -Version 5.1
# scripts/teardown-service-health-alert.ps1 — delete the Service Health alert resources.
#
# Usage:
#   .\scripts\teardown-service-health-alert.ps1 [-Force] [-SubscriptionId <id>]
#                                               [-ResourceGroup <rg>]
#
# Deletes (idempotent — no error if already gone):
#   - alert-amlab-service-health  (microsoft.insights/activityLogAlerts)
#   - ag-amlab-service-health     (microsoft.insights/actionGroups)
#
# Does NOT touch any other lab resources (workspace, DCRs, VMs, other alerts).
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$SubscriptionId,
    [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

# Dot-source shared helpers
. (Join-Path $PSScriptRoot 'common.ps1')

if ($SubscriptionId) { $script:SubscriptionId = $SubscriptionId }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
Assert-AzCli
Set-AzSubscription -SubscriptionId $script:SubscriptionId

$repoRoot = $script:RepoRoot

# ---------------------------------------------------------------------------
# Resolve resource group from lab.env or param
# ---------------------------------------------------------------------------
$labEnvPath = Join-Path $repoRoot 'config\lab.env'
$labRg = $ResourceGroup

if (-not $labRg) {
    if (Test-Path $labEnvPath) {
        Get-Content $labEnvPath | ForEach-Object {
            if ($_ -match '^LAB_RESOURCE_GROUP=(.+)$') { $labRg = $Matches[1].Trim() }
        }
    }
    if (-not $labRg) { $labRg = 'rg-amlab' }
}

$alertName       = 'alert-amlab-service-health'
$actionGroupName = 'ag-amlab-service-health'

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Service Health Alert Teardown ===' -ForegroundColor Yellow
Write-Host "  Subscription  : $($script:SubscriptionId)"
Write-Host "  Resource Group: $labRg"
Write-Host ''
Write-Host '  Resources to be DELETED (if present):'
Write-Host "    Activity Log Alert : $alertName"
Write-Host "    Action Group       : $actionGroupName"
Write-Host ''
Write-Host '  Resources NOT touched:'
Write-Host '    All other lab resources (workspace, DCRs, VMs, scenario alerts, etc.)'
Write-Host ''

if (-not $Force) {
    $answer = Read-Host "Type 'yes' to DELETE (Ctrl+C to abort)"
    if ($answer -ne 'yes') {
        Write-Host 'Teardown cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

# Helper: delete an activity log alert by name, no-op if already gone
function Remove-ActivityLogAlert {
    param([string]$Rg, [string]$Name)
    $exists = az monitor activity-log alert show --resource-group $Rg --name $Name 2>$null
    if ($LASTEXITCODE -eq 0 -and $exists) {
        Write-Host "  Deleting activity log alert: $Name"
        az monitor activity-log alert delete --resource-group $Rg --name $Name --yes 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Delete returned non-zero for $Name (may already be gone)"
        } else {
            Write-Host "  Deleted: $Name"
        }
    } else {
        Write-Host "  Already gone (or not found): $Name"
    }
}

# Helper: delete an action group by name, no-op if already gone
function Remove-ActionGroup {
    param([string]$Rg, [string]$Name)
    $exists = az monitor action-group show --resource-group $Rg --name $Name 2>$null
    if ($LASTEXITCODE -eq 0 -and $exists) {
        Write-Host "  Deleting action group: $Name"
        az monitor action-group delete --resource-group $Rg --name $Name 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Delete returned non-zero for $Name (may already be gone)"
        } else {
            Write-Host "  Deleted: $Name"
        }
    } else {
        Write-Host "  Already gone (or not found): $Name"
    }
}

Write-Host ''
Write-Host '=== Deleting Service Health alert resources ===' -ForegroundColor Green

# 1. Delete alert first (it references the action group)
Remove-ActivityLogAlert -Rg $labRg -Name $alertName

# 2. Delete action group
Remove-ActionGroup -Rg $labRg -Name $actionGroupName

Write-Host ''
Write-Host '=== Service Health alert teardown complete. All other lab resources untouched. ===' -ForegroundColor Green
