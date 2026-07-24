#Requires -Version 5.1
# scripts/validate.ps1 — pre-deploy local gate: lint + build bicep files.
#
# Usage:
#   .\scripts\validate.ps1 [-WhatIfMode]
#
# Steps:
#   1. Clean stale .json build artifacts
#   2. az bicep build --file infra/main.bicep  (must exit 0)
#   3. az bicep lint  --file infra/main.bicep  (must exit 0)
#   4. Optional: az deployment sub what-if (requires Azure login; skipped by default)
#
# Exit codes: 0 = PASS, 1 = FAIL
[CmdletBinding()]
param(
    # Also run az deployment sub what-if (requires az login + subscription access)
    [switch]$WhatIfMode,

    # Subscription for what-if (default: LAB_SUBSCRIPTION_ID env or lab default)
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

# Dot-source shared helpers
. (Join-Path $PSScriptRoot 'common.ps1')

if ($SubscriptionId) { $script:SubscriptionId = $SubscriptionId }

$repoRoot  = $script:RepoRoot
$bicepFile = Join-Path $repoRoot 'infra\main.bicep'
$pass      = $true
$results   = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[PASS]' } else { '[FAIL]' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    $msg    = "$symbol $Label"
    if ($Detail) { $msg += " — $Detail" }
    Write-Host $msg -ForegroundColor $color
    $results.Add($msg)
    if (-not $Ok) { $script:pass = $false }
}

Write-Host ''
Write-Host '=== validate.ps1 — Pre-Deploy Gate ===' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Step 0: Verify az CLI is available
# ---------------------------------------------------------------------------
$azOk = $null -ne (Get-Command az -ErrorAction SilentlyContinue)
Add-Result 'az CLI present' $azOk
if (-not $azOk) {
    Write-Host ''
    Write-Host 'FAIL: az CLI not found — cannot continue.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Step 1: Clean stale .json build artifacts
# ---------------------------------------------------------------------------
Write-Host '  Cleaning stale .json build artifacts...'
Get-ChildItem -Path "$repoRoot\infra"   -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "$repoRoot\alerts"  -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Add-Result 'Stale .json cleaned' $true

# ---------------------------------------------------------------------------
# Step 2: az bicep build
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  Running az bicep build...'
$buildOutput = az bicep build --file $bicepFile 2>&1
$buildOk     = $LASTEXITCODE -eq 0
Add-Result 'az bicep build' $buildOk ($buildOutput | Where-Object { $_ -match 'error|warning' } | Select-Object -First 3 | Out-String).Trim()
if (-not $buildOk) {
    Write-Host ($buildOutput | Out-String) -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Step 3: az bicep lint
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  Running az bicep lint...'
$lintOutput = az bicep lint --file $bicepFile 2>&1
$lintOk     = $LASTEXITCODE -eq 0
Add-Result 'az bicep lint' $lintOk ($lintOutput | Where-Object { $_ -match 'error|warning' } | Select-Object -First 3 | Out-String).Trim()
if (-not $lintOk) {
    Write-Host ($lintOutput | Out-String) -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Step 4 (optional): az deployment sub what-if
# ---------------------------------------------------------------------------
if ($WhatIfMode) {
    Write-Host ''
    Write-Host '  Running az deployment sub what-if...'

    $azLoggedIn = $false
    try {
        $null = az account show 2>&1
        $azLoggedIn = $LASTEXITCODE -eq 0
    } catch { }

    if (-not $azLoggedIn) {
        Add-Result 'az deployment sub what-if' $false 'Skipped — not logged in to Azure'
    } else {
        Set-AzSubscription -SubscriptionId $script:SubscriptionId

        $principalId = $env:LAB_PRINCIPAL_ID
        if (-not $principalId) {
            $principalId = (az ad signed-in-user show --query id -o tsv 2>$null | ForEach-Object { $_.Trim() })
        }
        if (-not $principalId) { $principalId = '' }

        $whatIfOutput = az deployment sub what-if `
            --name "validate-whatif-$(Get-Date -Format 'yyyyMMddHHmmss')" `
            --location $script:Location `
            --template-file $bicepFile `
            --parameters "$repoRoot\infra\main.bicepparam" `
            --parameters "principalId=$principalId" `
            2>&1
        $whatIfOk = $LASTEXITCODE -eq 0
        Add-Result 'az deployment sub what-if' $whatIfOk
        if (-not $whatIfOk) {
            Write-Host ($whatIfOutput | Out-String) -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
$results | ForEach-Object { Write-Host "  $_" }
Write-Host ''

if ($pass) {
    Write-Host 'RESULT: PASS — all checks passed.' -ForegroundColor Green
    exit 0
} else {
    Write-Host 'RESULT: FAIL — one or more checks failed.' -ForegroundColor Red
    exit 1
}
