# Hands-On Lab — Monitoring in Your Environment

> **Maps to:** Workshop deck slide 31 ("Hands-On Lab — Monitoring in Your Environment").
> **Goal:** a working reference pattern your team can replicate across every future workload —
> proof, in your own environment, on day one.
> **Last updated:** 2026-07-23
> **Time to complete:** ~90–120 min (steps 1–5); +30 min for the optional AKS step 6.

This is the end-to-end lab that ties the six slide steps to the artifacts already in this
repo (`infra/`, `workbooks/`, `kql/`, `alerts/`, `scripts/`). Where the repo automates a
step, you run a script. Where the step is a portal/manual exercise (App Insights, the
dashboard, Grafana/Prometheus), the exact click-path and CLI are given.

| # | Slide step | Repo does it? | You run / do |
|---|---|---|---|
| 1 | Stand up / confirm a central Log Analytics workspace | ✅ Automated | `scripts/deploy` |
| 2 | Apply the diagnostic-settings policy to a subscription | ⚠️ RG-scoped demo built in; sub-scope is manual | `scripts/demo-policy-keyvault` + portal assign at sub scope |
| 3 | Onboard a sample VM + app — AMA/DCR + Application Insights | ⚠️ VM automated; App Insights manual | `scripts/deploy-vm` + portal App Insights |
| 4 | Build a golden-signals workbook and a dashboard | ⚠️ Workbook automated; dashboard manual | deployed workbook + pin to dashboard |
| 5 | Create an SLO-based alert + action group — fire a test | ⚠️ SLO rules automated; **action group is not** | wire action group, then `scripts/reseed` to fire |
| 6 | Optional: Managed Grafana + Managed Prometheus for AKS | ❌ Not in repo | `az aks update --enable-azure-monitor-metrics` |

---

## Before You Start

### Prerequisites

| Requirement | Detail |
|---|---|
| Azure subscription | Contributor on the subscription. **Owner** or **User Access Administrator** is needed for step 2's policy role assignments and for the DCR role grants in step 1. |
| Azure CLI | `>= 2.50` with Bicep — `az bicep install` |
| Python | `>= 3.11` with `pip` (telemetry generator, steps 1/5) |
| Shell | PowerShell 7+ **or** bash for the helper scripts |
| Signed in | `az login` and the correct subscription selected (see below) |

### Clone and set up (Step 0)

