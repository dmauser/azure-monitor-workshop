# Squad Team

> azure-monitor-workshop

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Trinity | Lead / Architect | `.squad/agents/trinity/charter.md` | 🏗️ Active |
| Tank | Infra / IaC Dev | `.squad/agents/tank/charter.md` | 🔧 Active |
| Dozer | Backend / Data Dev | `.squad/agents/dozer/charter.md` | 🐍 Active |
| Ghost | Tester / QA | `.squad/agents/ghost/charter.md` | 🧪 Active |
| Mouse | Content & Docs | `.squad/agents/mouse/charter.md` | 📝 Active |
| Scribe | Session Logger | `.squad/agents/scribe/charter.md` | 📋 Silent |
| Ralph | Work Monitor | — | 🔄 Monitor |

## Project Context

- **Project:** azure-monitor-workshop — Azure Monitor Observability Demo Lab
- **Requested by:** Daniel Mauser (@dmauser)
- **Created:** 2026-07-15
- **Universe:** The Matrix
- **Goal:** Deployable lab that provisions the modern Logs Ingestion stack (Log Analytics + DCE + per-scenario DCRs + custom tables), a Python telemetry generator, KQL, Workbooks, and scheduled-query alerts across 5 scenarios; live deploy + smoke-test to `southcentralus`.
- **Source of truth:** `docs/Azure-Monitor-Observability-Workshop.pptx` (38 slides). Appendix slides 34–38 define the 5 scenarios in a **Watch / Onboard / Alerts & SLOs / Watch-outs** shape.
- **Scenarios & signals (from deck):**
  - **Virtual Machines (IaaS):** CPU, memory, disk space/IOPS, network, heartbeat, boot diag. Alerts: heartbeat lost, disk < 10%, CPU > 90%, availability SLO.
  - **App Service / PaaS:** requests, response time, HTTP 5xx/4xx, restarts, plan CPU/mem. Alerts: 5xx spike, P95 latency SLO, availability-test failure, restart storms.
  - **AKS / Containers:** node/pod CPU/mem, restarts, crashloop, node NotReady, PV usage, control-plane. Alerts: CrashLoopBackOff, node NotReady, PVC full, HPA maxed, API-server errors.
  - **Azure SQL / Databases:** DTU/vCore %, CPU, connections, deadlocks, storage %, query duration. Alerts: high DTU/CPU, storage near cap, connection failures, deadlocks, query-latency SLO.
  - **Applications (APM):** golden signals (rate, errors, latency P50/95/99), dependencies, exceptions, traces. Alerts: failure-rate, P95 latency, dependency failures, availability, error-budget burn.
- **Confirmed build decisions:** live deploy · `DefaultAzureCredential` · per-scenario custom tables (5) · bash + PowerShell scripts · region `southcentralus`.
