#!/usr/bin/env bash
# scripts/teardown.sh — delete the azure-monitor-workshop resource group and clean up.
#
# Usage:
#   ./scripts/teardown.sh [--force] [--subscription <id>] [--resource-group <rg>]
#
# Without --force, prompts for confirmation before deleting.
# Reads LAB_RESOURCE_GROUP from config/lab.env; falls back to 'rg-amlab'.
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
        --force)           FORCE=true;              shift   ;;
        --subscription)    LAB_SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group)  RESOURCE_GROUP="$2";      shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--force] [--subscription <id>] [--resource-group <rg>]"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

LAB_ENV_PATH="${REPO_ROOT}/config/lab.env"

# ---------------------------------------------------------------------------
# Resolve resource group name
# ---------------------------------------------------------------------------
if [[ -z "$RESOURCE_GROUP" ]]; then
    if [[ -f "$LAB_ENV_PATH" ]]; then
        RESOURCE_GROUP="$(grep -E '^LAB_RESOURCE_GROUP=' "$LAB_ENV_PATH" | cut -d= -f2 | tr -d '[:space:]')" || true
    fi
fi
if [[ -z "$RESOURCE_GROUP" ]]; then
    RESOURCE_GROUP="rg-${LAB_NAME_PREFIX}"
    echo "  WARNING: config/lab.env not found or LAB_RESOURCE_GROUP not set; defaulting to '$RESOURCE_GROUP'" >&2
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
assert_az_cli
set_az_subscription "$LAB_SUBSCRIPTION_ID"

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
echo ""
echo "=== Teardown ==="
echo "  Subscription  : $LAB_SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  lab.env       : $LAB_ENV_PATH"
echo ""

if [[ "$FORCE" != "true" ]]; then
    read -r -p "Type 'yes' to DELETE resource group '$RESOURCE_GROUP' and remove lab.env (Ctrl+C to abort): " answer
    if [[ "$answer" != "yes" ]]; then
        echo "Teardown cancelled."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Delete resource group (non-blocking)
# ---------------------------------------------------------------------------
echo ""
echo "  Deleting resource group '$RESOURCE_GROUP' (--no-wait)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "  Delete submitted. The resource group will be removed in the background."

# ---------------------------------------------------------------------------
# Remove config/lab.env
# ---------------------------------------------------------------------------
if [[ -f "$LAB_ENV_PATH" ]]; then
    rm -f "$LAB_ENV_PATH"
    echo "  Removed: $LAB_ENV_PATH"
else
    echo "  config/lab.env not present (nothing to remove)."
fi

echo ""
echo "=== Teardown complete. ==="
