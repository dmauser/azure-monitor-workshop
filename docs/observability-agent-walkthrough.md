# Observability Agent Walkthrough: AI-Assisted Alert Investigation

> **Last updated:** 2026-07-16
> **Scope:** Using the **Azure Copilot Observability Agent (preview)** to investigate an
> alert that this lab fires on demand.
> **Source:** [Investigate alerts with the Observability agent — Microsoft Learn](https://learn.microsoft.com/en-us/azure/copilot/observability-agent)

---

## What It Is

The **Observability Agent** is a preview capability of **Azure Copilot's agent mode**. When an
Azure Monitor alert fires, you can hand the alert to the agent and it will run an
**AIOps investigation** on your behalf — correlating related telemetry, proposing a likely
root cause, and recommending remediation steps. It writes its work up as an **Azure Monitor
issue** so the investigation is traceable.

This lab is a natural fit: the Live Demo slides (the workshop deck)
already drive a scenario from **reseed → alert fires**. The Observability Agent picks up exactly
where that leaves off — turning a fired alert into an AI-assisted, explainable triage instead of a
manual KQL dig.

> **Preview scope (operative):** the agent's **fullest support today is for Application Insights
> alerts**. For that reason this walkthrough uses the lab's **APM** scenario as the primary example.
> Other alert types are not yet supported by the agent. The agent **recommends but cannot remediate**
> — it will not change your resources itself.

### Prerequisites

| Requirement | Detail |
|---|---|
| Deployed lab | `rg-amlab` with the `APM_CL` table and the APM alert rules deployed (see [Architecture](architecture.md)) |
| Tenant access | Your tenant must have access to **Agents (preview)** in Azure Copilot |
| RBAC | **Contributor**, **Monitoring Contributor**, *or* **Issue Contributor** on the Azure Monitor Workspace (see [Roles](#how-it-works)) |
| A fired alert | An Application Insights / APM alert in the fired state — Step 1 creates one |

---

## Step 1 — Trigger an Anomaly

Use the lab's reseed script to inject a deterministic APM anomaly. The `errorrate` anomaly has a
failure floor that guarantees failed requests every tick, so it reliably trips the failure-rate
alert:

```powershell
.\scripts\reseed.ps1 -Scenario apm -Anomaly errorrate -Minutes 15
```

This clears and re-seeds the `APM_CL` table with 15 minutes of telemetry in which the request error
rate is driven above the 1% threshold.

> **Alternate anomaly:** `-Anomaly latency` drives P95 request latency above 500 ms and trips the
> **P95 latency** alert instead. `errorrate` is preferred here because its deterministic failure floor
> makes the demo repeatable.

---

## Step 2 — Wait for the Alert to Fire

The APM alerts are **Log Analytics scheduled-query rules**. They evaluate **every 5 minutes**, and
Log Analytics ingestion adds **5–15 minutes** of latency (see
[Troubleshooting → ingestion latency](troubleshooting.md)). Allow up to ~15 minutes after reseed
before the alert appears.

The alert that fires from the `errorrate` anomaly:

| Alert rule | Display name | Severity | Condition |
|---|---|---|---|
| `alert-amlab-apm-failure-rate` | **amlab \| APM \| Failure rate > 1%** | **Sev 2** | request error rate > 1% over 5 min |

Related APM rules (for reference — `latency` / sustained `errorrate`):

| Alert rule | Display name | Severity | Condition |
|---|---|---|---|
| `alert-amlab-apm-p95-latency` | amlab \| APM \| P95 latency > 500 ms | Sev 2 | P95 latency > 500 ms over 5 min |
| `alert-amlab-apm-error-budget-burn` | amlab \| APM \| Error-budget burn > 2% (rolling 1h) | Sev 1 | rolling 1 h failure rate > 2% |

**Locate the fired alert:** in the Azure portal go to **Monitor → Alerts**, scope to resource group
`rg-amlab`, and open the fired **`amlab | APM | Failure rate > 1%`** alert.

---

## Step 3 — Investigate with Azure Copilot

1. Open **Azure Copilot** in the portal.
2. Enable **agent mode (preview)** via the **agent-mode icon** in the Copilot pane.
3. Start an investigation using **either** prompt form below. Use **"Show activity"** at any time to
   watch the agent's progress and reasoning.

### (a) While viewing the alert in the portal

With the fired alert open, simply ask:

```text
Can you help investigate this alert?
```

```text
Start an investigation for this alert.
```

Copilot picks up the alert you are viewing as context.

### (b) By pasting the alert resource ID

If you are not on the alert blade, paste the alert's resource ID. This is the pattern the
Observability Agent documents for **Application Insights component** alerts:

```text
Start an investigation for my alert: /subscriptions/SUB_ID/resourcegroups/RESOURCE_GROUP/providers/microsoft.insights/components/COMPONENT_NAME/providers/Microsoft.AlertsManagement/alerts/ALERT_ID
```

Equivalent phrasings also work:

```text
Can you help with this alert? The ID is /subscriptions/SUB_ID/resourcegroups/RESOURCE_GROUP/providers/microsoft.insights/components/COMPONENT_NAME/providers/Microsoft.AlertsManagement/alerts/ALERT_ID
```

```text
Troubleshoot this alert: /subscriptions/SUB_ID/resourcegroups/RESOURCE_GROUP/providers/microsoft.insights/components/COMPONENT_NAME/providers/Microsoft.AlertsManagement/alerts/ALERT_ID
```

Fill in the placeholders — for this lab, `SUB_ID` = `00000000-0000-0000-0000-000000000000` and
`RESOURCE_GROUP` = `rg-amlab`.

> **Note on this lab's alerts:** the sample resource-ID form above targets a
> `microsoft.insights/components/COMPONENT_NAME` (an **Application Insights component**) — that is the
> Observability Agent's documented pattern and the shape it supports best today. **This lab's APM
> alerts are Log Analytics scheduled-query rules**, not App Insights component alerts, so `COMPONENT_NAME`
> and `ALERT_ID` are **placeholders**: substitute the identifiers from your own App-Insights-backed
> alert when following the paste-the-ID form. Prompt form **(a)** — investigating the alert you are
> viewing in the portal — is the most reliable way to hand this lab's fired alert to the agent.

---

## Step 4 — Review the Investigation

When the investigation completes, the agent returns:

- A concise **investigation summary**.
- **Findings** it uncovered while correlating telemetry.
- **Possible explanations** / candidate root causes.
- Suggested **remediation steps** (advisory — the agent does not apply them).
- A link to the **Azure Monitor issue** it created for the investigation.

Follow the link to the Azure Monitor issue to see the full write-up, keep an audit trail, and share the
triage with your on-call team.

---

## How It Works

Behind the scenes the Observability Agent:

- Creates an **Azure Monitor issue** to represent the investigation.
- Runs an **AIOps investigation** across telemetry related to the alert.
- **Auto-configures an Azure Monitor Workspace** if none is set (and none is passed as context).

### Roles

To run an investigation you need **one** of the following on the **Azure Monitor Workspace**:

| Role | Notes |
|---|---|
| **Contributor** | Broadest — full management on the workspace scope |
| **Monitoring Contributor** | Monitoring-focused management role |
| **Issue Contributor** | Least-privilege role scoped to Azure Monitor issues |

---

## Preview Limitations

> **⚠️ This is a preview capability. Treat these as operative constraints:**
>
> - **Tenant preview access** — availability is limited to tenants with access to **Agents (preview)**
>   in Azure Copilot.
> - **Application Insights alerts only (today)** — agent capabilities currently offer their **fullest
>   support for alerts from Application Insights components**; other alert types are not yet supported.
>   (Documentation also carries a broader "all alert types" statement — treat the App-Insights-only
>   support as the operative limit for now.)
> - **Recommends, doesn't remediate** — the agent can investigate and recommend, but **cannot perform
>   remediation itself**. You apply the fix.

---

## See Also

- [Architecture](architecture.md) — ingestion path, alert rules, resource map.
- [Data Model](data-model.md) — `APM_CL` columns and the alert-driving fields.
- [Troubleshooting](troubleshooting.md) — ingestion latency and query examples.
- [Investigate alerts with the Observability agent — Microsoft Learn](https://learn.microsoft.com/en-us/azure/copilot/observability-agent)
