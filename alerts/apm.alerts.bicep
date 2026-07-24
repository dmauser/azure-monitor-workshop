// =============================================================================
// alerts/apm.alerts.bicep
// Scope: resourceGroup
//
// Scheduled-query alert rules for the APM / Applications scenario.
// KQL source: kql/apm.kql  (alert blocks [7], [8], [9])
// Thresholds: failure rate > 1% / 5 min | P95 latency > 500 ms | error-budget burn rolling 1h > 2%
// =============================================================================

targetScope = 'resourceGroup'

@description('Log Analytics Workspace ARM resource ID — scope for all alert queries.')
param workspaceResourceId string

@description('Azure region for alert rule resources.')
param location string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

// ---------------------------------------------------------------------------
// Alert 1: APM failure rate — error rate > 1% over 5-min window
// Source: kql/apm.kql  [7] Alert: Failure rate > 1%
// ---------------------------------------------------------------------------
module alertApmFailureRate '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-apm-failure-rate'
  params: {
    alertName: 'alert-${namePrefix}-apm-failure-rate'
    displayName: '${namePrefix} | APM | Failure rate > 1%'
    alertDescription: 'Fires when request error rate exceeds 1% in the last 5 min. Source: kql/apm.kql [7].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _failRateThreshold = 1.0;
APM_CL
| where TimeGenerated >= ago(5m)
| where ItemType == "request"
| summarize
    TotalReqs  = count(),
    FailedReqs = countif(IsSuccess == false)
    by bin(TimeGenerated, 5m), Resource, Environment
| where TotalReqs > 0
| extend ErrorRatePct = FailedReqs * 100.0 / TotalReqs
| where ErrorRatePct > _failRateThreshold
| project TimeGenerated, Resource, Environment, TotalReqs, FailedReqs, ErrorRatePct
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 2: APM P95 latency SLO breach — P95 > 500 ms
// Source: kql/apm.kql  [8] Alert: P95 latency SLO breach > 500 ms
// ---------------------------------------------------------------------------
module alertApmP95Latency '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-apm-p95-latency'
  params: {
    alertName: 'alert-${namePrefix}-apm-p95-latency'
    displayName: '${namePrefix} | APM | P95 latency > 500 ms'
    alertDescription: 'Fires when P95 request latency exceeds 500 ms in the last 5 min. Source: kql/apm.kql [8].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _p95Threshold = 500.0;
APM_CL
| where TimeGenerated >= ago(5m)
| where ItemType == "request"
| summarize P95Ms = percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m), Resource, Environment
| where P95Ms > _p95Threshold
| project TimeGenerated, Resource, Environment, P95Ms
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 3: APM error-budget burn — rolling 1h failure rate > 2%
// Source: kql/apm.kql  [9] Alert: Error-budget burn rolling 1h > 2%
// WindowSize PT1H to match the 60-min lookback in the query.
// ---------------------------------------------------------------------------
module alertApmErrorBudgetBurn '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-apm-error-budget-burn'
  params: {
    alertName: 'alert-${namePrefix}-apm-error-budget-burn'
    displayName: '${namePrefix} | APM | Error-budget burn > 2% (rolling 1h)'
    alertDescription: 'Fires when rolling 1-hour error rate exceeds 2%, indicating fast error-budget consumption. Source: kql/apm.kql [9].'
    severity: 1
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT1H'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _errorBudgetThreshold = 2.0;
APM_CL
| where TimeGenerated >= ago(60m)
| where ItemType == "request"
| summarize
    TotalReqs  = count(),
    FailedReqs = countif(IsSuccess == false)
    by bin(TimeGenerated, 60m), Resource, Environment
| where TotalReqs > 0
| extend RollingErrorRatePct = FailedReqs * 100.0 / TotalReqs
| where RollingErrorRatePct > _errorBudgetThreshold
| project TimeGenerated, Resource, Environment, TotalReqs, FailedReqs, RollingErrorRatePct
'''
  }
}

@description('Alert rule IDs for this scenario.')
output alertIds array = [
  alertApmFailureRate.outputs.alertId
  alertApmP95Latency.outputs.alertId
  alertApmErrorBudgetBurn.outputs.alertId
]

@description('Alert rule names for this scenario.')
output alertNames array = [
  alertApmFailureRate.outputs.alertName
  alertApmP95Latency.outputs.alertName
  alertApmErrorBudgetBurn.outputs.alertName
]
