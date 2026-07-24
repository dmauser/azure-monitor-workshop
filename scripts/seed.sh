#!/usr/bin/env bash
# seed.sh — Populate all 5 custom-log tables (baseline + anomaly passes).
#
# 1. Loads config/lab.env (via scripts/common.sh if present, else directly).
# 2. Sets PYTHONPATH to the repo root.
# 3. Runs a baseline pass: --scenario all --backfill-minutes 15
# 4. Runs one anomaly pass per alert-triggering key (12 total).
#
# Exits non-zero on any generator upload failure.
# Custom logs cannot be selectively deleted; repeated runs append rows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAB_ENV="$REPO_ROOT/config/lab.env"
COMMON="$SCRIPT_DIR/common.sh"

# ── Load common helpers (Tank owns this; provides helpers, not lab.env vars) ──
if [[ -f "$COMMON" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON"
fi

# ── Always load config/lab.env (common.sh does not expose lab vars) ───────────
if [[ ! -f "$LAB_ENV" ]]; then
    echo "ERROR: config/lab.env not found at '$LAB_ENV'. Run scripts/deploy first." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$LAB_ENV"
set +a

# ── Set subscription ───────────────────────────────────────────────────────────
if [[ -n "${LAB_SUBSCRIPTION_ID:-}" ]]; then
    echo "→ Setting subscription ${LAB_SUBSCRIPTION_ID}"
    az account set --subscription "${LAB_SUBSCRIPTION_ID}"
fi

# ── Validate required env vars ────────────────────────────────────────────────
required_vars=(
    DCE_LOGS_INGESTION_ENDPOINT
    DCR_IMMUTABLE_ID_VIRTUAL_MACHINES
    DCR_IMMUTABLE_ID_APP_SERVICE
    DCR_IMMUTABLE_ID_AKS
    DCR_IMMUTABLE_ID_AZURE_SQL
    DCR_IMMUTABLE_ID_APM
)
for v in "${required_vars[@]}"; do
    if [[ -z "${!v:-}" ]]; then
        echo "ERROR: Required env var '$v' is empty. Ensure config/lab.env is fully populated." >&2
        exit 1
    fi
done

# ── Set PYTHONPATH ────────────────────────────────────────────────────────────
export PYTHONPATH="$REPO_ROOT"
echo "→ PYTHONPATH=$PYTHONPATH"

# ── Helper ─────────────────────────────────────────────────────────────────────
run_generator() {
    echo "  \$ python generator/main.py $*"
    python "$REPO_ROOT/generator/main.py" "$@"
}

# ── 1. Baseline pass ──────────────────────────────────────────────────────────
echo ""
echo "=== BASELINE PASS (all scenarios, 15-min backfill) ==="
run_generator --scenario all --backfill-minutes 15

# ── 2. Anomaly passes ─────────────────────────────────────────────────────────
# One pass per anomaly key; --seed 42 keeps output reproducible.
# Generators that don't recognise a key treat it as a no-op baseline (safe).
echo ""
echo "=== ANOMALY PASSES (one per alert-triggering key) ==="

# Format: "scenario:key"
anomalies=(
    "virtualmachines:cpu"
    "virtualmachines:disk"
    "virtualmachines:heartbeat"
    "appservice:5xx"
    "appservice:latency"
    "aks:crashloop"
    "aks:nodenotready"
    "azuresql:dtu"
    "azuresql:storage"
    "azuresql:deadlock"
    "apm:errorrate"
    "apm:latency"
)

for entry in "${anomalies[@]}"; do
    scenario="${entry%%:*}"
    key="${entry##*:}"
    echo ""
    echo "  -- ${scenario} / ${key}"
    run_generator \
        --scenario        "$scenario" \
        --anomaly         "$key" \
        --backfill-minutes 15 \
        --seed            42
done

echo ""
echo "✓ Seed complete — baseline + 12 anomaly passes uploaded."
echo "  Allow 5-15 minutes for custom-log ingestion before running smoke-test."
