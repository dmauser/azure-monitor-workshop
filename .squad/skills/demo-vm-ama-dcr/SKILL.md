# SKILL: Single-Module VM + AMA + DCR (Linux Guest Metrics)

**Author:** Tank  
**Date:** 2026-07-16  
**Reusable in:** any RG-scoped deployment that needs a minimal Linux VM with guest metrics

---

## Problem

You need a single self-contained Bicep module that deploys a Linux VM with the Azure Monitor Agent (AMA) and a guest-metrics DCR, wired to an existing Log Analytics workspace — without a subscription-level deployment or touching any existing lab resources.

## Pattern

**Scope:** `resourceGroup`  
**Key design decisions:**
1. Derive all resource names from a `uid` param defaulting to `take(uniqueString(resourceGroup().id, '<seed>'), 6)` — stable across re-deployments, avoids collisions.
2. **System-assigned managed identity is required for AMA.** Add `identity: { type: 'SystemAssigned' }` to the VM resource. Without it, AMA extension provisions but immediately fails with IMDS MSI token errors and never downloads DCR configuration.
3. AMA extension as child resource of VM (`parent: vm`). Set `dependsOn: [amaExt]` on the DCRA so the DCR association waits for the extension to provision.
4. DCR `kind: 'Linux'` with `performanceCounters` data source and two streams: `Microsoft-InsightsMetrics` (→ InsightsMetrics table) + `Microsoft-Perf` (→ Perf table).
5. Auto-shutdown schedule name **must** be `shutdown-computevm-<vmName>` — Azure portal uses this convention for the linked experience.
6. NIC and OS disk carry `deleteOption: 'Delete'` so VM deletion removes them automatically.
7. NSG with empty `securityRules: []` — zero inbound allow rules; DenyAllInBound default applies.

## Bicep Gotchas

- **Backslash in counter specifiers:** Bicep strings treat `\` as escape. Write `'Processor(*)\\% Processor Time'` (double backslash) to get the literal `\` in the ARM JSON.
- **DCRA scope:** Use `scope: vm` on the DCRA resource — this creates the association as a child of the VM resource.
- **`kind` on DCR:** Top-level property on the resource, not inside `properties`.
- **DevTestLab schedules:** API `2018-09-15` is the latest stable GA. The `targetResourceId` is the VM's `.id`.
- **System identity + AMA:** AMA uses IMDS to obtain an MSI token for authenticating to the Azure Monitor config endpoint. Missing identity = silent collection failure (extension shows Succeeded but no data flows).

## Validated API Versions

| Resource type | API version |
|---|---|
| `Microsoft.Compute/virtualMachines` | `2024-07-01` |
| `Microsoft.Compute/virtualMachines/extensions` | `2024-07-01` |
| `Microsoft.Network/virtualNetworks` | `2023-09-01` |
| `Microsoft.Network/networkSecurityGroups` | `2023-09-01` |
| `Microsoft.Network/networkInterfaces` | `2023-09-01` |
| `Microsoft.Insights/dataCollectionRules` | `2023-03-11` |
| `Microsoft.Insights/dataCollectionRuleAssociations` | `2023-03-11` |
| `Microsoft.DevTestLab/schedules` | `2018-09-15` |

## Reference Implementation

`infra/modules/demo-vm.bicep` in this repo.
