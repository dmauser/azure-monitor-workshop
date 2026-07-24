#Requires -Version 5.1
# scripts/deploy-service-health-alert.ps1 — deploy the Service Health alert to rg-amlab.
#
# Usage:
#   .\scripts\deploy-service-health-alert.ps1 [-EmailAddress <email>] [-SubscriptionId <id>]
#                                              [-ResourceGroup <rg>] [-WhatIfMode]
#
# Reads config/lab.env for LAB_RESOURCE_GROUP / LAB_LOCATION / LAB_SUBSCRIPTION_ID.
# Deploys alerts/service-health.alerts.bicep — creates action group + activity log alert.
#
# ADDITIVE ONLY: does NOT modify or delete any existing lab resources.
[CmdletBinding()]
param(
    [string]$EmailAddress    = 'you@example.com',
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [switch]$WhatIfMode
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
# Load lab.env
# ---------------------------------------------------------------------------
$labEnvPath = Join-Path $repoRoot 'config\lab.env'
if (-not (Test-Path $labEnvPath)) {
    throw 'config/lab.env not found. Run scripts/deploy first.'
}

$labEnv = @{}
Get-Content $labEnvPath | ForEach-Object {
    if ($_ -match '^([A-Z_]+)=(.+)$') {
        $labEnv[$Matches[1]] = $Matches[2].Trim()
    }
}

$labRg = if ($ResourceGroup) { $ResourceGroup } else { $labEnv['LAB_RESOURCE_GROUP'] }

Write-Host "  Resource Group : $labRg"
Write-Host "  Email Address  : $EmailAddress"
Write-Host "  Subscription   : $($script:SubscriptionId)"

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based
# ---------------------------------------------------------------------------
$ts             = Get-Date -Format 'yyyyMMddHHmmss'
$deploymentName = "amlab-svc-health-$ts"

# ---------------------------------------------------------------------------
# Build parameter list
# ---------------------------------------------------------------------------
$templateFile = Join-Path $repoRoot 'alerts\service-health.alerts.bicep'
$params = @(
    '--resource-group', $labRg,
    '--name',           $deploymentName,
    '--template-file',  $templateFile,
    '--parameters',     "emailAddress=$EmailAddress"
)

# ---------------------------------------------------------------------------
# What-If path
# ---------------------------------------------------------------------------
if ($WhatIfMode) {
    Write-Host ''
    Write-Host '=== WHAT-IF (no actual deploy) ===' -ForegroundColor Cyan
    az deployment group what-if @params
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "=== Deploying Service Health alert: $deploymentName -> $labRg ===" -ForegroundColor Green
az deployment group create @params
if ($LASTEXITCODE -ne 0) { throw "Deployment '$deploymentName' failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Print created resources
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Service Health Alert Resources ===' -ForegroundColor Green

Write-Host ''
Write-Host '--- Activity Log Alert ---' -ForegroundColor Cyan
az monitor activity-log alert show `
    --resource-group $labRg `
    --name "alert-amlab-service-health" `
    -o json

Write-Host ''
Write-Host '--- Action Group ---' -ForegroundColor Cyan
az monitor action-group show `
    --resource-group $labRg `
    --name "ag-amlab-service-health" `
    -o json

Write-Host ''
Write-Host '=== Deploy-Service-Health-Alert Complete ===' -ForegroundColor Green
Write-Host "  Alert : alert-amlab-service-health"
Write-Host "  Action Group : ag-amlab-service-health"
Write-Host "  Email  : $EmailAddress"
Write-Host "  Cost   : `$0 (Activity Log alerts and email notifications are free)"
