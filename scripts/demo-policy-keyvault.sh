#!/usr/bin/env bash
# =============================================================================
# scripts/demo-policy-keyvault.sh
#
# Live demo: Azure Policy (DeployIfNotExists) auto-configures Key Vault
# diagnostic settings to the lab's Log Analytics workspace.
#
#   1. Create a Key Vault in rg-amlab (RBAC-auth, Standard SKU).
#   2. Trigger an on-demand policy remediation (fast-path the DINE deployment).
#   3. Poll until the policy-created diagnostic setting appears on the vault.
#   4. Grant the signed-in user Key Vault Secrets Officer + write a secret
#      (generates an AuditEvent).
#   5. Print verification KQL + portal links + cleanup commands.
#
# Requires the policy assignment from infra/main.bicep (deployPolicy=true).
#
# Usage:  scripts/demo-policy-keyvault.sh [--cleanup] [--vault NAME]
# =============================================================================
set -euo pipefail

SUBSCRIPTION="${SUBSCRIPTION:-$(az account show --query id -o tsv 2>/dev/null)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_ENV="$REPO_ROOT/config/lab.env"
ASSIGNMENT_NAME="dep-diag-kv-amlab"
CLEANUP=false
VAULT_NAME=""
MAX_WAIT_MIN="${MAX_WAIT_MIN:-20}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup) CLEANUP=true; shift ;;
    --vault)   VAULT_NAME="$2"; shift 2 ;;
    --max-wait-min) MAX_WAIT_MIN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Load lab.env (best-effort) for LAB_RESOURCE_GROUP / LAB_LOCATION / LAW_ID
