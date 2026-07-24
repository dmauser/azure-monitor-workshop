# Demo VM: Azure Monitor Guest Metrics

> **Last updated:** 2026-07-16  
> **Scope:** Minimal-cost Ubuntu VM for live Azure Monitor guest metrics demo.  
> **Module:** `infra/modules/demo-vm.bicep`

---

## What Gets Deployed

All resources are **additive** — they do not touch the existing lab stack (workspace, DCE, scenario DCRs, custom tables, alerts).

```
rg-amlab  (existing)
├── nsg-amlab-vmguest-<uid6>      NSG, no inbound allow rules (DenyAllInBound default)
├── vnet-amlab-<uid6>             VNet 10.10.0.0/24
│   └── snet-vmguest              subnet 10.10.0.0/27 + NSG attached
├── nic-amlab-<uid6>              NIC, private IP only (no public IP)
├── vm-amlab-<uid6>               Ubuntu 22.04 LTS Gen2, Standard_B2ats_v2
│   │                             Standard_LRS 30 GB OS disk, boot diag managed
│   └── AzureMonitorLinuxAgent    AMA extension, auto-upgrade enabled
├── dcr-amlab-vmguest-<uid6>      DCR (kind Linux):
│                                   performanceCounters → InsightsMetrics + Perf
│                                   samplingFrequencyInSeconds: 60
│                                   destination: law-amlab-<uid>
└── shutdown-computevm-vm-amlab-<uid6>
                                  DevTestLab auto-shutdown, 19:00 CST daily
```

`<uid6>` = `take(uniqueString(resourceGroup().id, 'vmguest'), 6)` — deterministic per RG.

### Resource Inventory and API Versions

| Resource | Bicep type | API version |
|---|---|---|
| NSG | `Microsoft.Network/networkSecurityGroups` | `2023-09-01` |
| VNet | `Microsoft.Network/virtualNetworks` | `2023-09-01` |
| NIC | `Microsoft.Network/networkInterfaces` | `2023-09-01` |
| VM | `Microsoft.Compute/virtualMachines` | `2024-07-01` |
| VM identity | `identity.type: SystemAssigned` on VM resource | n/a (required by AMA) |
| AMA extension | `Microsoft.Compute/virtualMachines/extensions` | `2024-07-01` |
| Guest DCR | `Microsoft.Insights/dataCollectionRules` | `2023-03-11` |
| DCR Association | `Microsoft.Insights/dataCollectionRuleAssociations` | `2023-03-11` |
| Auto-shutdown | `Microsoft.DevTestLab/schedules` | `2018-09-15` |

API references:
- VM: https://learn.microsoft.com/azure/templates/microsoft.compute/2024-07-01/virtualmachines
- VM extensions: https://learn.microsoft.com/azure/templates/microsoft.compute/2024-07-01/virtualmachines/extensions
- DCR: https://learn.microsoft.com/azure/templates/microsoft.insights/2023-03-11/datacollectionrules
- Auto-shutdown: https://learn.microsoft.com/azure/templates/microsoft.devtestlab/2018-09-15/schedules
- AMA agent management: https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-manage
- DCR performance counters: https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-performance

### Guest DCR: Lean Counter Set

| Counter | Stream |
|---|---|
| `Processor(*)\% Processor Time` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |
| `Memory(*)\% Available Memory` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |
| `Memory(*)\Available MBytes Memory` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |
| `LogicalDisk(*)\% Used Space` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |
| `LogicalDisk(*)\Disk Transfers/sec` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |
| `Network(*)\Total Bytes` | `Microsoft-InsightsMetrics`, `Microsoft-Perf` |

- `Microsoft-InsightsMetrics` lands in the `InsightsMetrics` table → queryable in VM Insights.
- `Microsoft-Perf` lands in the `Perf` table → classic performance counter table.
- Platform metrics (host CPU %, network, disk I/O) are **free and automatic** — no agent needed.

> **Prerequisite:** AMA requires the VM to have a **system-assigned managed identity** (`identity.type: SystemAssigned` on the VM resource). Without it, AMA cannot obtain an IMDS token and will not download its DCR configuration. The Bicep module includes this automatically.

---

## Monthly Cost Estimate

> **Assumptions (as of 2026-07-16):** southcentralus region, Pay-As-You-Go pricing, USD.  
> Prices sourced from the Azure Pricing Calculator; confirm current rates at https://azure.microsoft.com/pricing/calculator/.

