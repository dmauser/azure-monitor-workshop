#!/usr/bin/env bash
# scripts/validate.sh — pre-deploy local gate: lint + build bicep files.
#
# Usage:
#   ./scripts/validate.sh [--what-if] [--subscription <id>]
#
# Steps:
#   1. Clean stale .json build artifacts
#   2. az bicep build --file infra/main.bicep  (must exit 0)
#   3. az bicep lint  --file infra/main.bicep  (must exit 0)
#   4. Optional: az deployment sub what-if (requires Azure login; off by default)
#
# Exit codes: 0 = PASS, 1 = FAIL
set -euo pipefail

# Source shared helpers
# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
WHAT_IF=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --what-if)      WHAT_IF=true;              shift   ;;
        --subscription) LAB_SUBSCRIPTION_ID="$2";  shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--what-if] [--subscription <id>]"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

BICEP_FILE="$REPO_ROOT/infra/main.bicep"
PASS=true

add_result() {
    local label="$1"
    local ok="$2"
    local detail="${3:-}"
    if [[ "$ok" == "true" ]]; then
        echo "  [PASS] $label${detail:+ — $detail}"
    else
        echo "  [FAIL] $label${detail:+ — $detail}"
        PASS=false
    fi
}

echo ""
echo "=== validate.sh — Pre-Deploy Gate ==="
echo ""

# ---------------------------------------------------------------------------
# Step 0: Verify az CLI is available
# ---------------------------------------------------------------------------
if command -v az &>/dev/null; then
    add_result "az CLI present" "true"
else
    add_result "az CLI present" "false" "az CLI not found"
    echo "FAIL: az CLI not found — cannot continue." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Clean stale .json build artifacts
# ---------------------------------------------------------------------------
echo "  Cleaning stale .json build artifacts..."
find "$REPO_ROOT/infra"   -name '*.json' -delete 2>/dev/null || true
find "$REPO_ROOT/alerts"  -name '*.json' -delete 2>/dev/null || true
add_result "Stale .json cleaned" "true"

# ---------------------------------------------------------------------------
# Step 2: az bicep build
# ---------------------------------------------------------------------------
echo ""
echo "  Running az bicep build..."
if az bicep build --file "$BICEP_FILE" 2>&1; then
    add_result "az bicep build" "true"
else
    add_result "az bicep build" "false"
fi

# ---------------------------------------------------------------------------
# Step 3: az bicep lint
# ---------------------------------------------------------------------------
echo ""
echo "  Running az bicep lint..."
if az bicep lint --file "$BICEP_FILE" 2>&1; then
    add_result "az bicep lint" "true"
else
    add_result "az bicep lint" "false"
fi

# ---------------------------------------------------------------------------
# Step 4 (optional): az deployment sub what-if
# ---------------------------------------------------------------------------
if [[ "$WHAT_IF" == "true" ]]; then
    echo ""
    echo "  Running az deployment sub what-if..."
    if ! az account show &>/dev/null; then
        add_result "az deployment sub what-if" "false" "Skipped — not logged in to Azure"
    else
        set_az_subscription "$LAB_SUBSCRIPTION_ID"
        PRINCIPAL_ID="${LAB_PRINCIPAL_ID:-}"
        if [[ -z "$PRINCIPAL_ID" ]]; then
            PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null | tr -d '[:space:]')" || true
        fi
        if az deployment sub what-if \
                --name "validate-whatif-$(date -u +%Y%m%d%H%M%S)" \
                --location "$LAB_LOCATION" \
                --template-file "$BICEP_FILE" \
                --parameters "$REPO_ROOT/infra/main.bicepparam" \
                --parameters "principalId=${PRINCIPAL_ID:-}" \
                2>&1; then
            add_result "az deployment sub what-if" "true"
        else
            add_result "az deployment sub what-if" "false"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo ""

if [[ "$PASS" == "true" ]]; then
    echo "RESULT: PASS — all checks passed."
    exit 0
else
    echo "RESULT: FAIL — one or more checks failed." >&2
    exit 1
fi