if [[ -f "$LAB_ENV" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$LAB_ENV"; set +a
fi
RESOURCE_GROUP="${LAB_RESOURCE_GROUP:-rg-amlab}"
LOCATION="${LAB_LOCATION:-southcentralus}"
WORKSPACE_GUID="${LAW_ID:-}"

echo "→ Setting subscription $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION"

# ── Cleanup mode ─────────────────────────────────────────────────────────────
if $CLEANUP; then
  if [[ -z "$VAULT_NAME" ]]; then
    echo "→ Discovering demo Key Vaults (kv-amlab-demo-*) in $RESOURCE_GROUP"
    VAULTS=$(az keyvault list -g "$RESOURCE_GROUP" --query "[?starts_with(name,'kv-amlab-demo-')].name" -o tsv)
  else
    VAULTS="$VAULT_NAME"
  fi
  for v in $VAULTS; do
    [[ -z "$v" ]] && continue
    echo "→ Deleting Key Vault $v"; az keyvault delete -g "$RESOURCE_GROUP" -n "$v" 2>/dev/null || true
    echo "→ Purging Key Vault $v";  az keyvault purge -n "$v" --location "$LOCATION" 2>/dev/null || true
  done
  echo "→ Deleting remediation task"
  az policy remediation delete --name "remediate-$ASSIGNMENT_NAME" --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
  echo "✓ Cleanup complete."
  exit 0
fi

# ── Preflight: assignment must exist ─────────────────────────────────────────
SCOPE="/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP"
echo "→ Verifying policy assignment '$ASSIGNMENT_NAME'"
ASSIGNMENT_ID=$(az policy assignment show --name "$ASSIGNMENT_NAME" --scope "$SCOPE" --query id -o tsv 2>/dev/null || true)
if [[ -z "$ASSIGNMENT_ID" ]]; then
  echo "ERROR: assignment '$ASSIGNMENT_NAME' not found. Deploy infra/main.bicep with deployPolicy=true first." >&2
  exit 1
fi
echo "   assignment: $ASSIGNMENT_ID"

# ── Vault name ───────────────────────────────────────────────────────────────
if [[ -z "$VAULT_NAME" ]]; then
  RAND=$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)
  VAULT_NAME="kv-amlab-demo-$RAND"
fi
echo "→ Key Vault name: $VAULT_NAME"

# ── 1. Create Key Vault ──────────────────────────────────────────────────────
echo "→ [1/5] Creating Key Vault (Standard, RBAC authorization)…"
KV_ID=$(az keyvault create -g "$RESOURCE_GROUP" -n "$VAULT_NAME" -l "$LOCATION" \
  --enable-rbac-authorization true --sku standard --query id -o tsv)
echo "   created: $KV_ID"

# ── 2. Trigger scan + remediation ────────────────────────────────────────────
echo "→ [2/5] Forcing a compliance scan + on-demand remediation…"
az policy state trigger-scan --resource-group "$RESOURCE_GROUP" --no-wait >/dev/null 2>&1 || true
az policy remediation create \
  --name "remediate-$ASSIGNMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --resource-discovery-mode ReEvaluateCompliance >/dev/null 2>&1 \
  || echo "   (remediation submit non-zero — DINE may still auto-deploy; continuing)"

# ── 3. Poll for diagnostic setting ───────────────────────────────────────────
# The built-in policy uses evaluationDelay 'AfterProvisioning' → Azure delays
# existence evaluation ~10–30 min after the vault provisions. Pre-create the
# vault before the demo segment.
MAX_ITERS=$(( MAX_WAIT_MIN * 2 ))
echo "→ [3/5] Waiting for the policy to deploy the diagnostic setting (up to ${MAX_WAIT_MIN} min)…"
DIAG_FOUND=false
for i in $(seq 1 "$MAX_ITERS"); do
  sleep 30
  DIAG=$(az monitor diagnostic-settings list --resource "$KV_ID" --query "value[].name" -o tsv 2>/dev/null || true)
  if [[ -n "$DIAG" ]]; then
    DIAG_FOUND=true
    echo "   ✓ diagnostic setting(s) present: $DIAG (after ~$((i*30))s)"
    break
  fi
  (( i % 4 == 0 )) && echo "   …still waiting ($((i*30/60)) min) — DINE 'AfterProvisioning' delay is normal"
done
$DIAG_FOUND || echo "   ⚠ No diagnostic setting yet after ${MAX_WAIT_MIN} min — cold-vault delay can reach ~30 min. Re-check: az monitor diagnostic-settings list --resource $KV_ID -o table"

# ── 4. Grant self + write secret (with RBAC-propagation retry) ────────────────
echo "→ [4/5] Granting yourself 'Key Vault Secrets Officer' and writing a demo secret…"
ME=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
if [[ -n "$ME" ]]; then
  az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
    --role "Key Vault Secrets Officer" --scope "$KV_ID" >/dev/null 2>&1 || true
  SECRET_OK=false
  for r in $(seq 1 8); do
    sleep 20
    if az keyvault secret set --vault-name "$VAULT_NAME" --name "demo-secret" --value "hello-observability" >/dev/null 2>&1; then
      SECRET_OK=true; break
    fi
    echo "   …waiting for Key Vault RBAC to propagate (attempt $r)"
  done
  if $SECRET_OK; then
    echo "   ✓ secret 'demo-secret' created — emits a Key Vault AuditEvent"
  else
    echo "   ⚠ secret write still failing. Retry: az keyvault secret set --vault-name $VAULT_NAME --name demo-secret --value hello"
  fi
else
  echo "   ⚠ Could not resolve your object ID — grant RBAC + write a secret manually to generate an audit event."
fi

# ── 5. Verification ──────────────────────────────────────────────────────────
cat <<EOF

→ [5/5] Verify in Log Analytics (allow ~5–10 min for AuditEvent ingestion):

  AzureDiagnostics
  | where ResourceProvider == 'MICROSOFT.KEYVAULT'
  | where Resource == toupper('$VAULT_NAME')
  | where Category == 'AuditEvent'
  | project TimeGenerated, OperationName, ResultType, CallerIPAddress, identity_claim_upn_s
  | order by TimeGenerated desc

  Policy compliance: Portal → Policy → Assignments → 'Deploy diagnostic settings for Key Vault…' → Compliance
  Vault diag settings: Portal → $VAULT_NAME → Diagnostic settings (policy-created profile)
  Cleanup: scripts/demo-policy-keyvault.sh --cleanup

✓ Demo setup complete.
EOF
