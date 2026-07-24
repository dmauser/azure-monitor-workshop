#!/usr/bin/env bash
# scripts/deploy.sh — deploy azure-monitor-workshop infrastructure to Azure.
#
# Usage:
#   ./scripts/deploy.sh [--subscription <id>] [--principal-id <oid>]
#                       [--name-prefix <prefix>] [--location <region>]
#                       [--what-if] [--skip-alerts] [--skip-workbooks]
#
# Idempotent: safe to re-run. Resource names are deterministic from namePrefix.
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
WHAT_IF=false
SKIP_ALERTS=false
SKIP_WORKBOOKS=false
PRINCIPAL_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription)   LAB_SUBSCRIPTION_ID="$2"; shift 2 ;;
        --principal-id)   PRINCIPAL_ID="$2";        shift 2 ;;
        --name-prefix)    LAB_NAME_PREFIX="$2";     shift 2 ;;
        --location)       LAB_LOCATION="$2";         shift 2 ;;
        --what-if)        WHAT_IF=true;              shift   ;;
        --skip-alerts)    SKIP_ALERTS=true;          shift   ;;
        --skip-workbooks) SKIP_WORKBOOKS=true;       shift   ;;
        --help|-h)
            echo "Usage: $0 [--subscription <id>] [--principal-id <oid>]"
            echo "          [--name-prefix <prefix>] [--location <region>]"
            echo "          [--what-if] [--skip-alerts] [--skip-workbooks]"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
assert_az_cli
set_az_subscription "$LAB_SUBSCRIPTION_ID"

# ---------------------------------------------------------------------------
# Resolve principalId
# Priority: --principal-id > env LAB_PRINCIPAL_ID > az ad signed-in-user > lab default
# ---------------------------------------------------------------------------
if [[ -z "$PRINCIPAL_ID" ]]; then
    PRINCIPAL_ID="${LAB_PRINCIPAL_ID:-}"
fi
if [[ -z "$PRINCIPAL_ID" ]]; then
    echo "  Resolving principalId from az ad signed-in-user show..."
    PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null | tr -d '[:space:]')" || true
fi
if [[ -z "$PRINCIPAL_ID" ]]; then
    echo "ERROR: Could not resolve principalId. Pass --principal-id <objectId> or set LAB_PRINCIPAL_ID." >&2
    exit 1
fi
echo "  principalId: $PRINCIPAL_ID"

# ---------------------------------------------------------------------------
# Clean stale .json build artifacts (prevents BCP037 false positives)
# ---------------------------------------------------------------------------
echo "  Cleaning stale .json build artifacts..."
find "$REPO_ROOT/infra"   -name '*.json' -delete 2>/dev/null || true
find "$REPO_ROOT/alerts"  -name '*.json' -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based, unique per run, stable output
# ---------------------------------------------------------------------------
DEPLOYMENT_NAME="amlab-$(date -u +%Y%m%d%H%M%S)"

# ---------------------------------------------------------------------------
# Bicep bool overrides
# ---------------------------------------------------------------------------
DEPLOY_ALERTS="true"
DEPLOY_WORKBOOKS="true"
[[ "$SKIP_ALERTS" == "true" ]]    && DEPLOY_ALERTS="false"
[[ "$SKIP_WORKBOOKS" == "true" ]] && DEPLOY_WORKBOOKS="false"

COMMON_ARGS=(
    --name          "$DEPLOYMENT_NAME"
    --location      "$LAB_LOCATION"
    --template-file "$REPO_ROOT/infra/main.bicep"
    --parameters    "$REPO_ROOT/infra/main.bicepparam"
    --parameters    "principalId=$PRINCIPAL_ID"
    --parameters    "deployAlerts=$DEPLOY_ALERTS"
    --parameters    "deployWorkbooks=$DEPLOY_WORKBOOKS"
)

# ---------------------------------------------------------------------------
# What-If path — print plan and exit
# ---------------------------------------------------------------------------
if [[ "$WHAT_IF" == "true" ]]; then
    echo ""
    echo "=== WHAT-IF (no actual deploy) ==="
    az deployment sub what-if "${COMMON_ARGS[@]}"
    exit $?
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
echo ""
echo "=== Deploying $DEPLOYMENT_NAME → $LAB_LOCATION ==="
az deployment sub create "${COMMON_ARGS[@]}"

# ---------------------------------------------------------------------------
# Extract outputs helper
# ---------------------------------------------------------------------------
get_output() {
    local name="$1"
    az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.${name}.value" \
        -o tsv | tr -d '[:space:]'
}

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
echo ""
echo "=== Extracting Bicep outputs ==="

LAB_LOCATION="$(get_output location)"
LAB_RESOURCE_GROUP="$(get_output resourceGroupName)"
LAB_SUBSCRIPTION_ID="$(az account show --query id -o tsv | tr -d '[:space:]')"
LAW_NAME="$(get_output workspaceName)"
LAW_ID="$(get_output workspaceCustomerId)"
LAW_RESOURCE_ID="$(get_output workspaceResourceId)"
DCE_LOGS_INGESTION_ENDPOINT="$(get_output dceLogsIngestionEndpoint)"
DCR_IMMUTABLE_ID_VIRTUAL_MACHINES="$(get_output dcrImmutableIdVirtualMachines)"
DCR_IMMUTABLE_ID_APP_SERVICE="$(get_output dcrImmutableIdAppService)"
DCR_IMMUTABLE_ID_AKS="$(get_output dcrImmutableIdAks)"
DCR_IMMUTABLE_ID_AZURE_SQL="$(get_output dcrImmutableIdAzureSql)"
DCR_IMMUTABLE_ID_APM="$(get_output dcrImmutableIdApm)"
STREAM_VIRTUAL_MACHINES="$(get_output streamVirtualMachines)"
STREAM_APP_SERVICE="$(get_output streamAppService)"
STREAM_AKS="$(get_output streamAks)"
STREAM_AZURE_SQL="$(get_output streamAzureSql)"
STREAM_APM="$(get_output streamApm)"
TABLE_VIRTUAL_MACHINES="$(get_output tableVirtualMachines)"
TABLE_APP_SERVICE="$(get_output tableAppService)"
TABLE_AKS="$(get_output tableAks)"
TABLE_AZURE_SQL="$(get_output tableAzureSql)"
TABLE_APM="$(get_output tableApm)"

# ---------------------------------------------------------------------------
# Write config/lab.env
# ---------------------------------------------------------------------------
write_lab_env

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Deploy Complete ==="
echo "  Resource Group : $LAB_RESOURCE_GROUP"
echo "  Workspace      : $LAW_NAME"
echo "  DCE Endpoint   : $DCE_LOGS_INGESTION_ENDPOINT"
echo "  lab.env        : $REPO_ROOT/config/lab.env"
