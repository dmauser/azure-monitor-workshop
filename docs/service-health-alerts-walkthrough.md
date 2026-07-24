# Service Health Alerts Walkthrough: Proactive Azure Service Health Monitoring

> **Last updated:** 2026-07-17
> **Scope:** Setting up **Azure Service Health alerts** to receive proactive
> notifications about service issues, planned maintenance, health advisories,
> and security advisories affecting your subscriptions.
> **Source:** [Azure Service Health overview — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/overview)

---

## What It Is

**Azure Service Health** is a suite of three components that keep you informed
about Azure platform events at different granularity levels:

| Component | What it shows | Scope |
|---|---|---|
| **Azure Status** | Global outage view at [azure.status.microsoft](https://azure.status.microsoft) | Widespread incidents affecting many customers |
| **Service Health** | **Personalized** per-subscription view: service issues, planned maintenance, health advisories | Only the services and regions **you** use |
| **Resource Health** | Health of **individual** resources, minute-by-minute | Single resource (VM, SQL DB, etc.) |

### Service Health alert events

Service Health alerts are **Activity Log alerts** on category `ServiceHealth`.
They fire for four event classes:

1. **Service issues** — ongoing incidents affecting Azure services.
2. **Planned maintenance** — upcoming maintenance that may impact availability.
3. **Health advisories** — changes that require your attention (e.g., feature retirements, quota changes).
4. **Security advisories** — security-related notifications affecting Azure services.

> **Important:** Service Health notifications do **not** alert on Resource Health
> events. Resource Health has its own, separate alerting mechanism.

### Cost

**$0.** Service Health / Activity Log alerts are free. Email notifications are
free. This is a fully additive demo — deploying these alerts does not modify or
incur cost on any existing lab resources.

### Prerequisites

| Requirement | Detail |
|---|---|
| Azure subscription | At least one active subscription in the target tenant |
| Resource group | A resource group to hold the alert rule (this lab uses `rg-amlab`) |
| RBAC | **Read** on the target resource; **Write** on the RG where the rule is created; **Read** on the associated action group |
| Action group region | **Must** be `Global` — Service Health alerts only fire when the action group's region is set to Global (supported only in public clouds) |

---

## Setup Path A — Portal (Hands-On)

Follow these steps in the Azure portal to create a Service Health alert
interactively.

### Step 1 — Open Service Health

Navigate to **Service Health** in the Azure portal
(search "Service Health" in the portal search bar). Select **Service Issues** in
the left menu to see current incidents, then click **Create service health
alert**.

### Step 2 — Scope

On the **Scope** tab, select the subscription(s) and tenant directory you want
to monitor.

### Step 3 — Condition

On the **Condition** tab, configure:

| Setting | Recommendation |
|---|---|
| **Services** | Select **All services** |
| **Regions** | Select **All regions** |
| **Event types** | Select the classes you want: Service issues, Planned maintenance, Health advisories, Security advisories |

> **Tip:** Selecting _all_ services and _all_ regions does **not** create noise.
> Service Health only triggers for the regions where your services actually run,
> so you stay covered without manual filtering.

### Step 4 — Actions

On the **Actions** tab, select or create an **action group**.

> **⚠️ The action group's region MUST be `Global`.**
> If the action group is not set to Global, the Service Health alert will not
> fire. This is a platform requirement for Activity Log alerts in the
> ServiceHealth category.

Configure at least one notification channel (e.g., email).

### Step 5 — Details

On the **Details** tab, fill in:

- **Resource group** — the RG where the alert rule will live (e.g., `rg-amlab`).
- **Alert rule name** — a descriptive name (e.g., `alert-amlab-service-health`).
- **Description** — optional but recommended.

### Step 6 — Tags & Create

Add any tags your organization requires, review, and click **Create**.

> **Portal reference:** [Create Activity Log alerts on Service Health
> notifications — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-portal)

---

## Setup Path B — IaC / CLI

This lab includes a ready-to-deploy Bicep template and helper scripts.

### Artifacts

| File | Purpose |
|---|---|
| `alerts/service-health.alerts.bicep` | Bicep template: action group (`Global`) + activity log alert (`category=ServiceHealth`) |
| `scripts/deploy-service-health-alert.ps1` | PowerShell deploy wrapper (reads `config/lab.env`) |
| `scripts/deploy-service-health-alert.sh` | Bash deploy wrapper |
| `scripts/teardown-service-health-alert.ps1` | PowerShell teardown |
| `scripts/teardown-service-health-alert.sh` | Bash teardown |

### Deploy

```bash
az deployment group create \
  --resource-group rg-amlab \
  --template-file alerts/service-health.alerts.bicep \
  --parameters emailAddress='you@example.com'
```

Or use the helper script:

```powershell
.\scripts\deploy-service-health-alert.ps1
```

### Validate

Confirm the alert was created and is enabled:

```bash
az monitor activity-log alert show \
  -g rg-amlab \
  -n alert-amlab-service-health
```

Look for `"enabled": true` and `"provisioningState": "Succeeded"` in the
output.

### What gets created

| Resource | Name | Location | Notes |
|---|---|---|---|
| Action group | `ag-amlab-service-health` | **Global** | Email receiver: `you@example.com` |
| Activity log alert | `alert-amlab-service-health` | **Global** | Scope: subscription; condition: `category=ServiceHealth`; enabled |

> **IaC reference:** [Create Activity Log alerts on Service Health notifications
> using Bicep — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-bicep)

---

## Key Points to Remember

- Service Health alerts = **Activity Log alerts** on `category = ServiceHealth`.
- Action groups for Service Health alerts **must** use region `Global`.
- Service Health alerts cover four event classes — they do **not** cover
  Resource Health events (those are separate).
- Selecting all services / all regions is recommended — Service Health
  self-filters to regions where you have deployed services.
- Cost: **$0** — both the alert rules and email notifications are free.
- RBAC: you need Read on the target resource, Write on the alert-rule RG, and
  Read on the action group.

---

## See Also

- [Azure Service Health overview — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/overview)
- [Create alerts on Service Health notifications (portal) — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-portal)
- [Create alerts on Service Health notifications (Bicep) — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-bicep)
- [Resource Health overview — Microsoft Learn](https://learn.microsoft.com/en-us/azure/service-health/resource-health-overview)
- [Action groups — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Architecture](architecture.md) — lab ingestion path, resource map.
- [Troubleshooting](troubleshooting.md) — ingestion latency, query examples.