| Component | SKU / Config | Running 24×7 | With auto-shutdown (8 h/day, ~workday) |
|---|---|---|---|
| **VM compute** | Standard_B2ats_v2 (2 vCPU / 1 GiB) | ~$14/mo | ~$5/mo |
| **OS disk** | Standard_LRS 30 GB (P6-equivalent) | ~$1.20/mo | ~$1.20/mo (storage billed regardless) |
| **Boot diagnostics** | Managed (no storage account) | $0 | $0 |
| **AMA agent** | Azure Monitor Agent extension | $0 | $0 |
| **Log Analytics ingestion** | ~6 counters × 60 s, ~1 row/min | ~$0.10/mo | ~$0.04/mo |
| **Platform metrics** | Host CPU, disk, network | $0 | $0 |
| **Total estimate** | | **~$15.30/mo** | **~$6.24/mo** |

Auto-shutdown saves ~60 % on compute cost. Storage billed continuously — run teardown-vm when the VM is no longer needed.

> ⚠️ B2ats_v2 carries burstable CPU credits; sustained 100% CPU for extended periods exhausts credits and drops to baseline (~20%). This is fine for the lab demo load (brief stress runs).

---

## Deploy

### Prerequisites

- Azure CLI logged in: `az login`
- Subscription set to Your-Subscription (`az account set --subscription 00000000-0000-0000-0000-000000000000`)
- `config/lab.env` present (run `scripts/deploy.sh` or `scripts/deploy.ps1` first)
- `ssh-keygen` available (built into Windows 10+, macOS, Linux)

### Run (bash)

```bash
./scripts/deploy-vm.sh
# optional: ./scripts/deploy-vm.sh --vm-size Standard_B2ls_v2 --what-if
```

### Run (PowerShell)

```powershell
.\scripts\deploy-vm.ps1
# optional: .\scripts\deploy-vm.ps1 -VmSize Standard_B2ls_v2 -WhatIfMode
```

Both scripts:
1. Generate an ed25519 SSH key pair at `config/keys/vm-amlab-ed25519` (if absent).
2. Deploy `infra/modules/demo-vm.bicep` to `rg-amlab`.
3. Write `config/vm.env` with resource IDs and SSH key path.

---

## Teardown

Deletes **only** the VM and its dedicated resources (VM, NIC, OS disk, NSG, VNet, DCR, auto-shutdown). The main lab stack is untouched.

```bash
./scripts/teardown-vm.sh           # prompts for confirmation
./scripts/teardown-vm.sh --force   # no prompt
```

```powershell
.\scripts\teardown-vm.ps1          # prompts for confirmation
.\scripts\teardown-vm.ps1 -Force   # no prompt
```

---

## Metrics Demo Script

### 1 — Host Platform Metrics (free, immediate, no agent needed)

In the Azure portal, open **rg-amlab → vm-amlab-<uid> → Metrics**. These are available the moment the VM is running:

| Metric | Namespace | Note |
|---|---|---|
| Percentage CPU | Virtual Machine Host | Host CPU bursting (burstable SKU) |
| Network In Total | Virtual Machine Host | Bytes received |
| Network Out Total | Virtual Machine Host | Bytes sent |
| OS Disk Read Operations/sec | Virtual Machine Host | Disk IOPS |

Via CLI (replace `<VM_ID>` with value from `config/vm.env`):

```bash
# Source vm.env first
source config/vm.env

# Query last 5 minutes of Percentage CPU
az monitor metrics list \
  --resource "$VM_ID" \
  --metric "Percentage CPU" \
  --interval PT1M \
  --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
  --aggregation Average \
  -o table
```

```powershell
# PowerShell equivalent
$vmEnv = @{}; Get-Content config\vm.env | ForEach-Object { if ($_ -match '^([A-Z_]+)=(.+)$') { $vmEnv[$Matches[1]] = $Matches[2] } }
$start = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
az monitor metrics list --resource $vmEnv['VM_ID'] --metric "Percentage CPU" `
  --interval PT1M --start-time $start --aggregation Average -o table
```

---

### 2 — Generate CPU Load In-Guest

Use `az vm run-command invoke` — no SSH, no Bastion needed.

```bash
# 60-second CPU busy loop — use openssl (reliable across shells) or dd
source config/vm.env
az vm run-command invoke \
  --resource-group "rg-amlab" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts 'timeout 60 openssl speed sha256 & timeout 60 openssl speed sha256 & wait; echo done'
