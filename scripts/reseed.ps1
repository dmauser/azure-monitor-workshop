#Requires -Version 5.1
<#
.SYNOPSIS
    Re-runs the generator with a fresh time window (convenience wrapper).
.DESCRIPTION
    Re-invokes the generator for a new time slice without deleting existing rows.

    NOTE: Azure Monitor custom logs do not support selective row deletion.
    Re-seeding appends new rows; existing data in <Scenario>_CL tables is retained.
    This is intentional — multiple seed passes increase row density for richer
    workbook visualisations and improve alert-trigger probability.

    Typical use-cases:
      • After a cold deploy, wait ~5 min then reseed to extend the time window.
      • Inject a specific anomaly after the initial seed.
      • Refresh data before a live demo.
#>
[CmdletBinding()]
param(
    [int]    $Minutes = 15,
    [string] $Anomaly = '',
    [string] $Scenario = 'all',
    [int]    $Seed = 42
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
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# ── Set PYTHONPATH ────────────────────────────────────────────────────────────
$env:PYTHONPATH = $RepoRoot
Write-Host "→ PYTHONPATH=$env:PYTHONPATH"

# ── Build generator args ──────────────────────────────────────────────────────
$genArgs = @('--scenario', $Scenario, '--backfill-minutes', $Minutes.ToString(), '--seed', $Seed.ToString())

if ($Anomaly -ne '') {
    $genArgs += @('--anomaly', $Anomaly)
    Write-Host "→ Reseed: scenario=$Scenario  anomaly=$Anomaly  minutes=$Minutes  seed=$Seed"
}
else {
    Write-Host "→ Reseed: scenario=$Scenario  minutes=$Minutes  seed=$Seed  (baseline, no anomaly)"
}

# ── Resolve a working Python interpreter (avoid the Windows Store stub) ─────────
$pyCmd = $null; $pyPrefix = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pyCmd = 'py'; $pyPrefix = @('-3')
}
else {
    $cand = Get-Command python -ErrorAction SilentlyContinue
    if ($cand -and $cand.Source -notmatch 'WindowsApps') { $pyCmd = $cand.Source }
}
if (-not $pyCmd) {
    Write-Error "No usable Python 3 interpreter found (install Python 3 or the 'py' launcher)."
    exit 1
}

# ── Run ───────────────────────────────────────────────────────────────────────
$entryPoint = Join-Path $RepoRoot 'generator\main.py'
Write-Host ''
Write-Host "  `$ $pyCmd $($pyPrefix -join ' ') generator/main.py $($genArgs -join ' ')"
& $pyCmd @pyPrefix $entryPoint @genArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Generator exited $LASTEXITCODE."
}

Write-Host ''
Write-Host '✓ Reseed complete. Rows appended (existing rows were NOT deleted).'
Write-Host '  Allow 5-15 minutes for ingestion latency before querying.'
