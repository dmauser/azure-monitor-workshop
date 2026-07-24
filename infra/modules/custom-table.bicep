// =============================================================================
// infra/modules/custom-table.bicep
// Scope: resourceGroup
//
// Provisions a single DCR-based custom Log Analytics table.
// API: Microsoft.OperationalInsights/workspaces/tables@2023-09-01
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.operationalinsights/workspaces/tables?pivots=deployment-language-bicep
// =============================================================================

@description('Log Analytics Workspace name (existing)')
param workspaceName string

@description('Custom table name, e.g. VirtualMachines_CL')
param tableName string

@description('Column definitions — array of { name: string, type: string }. TimeGenerated (datetime) must be included.')
param columns array

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: columns
    }
    plan: 'Analytics'
    retentionInDays: 30
  }
}

@description('Custom table name')
output tableName string = customTable.name
