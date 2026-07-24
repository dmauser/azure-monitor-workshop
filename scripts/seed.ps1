#Requires -Version 5.1
<#
.SYNOPSIS
    Populates all 5 custom-log tables by running the generator (baseline + anomaly passes).
.DESCRIPTION
    1. Loads config/lab.env (via scripts/common.ps1 if present, else directly).
    2. Sets PYTHONPATH to the repo root.
    3. Runs a baseline pass: --scenario all --backfill-minutes 15
    4. Runs one anomaly pass per alert-triggering key (12 total) to ensure
       alert rules have data to evaluate against.

    Exits non-zero on any generator upload failure.
    Custom logs cannot be selectively deleted; repeated runs append rows.
#>
[CmdletBinding()]
param()

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

# ── Validate required env vars ────────────────────────────────────────────────
$requiredVars = @(
    'DCE_LOGS_INGESTION_ENDPOINT'
    'DCR_IMMUTABLE_ID_VIRTUAL_MACHINES'
    'DCR_IMMUTABLE_ID_APP_SERVICE'
    'DCR_IMMUTABLE_ID_AKS'
    'DCR_IMMUTABLE_ID_AZURE_SQL'
    'DCR_IMMUTABLE_ID_APM'
)
foreach ($v in $requiredVars) {
    if (-not [System.Environment]::GetEnvironmentVariable($v)) {
        Write-Error "Required env var '$v' is empty. Ensure config\lab.env is fully populated."
    }
}

# ── Set PYTHONPATH ────────────────────────────────────────────────────────────
$env:PYTHONPATH = $RepoRoot
Write-Host "→ PYTHONPATH=$env:PYTHONPATH"

# ── Resolve a working Python interpreter ─────────────────────────────────────
# Prefer a real `python` on PATH, else the `py` launcher (Windows). The bare
# WindowsApps `python.exe` alias is a non-functional stub, so verify it runs.
function Resolve-PythonCommand {
    foreach ($candidate in @(
        @('python'),
        @('py', '-3'),
        @('py')
    )) {
        $exe = $candidate[0]
        if (Get-Command $exe -ErrorAction SilentlyContinue) {
            $probeArgs = @($candidate[1..($candidate.Count - 1)]) + @('-c', 'import sys')
            & $exe @probeArgs 2>$null
            if ($LASTEXITCODE -eq 0) { return , $candidate }
        }
    }
    Write-Error "No working Python interpreter found. Install Python 3.11+ and 'pip install -r requirements.txt'."
}

$script:PythonCmd = Resolve-PythonCommand
Write-Host "→ Python: $($script:PythonCmd -join ' ')"

# ── Helper ────────────────────────────────────────────────────────────────────
function Invoke-Generator {
    [CmdletBinding()]
    param([string[]]$GenArgs)
    $entryPoint = Join-Path $RepoRoot 'generator\main.py'
    $exe = $script:PythonCmd[0]
    $pyArgs = @($script:PythonCmd[1..($script:PythonCmd.Count - 1)]) + @($entryPoint) + $GenArgs
    Write-Host "  `$ $($script:PythonCmd -join ' ') generator/main.py $($GenArgs -join ' ')"
    & $exe @pyArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Generator exited $LASTEXITCODE — aborting seed."
    }
}

# ── 1. Baseline pass ──────────────────────────────────────────────────────────
Write-Host ''
Write-Host '=== BASELINE PASS (all scenarios, 15-min backfill) ==='
Invoke-Generator @('--scenario', 'all', '--backfill-minutes', '15')

# ── 2. Anomaly passes ─────────────────────────────────────────────────────────
# One pass per anomaly key; --seed 42 keeps output reproducible.
# Generators that don't recognise a key treat it as a no-op baseline (safe).
Write-Host ''
Write-Host '=== ANOMALY PASSES (one per alert-triggering key) ==='

$anomalies = @(
    [pscustomobject]@{ Scenario = 'virtualmachines'; Key = 'cpu'          }
    [pscustomobject]@{ Scenario = 'virtualmachines'; Key = 'disk'         }
    [pscustomobject]@{ Scenario = 'virtualmachines'; Key = 'heartbeat'    }
    [pscustomobject]@{ Scenario = 'appservice';      Key = '5xx'          }
    [pscustomobject]@{ Scenario = 'appservice';      Key = 'latency'      }
    [pscustomobject]@{ Scenario = 'aks';             Key = 'crashloop'    }
    [pscustomobject]@{ Scenario = 'aks';             Key = 'nodenotready' }
    [pscustomobject]@{ Scenario = 'azuresql';        Key = 'dtu'          }
    [pscustomobject]@{ Scenario = 'azuresql';        Key = 'storage'      }
    [pscustomobject]@{ Scenario = 'azuresql';        Key = 'deadlock'     }
    [pscustomobject]@{ Scenario = 'apm';             Key = 'errorrate'    }
    [pscustomobject]@{ Scenario = 'apm';             Key = 'latency'      }
)

foreach ($a in $anomalies) {
    Write-Host ''
    Write-Host "  -- $($a.Scenario) / $($a.Key)"
    Invoke-Generator @(
        '--scenario',        $a.Scenario,
        '--anomaly',         $a.Key,
        '--backfill-minutes', '15',
        '--seed',            '42'
    )
}

Write-Host ''
Write-Host '✓ Seed complete — baseline + 12 anomaly passes uploaded.'
Write-Host '  Allow 5-15 minutes for custom-log ingestion before running smoke-test.'