```powershell
git clone https://github.com/dmauser/azure-monitor-workshop.git
cd azure-monitor-workshop
pip install -r requirements.txt

az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

> The scripts default to your current `az` context subscription. Override
> with `-SubscriptionId` (PowerShell) / `SUBSCRIPTION_ID=…` env, or edit `config/lab.env`
> after step 1. Everywhere below, `<uid6>` is a deterministic 6-char suffix derived from your
> subscription ID + prefix (e.g. `law-amlab-<uid>`).

### The reference architecture you're building

```
Azure Subscription
└── rg-amlab                                   (Resource Group)          ← Step 1
    ├── law-amlab-<uid6>                        (Log Analytics Workspace) ← Step 1  (the "central" LAW)
    │   ├── VirtualMachines_CL / AppService_CL / AKS_CL / AzureSQL_CL / APM_CL   (custom tables)
    │   ├── Perf / InsightsMetrics / Heartbeat  (from the demo VM's AMA)  ← Step 3
    │   └── AzureDiagnostics                     (from the KV policy)     ← Step 2
    ├── dce-amlab-<uid6>                         (Data Collection Endpoint)← Step 1
    ├── dcr-amlab-<scenario>-<uid6>  (×5)        (Data Collection Rules)  ← Step 1
    ├── 6 × Azure Monitor Workbook (Overview + 5 scenarios)              ← Step 4
    ├── scenario SLO alert rules (incl. APM failure-rate / P95 / burn)  ← Step 5
    ├── dep-diag-kv-amlab   (Key Vault diagnostics DINE policy)          ← Step 2
    ├── vm-amlab-<uid6> + AzureMonitorLinuxAgent + dcr-amlab-vmguest     ← Step 3
    └── ag-amlab-…          (action group — you create/attach)           ← Step 5
```

Deep-dive reference: [`architecture.md`](architecture.md) · [`data-model.md`](data-model.md).

---

## Step 1 — Stand up / confirm a central Log Analytics workspace

**Goal:** one workspace that every future workload streams to, plus the modern Logs
Ingestion API plumbing (DCE + 5 DCRs + 5 custom tables) so you can prove data lands.

### 1.1 Deploy the base stack

```powershell
# PowerShell
.\scripts\deploy.ps1
# Optional: preview only, no changes
.\scripts\deploy.ps1 -WhatIfMode
```

```bash
# bash
bash scripts/deploy.sh
```

This subscription-scoped Bicep deployment (`infra/main.bicep`) creates the resource group,
the **central Log Analytics workspace** (`law-amlab-<uid6>`, PerGB2018, 30-day retention),
the Data Collection Endpoint, 5 custom tables, 5 DCRs, the 6 workbooks (step 4), the scenario
alert rules (step 5), and the Key Vault diagnostics policy (step 2). It then writes every
output ID to **`config/lab.env`** — nothing downstream is hardcoded.

Useful flags: `-SkipWorkbooks` and `-SkipAlerts` to defer steps 4/5; `-NamePrefix` /
`-Location` to change naming/region; `-PrincipalId <oid>` to grant a specific identity the
**Monitoring Metrics Publisher** role on each DCR (defaults to the signed-in user).

### 1.2 Seed synthetic telemetry

```powershell
.\scripts\seed.ps1            # or: bash scripts/seed.sh
```

The Python generator posts records over HTTPS through the DCE, routed by each DCR into the
matching `<Scenario>_CL` table.

### 1.3 Verify (smoke test + KQL)

```powershell
.\scripts\smoke-test.ps1      # or: bash scripts/smoke-test.sh
```

Then in the portal open **`law-amlab-<uid6>` → Logs** and confirm data landed:

```kql
union VirtualMachines_CL, AppService_CL, AKS_CL, AzureSQL_CL, APM_CL
| summarize Rows = count() by Type = $table
| order by Rows desc
```

> **Ingestion latency:** allow **5–15 min** after seeding before rows appear. If a table is
> empty, see [`troubleshooting.md`](troubleshooting.md).

✅ **Done when:** all five `*_CL` tables return rows and `config/lab.env` exists with a
populated `LAW_RESOURCE_ID` and `DCE_LOGS_INGESTION_ENDPOINT`.

---

## Step 2 — Apply the diagnostic-settings policy to a subscription

**Goal:** prove governance turns on observability automatically — a **DeployIfNotExists
(DINE)** policy that configures diagnostic settings so a resource streams its platform logs
to the central workspace **without anyone remembering to click it**.

### 2.1 What the lab already applied (resource-group scope)

`scripts/deploy` (step 1) assigned the built-in policy **"Deploy Diagnostic Settings for Key
Vault to Log Analytics workspace"** at `rg-amlab` scope (`deployPolicy=true` by default),
with a managed identity holding **Monitoring Contributor** + **Log Analytics Contributor**.
Any Key Vault created in `rg-amlab` is auto-wired to `law-amlab-<uid6>`.

Run the guided demo and watch it remediate:

```powershell
pwsh scripts/demo-policy-keyvault.ps1        # or: bash scripts/demo-policy-keyvault.sh
```

It creates a Key Vault, forces an on-demand remediation, waits for the diagnostic setting to
appear, writes a secret, and prints the verification KQL. Full narration + timing gotchas
(the `AfterProvisioning` delay, drift/re-remediation): [`policy-diagnostics-walkthrough.md`](policy-diagnostics-walkthrough.md).

Verify the audit trail reached the workspace:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where Category == "AuditEvent"
| project TimeGenerated, Resource, OperationName, ResultType, CallerIPAddress
| order by TimeGenerated desc
```

### 2.2 Promote the policy to *subscription* scope (the slide's ask)

The demo is RG-scoped so it's safe and cheap. To do what the slide says — enforce diagnostic
settings across a whole **subscription** — assign a diagnostics policy (or the "Enable Azure
Monitor" initiative) at subscription scope:

**Portal:** **Policy → Assignments → Assign initiative/policy** → set **Scope = the
subscription** → pick a *"Deploy diagnostic settings … to Log Analytics workspace"* built-in →
set the `logAnalytics` parameter to `LAW_RESOURCE_ID` from `config/lab.env` → on the
**Remediation** tab check **Create a remediation task** and let Azure create the managed
identity.

**CLI (Key Vault built-in, sub scope):**

```bash
az policy assignment create \
  --name enable-kv-diag-sub \
  --display-name "Deploy KV diagnostics to LAW (subscription)" \
  --scope "/subscriptions/<YOUR_SUBSCRIPTION_ID>" \
  --policy "bef3f64c-5290-43b7-85b0-9b254eef4c47" \
  --mi-system-assigned --location <region> \
  --params "{ \"logAnalytics\": { \"value\": \"<LAW_RESOURCE_ID>\" } }"
# Then grant the assignment identity Monitoring Contributor + Log Analytics Contributor
# at subscription scope, and create a remediation task.
```

> ⚠️ **Blast radius:** a subscription-scoped DINE policy touches every matching resource in
> the subscription. In a shared/production subscription, start with **`Audit`** effect (or a
> narrow resource type) before switching to `DeployIfNotExists`.

✅ **Done when:** a new Key Vault gets a diagnostic setting with no manual action, and its
`AuditEvent` rows appear in the workspace.

---

## Step 3 — Onboard a sample VM + app (AMA/DCR + Application Insights)

**Goal:** onboard real signals two ways — **infrastructure** (VM guest metrics via the Azure
Monitor Agent + a DCR) and **application** (an app reporting to Application Insights).

### 3.1 VM half — automated (AMA + guest DCR)

```powershell
.\scripts\deploy-vm.ps1       # or: bash scripts/deploy-vm.sh
```

Deploys an additive, low-cost Ubuntu VM (`vm-amlab-<uid6>`, `Standard_B2ats_v2`, no public IP,
auto-shutdown) with the **AzureMonitorLinuxAgent** extension and a guest **DCR** that streams
CPU / memory / disk / network counters into `Perf` and `InsightsMetrics`. It writes
`config/vm.env`. Full script, cost (~$6/mo with auto-shutdown), counter set, and load-gen
commands: [`metrics-demo-vm.md`](metrics-demo-vm.md).

Verify the agent is alive and reporting (allow 3–10 min after deploy):

```kql
Heartbeat
| where Computer has "vm-amlab"
| summarize LastSeen = max(TimeGenerated) by Computer, OSType, Version
```

```kql
Perf
| where Computer has "vm-amlab"
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by bin(TimeGenerated, 1m), Computer
| order by TimeGenerated desc
```

Generate a CPU spike without SSH, then re-query:

```bash
source config/vm.env
az vm run-command invoke -g rg-amlab -n "$VM_NAME" --command-id RunShellScript \
  --scripts 'timeout 60 openssl speed sha256 & timeout 60 openssl speed sha256 & wait; echo done'
```

### 3.2 App half — Application Insights (portal, ~10 min)

The repo has no App Insights automation, so onboard one manually. Two options:

**A) Real Azure app (recommended for the "app" story).** Create a small App Service, then:

1. **Create the App Insights resource (workspace-based):** Portal → **Application Insights →
   Create** → put it in `rg-amlab`, and set **Workspace** = `law-amlab-<uid6>` so telemetry
   lands in your central workspace.
2. **Enable auto-instrumentation (codeless):** open the App Service → **Settings →
   Application Insights → Turn on** → select the App Insights resource → **Apply**. For
   supported runtimes this instruments requests/dependencies/exceptions with **no code
   change**. (Equivalent manual wiring: set the app setting
   `APPLICATIONINSIGHTS_CONNECTION_STRING` to the resource's connection string.)
3. Drive a little traffic (browse the site), wait ~2–5 min, then confirm:

```kql
requests
| where timestamp > ago(30m)
| summarize count() by bin(timestamp, 1m), resultCode
| order by timestamp desc
```

**B) No spare app?** Use the lab's **`APM_CL`** table as the stand-in application signal —
it already carries golden-signals telemetry (requests, dependencies, exceptions, traces) from
the generator, and it's what steps 4 and 5 build on. This keeps you moving without standing up
App Service.

> App Insights' `requests`/`dependencies`/`exceptions` tables and the lab's `APM_CL` model the
> **same golden signals**; the workbook/alerts below use `APM_CL` so they work with either
> path.

✅ **Done when:** VM `Perf`/`Heartbeat` rows are flowing **and** you have an application signal
(either App Insights `requests` or `APM_CL`).

---

## Step 4 — Build a golden-signals workbook and a dashboard

**Goal:** a single glass pane for the **golden signals** (rate, errors, latency P50/P95/P99,
dependencies) plus a shareable dashboard for at-a-glance status.

### 4.1 The workbook is already deployed

`scripts/deploy` published 6 Azure Monitor Workbooks (unless you passed `-SkipWorkbooks`).
Open **`law-amlab-<uid6>` → Workbooks** (or **Monitor → Workbooks**, scope `rg-amlab`) and open
**"Azure Monitor Lab — APM"** — this is your golden-signals board (request rate, error rate,
P50/P95/P99 latency, dependency failures, exceptions). The **"… — Overview"** workbook rolls
up all five scenarios.

The panels are driven by [`kql/apm.kql`](../kql/apm.kql) blocks [1]–[6]. Example — the latency
percentiles panel:

```kql
APM_CL
| where TimeGenerated >= ago(1h)
| where ItemType == "request"
| summarize P50Ms = percentile(DurationMs, 50),
            P95Ms = percentile(DurationMs, 95),
            P99Ms = percentile(DurationMs, 99)
    by bin(TimeGenerated, 5m), Resource, Environment
| order by TimeGenerated asc
```

> Re-deploying workbooks after edits: `.\scripts\deploy.ps1` (idempotent). To iterate on a
> panel, edit the workbook in the portal, then **Edit → Advanced Editor** to export JSON back
> into `workbooks/apm.workbook.json`.

### 4.2 Build the dashboard (portal, ~10 min)

Workbooks are interactive; a **dashboard** is the pinned, glanceable summary.

1. In the APM workbook, put it in **edit** mode, hover a chart tile → **⋯ → Pin to
   dashboard** → **Create new** → name it `Golden Signals`.
2. Add a couple of raw **Metrics** tiles for breadth: **Monitor → Metrics** → scope the demo
   VM → e.g. *Percentage CPU* → **Pin to dashboard** (same dashboard).
3. Open **Dashboard → Golden Signals**, arrange tiles, set the default time range,
   and **Share** it (publishes to `rg-amlab` as a shared dashboard so the team sees it).

✅ **Done when:** the APM workbook shows rate/errors/latency and a shared **Golden
Signals** dashboard exists with at least one workbook tile + one metric tile.

---

## Step 5 — Create an SLO-based alert + action group, and fire a test

**Goal:** an alert tied to a **Service Level Objective** (P95 latency < 500 ms; failure rate
< 1%), wired to an **action group** that notifies you — then deliberately break the SLO and
watch it fire.

### 5.1 The SLO rules already exist

`scripts/deploy` created these APM SLO alert rules (source: `alerts/apm.alerts.bicep`,
KQL blocks [7]–[9]):

| Alert rule | Display name | Sev | SLO condition |
|---|---|---|---|
| `alert-amlab-apm-failure-rate` | amlab \| APM \| Failure rate > 1% | 2 | error rate > 1% / 5 min |
| `alert-amlab-apm-p95-latency` | amlab \| APM \| P95 latency > 500 ms | 2 | P95 > 500 ms / 5 min |
| `alert-amlab-apm-error-budget-burn` | amlab \| APM \| Error-budget burn > 2% (rolling 1h) | 1 | rolling-1h error rate > 2% |

Find them under **Monitor → Alerts → Alert rules**, scope `rg-amlab`.

### 5.2 Create + attach an action group (required — the lab does not add one)

> ⚠️ **Gap to close:** the scenario SLO rules deploy **without** an action group
> (`infra/modules/scheduled-query-alert.bicep` takes no action-group parameter), so by default
> they change state but **send no notification**. Do one of the following.

**Option A — reuse the repo's action-group pattern (fastest).** The Service Health helper
already builds a Global email action group (`ag-amlab-service-health`). Deploy it to get an
action group you can attach:

```powershell
.\scripts\deploy-service-health-alert.ps1     # prompts / uses your email
```

**Option B — create one directly:**

```bash
az monitor action-group create \
  -g rg-amlab -n ag-amlab-slo --short-name amlabSLO \
  --action email oncall <you>@example.com
```

**Attach it to each APM SLO rule** (portal): **Monitor → Alert rules** → open
`alert-amlab-apm-p95-latency` → **Actions → Select action group** → pick the group → **Save**.
Repeat for `alert-amlab-apm-failure-rate`. (CLI: `az monitor scheduled-query update -g
rg-amlab -n <alertName> --action-groups <actionGroupResourceId>`.)

### 5.3 Fire a test — break the SLO on purpose

Inject a deterministic APM anomaly so the failure-rate rule trips:

```powershell
.\scripts\reseed.ps1 -Scenario apm -Anomaly errorrate -Minutes 15
```

This re-seeds 15 min of APM telemetry with the request error rate driven above 1%. Use
`-Anomaly latency` instead to push P95 > 500 ms and trip the latency rule.

### 5.4 Watch it fire

The rules evaluate **every 5 min** and ingestion adds **5–15 min** latency, so allow up to
~15 min. Check **Monitor → Alerts** (scope `rg-amlab`) for a fired
**amlab | APM | Failure rate > 1%** alert and confirm your action group sent the email.

Preview the exact condition the rule evaluates:

```kql
APM_CL
| where TimeGenerated >= ago(5m)
| where ItemType == "request"
| summarize TotalReqs = count(), FailedReqs = countif(IsSuccess == false)
    by bin(TimeGenerated, 5m), Resource, Environment
| where TotalReqs > 0
| extend ErrorRatePct = FailedReqs * 100.0 / TotalReqs
| where ErrorRatePct > 1.0
```

> **Take it further (AI triage):** hand the fired alert to the Azure Copilot **Observability
> Agent** to auto-investigate — see [`observability-agent-walkthrough.md`](observability-agent-walkthrough.md).

✅ **Done when:** the SLO alert fires after the reseed **and** the attached action group
notifies you.

---

## Step 6 — Optional: Managed Grafana + Managed Prometheus for AKS

**Goal:** show the cloud-native metrics stack — **Azure Monitor managed service for
Prometheus** scraping an AKS cluster, visualized in **Azure Managed Grafana**. Not automated
by this repo; here's the minimal path.

> **Note:** Managed Prometheus stores metrics in an **Azure Monitor workspace (AMW)** — a
> different resource type from the Log Analytics workspace used in steps 1–5. Managed Grafana
> is a separate resource. Both incur cost; tear them down when finished.

```bash
# 1) Create an Azure Monitor workspace (Prometheus metrics store) and Managed Grafana
az monitor account create -g rg-amlab -n amw-amlab -l <region>
az grafana create -g rg-amlab -n amg-amlab -l <region>

# 2) Create (or reuse) an AKS cluster, then enable Managed Prometheus + link Grafana
az aks update \
  -g rg-amlab -n <aksClusterName> \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id "<AMW_RESOURCE_ID>" \
  --grafana-resource-id "<GRAFANA_RESOURCE_ID>"
```

`--enable-azure-monitor-metrics` installs the metrics add-on (ama-metrics pods) that scrapes
Prometheus endpoints into the AMW; `--grafana-resource-id` wires the AMW as a Grafana data
source. Then open **Managed Grafana → Endpoint** and load the prebuilt **Kubernetes /
Compute Resources** dashboards, or query with **PromQL** (e.g.
`sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)`).

The lab's `AKS_CL` table (steps 1/4) already gives you an AKS golden-signals workbook in the
Log Analytics stack — step 6 is the **PromQL/Grafana** complement for teams standardizing on
Prometheus.

✅ **Done when:** Managed Grafana renders live AKS Prometheus metrics from the AMW.

---

## Outcome

You now have a reusable reference pattern, proven in your own environment:

- a **central Log Analytics workspace** every workload can stream to (Step 1),
- **governance** that turns diagnostics on automatically (Step 2),
- **infra + app onboarding** via AMA/DCR and Application Insights (Step 3),
- a **golden-signals workbook + dashboard** (Step 4),
- an **SLO alert + action group** you fired on demand (Step 5),
- and an optional **Prometheus/Grafana** path for AKS (Step 6).

Replicate it for the next workload by pointing its diagnostics/agents at the same workspace
and cloning the workbook + alert patterns.

---

## Cleanup

```powershell
# Remove just the demo VM (keeps the lab stack)
.\scripts\teardown-vm.ps1

# Remove the Service Health action group/alert if you deployed it
.\scripts\teardown-service-health-alert.ps1

# Remove the Key Vault policy demo objects
pwsh scripts/demo-policy-keyvault.ps1 -Cleanup
```

To remove **everything**, use the repo's teardown (deletes the resource group — this destroys
the workspace and all lab data):

