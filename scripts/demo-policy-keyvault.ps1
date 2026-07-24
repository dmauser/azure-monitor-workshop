#Requires -Version 5.1
<#
.SYNOPSIS
    Live demo: Azure Policy (DeployIfNotExists) auto-configures Key Vault
    diagnostic settings to the lab's Log Analytics workspace.
.DESCRIPTION
    Proves the governance story end-to-end:
      1. Create a Key Vault in rg-amlab (RBAC-auth, Standard SKU).
      2. Trigger an on-demand policy remediation so the diagnostic setting is
         deployed promptly (instead of waiting for the ~30-min compliance scan).
      3. Poll until the policy-created diagnostic setting appears on the vault.
      4. Grant the signed-in user Key Vault Secrets Officer and write a secret
         (generates an AuditEvent).
      5. Print the verification KQL + portal links + cleanup commands.

    Requires the policy assignment created by infra/main.bicep (deployPolicy=true).
    Read-only to the lab telemetry; creates ONLY a throwaway Key Vault.
.PARAMETER VaultName
    Optional Key Vault name. Defaults to a unique kv-amlab-demo-<rand> name.
.PARAMETER Cleanup
    Delete + purge the demo Key Vault and the remediation task, then exit.
.EXAMPLE
    pwsh scripts/demo-policy-keyvault.ps1
.EXAMPLE
    pwsh scripts/demo-policy-keyvault.ps1 -Cleanup
#>
[CmdletBinding()]
param(
    [string]$VaultName,
    [string]$ResourceGroup,
    [string]$Location,
    [string]$Subscription = (az account show --query id -o tsv 2>$null),
    [int]$MaxWaitMinutes = 20,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# ── Paths / config ────────────────────────────────────────────────────────────
$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LabEnvPath = Join-Path $RepoRoot 'config\lab.env'

# Load lab.env (best-effort) to pick up LAB_RESOURCE_GROUP / LAB_LOCATION / LAW_ID
if (Test-Path $LabEnvPath) {
    Get-Content $LabEnvPath | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)\s*$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim(), 'Process')
        }
    }
}

if (-not $ResourceGroup) {
    $ResourceGroup = [System.Environment]::GetEnvironmentVariable('LAB_RESOURCE_GROUP')
    if (-not $ResourceGroup) { $ResourceGroup = 'rg-amlab' }
}
if (-not $Location) {
    $Location = [System.Environment]::GetEnvironmentVariable('LAB_LOCATION')
    if (-not $Location) { $Location = 'southcentralus' }
}
$WorkspaceGuid = [System.Environment]::GetEnvironmentVariable('LAW_ID')   # customerId GUID (for KQL portal deep-link only)

# Policy assignment name authored by infra/modules/policy-keyvault-diagnostics.bicep
$AssignmentName = 'dep-diag-kv-amlab'

# ── Subscription ──────────────────────────────────────────────────────────────
Write-Host "→ Setting subscription $Subscription"
az account set --subscription $Subscription | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set subscription." }

# ── Cleanup mode ──────────────────────────────────────────────────────────────
if ($Cleanup) {
    if (-not $VaultName) {
        Write-Host "→ Discovering demo Key Vaults (name starts with 'kv-amlab-demo-') in $ResourceGroup"
        $vaults = az keyvault list -g $ResourceGroup --query "[?starts_with(name,'kv-amlab-demo-')].name" -o tsv
        if (-not $vaults) { Write-Host "   (none found)"; }
    } else {
        $vaults = @($VaultName)
    }
    foreach ($v in $vaults) {
        if (-not $v) { continue }
        Write-Host "→ Deleting Key Vault $v"
        az keyvault delete -g $ResourceGroup -n $v 2>$null | Out-Null
        Write-Host "→ Purging soft-deleted Key Vault $v"
        az keyvault purge -n $v --location $Location 2>$null | Out-Null
    }
    Write-Host "→ Deleting remediation tasks for $AssignmentName"
    az policy remediation delete --name "remediate-$AssignmentName" --resource-group $ResourceGroup 2>$null | Out-Null
    Write-Host "✓ Cleanup complete."
    exit 0
}

# ── Preflight: policy assignment must exist ──────────────────────────────────
Write-Host "→ Verifying policy assignment '$AssignmentName' exists at RG scope"
$scope = "/subscriptions/$Subscription/resourceGroups/$ResourceGroup"
$assignmentId = az policy assignment show --name $AssignmentName --scope $scope --query id -o tsv 2>$null
if (-not $assignmentId) {
    Write-Error "Policy assignment '$AssignmentName' not found in $ResourceGroup. Deploy infra/main.bicep with deployPolicy=true first."
}
Write-Host "   assignment: $assignmentId"

# ── Vault name ────────────────────────────────────────────────────────────────
if (-not $VaultName) {
    $rand = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $VaultName = "kv-amlab-demo-$rand"
}
Write-Host "→ Key Vault name: $VaultName"

