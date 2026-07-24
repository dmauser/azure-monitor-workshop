#!/usr/bin/env bash
# scripts/deploy-vm.sh — deploy the demo VM module (demo-vm.bicep) to rg-amlab.
#
# Usage:
#   ./scripts/deploy-vm.sh [--subscription <id>] [--resource-group <rg>]
#                          [--vm-size <size>] [--what-if]
#
# Reads config/lab.env for LAB_RESOURCE_GROUP / LAW_RESOURCE_ID / LAB_LOCATION.
# Generates an ed25519 SSH key pair under config/keys/ if absent.
# Writes config/vm.env on success.
#
# ADDITIVE ONLY: does NOT touch existing lab resources.
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
WHAT_IF=false
VM_SIZE=""
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription)   LAB_SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group) RESOURCE_GROUP="$2";       shift 2 ;;
        --vm-size)        VM_SIZE="$2";              shift 2 ;;
        --what-if)        WHAT_IF=true;              shift   ;;
        --help|-h)
            echo "Usage: $0 [--subscription <id>] [--resource-group <rg>]"
            echo "          [--vm-size <size>] [--what-if]"
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
echo "  Location       : $LAB_LOCATION"
echo "  Workspace ID   : $LAW_RESOURCE_ID"

# ---------------------------------------------------------------------------
# SSH key — generate ed25519 pair under config/keys/ if absent
# ---------------------------------------------------------------------------
KEYS_DIR="${REPO_ROOT}/config/keys"
mkdir -p "$KEYS_DIR"
SSH_KEY_PATH="${KEYS_DIR}/vm-amlab-ed25519"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo ""
    echo "  Generating SSH ed25519 key pair → $SSH_KEY_PATH"
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "vm-amlab-lab-key" \
        -q 2>/dev/null || { echo "ERROR: ssh-keygen failed" >&2; exit 1; }
    chmod 600 "$SSH_KEY_PATH"
    echo "  SSH private key: $SSH_KEY_PATH"
    echo "  SSH public key : ${SSH_KEY_PATH}.pub"
else
    echo "  SSH key already exists: $SSH_KEY_PATH"
fi

SSH_PUBLIC_KEY="$(cat "${SSH_KEY_PATH}.pub")"

# ---------------------------------------------------------------------------
# Deployment name — timestamp-based
# ---------------------------------------------------------------------------
DEPLOYMENT_NAME="amlab-vm-$(date -u +%Y%m%d%H%M%S)"

# ---------------------------------------------------------------------------
# Build extra params
# ---------------------------------------------------------------------------
EXTRA_PARAMS=()
[[ -n "$VM_SIZE" ]] && EXTRA_PARAMS+=("--parameters" "vmSize=${VM_SIZE}")

COMMON_ARGS=(
    --resource-group "$RESOURCE_GROUP"
    --name           "$DEPLOYMENT_NAME"
    --template-file  "${REPO_ROOT}/infra/modules/demo-vm.bicep"
    --parameters     "location=${LAB_LOCATION}"
    --parameters     "workspaceResourceId=${LAW_RESOURCE_ID}"
    --parameters     "sshPublicKey=${SSH_PUBLIC_KEY}"
    "${EXTRA_PARAMS[@]}"
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
echo "=== Deploying demo VM: $DEPLOYMENT_NAME → $RESOURCE_GROUP ==="
az deployment group create "${COMMON_ARGS[@]}"

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
echo ""
echo "=== Extracting Bicep outputs ==="

get_output() {
    local name="$1"
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name           "$DEPLOYMENT_NAME" \
        --query          "properties.outputs.${name}.value" \
        -o tsv | tr -d '[:space:]'
}

VM_NAME="$(get_output vmName)"
VM_ID="$(get_output vmId)"
VM_PRIVATE_IP="$(get_output privateIp)"
DCR_ID="$(get_output dcrId)"
NSG_ID="$(get_output nsgId)"
VNET_ID="$(get_output vnetId)"
NIC_ID="$(get_output nicId)"
OS_DISK_NAME="$(get_output osDiskName)"

echo "  VM Name        : $VM_NAME"
echo "  VM Private IP  : $VM_PRIVATE_IP"
echo "  DCR ID         : $DCR_ID"

# ---------------------------------------------------------------------------
# Write config/vm.env
# ---------------------------------------------------------------------------
VM_ENV_PATH="${REPO_ROOT}/config/vm.env"
mkdir -p "$(dirname "$VM_ENV_PATH")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

cat >"$VM_ENV_PATH" <<EOF
# =============================================================================
# config/vm.env — generated by scripts/deploy-vm on ${ts}
# DO NOT EDIT — re-run scripts/deploy-vm to regenerate.
# NEVER commit this file (gitignored).
# =============================================================================
LAB_RESOURCE_GROUP=${RESOURCE_GROUP}
VM_NAME=${VM_NAME}
VM_ID=${VM_ID}
VM_PRIVATE_IP=${VM_PRIVATE_IP}
DCR_ID=${DCR_ID}
NSG_ID=${NSG_ID}
VNET_ID=${VNET_ID}
NIC_ID=${NIC_ID}
OS_DISK_NAME=${OS_DISK_NAME}
SSH_KEY_PATH=${SSH_KEY_PATH}
ADMIN_USERNAME=azureuser
AUTO_SHUTDOWN_NAME=shutdown-computevm-${VM_NAME}
EOF

echo ""
echo "=== Deploy-VM Complete ==="
echo "  VM Name      : $VM_NAME"
echo "  Private IP   : $VM_PRIVATE_IP"
echo "  SSH Key      : $SSH_KEY_PATH"
echo "  vm.env       : $VM_ENV_PATH"
echo ""
echo "  Access VM via Azure Serial Console or:"
echo "    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME \\"
echo "      --command-id RunShellScript --scripts 'uptime'"
