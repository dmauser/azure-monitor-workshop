#!/usr/bin/env bash
# smoke-test.sh — Post-deploy verification gate.
#
# 1. Loads config/lab.env.
# 2. For each of the 5 custom-log tables, polls Log Analytics until rows appear
#    (up to MAX_WAIT_MINUTES; custom-log ingestion can lag 5-15 min after upload).
# 3. Lists all scheduled-query alert rules in the resource group and confirms
#    all 13 expected rules exist and are enabled.
# 4. Prints a PASS/FAIL summary table.
# 5. Exits non-zero if any table has 0 rows after retries, or any alert rule
#    is missing or disabled.
#
# Usage:
#   ./scripts/smoke-test.sh [--max-wait-minutes N] [--poll-interval-seconds N]
#
# NOTE on fired-alert state: az CLI does not expose scheduled-query-rule fire
# history directly.  After this script passes, verify fired alerts via:
#   Azure Portal → Monitor → Alerts → Alert history (filter by RG)
# Or via REST:
#   az rest --method get \
#     --url 'https://management.azure.com/subscriptions/<sub>/resourceGroups/<RG>/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01&alertState=Fired'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAB_ENV="$REPO_ROOT/config/lab.env"
COMMON="$SCRIPT_DIR/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
MAX_WAIT_MINUTES=20
POLL_INTERVAL_SECONDS=60

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-wait-minutes)      MAX_WAIT_MINUTES="$2";      shift 2 ;;
        --poll-interval-seconds) POLL_INTERVAL_SECONDS="$2"; shift 2 ;;
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

# ── Resolve key env vars ──────────────────────────────────────────────────────
LAW_ID="${LAW_ID:-}"
LAB_RESOURCE_GROUP="${LAB_RESOURCE_GROUP:-}"

if [[ -z "$LAW_ID" ]]; then
    echo "ERROR: LAW_ID is empty in config/lab.env." >&2; exit 1
fi
if [[ -z "$LAB_RESOURCE_GROUP" ]]; then
    echo "ERROR: LAB_RESOURCE_GROUP is empty in config/lab.env." >&2; exit 1
fi

# Table name map (fall back to static defaults when lab.env values are absent)
table_labels=("VirtualMachines" "AppService" "AKS" "AzureSQL" "APM")
table_names=(
    "${TABLE_VIRTUAL_MACHINES:-VirtualMachines_CL}"
    "${TABLE_APP_SERVICE:-AppService_CL}"
    "${TABLE_AKS:-AKS_CL}"
    "${TABLE_AZURE_SQL:-AzureSQL_CL}"
    "${TABLE_APM:-APM_CL}"
)
declare -A table_counts
for lbl in "${table_labels[@]}"; do table_counts["$lbl"]=0; done

# Expected alert rule names (13 total) — from tank-alerts-workbooks.md
expected_alerts=(
    "alert-amlab-vm-cpu-high"
    "alert-amlab-vm-disk-low"
    "alert-amlab-vm-heartbeat-missing"
    "alert-amlab-app-5xx-high"
    "alert-amlab-app-p95-high"
    "alert-amlab-aks-crashloop"
    "alert-amlab-aks-node-notready"
    "alert-amlab-sql-dtu-high"
    "alert-amlab-sql-storage-high"
    "alert-amlab-sql-deadlocks"
    "alert-amlab-apm-failure-rate"
    "alert-amlab-apm-p95-latency"
    "alert-amlab-apm-error-budget-burn"
)
declare -A alert_status
for name in "${expected_alerts[@]}"; do alert_status["$name"]="MISSING"; done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Table row counts with retry loop
# Custom-log ingestion can lag 5-15 min; poll until rows appear or timeout.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
printf '═%.0s' {1..65}; echo
echo "STEP 1 — Table row counts"
echo "  Retry window : ${MAX_WAIT_MINUTES} min  |  Poll interval : ${POLL_INTERVAL_SECONDS}s"
echo "  Custom-log ingestion latency is typically 5-15 min after upload."
printf '═%.0s' {1..65}; echo

max_iter=$(( (MAX_WAIT_MINUTES * 60 + POLL_INTERVAL_SECONDS - 1) / POLL_INTERVAL_SECONDS ))
iteration=0
pending_indices=()
for i in "${!table_labels[@]}"; do pending_indices+=("$i"); done

