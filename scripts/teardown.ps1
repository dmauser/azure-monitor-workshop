#Requires -Version 5.1
# scripts/teardown.ps1 — delete the azure-monitor-lab resource group and clean up.
#
# Usage:
#   .\scripts\teardown.ps1 [-Force] [-SubscriptionId <id>] [-ResourceGroup <rg>]
#
# Without -Force, prompts for confirmation before deleting.
# Reads LAB_RESOURCE_GROUP from config/lab.env; falls back to 'rg-amlab'.
[CmdletBinding()]
param(
    # Skip the confirmation prompt
    [switch]$Force,

    # Override subscription (default: LAB_SUBSCRIPTION_ID env or lab default)
    [string]$SubscriptionId,

    # Override resource group name (default: from config/lab.env or 'rg-amlab')
    [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

# Dot-source shared helpers
. (Join-Path $PSScriptRoot 'common.ps1')

if ($SubscriptionId) { $script:SubscriptionId = $SubscriptionId }

$repoRoot   = $script:RepoRoot
$labEnvPath = Join-Path $repoRoot 'config\lab.env'

# ---------------------------------------------------------------------------
# Resolve resource group name
# ---------------------------------------------------------------------------
if (-not $ResourceGroup) {
    # Try to read from config/lab.env
    if (Test-Path $labEnvPath) {
        $line = Get-Content $labEnvPath | Where-Object { $_ -match '^LAB_RESOURCE_GROUP=' } | Select-Object -First 1
        if ($line) {
            $ResourceGroup = ($line -split '=', 2)[1].Trim()
        }
    }
}
if (-not $ResourceGroup) {
    $ResourceGroup = "rg-$($script:NamePrefix)"
    Write-Warning "config/lab.env not found or LAB_RESOURCE_GROUP not set; defaulting to '$ResourceGroup'"
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
Assert-AzCli
Set-AzSubscription -SubscriptionId $script:SubscriptionId

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "=== Teardown ===" -ForegroundColor Yellow
Write-Host "  Subscription  : $($script:SubscriptionId)"
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  lab.env       : $labEnvPath"
Write-Host ''

if (-not $Force) {
    $answer = Read-Host "Type 'yes' to DELETE resource group '$ResourceGroup' and remove lab.env (Ctrl+C to abort)"
    if ($answer -ne 'yes') {
        Write-Host 'Teardown cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Delete resource group (non-blocking)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "  Deleting resource group '$ResourceGroup' (--no-wait)..."
az group delete --name $ResourceGroup --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw "az group delete failed for '$ResourceGroup' (exit $LASTEXITCODE)" }
Write-Host "  Delete submitted. The resource group will be removed in the background."

# ---------------------------------------------------------------------------
# Remove config/lab.env
# ---------------------------------------------------------------------------
if (Test-Path $labEnvPath) {
    Remove-Item -Path $labEnvPath -Force
    Write-Host "  Removed: $labEnvPath"
} else {
    Write-Host "  config/lab.env not present (nothing to remove)."
}

Write-Host ''
Write-Host '=== Teardown complete. ===' -ForegroundColor Green
