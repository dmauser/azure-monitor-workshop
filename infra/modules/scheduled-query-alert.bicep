// =============================================================================
// infra/modules/scheduled-query-alert.bicep
// Scope: resourceGroup
//
// Provisions a Scheduled Query Rule (log alert) in Azure Monitor.
// API: Microsoft.Insights/scheduledQueryRules@2022-06-15
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.insights/2022-06-15/scheduledqueryrules
// =============================================================================

@description('Alert rule resource name. Must not contain #<>%&:?/{}*.')
param alertName string

@description('Human-readable display name shown in the Azure portal.')
param displayName string = alertName

@description('Alert description shown in the Azure Monitor portal.')
param alertDescription string = ''

@description('Alert severity: 0=Critical 1=Error 2=Warning 3=Informational 4=Verbose.')
@minValue(0)
@maxValue(4)
param severity int

@description('Log Analytics Workspace ARM resource ID — used as the query scope.')
param workspaceResourceId string

@description('KQL query that returns rows when the alert condition is met.')
param query string

@description('Evaluation frequency in ISO 8601 duration format, e.g. PT5M.')
param evaluationFrequency string = 'PT5M'

@description('Query lookback window in ISO 8601 duration format, e.g. PT5M.')
param windowSize string = 'PT5M'

@description('Result-count threshold. Alert fires when count {operator} threshold.')
param threshold int = 0

@description('Comparison operator applied to the aggregated result count.')
@allowed(['Equals', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual'])
param operator string = 'GreaterThan'

@description('Aggregation type for the criteria measure.')
@allowed(['Count', 'Average', 'Maximum', 'Minimum', 'Total'])
param timeAggregation string = 'Count'

@description('Whether this alert rule is enabled.')
param enabled bool = true

@description('Azure region for the alert rule resource.')
param location string

resource alertRule 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: alertName
  location: location
  properties: {
    displayName: displayName
    description: alertDescription
    severity: severity
    enabled: enabled
    scopes: [workspaceResourceId]
    autoMitigate: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: query
          timeAggregation: timeAggregation
          operator: operator
          threshold: threshold
        }
      ]
    }
  }
}

@description('Alert rule ARM resource ID.')
output alertId string = alertRule.id

@description('Alert rule resource name.')
output alertName string = alertRule.name
