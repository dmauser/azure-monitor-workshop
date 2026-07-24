<div align="center">

# 📊 Azure Monitor Observability Demo Lab

**One command to stand up the modern Azure [Logs Ingestion API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview) stack** — a Data Collection Endpoint, five scenario-specific Data Collection Rules, and custom tables — then stream synthetic telemetry across five real-world observability scenarios.

Authored for the **Azure Monitor Observability Workshop** · Daniel Mauser ([@dmauser](https://github.com/dmauser))

![Azure Monitor](https://img.shields.io/badge/Azure-Monitor-0078D4?logo=microsoftazure&logoColor=white) ![IaC: Bicep](https://img.shields.io/badge/IaC-Bicep-3178C6?logo=azurepipelines&logoColor=white) ![Python 3.11+](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&logoColor=white) ![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f)

**[📖 Hands-On Lab](docs/hands-on-lab.md)** · [📚 Documentation](#-documentation) · [🚀 Quickstart](#-quickstart) · [🏛 Architecture](#-architecture-summary)

</div>

---

## 📚 Documentation

New here? **Start with the [Hands-On Lab Guide](docs/hands-on-lab.md)** — the complete end-to-end walkthrough. All guides live in [`docs/`](docs/).

### 🚀 Start Here

| Guide | What it covers |
| --- | --- |
| **[Hands-On Lab Guide](docs/hands-on-lab.md)** | The complete end-to-end lab — workspace → policy → VM/app → golden-signals workbook → SLO alert, with exact commands, KQL, and verification (maps to deck slide 31). |
| **[Scenario Walkthroughs](docs/scenario-walkthroughs.md)** | A guided tour of each of the five telemetry scenarios — what it simulates, sample KQL, golden-signal queries, and how to inject the built-in anomaly to fire an alert. |

### 🧭 Feature Walkthroughs

| Walkthrough | What it covers |
| --- | --- |
| [Observability Agent](docs/observability-agent-walkthrough.md) | Investigate a fired lab alert with the **Azure Copilot Observability Agent** (preview) — AI-assisted root-cause analysis. |
| [Service Health Alerts](docs/service-health-alerts-walkthrough.md) | Proactive notifications for service issues, planned maintenance, and health/security advisories (portal + IaC). |
| [Azure Policy Diagnostics](docs/policy-diagnostics-walkthrough.md) | Governance demo — a **DeployIfNotExists** policy auto-configures Key Vault diagnostic settings into the workspace. |
| [Demo VM — Guest Metrics](docs/metrics-demo-vm.md) | Stand up a minimal-cost Ubuntu VM for a live Azure Monitor guest-metrics demo (additive to the lab stack). |

### 📐 Reference

| Doc | What it covers |
| --- | --- |
| [Architecture](docs/architecture.md) | End-to-end design of the Logs Ingestion API stack — Bicep deployment to queryable KQL tables. |
| [Data Model](docs/data-model.md) | Custom table schemas, column contracts, and scenario/stream naming conventions. |
| [Design Decisions](docs/design-decisions.md) | The key architectural choices and the rationale behind each one. |

### 🛠️ Support

| Doc | What it covers |
| --- | --- |
| [Troubleshooting](docs/troubleshooting.md) | Diagnostics checklist and fixes for common deployment, ingestion, and query issues. |

---

## 🧩 What the Lab Does

The lab provisions:

| Component | Resource |
| --- | --- |
| Log Analytics Workspace | Central store for all ingested data |
| Data Collection Endpoint (DCE) | HTTPS receiver for the Logs Ingestion API |
| 5 × Data Collection Rule (DCR) | One per scenario — routes, transforms, and writes data |
| 5 × Custom Table (`<Scenario>_CL`) | Dedicated table per scenario in the workspace |
| Workbook (planned) | Unified Azure Monitor Workbook for all scenarios |
| Scheduled-Query Alerts (planned) | Per-scenario alert rules |
| Azure Policy assignment (governance demo) | DeployIfNotExists policy that auto-configures Key Vault diagnostic settings → workspace |

### Ingestion Path

```text
Python generator
    │
    ▼ HTTPS POST (azure-monitor-ingestion SDK + DefaultAzureCredential)
Data Collection Endpoint  (DCE)
    │
    ▼ routes by stream name  (Custom-<Scenario>_CL)
Data Collection Rule  (DCR)  →  transformKql  →  <Scenario>_CL table
    │
    ▼
Log Analytics Workspace  (queryable via KQL / Workbooks / Alerts)
```

### Preview

<!-- To show the workbook, add a screenshot at docs/images/golden-signals-workbook.png and uncomment the line below: -->
<!-- ![Golden-signals workbook](docs/images/golden-signals-workbook.png) -->
> 📸 *Workbook preview coming soon — drop a PNG at `docs/images/golden-signals-workbook.png` and uncomment the image tag above.*

---

## 🎯 Scenarios

| Scenario | Table | Key Signals |
|----------|-------|-------------|
| **Virtual Machines** | `VirtualMachines_CL` | CPU, memory, disk IOPS, network, heartbeat, boot-diag |
| **App Service / PaaS** | `AppService_CL` | Requests, response time, HTTP 5xx/4xx, restarts, plan CPU/mem |
| **AKS / Containers** | `AKS_CL` | Node/pod CPU/mem, restarts, CrashLoopBackOff, PV usage, control-plane |
| **Azure SQL** | `AzureSQL_CL` | DTU/vCore %, connections, deadlocks, storage %, query duration |
| **Applications (APM)** | `APM_CL` | Golden signals: rate, errors, latency P50/P95/P99, dependencies, traces |

> 📘 **New:** step-by-step [**Scenario Walkthroughs**](docs/scenario-walkthroughs.md) — explore each table, run the golden-signal KQL, and inject the built-in anomaly to trigger an alert.

---

## 🏛 Architecture Summary

```text
subscription
└── rg-amlab
    ├── law-amlab-<uid>        (Log Analytics Workspace, PerGB2018, 30-day retention)
    ├── dce-amlab-<uid>        (Data Collection Endpoint)
    ├── dcr-amlab-virtualmachines-<uid>  → VirtualMachines_CL
    ├── dcr-amlab-appservice-<uid>       → AppService_CL
    ├── dcr-amlab-aks-<uid>              → AKS_CL
    ├── dcr-amlab-azuresql-<uid>         → AzureSQL_CL
    └── dcr-amlab-apm-<uid>              → APM_CL

    (governance demo, deployPolicy=true)
    └── dep-diag-kv-amlab   (Policy assignment: DeployIfNotExists → Key Vault diagnostics → workspace)
        + 2 role assignments on the assignment's managed identity
          (Monitoring Contributor, Log Analytics Contributor)
```

`<uid>` = first 6 chars of `uniqueString(subscriptionId, namePrefix)` — deterministic, stable across re-deployments.

All downstream configuration (endpoint URLs, immutable IDs) is sourced from Bicep outputs written to `config/lab.env`. **Nothing is hardcoded** outside of Bicep.

---

## ✅ Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) `>= 2.50` with Bicep (`az bicep install`)
- An Azure subscription with Contributor access
- `az login` (or set `AZURE_SUBSCRIPTION_ID` + service principal env vars for CI)
- Python `>= 3.11` with `pip`
- (Optional) bash or PowerShell 7+ for the helper scripts

---

## 🚀 Quickstart

```bash
# 1. Clone and enter the repo
git clone https://github.com/dmauser/azure-monitor-workshop.git
cd azure-monitor-workshop

# 2. Install Python dependencies
pip install -r requirements.txt

# 3. Deploy infrastructure (creates RG, workspace, DCE, DCRs, tables)
#    Writes config/lab.env with all outputs
bash scripts/deploy          # or: pwsh scripts/deploy.ps1

# 4. Seed synthetic telemetry for all 5 scenarios
bash scripts/seed            # or: pwsh scripts/seed.ps1

# 5. Run smoke-tests to verify data landed in the workspace
bash scripts/smoke-test      # or: pwsh scripts/smoke-test.ps1
```

> **Note:** `scripts/deploy`, `scripts/seed`, and `scripts/smoke-test` each ship with bash and PowerShell (`.ps1`) variants.  
> New to the lab? Follow the **[Hands-On Lab Guide](docs/hands-on-lab.md)**, or browse every guide in [Documentation](#-documentation) above.

---

## ⚙️ Configuration

After deployment, `config/lab.env` is auto-generated from Bicep outputs.  
See [`config/lab.env.example`](config/lab.env.example) for the full variable contract.  
`config/lab.env` is gitignored to prevent accidental credential exposure.

---

## 📁 Repository Layout

```text
azure-monitor-workshop/
├── config/
│   └── lab.env.example      # Variable template (committed)
├── docs/                    # Guides, walkthroughs & reference (see Documentation)
├── generator/               # Python telemetry generator
│   └── scenarios/           # Per-scenario payload builders
├── infra/
│   ├── main.bicep           # Subscription-scoped entry point
│   ├── main.bicepparam      # Default parameters
│   └── modules/             # Reusable Bicep modules
├── scripts/                 # deploy / seed / smoke-test
├── tests/                   # pytest smoke-tests
├── CONTRIBUTING.md
├── LICENSE
├── requirements.txt
└── README.md
```

---

## 🧹 Cleanup

Tear everything down when you're finished to stop incurring charges:

```bash
bash scripts/teardown            # or: pwsh scripts/teardown.ps1
```

This deletes the lab resource group (`rg-amlab` by default) and removes `config/lab.env`. Add `--force` to skip the confirmation prompt. The optional additive demos have their own teardown scripts:

| Demo | Teardown |
| --- | --- |
| Demo VM (guest metrics) | `scripts/teardown-vm` &nbsp;·&nbsp; `scripts/teardown-vm.ps1` |
| Service Health alert | `scripts/teardown-service-health-alert` &nbsp;·&nbsp; `.ps1` |

> 💡 **Cost note:** The core lab uses a `PerGB2018` Log Analytics workspace (30-day retention) holding only synthetic telemetry, so idle cost is minimal. The optional **Demo VM** is the main cost driver — run `scripts/teardown-vm` as soon as the guest-metrics demo is done.

---

## 📄 License

Released under the **MIT License** — see [LICENSE](LICENSE).

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) to get started.