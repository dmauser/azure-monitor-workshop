#Requires -Version 5.1
# scripts/teardown-vm.ps1 — delete ONLY the demo VM and its dedicated resources.
#
# Usage:
#   .\scripts\teardown-vm.ps1 [-Force] [-SubscriptionId <id>]
#
# Reads config/vm.env for resource IDs. Does NOT touch the main lab stack
# (workspace, DCE, scenario DCRs, custom tables, alerts).
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$SubscriptionId
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

$repoRoot  = $script:RepoRoot
$vmEnvPath = Join-Path $repoRoot 'config\vm.env'

# ---------------------------------------------------------------------------
# Load vm.env
# ---------------------------------------------------------------------------
if (-not (Test-Path $vmEnvPath)) {
    throw 'config/vm.env not found. Was deploy-vm.ps1 run?'
}

$vmEnv = @{}
Get-Content $vmEnvPath | ForEach-Object {
    if ($_ -match '^([A-Z_]+)=(.+)$') {
        $vmEnv[$Matches[1]] = $Matches[2].Trim()
    }
}

$labRg            = $vmEnv['LAB_RESOURCE_GROUP']
$vmName           = $vmEnv['VM_NAME']
$dcrId            = $vmEnv['DCR_ID']
$nsgId            = $vmEnv['NSG_ID']
$vnetId           = $vmEnv['VNET_ID']
$nicId            = $vmEnv['NIC_ID']
$osDiskName       = $vmEnv['OS_DISK_NAME']
$autoShutdownName = $vmEnv['AUTO_SHUTDOWN_NAME']
if (-not $autoShutdownName) { $autoShutdownName = "shutdown-computevm-$vmName" }

foreach ($key in @('LAB_RESOURCE_GROUP','VM_NAME','DCR_ID','NSG_ID','VNET_ID')) {
    if (-not $vmEnv[$key]) { throw "$key not set in config/vm.env" }
}

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Demo VM Teardown ===' -ForegroundColor Yellow
Write-Host "  Subscription  : $($script:SubscriptionId)"
Write-Host "  Resource Group: $labRg"
Write-Host "  VM Name       : $vmName"
Write-Host ''
Write-Host '  Resources to be DELETED:'
Write-Host "    $autoShutdownName"
Write-Host "    VM: $vmName  (NIC + OS disk auto-delete via deleteOption)"
Write-Host "    DCR: $($dcrId.Split('/')[-1])"
Write-Host "    NSG: $($nsgId.Split('/')[-1])"
Write-Host "    VNet: $($vnetId.Split('/')[-1])"
Write-Host ''
Write-Host '  Resources NOT touched (main lab stack stays intact):'
Write-Host '    law-amlab-* / dce-amlab-* / scenario DCRs / custom tables / alerts'
Write-Host ''

if (-not $Force) {
    $answer = Read-Host "Type 'yes' to DELETE the demo VM and its resources (Ctrl+C to abort)"
    if ($answer -ne 'yes') {
        Write-Host 'Teardown cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

# Helper: delete by resource ID, no-op if already gone
function Remove-ByResourceId {
    param([string]$ResourceId, [string]$Label)
    $exists = az resource show --ids $ResourceId 2>$null
    if ($LASTEXITCODE -eq 0 -and $exists) {
        Write-Host "  Deleting $Label..."
        az resource delete --ids $ResourceId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Delete returned non-zero for $Label (may already be gone)"
        }
    } else {
        Write-Host "  Already gone: $Label"
    }
}

Write-Host ''
Write-Host '=== Deleting demo VM resources ===' -ForegroundColor Green

# 1. Auto-shutdown schedule
Write-Host "  Deleting auto-shutdown schedule: $autoShutdownName"
az resource delete `
    --resource-group $labRg `
    --resource-type 'Microsoft.DevTestLab/schedules' `
    --name $autoShutdownName `
    --api-version '2018-09-15' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  NOTE: auto-shutdown schedule may already be gone'
}

# 2. VM (NIC + OS disk carry deleteOption: Delete → auto-deleted)
Write-Host "  Deleting VM: $vmName (NIC + OS disk will auto-delete)"
az vm delete --resource-group $labRg --name $vmName --yes 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  NOTE: VM may already be gone'
}

# 3. DCR
Remove-ByResourceId -ResourceId $dcrId -Label "DCR $($dcrId.Split('/')[-1])"

# 4. NSG
Remove-ByResourceId -ResourceId $nsgId -Label "NSG $($nsgId.Split('/')[-1])"

# 5. VNet
Remove-ByResourceId -ResourceId $vnetId -Label "VNet $($vnetId.Split('/')[-1])"

# ---------------------------------------------------------------------------
# Remove config/vm.env
# ---------------------------------------------------------------------------
Remove-Item -Path $vmEnvPath -Force -ErrorAction SilentlyContinue
Write-Host "  Removed: $vmEnvPath"

Write-Host ''
Write-Host '=== Demo VM teardown complete. Main lab stack untouched. ===' -ForegroundColor Green