```powershell
.\scripts\teardown.ps1 -Force      # or: bash scripts/teardown.sh
```

Step 6 resources (`amw-amlab`, `amg-amlab`, any AKS cluster) are separate — delete them
individually if you created them.

---

## Troubleshooting quick reference

| Symptom | Fix |
|---|---|
| `*_CL` table empty after seed | Wait 5–15 min (ingestion latency); confirm role **Monitoring Metrics Publisher** on the DCRs; see [`troubleshooting.md`](troubleshooting.md) |
| `config/lab.env` missing | Re-run `scripts/deploy`; it's written from Bicep outputs |
| VM `Perf`/`InsightsMetrics` empty | Confirm AMA provisioned + VM has a system-assigned identity; [`metrics-demo-vm.md`](metrics-demo-vm.md) |
| SLO alert never fires | Confirm the reseed injected the anomaly; rules need 5-min eval + 5–15-min ingestion; check the KQL returns rows |
| SLO alert fires but no email | Action group not attached — do Step 5.2 |
| KV diagnostic setting not appearing | `AfterProvisioning` delay (~10–30 min) or run an on-demand remediation; [`policy-diagnostics-walkthrough.md`](policy-diagnostics-walkthrough.md) |

## See also

- [`architecture.md`](architecture.md) — full topology, ingestion path, API versions
- [`data-model.md`](data-model.md) — every `*_CL` table's columns
- [`policy-diagnostics-walkthrough.md`](policy-diagnostics-walkthrough.md) — Step 2 deep dive
- [`metrics-demo-vm.md`](metrics-demo-vm.md) — Step 3 VM deep dive
- [`service-health-alerts-walkthrough.md`](service-health-alerts-walkthrough.md) — action-group pattern
- [`observability-agent-walkthrough.md`](observability-agent-walkthrough.md) — AI-assisted Step 5 triage
- [`troubleshooting.md`](troubleshooting.md) — ingestion latency, common failures
