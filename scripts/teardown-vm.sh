#!/usr/bin/env bash
# scripts/teardown-vm.sh — delete ONLY the demo VM and its dedicated resources.
#
# Usage:
#   ./scripts/teardown-vm.sh [--force] [--subscription <id>]
#
# Reads config/vm.env for resource IDs. Does NOT touch the main lab stack
# (workspace, DCE, scenario DCRs, custom tables, alerts).
#
# Resources deleted (in dependency order):
#   1. Auto-shutdown schedule
#   2. VM (triggers NIC + OS disk delete via deleteOption: Delete)
#   3. DCR Association (implicit with VM delete, but explicit for safety)
#   4. DCR (guest-metrics DCR)
#   5. NSG
#   6. VNet
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)         FORCE=true;              shift   ;;
        --subscription)  LAB_SUBSCRIPTION_ID="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--force] [--subscription <id>]"
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
# Load vm.env
# ---------------------------------------------------------------------------
VM_ENV_PATH="${REPO_ROOT}/config/vm.env"
if [[ ! -f "$VM_ENV_PATH" ]]; then
    echo "ERROR: config/vm.env not found. Was deploy-vm.sh run?" >&2
    exit 1
fi
# shellcheck source=../config/vm.env
source "$VM_ENV_PATH"

# Validate required vars
for v in LAB_RESOURCE_GROUP VM_NAME VM_ID DCR_ID NSG_ID VNET_ID; do
    if [[ -z "${!v:-}" ]]; then
        echo "ERROR: $v not set in config/vm.env" >&2
        exit 1
    fi
done

AUTO_SHUTDOWN_NAME="${AUTO_SHUTDOWN_NAME:-shutdown-computevm-${VM_NAME}}"

# ---------------------------------------------------------------------------
# Confirmation prompt
# ---------------------------------------------------------------------------
echo ""
echo "=== Demo VM Teardown ==="
echo "  Subscription  : $LAB_SUBSCRIPTION_ID"
echo "  Resource Group: $LAB_RESOURCE_GROUP"
echo "  VM Name       : $VM_NAME"
echo "  DCR ID        : $DCR_ID"
echo ""
echo "  Resources to be DELETED:"
echo "    shutdown-computevm-${VM_NAME}"
echo "    VM: ${VM_NAME}"
echo "    NIC: ${NIC_ID##*/}"
echo "    OS Disk: ${OS_DISK_NAME}"
echo "    DCR: ${DCR_ID##*/}"
echo "    NSG: ${NSG_ID##*/}"
echo "    VNet: ${VNET_ID##*/}"
echo ""
echo "  Resources NOT touched (main lab stack stays intact):"
echo "    law-amlab-* / dce-amlab-* / dcr-amlab-virtualmachines-* / custom tables / alerts"
echo ""

if [[ "$FORCE" != "true" ]]; then
    read -r -p "Type 'yes' to DELETE the demo VM and its resources (Ctrl+C to abort): " answer
    if [[ "$answer" != "yes" ]]; then
        echo "Teardown cancelled."
        exit 0
    fi
fi

RG="$LAB_RESOURCE_GROUP"

# Helper: delete by ID (silently no-op if already gone)
delete_resource() {
    local id="$1"
    local label="$2"
    if az resource show --ids "$id" &>/dev/null 2>&1; then
        echo "  Deleting $label..."
        az resource delete --ids "$id" --verbose 2>/dev/null || \
            echo "  WARNING: delete returned non-zero for $label (may already be gone)"
    else
        echo "  Already gone: $label"
    fi
}

echo ""
echo "=== Deleting demo VM resources ==="

# 1. Auto-shutdown schedule
echo "  Deleting auto-shutdown schedule: $AUTO_SHUTDOWN_NAME"
az devtestlab schedule delete --resource-group "$RG" --lab-name "" --name "$AUTO_SHUTDOWN_NAME" 2>/dev/null || \
    az resource delete \
        --resource-group "$RG" \
        --resource-type "Microsoft.DevTestLab/schedules" \
        --name "$AUTO_SHUTDOWN_NAME" \
        --api-version 2018-09-15 2>/dev/null || \
    echo "  NOTE: auto-shutdown schedule may already be gone or will be deleted with VM"

# 2. VM (NIC and OS disk carry deleteOption: Delete → auto-deleted)
echo "  Deleting VM: $VM_NAME (NIC + OS disk will auto-delete)"
az vm delete --resource-group "$RG" --name "$VM_NAME" --yes --no-wait 2>/dev/null || \
    echo "  NOTE: VM may already be gone"
echo "  Waiting for VM deletion to complete..."
az vm wait --resource-group "$RG" --name "$VM_NAME" --deleted 2>/dev/null || true

# 3. DCR (DCRA is auto-deleted when VM is deleted)
delete_resource "$DCR_ID" "DCR ${DCR_ID##*/}"

# 4. NSG
delete_resource "$NSG_ID" "NSG ${NSG_ID##*/}"

# 5. VNet
delete_resource "$VNET_ID" "VNet ${VNET_ID##*/}"

# ---------------------------------------------------------------------------
# Remove config/vm.env
# ---------------------------------------------------------------------------
rm -f "$VM_ENV_PATH"
echo "  Removed: $VM_ENV_PATH"

echo ""
echo "=== Demo VM teardown complete. Main lab stack untouched. ==="
