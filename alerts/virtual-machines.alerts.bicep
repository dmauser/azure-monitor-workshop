// =============================================================================
// alerts/virtual-machines.alerts.bicep
// Scope: resourceGroup
//
// Scheduled-query alert rules for the Virtual Machines scenario.
// KQL source: kql/virtual-machines.kql  (alert blocks [5] + adapted workbook blocks)
// Thresholds: CPU > 90% / 5 min | Disk free < 10% | Heartbeat missing > 5 min
// =============================================================================

targetScope = 'resourceGroup'

@description('Log Analytics Workspace ARM resource ID — scope for all alert queries.')
param workspaceResourceId string

@description('Azure region for alert rule resources.')
param location string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

// ---------------------------------------------------------------------------
// Alert 1: VM CPU High — avg CPU > 90% over a 5-min bin
// Source: kql/virtual-machines.kql  [5] Alert: CPU > 90% sustained
// ---------------------------------------------------------------------------
module alertVmCpuHigh '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-vm-cpu-high'
  params: {
    alertName: 'alert-${namePrefix}-vm-cpu-high'
    displayName: '${namePrefix} | VM | CPU > 90%'
    alertDescription: 'Fires when any VM has avg CPU > 90% over the last 5-min bin. Source: kql/virtual-machines.kql [5].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _cpuThreshold = 90.0;
VirtualMachines_CL
| where TimeGenerated >= ago(5m)
| summarize AvgCpu = avg(CpuPercent) by bin(TimeGenerated, 5m), Resource, Environment
| where AvgCpu > _cpuThreshold
| project TimeGenerated, Resource, Environment, AvgCpu
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 2: VM Disk Low — min disk free < 10% over a 5-min bin
// Source: kql/virtual-machines.kql  [3] Workbook: Disk free % (adapted for alert)
// ---------------------------------------------------------------------------
module alertVmDiskLow '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-vm-disk-low'
  params: {
    alertName: 'alert-${namePrefix}-vm-disk-low'
    displayName: '${namePrefix} | VM | Disk free < 10%'
    alertDescription: 'Fires when any VM volume has disk free below 10% in the last 5-min bin. Source: kql/virtual-machines.kql [3] adapted.'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
VirtualMachines_CL
| where TimeGenerated >= ago(5m)
| summarize MinDiskFree = min(DiskFreePercent) by bin(TimeGenerated, 5m), Resource, DiskName, Environment
| where MinDiskFree < 10.0
| project TimeGenerated, Resource, DiskName, Environment, MinDiskFree
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 3: VM Heartbeat Missing — no row from a resource for > 5 min
// Source: kql/virtual-machines.kql  [4] Workbook: Heartbeat / last-seen (adapted)
// WindowSize PT1H so the query can examine the full 1-h lookback for last-seen.
// ---------------------------------------------------------------------------
module alertVmHeartbeatMissing '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-vm-heartbeat-missing'
  params: {
    alertName: 'alert-${namePrefix}-vm-heartbeat-missing'
    displayName: '${namePrefix} | VM | Heartbeat missing > 5 min'
    alertDescription: 'Fires when any VM has not sent data for more than 5 minutes within the last hour. Source: kql/virtual-machines.kql [4] adapted.'
    severity: 1
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT1H'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
VirtualMachines_CL
| where TimeGenerated >= ago(1h)
| summarize LastSeen = max(TimeGenerated) by Resource, Environment, Region
| extend MinutesSilent = datetime_diff('minute', now(), LastSeen)
| where MinutesSilent > 5
| project Resource, Environment, Region, LastSeen, MinutesSilent
'''
  }
}

@description('Alert rule IDs for this scenario.')
output alertIds array = [
  alertVmCpuHigh.outputs.alertId
  alertVmDiskLow.outputs.alertId
  alertVmHeartbeatMissing.outputs.alertId
]

@description('Alert rule names for this scenario.')
output alertNames array = [
  alertVmCpuHigh.outputs.alertName
  alertVmDiskLow.outputs.alertName
  alertVmHeartbeatMissing.outputs.alertName
]
