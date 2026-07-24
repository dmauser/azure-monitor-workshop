#Requires -Version 5.1
# scripts/deploy-vm.ps1 — deploy the demo VM module (demo-vm.bicep) to rg-amlab.
#
# Usage:
#   .\scripts\deploy-vm.ps1 [-SubscriptionId <id>] [-ResourceGroup <rg>]
#                           [-VmSize <size>] [-WhatIfMode]
#
# Reads config/lab.env for LAB_RESOURCE_GROUP / LAW_RESOURCE_ID / LAB_LOCATION.
# Generates an ed25519 SSH key pair under config/keys/ if absent.
# Writes config/vm.env on success.
#
# ADDITIVE ONLY: does NOT touch existing lab resources.
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$VmSize,
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

$labLocation  = $labEnv['LAB_LOCATION']
$labRg        = if ($ResourceGroup) { $ResourceGroup } else { $labEnv['LAB_RESOURCE_GROUP'] }
$lawResId     = $labEnv['LAW_RESOURCE_ID']

Write-Host "  Resource Group : $labRg"
Write-Host "  Location       : $labLocation"
Write-Host "  Workspace ID   : $lawResId"

# ---------------------------------------------------------------------------
# SSH key — generate ed25519 pair under config/keys/ if absent
# ---------------------------------------------------------------------------
$keysDir    = Join-Path $repoRoot 'config\keys'
if (-not (Test-Path $keysDir)) { New-Item -ItemType Directory -Path $keysDir | Out-Null }

$sshKeyPath = Join-Path $keysDir 'vm-amlab-ed25519'
$sshPubPath = "$sshKeyPath.pub"

if (-not (Test-Path $sshKeyPath)) {
    Write-Host ''
    Write-Host "  Generating SSH ed25519 key pair -> $sshKeyPath"
    $sshKeygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    if (-not $sshKeygen) {
        throw 'ssh-keygen not found. Install OpenSSH (Settings > Apps > Optional Features > OpenSSH Client).'
    }
    & ssh-keygen -t ed25519 -f $sshKeyPath -N '""' -C 'vm-amlab-lab-key' -q 2>$null
    if ($LASTEXITCODE -ne 0) {
        # try without quoted passphrase (some Windows versions)
        & ssh-keygen -t ed25519 -f $sshKeyPath -N '' -C 'vm-amlab-lab-key'
    }
    Write-Host "  SSH private key: $sshKeyPath"
    Write-Host "  SSH public key : $sshPubPath"
} else {
    Write-Host "  SSH key already exists: $sshKeyPath"
}

$sshPublicKey = (Get-Content $sshPubPath -Raw).Trim()

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based
# ---------------------------------------------------------------------------
$ts             = Get-Date -Format 'yyyyMMddHHmmss'
$deploymentName = "amlab-vm-$ts"

# ---------------------------------------------------------------------------
# Build parameter list
# ---------------------------------------------------------------------------
$params = @(
    '--resource-group', $labRg,
    '--name',           $deploymentName,
    '--template-file',  (Join-Path $repoRoot 'infra\modules\demo-vm.bicep'),
    '--parameters',     "location=$labLocation",
    '--parameters',     "workspaceResourceId=$lawResId",
    '--parameters',     "sshPublicKey=$sshPublicKey"
)
if ($VmSize) { $params += '--parameters'; $params += "vmSize=$VmSize" }

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
Write-Host "=== Deploying demo VM: $deploymentName -> $labRg ===" -ForegroundColor Green
az deployment group create @params
if ($LASTEXITCODE -ne 0) { throw "Deployment '$deploymentName' failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Extracting Bicep outputs ===' -ForegroundColor Green

function Get-VmOutput {
    param([string]$OutputName)
    $val = az deployment group show `
        --resource-group $labRg `
        --name $deploymentName `
        --query "properties.outputs.$OutputName.value" `
        -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to read output '$OutputName'" }
    return ($val | ForEach-Object { $_.Trim() })
}

$vmName      = Get-VmOutput 'vmName'
$vmId        = Get-VmOutput 'vmId'
$privateIp   = Get-VmOutput 'privateIp'
$dcrId       = Get-VmOutput 'dcrId'
$nsgId       = Get-VmOutput 'nsgId'
$vnetId      = Get-VmOutput 'vnetId'
$nicId       = Get-VmOutput 'nicId'
$osDiskName  = Get-VmOutput 'osDiskName'

Write-Host "  VM Name       : $vmName"
Write-Host "  VM Private IP : $privateIp"
Write-Host "  DCR ID        : $dcrId"

# ---------------------------------------------------------------------------
# Write config/vm.env
# ---------------------------------------------------------------------------
$vmEnvPath = Join-Path $repoRoot 'config\vm.env'
$tsNow     = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'

$vmEnvContent = @"
# =============================================================================
# config/vm.env — generated by scripts/deploy-vm on $tsNow
# DO NOT EDIT — re-run scripts/deploy-vm to regenerate.
# NEVER commit this file (gitignored).
# =============================================================================
LAB_RESOURCE_GROUP=$labRg
VM_NAME=$vmName
VM_ID=$vmId
VM_PRIVATE_IP=$privateIp
DCR_ID=$dcrId
NSG_ID=$nsgId
VNET_ID=$vnetId
NIC_ID=$nicId
OS_DISK_NAME=$osDiskName
SSH_KEY_PATH=$sshKeyPath
ADMIN_USERNAME=azureuser
AUTO_SHUTDOWN_NAME=shutdown-computevm-$vmName
"@

Set-Content -Path $vmEnvPath -Value $vmEnvContent -Encoding UTF8
Write-Host ''
Write-Host '=== Deploy-VM Complete ===' -ForegroundColor Green
Write-Host "  VM Name    : $vmName"
Write-Host "  Private IP : $privateIp"
Write-Host "  SSH Key    : $sshKeyPath"
Write-Host "  vm.env     : $vmEnvPath"
Write-Host ''
Write-Host '  Access VM via Azure Serial Console or:'
Write-Host "    az vm run-command invoke -g $labRg -n $vmName ``"
Write-Host "      --command-id RunShellScript --scripts 'uptime'"