# ── 1. Create the Key Vault (RBAC-auth, Standard) ─────────────────────────────
Write-Host "→ [1/5] Creating Key Vault (Standard, RBAC authorization)…"
$kvId = az keyvault create -g $ResourceGroup -n $VaultName -l $Location `
    --enable-rbac-authorization true --sku standard `
    --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $kvId) { Write-Error "Key Vault creation failed." }
Write-Host "   created: $kvId"

# ── 2. Kick policy evaluation + on-demand remediation ────────────────────────
Write-Host "→ [2/5] Forcing a compliance scan + on-demand remediation…"
# A scan drives DeployIfNotExists evaluation for the new vault.
az policy state trigger-scan --resource-group $ResourceGroup --no-wait 2>$null | Out-Null
az policy remediation create `
    --name "remediate-$AssignmentName" `
    --resource-group $ResourceGroup `
    --policy-assignment $assignmentId `
    --resource-discovery-mode ReEvaluateCompliance 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "   (remediation task submit returned non-zero — DINE may still auto-deploy on create; continuing)"
}

# ── 3. Poll for the policy-created diagnostic setting ────────────────────────
# NOTE: the built-in policy uses evaluationDelay 'AfterProvisioning', so Azure
# intentionally delays existence evaluation ~10–30 min after the vault is
# provisioned. Budget accordingly for a live demo (pre-create the vault!).
$maxIters = [int]($MaxWaitMinutes * 2)   # 30s per iteration
Write-Host "→ [3/5] Waiting for the policy to deploy the diagnostic setting (up to $MaxWaitMinutes min)…"
$diagFound = $false
for ($i = 1; $i -le $maxIters; $i++) {
    Start-Sleep -Seconds 30
    $diag = az monitor diagnostic-settings list --resource $kvId --query "value[].name" -o tsv 2>$null
    if ($diag) {
        $diagFound = $true
        Write-Host "   ✓ diagnostic setting(s) present: $($diag -join ', ')  (after ~$([int]($i*30))s)"
        break
    }
    if ($i % 4 -eq 0) { Write-Host "   …still waiting ($([int]($i*30/60)) min) — DINE 'AfterProvisioning' delay is normal" }
}
if (-not $diagFound) {
    Write-Host "   ⚠ No diagnostic setting yet after $MaxWaitMinutes min. This is normal for a cold vault —"
    Write-Host "     the 'AfterProvisioning' delay can reach ~30 min. Re-check: "
    Write-Host "     az monitor diagnostic-settings list --resource $kvId -o table"
}

# ── 4. Grant self Secrets Officer + write a secret (generates AuditEvent) ────
Write-Host "→ [4/5] Granting yourself 'Key Vault Secrets Officer' and writing a demo secret…"
$me = az ad signed-in-user show --query id -o tsv 2>$null
if ($me) {
    az role assignment create --assignee-object-id $me --assignee-principal-type User `
        --role "Key Vault Secrets Officer" --scope $kvId 2>$null | Out-Null
    # Data-plane RBAC can take a few minutes to propagate — retry the write.
    $secretOk = $false
    for ($r = 1; $r -le 8; $r++) {
        Start-Sleep -Seconds 20
        az keyvault secret set --vault-name $VaultName --name "demo-secret" `
            --value "hello-observability" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $secretOk = $true; break }
        Write-Host "   …waiting for Key Vault RBAC to propagate (attempt $r)"
    }
    if ($secretOk) {
        Write-Host "   ✓ secret 'demo-secret' created — this emits a Key Vault AuditEvent"
    } else {
        Write-Host "   ⚠ secret write still failing. Retry manually in a minute:"
        Write-Host "     az keyvault secret set --vault-name $VaultName --name demo-secret --value hello"
    }
} else {
    Write-Host "   ⚠ Could not resolve your object ID (az ad signed-in-user). Grant RBAC + write a secret manually to generate an audit event."
}

# ── 5. Verification / next steps ─────────────────────────────────────────────
Write-Host ""
Write-Host "→ [5/5] Verify the audit log in Log Analytics (allow ~5–10 min for AuditEvent ingestion):"
Write-Host ""
Write-Host "  AzureDiagnostics"
Write-Host "  | where ResourceProvider == 'MICROSOFT.KEYVAULT'"
Write-Host "  | where Resource == toupper('$VaultName')"
Write-Host "  | where Category == 'AuditEvent'"
Write-Host "  | project TimeGenerated, OperationName, ResultType, CallerIPAddress, identity_claim_upn_s"
Write-Host "  | order by TimeGenerated desc"
Write-Host ""
if ($WorkspaceGuid) {
    Write-Host "  Logs blade: https://portal.azure.com/#blade/Microsoft_OperationsManagementSuite_Workspace/Logs.ReactView (workspace $WorkspaceGuid)"
}
Write-Host "  Policy compliance: Portal → Policy → Assignments → 'Deploy diagnostic settings for Key Vault…' → Compliance"
Write-Host "  Vault diag settings: Portal → $VaultName → Diagnostic settings (should show a policy-created profile)"
Write-Host ""
Write-Host "  Cleanup when done:  pwsh scripts/demo-policy-keyvault.ps1 -Cleanup"
Write-Host ""
Write-Host "✓ Demo setup complete."
