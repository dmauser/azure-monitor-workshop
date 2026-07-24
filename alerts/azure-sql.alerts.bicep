// =============================================================================
// alerts/azure-sql.alerts.bicep
// Scope: resourceGroup
//
// Scheduled-query alert rules for the Azure SQL scenario.
// KQL source: kql/azure-sql.kql  (alert blocks [6], [7], [8])
// Thresholds: DTU > 85% / 5 min | Storage > 90% | Deadlocks > 0 / 5 min
// =============================================================================

targetScope = 'resourceGroup'

@description('Log Analytics Workspace ARM resource ID — scope for all alert queries.')
param workspaceResourceId string

@description('Azure region for alert rule resources.')
param location string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

// ---------------------------------------------------------------------------
// Alert 1: Azure SQL high DTU — avg DTU > 85% over a 5-min bin
// Source: kql/azure-sql.kql  [6] Alert: High DTU
// ---------------------------------------------------------------------------
module alertSqlDtuHigh '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-sql-dtu-high'
  params: {
    alertName: 'alert-${namePrefix}-sql-dtu-high'
    displayName: '${namePrefix} | Azure SQL | DTU > 85%'
    alertDescription: 'Fires when avg DTU exceeds 85% in the last 5-min window. Source: kql/azure-sql.kql [6].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _dtuThreshold = 85.0;
AzureSQL_CL
| where TimeGenerated >= ago(5m)
| summarize AvgDtu = avg(DtuPercent)
    by bin(TimeGenerated, 5m), Resource, DatabaseName, Environment
| where AvgDtu > _dtuThreshold
| project TimeGenerated, Resource, DatabaseName, Environment, AvgDtu
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 2: Azure SQL storage near capacity — max storage > 90%
// Source: kql/azure-sql.kql  [7] Alert: Storage near capacity
// ---------------------------------------------------------------------------
module alertSqlStorageHigh '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-sql-storage-high'
  params: {
    alertName: 'alert-${namePrefix}-sql-storage-high'
    displayName: '${namePrefix} | Azure SQL | Storage > 90%'
    alertDescription: 'Fires when any database storage exceeds 90% in the last 5-min window. Source: kql/azure-sql.kql [7].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
let _storageThreshold = 90.0;
AzureSQL_CL
| where TimeGenerated >= ago(5m)
| summarize MaxStoragePct = max(StoragePercent)
    by bin(TimeGenerated, 5m), Resource, DatabaseName, Environment
| where MaxStoragePct > _storageThreshold
| project TimeGenerated, Resource, DatabaseName, Environment, MaxStoragePct
'''
  }
}

// ---------------------------------------------------------------------------
// Alert 3: Azure SQL deadlocks — any deadlock in last 5-min window
// Source: kql/azure-sql.kql  [8] Alert: Deadlocks detected
// ---------------------------------------------------------------------------
module alertSqlDeadlocks '../infra/modules/scheduled-query-alert.bicep' = {
  name: 'deploy-alert-sql-deadlocks'
  params: {
    alertName: 'alert-${namePrefix}-sql-deadlocks'
    displayName: '${namePrefix} | Azure SQL | Deadlocks detected'
    alertDescription: 'Fires when any deadlock is detected in the last 5-min window. Source: kql/azure-sql.kql [8].'
    severity: 2
    workspaceResourceId: workspaceResourceId
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    threshold: 0
    operator: 'GreaterThan'
    timeAggregation: 'Count'
    location: location
    query: '''
AzureSQL_CL
| where TimeGenerated >= ago(5m)
| summarize TotalDeadlocks = sum(DeadlockCount)
    by bin(TimeGenerated, 5m), Resource, DatabaseName, Environment
| where TotalDeadlocks > 0
| project TimeGenerated, Resource, DatabaseName, Environment, TotalDeadlocks
'''
  }
}

@description('Alert rule IDs for this scenario.')
output alertIds array = [
  alertSqlDtuHigh.outputs.alertId
  alertSqlStorageHigh.outputs.alertId
  alertSqlDeadlocks.outputs.alertId
]

@description('Alert rule names for this scenario.')
output alertNames array = [
  alertSqlDtuHigh.outputs.alertName
  alertSqlStorageHigh.outputs.alertName
  alertSqlDeadlocks.outputs.alertName
]
