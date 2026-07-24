// =============================================================================
// alerts/app-service.alerts.bicep
// Scope: resourceGroup
//
// Scheduled-query alert rules for the App Service scenario.
// KQL source: kql/app-service.kql  (alert blocks [6] and [7])
// Thresholds: 5xx error rate > 5% / 5 min | P95 latency > 2 000 ms
// =============================================================================

targetScope = 'resourceGroup'

@description('Log Analytics Workspace ARM resource ID — scope for all alert queries.')
param workspaceResourceId string

@description('Azure region for alert rule resources.')
param location string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

// ---------------------------------------------------------------------------
// Alert 1: App Service 5xx spike — error rate > 5% over a 5-min window
// Source: kql/app-service.kql  [6] Alert: 5xx spike
// ---------------------------------------------------------------------------
module alertApp5xxHigh '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-app-5xx-high'
  params: {
    alertName: 'alert-${namePrefix}-app-5xx-high'
    displayName: '${namePrefix} | App Service | 5xx rate > 5%'
    alertDescription: 'Fires when Http5xxCount / RequestCount exceeds 5% in the last 5 min. Source: kql/app-service.kql [6].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _errorRateThreshold = 5.0;
AppService_CL
| where TimeGenerated >= ago(5m)
| summarize
    Total5xx  = sum(Http5xxCount),
    TotalReqs = sum(RequestCount)
    by bin(TimeGenerated, 5m), Resource, Environment
| where TotalReqs > 0
| extend ErrorRatePct = Total5xx * 100.0 / TotalReqs
| where ErrorRatePct > _errorRateThreshold
| project TimeGenerated, Resource, Environment, Total5xx, TotalReqs, ErrorRatePct
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 2: App Service P95 latency SLO breach — max P95 > 2 000 ms
// Source: kql/app-service.kql  [7] Alert: P95 latency SLO breach > 2 000 ms
// ---------------------------------------------------------------------------
module alertAppP95High '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-app-p95-high'
  params: {
    alertName: 'alert-${namePrefix}-app-p95-high'
    displayName: '${namePrefix} | App Service | P95 latency > 2000 ms'
    alertDescription: 'Fires when max P95 response time exceeds 2 000 ms in a 5-min bin. Source: kql/app-service.kql [7].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _p95Threshold = 2000.0;
AppService_CL
| where TimeGenerated >= ago(5m)
| summarize MaxP95Ms = max(ResponseTimeP95Ms)
    by bin(TimeGenerated, 5m), Resource, Environment
| where MaxP95Ms > _p95Threshold
| project TimeGenerated, Resource, Environment, MaxP95Ms
'''
  }
}

@description('Alert rule IDs for this scenario.')
output alertIds array = [
  alertApp5xxHigh.outputs.alertId
  alertAppP95High.outputs.alertId
]

@description('Alert rule names for this scenario.')
output alertNames array = [
  alertApp5xxHigh.outputs.alertName
  alertAppP95High.outputs.alertName
]
