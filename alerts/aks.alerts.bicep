// =============================================================================
// alerts/aks.alerts.bicep
// Scope: resourceGroup
//
// Scheduled-query alert rules for the AKS / Containers scenario.
// KQL source: kql/aks.kql  (alert blocks [7] and [8])
// Thresholds: CrashLoopBackOff any pod in 5 min | Node NotReady any node in 5 min
// =============================================================================

targetScope = 'resourceGroup'

@description('Log Analytics Workspace ARM resource ID — scope for all alert queries.')
param workspaceResourceId string

@description('Azure region for alert rule resources.')
param location string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

// ---------------------------------------------------------------------------
// Alert 1: AKS CrashLoopBackOff — any pod in last 5-min window
// Source: kql/aks.kql  [7] Alert: CrashLoopBackOff
// ---------------------------------------------------------------------------
module alertAksCrashLoop '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-aks-crashloop'
  params: {
    alertName: 'alert-${namePrefix}-aks-crashloop'
    displayName: '${namePrefix} | AKS | CrashLoopBackOff detected'
    alertDescription: 'Fires when any pod reports CrashLoopBackOff in the last 5-min window. Source: kql/aks.kql [7].'
    severity: 1
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
AKS_CL
| where TimeGenerated >= ago(5m)
| where PodReason == "CrashLoopBackOff"
| summarize
    CrashCount  = count(),
    MaxRestarts = max(PodRestartCount)
    by bin(TimeGenerated, 5m), Resource, Namespace, PodName, Environment
| project TimeGenerated, Resource, Namespace, PodName, Environment, CrashCount, MaxRestarts
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 2: AKS Node NotReady — any node in last 5-min window
// Source: kql/aks.kql  [8] Alert: Node NotReady detected
// ---------------------------------------------------------------------------
module alertAksNodeNotReady '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-aks-node-notready'
  params: {
    alertName: 'alert-${namePrefix}-aks-node-notready'
    displayName: '${namePrefix} | AKS | Node NotReady detected'
    alertDescription: 'Fires when any node enters NotReady state in the last 5-min window. Source: kql/aks.kql [8].'
    severity: 1
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
AKS_CL
| where TimeGenerated >= ago(5m)
| where NodeStatus == "NotReady"
| summarize NotReadyCount = count()
    by bin(TimeGenerated, 5m), Resource, NodeName, Environment
| project TimeGenerated, Resource, NodeName, Environment, NotReadyCount
'''
  }
}

@description('Alert rule IDs for this scenario.')
output alertIds array = [
  alertAksCrashLoop.outputs.alertId
  alertAksNodeNotReady.outputs.alertId
]

@description('Alert rule names for this scenario.')
output alertNames array = [
  alertAksCrashLoop.outputs.alertName
  alertAksNodeNotReady.outputs.alertName
]
