#Requires -Version 5.1
# scripts/deploy.ps1 — deploy azure-monitor-workshop infrastructure to Azure.
#
# Usage:
#   .\scripts\deploy.ps1 [-SubscriptionId <id>] [-PrincipalId <oid>]
#                        [-NamePrefix <prefix>] [-Location <region>]
#                        [-WhatIfMode] [-SkipAlerts] [-SkipWorkbooks]
#
# Idempotent: safe to re-run. Resource names are deterministic from namePrefix.
[CmdletBinding()]
param(
    # Azure subscription ID (default: LAB_SUBSCRIPTION_ID env or current az context)
    [string]$SubscriptionId,

    # AAD principal OID to grant Monitoring Metrics Publisher.
    # Falls back to: env LAB_PRINCIPAL_ID → az ad signed-in-user show → lab default.
    [string]$PrincipalId,

    # Bicep namePrefix parameter (default: amlab)
    [string]$NamePrefix,

    # Azure region (default: southcentralus)
    [string]$Location,

    # Run az deployment sub what-if and exit; does NOT deploy.
    [switch]$WhatIfMode,

    # Pass deployAlerts=false to Bicep
    [switch]$SkipAlerts,

    # Pass deployWorkbooks=false to Bicep
    [switch]$SkipWorkbooks
)

$ErrorActionPreference = 'Stop'

# Dot-source shared helpers (always in the same directory as this script)
. (Join-Path $PSScriptRoot 'common.ps1')

# ---------------------------------------------------------------------------
# Override defaults from explicit params
# ---------------------------------------------------------------------------
if ($SubscriptionId) { $script:SubscriptionId = $SubscriptionId }
if ($NamePrefix)     { $script:NamePrefix     = $NamePrefix }
if ($Location)       { $script:Location       = $Location }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
Assert-AzCli
Set-AzSubscription -SubscriptionId $script:SubscriptionId

# ---------------------------------------------------------------------------
# Resolve principalId
# Priority: -PrincipalId param > env LAB_PRINCIPAL_ID > az ad signed-in-user
# ---------------------------------------------------------------------------
if (-not $PrincipalId) {
    $PrincipalId = $env:LAB_PRINCIPAL_ID
}
if (-not $PrincipalId) {
    Write-Host '  Resolving principalId from az ad signed-in-user show...'
    $resolvedOid = (az ad signed-in-user show --query id -o tsv 2>$null | ForEach-Object { $_.Trim() })
    if ($resolvedOid) {
        $PrincipalId = $resolvedOid
    } else {
        throw 'Could not resolve principalId via az ad. Pass -PrincipalId <objectId> or set LAB_PRINCIPAL_ID.'
    }
}
Write-Host "  principalId: $PrincipalId"

# ---------------------------------------------------------------------------
# Clean stale .json build artifacts (prevents BCP037 false positives)
# ---------------------------------------------------------------------------
Write-Host '  Cleaning stale .json build artifacts...'
$repoRoot = $script:RepoRoot
Get-ChildItem -Path "$repoRoot\infra" -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "$repoRoot\alerts" -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based, unique per run, stable output
# ---------------------------------------------------------------------------
$timestamp      = Get-Date -Format 'yyyyMMddHHmmss'
$deploymentName = "amlab-$timestamp"

# ---------------------------------------------------------------------------
# Bicep bool overrides
# ---------------------------------------------------------------------------
$deployAlerts    = if ($SkipAlerts)    { 'false' } else { 'true' }
$deployWorkbooks = if ($SkipWorkbooks) { 'false' } else { 'true' }

$commonArgs = @(
    '--name',          $deploymentName,
    '--location',      $script:Location,
    '--template-file', "$repoRoot\infra\main.bicep",
    '--parameters',    "$repoRoot\infra\main.bicepparam",
    '--parameters',    "principalId=$PrincipalId",
    '--parameters',    "deployAlerts=$deployAlerts",
    '--parameters',    "deployWorkbooks=$deployWorkbooks"
)

# ---------------------------------------------------------------------------
# What-If path — print plan and exit
# ---------------------------------------------------------------------------
if ($WhatIfMode) {
    Write-Host ''
    Write-Host '=== WHAT-IF (no actual deploy) ===' -ForegroundColor Cyan
    az deployment sub what-if @commonArgs
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "=== Deploying $deploymentName → $($script:Location) ===" -ForegroundColor Green

az deployment sub create @commonArgs
if ($LASTEXITCODE -ne 0) { throw "Deployment '$deploymentName' failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Extracting Bicep outputs ===' -ForegroundColor Green

function Get-DeployOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputName)
    $val = az deployment sub show `
        --name $deploymentName `
        --query "properties.outputs.$OutputName.value" `
        -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to read Bicep output '$OutputName'" }
    return ($val | ForEach-Object { $_.Trim() })
}

$labVars = [ordered]@{
    LAB_LOCATION                      = Get-DeployOutput 'location'
    LAB_RESOURCE_GROUP                = Get-DeployOutput 'resourceGroupName'
    LAB_SUBSCRIPTION_ID               = (az account show --query id -o tsv).Trim()
    LAW_NAME                          = Get-DeployOutput 'workspaceName'
    LAW_ID                            = Get-DeployOutput 'workspaceCustomerId'
    LAW_RESOURCE_ID                   = Get-DeployOutput 'workspaceResourceId'
    DCE_LOGS_INGESTION_ENDPOINT       = Get-DeployOutput 'dceLogsIngestionEndpoint'
    DCR_IMMUTABLE_ID_VIRTUAL_MACHINES = Get-DeployOutput 'dcrImmutableIdVirtualMachines'
    DCR_IMMUTABLE_ID_APP_SERVICE      = Get-DeployOutput 'dcrImmutableIdAppService'
    DCR_IMMUTABLE_ID_AKS              = Get-DeployOutput 'dcrImmutableIdAks'
    DCR_IMMUTABLE_ID_AZURE_SQL        = Get-DeployOutput 'dcrImmutableIdAzureSql'
    DCR_IMMUTABLE_ID_APM              = Get-DeployOutput 'dcrImmutableIdApm'
    STREAM_VIRTUAL_MACHINES           = Get-DeployOutput 'streamVirtualMachines'
    STREAM_APP_SERVICE                = Get-DeployOutput 'streamAppService'
    STREAM_AKS                        = Get-DeployOutput 'streamAks'
    STREAM_AZURE_SQL                  = Get-DeployOutput 'streamAzureSql'
    STREAM_APM                        = Get-DeployOutput 'streamApm'
    TABLE_VIRTUAL_MACHINES            = Get-DeployOutput 'tableVirtualMachines'
    TABLE_APP_SERVICE                 = Get-DeployOutput 'tableAppService'
    TABLE_AKS                         = Get-DeployOutput 'tableAks'
    TABLE_AZURE_SQL                   = Get-DeployOutput 'tableAzureSql'
    TABLE_APM                         = Get-DeployOutput 'tableApm'
}

# ---------------------------------------------------------------------------
# Write config/lab.env
# ---------------------------------------------------------------------------
Write-LabEnv -Vars $labVars

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Deploy Complete ===' -ForegroundColor Green
Write-Host "  Resource Group : $($labVars['LAB_RESOURCE_GROUP'])"
Write-Host "  Workspace      : $($labVars['LAW_NAME'])"
Write-Host "  DCE Endpoint   : $($labVars['DCE_LOGS_INGESTION_ENDPOINT'])"
Write-Host "  lab.env        : $(Join-Path $script:RepoRoot 'config\lab.env')"
