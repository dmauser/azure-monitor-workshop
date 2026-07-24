#!/usr/bin/env bash
# reseed.sh — Re-run the generator with a fresh time window (convenience wrapper).
#
# NOTE: Azure Monitor custom logs do not support selective row deletion.
# Re-seeding appends new rows; existing data in <Scenario>_CL tables is retained.
# This is intentional — multiple seed passes increase row density for richer
# workbook visualisations and improve alert-trigger probability.
#
# Usage:
#   ./scripts/reseed.sh [--minutes N] [--anomaly KEY] [--scenario SCENARIO] [--seed N]
#
# Defaults: --minutes 15  --scenario all  --seed 42  (no anomaly)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAB_ENV="$REPO_ROOT/config/lab.env"
COMMON="$SCRIPT_DIR/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
MINUTES=15
ANOMALY=""
SCENARIO="all"
SEED=42

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --minutes)   MINUTES="$2";  shift 2 ;;
        --anomaly)   ANOMALY="$2";  shift 2 ;;
        --scenario)  SCENARIO="$2"; shift 2 ;;
        --seed)      SEED="$2";     shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

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

# ── Set PYTHONPATH ────────────────────────────────────────────────────────────
export PYTHONPATH="$REPO_ROOT"
echo "→ PYTHONPATH=$PYTHONPATH"

# ── Build and run generator ───────────────────────────────────────────────────
gen_args=(--scenario "$SCENARIO" --backfill-minutes "$MINUTES" --seed "$SEED")

if [[ -n "$ANOMALY" ]]; then
    gen_args+=(--anomaly "$ANOMALY")
    echo "→ Reseed: scenario=${SCENARIO}  anomaly=${ANOMALY}  minutes=${MINUTES}  seed=${SEED}"
else
    echo "→ Reseed: scenario=${SCENARIO}  minutes=${MINUTES}  seed=${SEED}  (baseline, no anomaly)"
fi

echo ""
echo "  \$ python generator/main.py ${gen_args[*]}"
python "$REPO_ROOT/generator/main.py" "${gen_args[@]}"

echo ""
echo "✓ Reseed complete. Rows appended (existing rows were NOT deleted)."
echo "  Allow 5-15 minutes for ingestion latency before querying."