```

```powershell
# PowerShell equivalent
$vmEnv = @{}; Get-Content config\vm.env | ForEach-Object { if ($_ -match '^([A-Z_]+)=(.+)$') { $vmEnv[$Matches[1]] = $Matches[2] } }
az vm run-command invoke `
  --resource-group "rg-amlab" `
  --name $vmEnv['VM_NAME'] `
  --command-id RunShellScript `
  --scripts "timeout 60 dd if=/dev/urandom of=/dev/null bs=1M & timeout 60 dd if=/dev/urandom of=/dev/null bs=1M & wait; echo done"
```

Wait ~2 minutes, then check host Percentage CPU in Metrics Explorer — you should see a spike.

---

### 3 — Query Guest Data in Log Analytics

Guest data via AMA takes **3–10 minutes** to appear after the agent provisions.

Open **law-amlab-<uid> → Logs** and run:

#### Check AMA heartbeat (confirm agent is alive)

```kql
Heartbeat
| where Computer has "vm-amlab"
| summarize LastSeen = max(TimeGenerated) by Computer, OSType, Version
| order by LastSeen desc
```

#### Perf table — classic performance counter data

```kql
Perf
| where Computer has "vm-amlab"
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by bin(TimeGenerated, 1m), Computer
| order by TimeGenerated desc
| take 20
```

#### InsightsMetrics table — VM Insights guest metrics

> **Note on first-collection lag:** When AMA first initializes the `Microsoft-InsightsMetrics` stream, the `Computer`, `Namespace`, `Name`, and `Tags` fields may be empty for the first ~20–30 minutes while the VMInsights schema fully initializes. Data IS flowing (check `_ResourceId` and `Val`). The `Perf` table populates with correct field names immediately.

```kql
// Query by _ResourceId if Computer field is empty initially
InsightsMetrics
| where _ResourceId has "vm-amlab"
| where isnotempty(Name)
| summarize AvgCPU = avg(Val) by bin(TimeGenerated, 1m), Computer, Namespace, Name
| order by TimeGenerated desc
| take 20
```

```kql
// Standard query once Computer field is populated
InsightsMetrics
| where Computer has "vm-amlab"
| where Namespace == "Processor" and Name == "UtilizationPercentage"
| summarize AvgCPU = avg(Val) by bin(TimeGenerated, 1m), Computer
| order by TimeGenerated desc
| take 20
```

#### Available memory

```kql
Perf
| where Computer has "vm-amlab"
| where ObjectName == "Memory" and CounterName == "Available MBytes Memory"
| summarize AvgMemMB = avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| order by TimeGenerated desc
| take 12
```

#### Full guest counter overview (last 15 minutes)

```kql
Perf
| where Computer has "vm-amlab"
| where TimeGenerated > ago(15m)
| summarize
    AvgValue = avg(CounterValue),
    MaxValue = max(CounterValue)
    by ObjectName, CounterName, InstanceName
| order by ObjectName, CounterName
```

> **Note:** If the tables return no rows within 10 minutes of VM start, verify:
>
> 1. AMA extension provisioning state (`Provisioning succeeded`):
>    ```bash
>    source config/vm.env
>    az vm get-instance-view -g "rg-amlab" -n "$VM_NAME" \
>      --query "instanceView.extensions[?name=='AzureMonitorLinuxAgent'].{state:statuses[0].displayStatus}" \
>      -o table
>    ```
> 2. VM has a system-assigned managed identity:
>    ```bash
>    az vm show -g "rg-amlab" -n "$VM_NAME" --query "identity" -o json
>    ```
>    If `identity` is null, assign it: `az vm identity assign -g rg-amlab -n <vm-name> --identities '[system]'`
>    Then restart AMA in-guest: `az vm run-command invoke -g rg-amlab -n <vm-name> --command-id RunShellScript --scripts 'systemctl restart azuremonitoragent'`
> 3. DCR association exists: verify via Azure portal VM → Insights → Data Collection Rules.

---

## Networking Notes

- **No public IP.** Access is exclusively via `az vm run-command invoke` or Azure Serial Console.
- **NSG:** zero inbound allow rules. DenyAllInBound default blocks all ingress.
- **Egress:** default Azure allow (needed for AMA to reach Azure Monitor endpoints).
- The VNet/subnet are isolated to this module — no peering to other VNets.
