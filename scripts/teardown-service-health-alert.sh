#!/usr/bin/env bash
# scripts/teardown-service-health-alert.sh — delete the Service Health alert resources.
#
# Usage:
#   ./scripts/teardown-service-health-alert.sh [--force] [--subscription <id>]
#                                              [--resource-group <rg>]
#
# Deletes (idempotent — no error if already gone):
#   - alert-amlab-service-health  (microsoft.insights/activityLogAlerts)
#   - ag-amlab-service-health     (microsoft.insights/actionGroups)
#
# Does NOT touch any other lab resources (workspace, DCRs, VMs, other alerts).
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORCE=false
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)          FORCE=true;               shift   ;;
        --subscription)   LAB_SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group) RESOURCE_GROUP="$2";      shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--force] [--subscription <id>] [--resource-group <rg>]"
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
# Resolve resource group from lab.env or param
# ---------------------------------------------------------------------------
LAB_ENV_PATH="${REPO_ROOT}/config/lab.env"
if [[ -z "$RESOURCE_GROUP" ]]; then
    if [[ -f "$LAB_ENV_PATH" ]]; then
        # shellcheck source=../config/lab.env
        source "$LAB_ENV_PATH"
        RESOURCE_GROUP="${LAB_RESOURCE_GROUP:-rg-amlab}"
    else
        RESOURCE_GROUP="rg-amlab"
    fi
fi

ALERT_NAME="alert-amlab-service-health"
ACTION_GROUP_NAME="ag-amlab-service-health"

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
echo ""
echo "=== Service Health Alert Teardown ==="
echo "  Subscription  : $LAB_SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP"
echo ""
echo "  Resources to be DELETED (if present):"
echo "    Activity Log Alert : $ALERT_NAME"
echo "    Action Group       : $ACTION_GROUP_NAME"
echo ""
echo "  Resources NOT touched:"
echo "    All other lab resources (workspace, DCRs, VMs, scenario alerts, etc.)"
echo ""

if [[ "$FORCE" != "true" ]]; then
    read -r -p "Type 'yes' to DELETE (Ctrl+C to abort): " answer
    if [[ "$answer" != "yes" ]]; then
        echo "Teardown cancelled."
        exit 0
    fi
fi

RG="$RESOURCE_GROUP"

# Helper: delete activity log alert by name, no-op if already gone
delete_activity_log_alert() {
    local name="$1"
    if az monitor activity-log alert show --resource-group "$RG" --name "$name" &>/dev/null 2>&1; then
        echo "  Deleting activity log alert: $name"
        az monitor activity-log alert delete --resource-group "$RG" --name "$name" --yes 2>/dev/null || \
            echo "  WARNING: delete returned non-zero for $name (may already be gone)"
        echo "  Deleted: $name"
    else
        echo "  Already gone (or not found): $name"
    fi
}

# Helper: delete action group by name, no-op if already gone
delete_action_group() {
    local name="$1"
    if az monitor action-group show --resource-group "$RG" --name "$name" &>/dev/null 2>&1; then
        echo "  Deleting action group: $name"
        az monitor action-group delete --resource-group "$RG" --name "$name" 2>/dev/null || \
            echo "  WARNING: delete returned non-zero for $name (may already be gone)"
        echo "  Deleted: $name"
    else
        echo "  Already gone (or not found): $name"
    fi
}

echo ""
echo "=== Deleting Service Health alert resources ==="

# 1. Delete alert first (it references the action group)
delete_activity_log_alert "$ALERT_NAME"

# 2. Delete action group
delete_action_group "$ACTION_GROUP_NAME"

echo ""
echo "=== Service Health alert teardown complete. All other lab resources untouched. ==="
