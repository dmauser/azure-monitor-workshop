# Azure Policy Diagnostics Walkthrough: Governance-Enforced Diagnostic Settings

> **Last updated:** 2026-07-21
> **Scope:** Using an **Azure Policy DeployIfNotExists (DINE)** assignment to
> automatically configure **Key Vault** diagnostic settings so that every Key
> Vault created in `rg-amlab` streams its audit logs to the lab's existing
> **Log Analytics workspace** — no manual configuration, enforced by governance.
> **Source:** [Azure Policy — DeployIfNotExists effect (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/effect-deploy-if-not-exists)

---

## What It Is

Diagnostic settings are the switch that routes a resource's platform logs and
metrics to a destination (Log Analytics, Storage, or Event Hub). Teams routinely
**forget to turn them on**, so resources go dark — no audit trail, no alerting,
no forensics. **Azure Policy** fixes this at the platform layer:

- **`AuditIfNotExists`** — flags non-compliant resources (reports only).
- **`DeployIfNotExists` (DINE)** — flags **and remediates**: Azure deploys the
  missing diagnostic setting for you, using a managed identity.

This demo assigns a **built-in DINE policy** that watches for Key Vaults and, on
any vault missing the setting, deploys a diagnostic setting pointing at the lab
workspace. The presenter creates a Key Vault, watches the setting appear
automatically, writes a secret, then queries the resulting audit log in Log
Analytics — the full "governance configures observability for you" story.

### The built-in policy

| Field | Value |
|---|---|
| Display name | **Deploy Diagnostic Settings for Key Vault to Log Analytics workspace** |
| Definition ID | `bef3f64c-5290-43b7-85b0-9b254eef4c47` |
| Effect | `DeployIfNotExists` |
| Key parameter | `logAnalytics` = the workspace ARM resource ID |
| Deploys | logs `AuditEvent` + `AzurePolicyEvaluationDetails`, metrics `AllMetrics` |
| Identity roles required | **Monitoring Contributor** (`749f88d5-…`) + **Log Analytics Contributor** (`92aaf0da-…`) |

### Why a managed identity + role assignments?

A DINE policy needs permission to *deploy* the remediation (the diagnostic
setting) and to *wire it to the workspace*. The assignment therefore gets a
**system-assigned managed identity**, and the lab grants that identity the two
roles the built-in definition declares. Bicep creates both role assignments at
`rg-amlab` scope. See `infra/modules/policy-keyvault-diagnostics.bicep`.

### Cost

**Negligible.** Key Vault Standard has no fixed fee (per-transaction pricing,
fractions of a cent for a demo). Log Analytics ingestion of a handful of audit
events is a few KB. Delete + purge the vault when done and the running cost is
effectively $0.

### Prerequisites

| Requirement | Detail |
|---|---|
| Lab deployed | `infra/main.bicep` deployed with `deployPolicy=true` (default) so the assignment + role assignments exist |
| RBAC (deploy) | The deploying principal needs **Owner** or **User Access Administrator** to create the identity's role assignments (already true in this lab) |
| RBAC (demo) | To write a secret you need **Key Vault Secrets Officer** on the vault — the demo script grants this to the signed-in user |

---

## How It's Wired (Bicep)

`infra/main.bicep` calls the module at resource-group scope, guarded by a flag:

```bicep
@description('Deploy the Key Vault diagnostics governance policy demo.')
param deployPolicy bool = true

module policyKeyVaultDiagnostics 'modules/policy-keyvault-diagnostics.bicep' = if (deployPolicy) {
  name: 'policyKeyVaultDiagnostics'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
  }
  dependsOn: [ logAnalytics ]
}
```

The module (`infra/modules/policy-keyvault-diagnostics.bicep`) creates:

1. `Microsoft.Authorization/policyAssignments@2024-04-01` named
   **`dep-diag-kv-amlab`**, with a system-assigned identity, referencing the
   built-in definition and passing `logAnalytics = <workspace resource ID>`.
2. Two `Microsoft.Authorization/roleAssignments@2022-04-01` on the assignment's
   `identity.principalId` (Monitoring Contributor + Log Analytics Contributor),
   GUID-named so re-deploys are idempotent.

To turn the demo off, redeploy with `deployPolicy=false`.

---

## Live-Demo Timing (read before presenting)

> **The single most important thing:** the built-in policy uses
> `evaluationDelay: AfterProvisioning`. Azure **deliberately delays** the
> DeployIfNotExists existence check until **~10–30 minutes after** the Key Vault
> finishes provisioning. Immediately after you create the vault it will briefly
> show as *Compliant* (a placeholder) with **no** diagnostic setting yet — this
> is expected, not a failure.

Two ways to run the segment so nothing stalls on stage:

1. **Pre-create (recommended).** Run `scripts/demo-policy-keyvault.ps1` (or
   create the vault in the portal) **~20–30 minutes before** the segment. By the
   time you reach it, the policy will already have deployed the diagnostic
   setting — you show the finished result and the compliance/remediation blade.
2. **Live create + on-demand remediation.** Create the vault live, then open the
   assignment's **Compliance → Create remediation task**. This shortens the wait
   versus the passive scan, but still budget several minutes; keep talking
   through the concept while it runs.

Key Vault **data-plane audit events** (from writing a secret) take a further
**~5–10 minutes** to surface in `AzureDiagnostics`. Write the secret early.

---

### Step 1 — Find the assignment

Portal → **Policy** → **Assignments**. Filter to scope `rg-amlab`. You'll see
**"Deploy diagnostic settings for Key Vault to Log Analytics (lab)"** — this is
the assignment Bicep created. Open it to show the `logAnalytics` parameter
pointing at `law-amlab-*` and the **Managed identity** tab with its two roles.

### Step 2 — Create a Key Vault

Portal → **Create resource** → **Key Vault**. Put it in `rg-amlab`, Standard SKU,
**Azure role-based access control** for the permission model. Create.

### Step 3 — Watch the policy remediate

Two ways the setting gets deployed:

- **Automatically** — the DINE effect evaluates on resource create; the
  diagnostic setting typically appears within a couple of minutes.
- **On demand** — open the assignment → **Compliance** → the vault shows as
  *Non-compliant* → **Create remediation task** to force it immediately.

Confirm on the vault: **Key Vault → Monitoring → Diagnostic settings**. A
policy-created profile (sending `AuditEvent` to the workspace) should be listed.

### Step 4 — Generate an audit event

Grant yourself **Key Vault Secrets Officer** on the vault (Access control (IAM)),
then **Secrets → Generate/Import** a secret. That `SecretSet` operation is
logged as an `AuditEvent`.

### Step 5 — Verify in Log Analytics

Run the [verification query](#verification-kql). Allow ~5–10 minutes for
Key Vault audit events to reach the workspace.

---

## Setup Path B — Script (Fast Demo)

The repo ships an end-to-end driver that does Path A in ~2 minutes:

```powershell
# Windows / PowerShell
pwsh scripts/demo-policy-keyvault.ps1
```

```bash
# Linux / macOS
scripts/demo-policy-keyvault.sh
```

It: creates a uniquely-named Key Vault in `rg-amlab`, triggers an on-demand
remediation (so you don't wait on the compliance scan), polls until the
policy-created diagnostic setting exists, grants you Secrets Officer, writes a
`demo-secret`, then prints the verification KQL and portal links.

Clean up (delete **and purge** the soft-deleted vault, remove the remediation
task):

```powershell
pwsh scripts/demo-policy-keyvault.ps1 -Cleanup
```

```bash
scripts/demo-policy-keyvault.sh --cleanup
```

---

## Verification KQL

> **Environment note (FDPO / hardened subscriptions):** some subscriptions run a
> governance policy that forces Key Vault `publicNetworkAccess = Disabled`. If so,
> writing a secret from your laptop returns `Forbidden – Public network access is
> disabled`. This does **not** affect this demo's proof — the DINE policy still
> creates the diagnostic setting, and audit events still flow to Log Analytics.
> To generate a clean `SecretSet`/`Success` event live, either run the secret
> write from an allowed network path (portal "trusted services", a peered VM, or
> add your client IP under the vault's Networking blade if policy permits), or
> simply show the diagnostic setting + policy compliance as the deliverable.

Key Vault audit logs land in the **`AzureDiagnostics`** table (classic
diagnostics mode), category `AuditEvent`:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where Category == "AuditEvent"
| project TimeGenerated, Resource, OperationName, ResultType, CallerIPAddress, identity_claim_upn_s
| order by TimeGenerated desc
```

Scope it to a single demo vault by adding
`| where Resource == toupper("kv-amlab-demo-xxxxxx")`.

Confirm the policy itself deployed the setting (its own evaluation trail):

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where Category == "AzurePolicyEvaluationDetails"
| order by TimeGenerated desc
```

---

## Drift & Re-Remediation (what happens if the setting is deleted)

A great live moment: **delete the diagnostic setting by hand** and show how the
platform brings it back. The behavior is subtler than "new resource" DINE:

| Event | Behavior |
| --- | --- |
| A **new** Key Vault is created | DINE auto-deploys the setting (~10–30 min, `AfterProvisioning` delay). No remediation task needed. |
| An **existing** vault's setting is **deleted** (drift) | Deleting a *child* diagnostic setting is **not** an update to the vault, so it does **not** re-trigger DINE. The vault is flagged non-compliant on the next scan, but the setting only returns when a **remediation task** runs. |
| Nothing is done | Standard compliance scan runs **~every 24 h**; even then it only flags — it won't self-heal without a remediation task. |

### Fix it on demand (the fast path)

```powershell
# 1) Force an on-demand compliance scan so the vault is flagged NonCompliant now
az policy state trigger-scan --resource-group rg-amlab --no-wait

# 2) Confirm it flipped to NonCompliant (wait a few minutes after the scan)
az policy state list -g rg-amlab `
  --filter "PolicyAssignmentName eq 'dep-diag-kv-amlab'" `
  --query "[].{res:resourceId, state:complianceState}" -o json

# 3) Once NonCompliant, run a DEFAULT-mode remediation — deploys immediately
az policy remediation create `
  --name fix-kv-diag-$(Get-Random) `
  --resource-group rg-amlab `
  --policy-assignment dep-diag-kv-amlab
```

Verify the setting returned (the `az monitor diagnostic-settings` command is
broken by a locked CLI extension on the lab box — query ARM directly instead):

```powershell
az rest --method get --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-amlab/providers/Microsoft.KeyVault/vaults/<vault>/providers/microsoft.insights/diagnosticSettings?api-version=2021-05-01-preview"
```

### Two gotchas learned the hard way

- **Discovery mode matters.** The default `ExistingNonCompliant` mode remediates
  the *already-flagged* resource immediately. `ReEvaluateCompliance` forces a
  **full fresh scan first** and can sit in `Evaluating` for 10–30 min — only use
  it when you're unsure the compliance data is current. For the delete-and-heal
  demo, trigger a scan yourself and use the **default** mode.
- **One remediation per assignment+scope at a time.** Trying to start a second
  returns `InvalidCreateRemediationRequest`. If an earlier task is stuck, cancel
  it first, wait for `Canceled`, then create the new one:

  ```powershell
  az policy remediation cancel --name <stuck-name> -g rg-amlab
  # wait until provisioningState == Canceled, then create the new task
  ```

---

## Talking Points

- **Shift-left governance:** developers don't have to remember to turn on
  logging — the platform guarantees it. New Key Vaults are observable by default.
- **Effect spectrum:** contrast `Audit` (visibility) vs `DeployIfNotExists`
  (auto-fix). Same pattern applies to SQL, Storage, App Service, AKS, etc. — the
  Key Vault policy is one of a whole built-in family.
- **Identity, not secrets:** remediation runs as a managed identity with exactly
  two scoped roles — least privilege, no credentials.
- **Latency honesty:** the default compliance scan can take up to ~30 min; the
  demo uses an on-demand remediation task to make it snappy. Data-plane audit
  events themselves take ~5–10 min to surface in Log Analytics.
- **Self-healing vs drift:** new resources are fixed automatically, but if
  someone *deletes* the setting, DINE flags it and a **remediation task** heals
  it — governance detects and corrects configuration drift (see the
  [Drift & Re-Remediation](#drift--re-remediation-what-happens-if-the-setting-is-deleted)
  section).

---

## Cleanup Notes

- Key Vault names are **globally unique** and **soft-deleted names stay
  reserved** — the demo uses a random suffix and the cleanup path runs
  `az keyvault purge`.
- Removing the governance demo entirely: redeploy `infra/main.bicep` with
  `deployPolicy=false`, or delete the `dep-diag-kv-amlab` assignment and its two
  role assignments.

---

## Related Docs

- [Architecture](architecture.md) — where this fits in the lab topology.
- [Service Health Alerts Walkthrough](service-health-alerts-walkthrough.md) —
  another additive, low-cost governance/observability demo.
- [Troubleshooting](troubleshooting.md).
