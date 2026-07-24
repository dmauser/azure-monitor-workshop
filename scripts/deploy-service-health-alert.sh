#!/usr/bin/env bash
# scripts/deploy-service-health-alert.sh — deploy the Service Health alert to rg-amlab.
#
# Usage:
#   ./scripts/deploy-service-health-alert.sh [--email-address <email>]
#                                            [--subscription <id>] [--resource-group <rg>]
#                                            [--what-if]
#
# Reads config/lab.env for LAB_RESOURCE_GROUP / LAB_LOCATION / LAB_SUBSCRIPTION_ID.
# Deploys alerts/service-health.alerts.bicep — creates action group + activity log alert.
#
# ADDITIVE ONLY: does NOT modify or delete any existing lab resources.
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
WHAT_IF=false
EMAIL_ADDRESS="you@example.com"
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email-address)  EMAIL_ADDRESS="$2";        shift 2 ;;
        --subscription)   LAB_SUBSCRIPTION_ID="$2";  shift 2 ;;
        --resource-group) RESOURCE_GROUP="$2";       shift 2 ;;
        --what-if)        WHAT_IF=true;              shift   ;;
        --help|-h)
            echo "Usage: $0 [--email-address <email>] [--subscription <id>]"
            echo "          [--resource-group <rg>] [--what-if]"
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
# Load lab.env
# ---------------------------------------------------------------------------
LAB_ENV_PATH="${REPO_ROOT}/config/lab.env"
if [[ ! -f "$LAB_ENV_PATH" ]]; then
    echo "ERROR: config/lab.env not found. Run scripts/deploy first." >&2
    exit 1
fi
# shellcheck source=../config/lab.env
source "$LAB_ENV_PATH"

# Resolve resource group (arg > lab.env > default)
if [[ -z "$RESOURCE_GROUP" ]]; then
    RESOURCE_GROUP="${LAB_RESOURCE_GROUP:-rg-amlab}"
fi

echo "  Resource Group : $RESOURCE_GROUP"
echo "  Email Address  : $EMAIL_ADDRESS"
echo "  Subscription   : $LAB_SUBSCRIPTION_ID"

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based
# ---------------------------------------------------------------------------
DEPLOYMENT_NAME="amlab-svc-health-$(date -u +%Y%m%d%H%M%S)"

TEMPLATE_FILE="${REPO_ROOT}/alerts/service-health.alerts.bicep"

COMMON_ARGS=(
    --resource-group "$RESOURCE_GROUP"
    --name           "$DEPLOYMENT_NAME"
    --template-file  "$TEMPLATE_FILE"
    --parameters     "emailAddress=${EMAIL_ADDRESS}"
)

# ---------------------------------------------------------------------------
# What-If path
# ---------------------------------------------------------------------------
if [[ "$WHAT_IF" == "true" ]]; then
    echo ""
    echo "=== WHAT-IF (no actual deploy) ==="
    az deployment group what-if "${COMMON_ARGS[@]}"
    exit $?
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
echo ""
echo "=== Deploying Service Health alert: $DEPLOYMENT_NAME → $RESOURCE_GROUP ==="
az deployment group create "${COMMON_ARGS[@]}"

# ---------------------------------------------------------------------------
# Print created resources
# ---------------------------------------------------------------------------
echo ""
echo "=== Service Health Alert Resources ==="

echo ""
echo "--- Activity Log Alert ---"
az monitor activity-log alert show \
    --resource-group "$RESOURCE_GROUP" \
    --name "alert-amlab-service-health" \
    -o json

echo ""
echo "--- Action Group ---"
az monitor action-group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "ag-amlab-service-health" \
    -o json

echo ""
echo "=== Deploy-Service-Health-Alert Complete ==="
echo "  Alert        : alert-amlab-service-health"
echo "  Action Group : ag-amlab-service-health"
echo "  Email        : $EMAIL_ADDRESS"
echo "  Cost         : \$0 (Activity Log alerts and email notifications are free)"