while [[ ${#pending_indices[@]} -gt 0 && $iteration -lt $max_iter ]]; do
    elapsed_sec=$(( iteration * POLL_INTERVAL_SECONDS ))
    echo ""
    echo "[Poll $(( iteration + 1 ))/${max_iter} | ${elapsed_sec}s elapsed] Querying ${#pending_indices[@]} table(s)..."

    still_pending=()
    for i in "${pending_indices[@]}"; do
        label="${table_labels[$i]}"
        tname="${table_names[$i]}"
        kql="${tname} | where TimeGenerated > ago(1h) | summarize RowCount=count()"
        count=0
        query_ok=true

        raw=$(az monitor log-analytics query \
            --workspace "$LAW_ID" \
            --analytics-query "$kql" \
            --query "[0].RowCount" \
            --output tsv 2>&1) || query_ok=false

        if [[ "$query_ok" == "false" ]]; then
            echo "  [${label}] Query error (will retry): ${raw}"
            still_pending+=("$i")
            continue
        fi

        count="${raw//[[:space:]]/}"
        if [[ ! "$count" =~ ^[0-9]+$ ]]; then count=0; fi

        if [[ "$count" -ge 1 ]]; then
            table_counts["$label"]="$count"
            echo "  [${label}] ✓  ${count} row(s)"
        else
            echo "  [${label}] 0 rows — ingestion pending, will retry"
            still_pending+=("$i")
        fi
    done

    pending_indices=("${still_pending[@]+"${still_pending[@]}"}")
    iteration=$(( iteration + 1 ))

    if [[ ${#pending_indices[@]} -gt 0 && $iteration -lt $max_iter ]]; then
        echo "  Waiting ${POLL_INTERVAL_SECONDS}s …"
        sleep "$POLL_INTERVAL_SECONDS"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Alert rule provisioning
# ─────────────────────────────────────────────────────────────────────────────
echo ""
printf '═%.0s' {1..65}; echo
echo "STEP 2 — Alert rule provisioning (resource group: ${LAB_RESOURCE_GROUP})"
printf '═%.0s' {1..65}; echo

# Fetch the JSON; tolerate az failure by falling back to empty array
alert_json="[]"
if ! alert_json=$(az monitor scheduled-query list \
        -g "$LAB_RESOURCE_GROUP" --output json 2>/dev/null); then
    echo "  WARNING: Could not list scheduled-query rules — marking all as QUERY_ERROR"
    for name in "${expected_alerts[@]}"; do alert_status["$name"]="QUERY_ERROR"; done
fi

# Python parser — reads JSON from stdin, writes "name=STATUS" lines to stdout.
# Uses process substitution so the while loop runs in the current shell and
# can update the alert_status associative array directly.
parse_py='
import sys, json
try:
    rules = json.loads(sys.stdin.read())
except (json.JSONDecodeError, ValueError):
    rules = []
rule_map = {}
for r in rules:
    n = r.get("name", "")
    # enabled may be at top level or under properties; default True if absent
    e = r.get("enabled", r.get("properties", {}).get("enabled", True))
    rule_map[n] = bool(e)
expected = [
    "alert-amlab-vm-cpu-high",
    "alert-amlab-vm-disk-low",
    "alert-amlab-vm-heartbeat-missing",
    "alert-amlab-app-5xx-high",
    "alert-amlab-app-p95-high",
    "alert-amlab-aks-crashloop",
    "alert-amlab-aks-node-notready",
    "alert-amlab-sql-dtu-high",
    "alert-amlab-sql-storage-high",
    "alert-amlab-sql-deadlocks",
    "alert-amlab-apm-failure-rate",
    "alert-amlab-apm-p95-latency",
    "alert-amlab-apm-error-budget-burn",
]
for name in expected:
    if name in rule_map:
        status = "ENABLED" if rule_map[name] else "DISABLED"
    else:
        status = "MISSING"
    print(f"{name}={status}")
'

while IFS='=' read -r a_name a_status; do
    alert_status["$a_name"]="$a_status"
done < <(echo "$alert_json" | python3 -c "$parse_py")

echo ""
echo "  NOTE — Verifying FIRED state requires the Azure Portal or REST API."
echo "  Portal : Monitor → Alerts → Alert history  (filter RG = '${LAB_RESOURCE_GROUP}')"
RG_FIRED_URL="https://management.azure.com/subscriptions/${LAB_SUBSCRIPTION_ID}"
RG_FIRED_URL+="/resourceGroups/${LAB_RESOURCE_GROUP}/providers/Microsoft.AlertsManagement"
RG_FIRED_URL+="/alerts?api-version=2019-03-01&alertState=Fired"
echo "  REST   : az rest --method get --url '${RG_FIRED_URL}'"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PASS/FAIL report
# ─────────────────────────────────────────────────────────────────────────────
echo ""
printf '═%.0s' {1..65}; echo
echo "SMOKE-TEST RESULTS"
printf '═%.0s' {1..65}; echo

echo ""
echo "┌─ Table Row Counts ──────────────────────────────────────────"
any_table_fail=false
for i in "${!table_labels[@]}"; do
    label="${table_labels[$i]}"
    tname="${table_names[$i]}"
    count="${table_counts[$label]:-0}"
    if [[ "$count" -ge 1 ]]; then
        printf "│  %-25s %6s rows   [PASS] ✓\n" "${tname}:" "$count"
    else
        printf "│  %-25s %6s rows   [FAIL] ✗\n" "${tname}:" "$count"
        any_table_fail=true
    fi
done
echo "└─────────────────────────────────────────────────────────────"

echo ""
echo "┌─ Alert Rule Provisioning ───────────────────────────────────"
any_alert_fail=false
for name in "${expected_alerts[@]}"; do
    st="${alert_status[$name]:-MISSING}"
    if [[ "$st" == "ENABLED" ]]; then
        printf "│  %-47s [%-12s] ✓\n" "$name" "$st"
    else
        printf "│  %-47s [%-12s] ✗\n" "$name" "$st"
        any_alert_fail=true
    fi
done
echo "└─────────────────────────────────────────────────────────────"

echo ""
if [[ "$any_table_fail" == "true" || "$any_alert_fail" == "true" ]]; then
    echo "OVERALL RESULT: ✗  FAIL"
    [[ "$any_table_fail" == "true" ]] && \
        echo "  → One or more tables had 0 rows after ${MAX_WAIT_MINUTES}-minute wait."
    [[ "$any_alert_fail" == "true" ]] && \
        echo "  → One or more alert rules are missing or disabled."
    exit 1
else
    echo "OVERALL RESULT: ✓  PASS"
fi
