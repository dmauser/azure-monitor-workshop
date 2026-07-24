// =============================================================================
// infra/modules/log-analytics.bicep
// Scope: resourceGroup
//
// Provisions a Log Analytics Workspace (PerGB2018, 30-day retention).
// API: Microsoft.OperationalInsights/workspaces@2023-09-01
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.operationalinsights/workspaces?pivots=deployment-language-bicep
// =============================================================================

@description('Workspace name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// TODO(tank): Custom tables (Microsoft.OperationalInsights/workspaces/tables@2023-09-01)
//             are child resources of this workspace.  Author them in modules/custom-table.bicep
//             and call from main.bicep passing workspaceId as input.

@description('ARM resource ID of the workspace')
output workspaceId string = workspace.id

@description('Workspace name')
output workspaceName string = workspace.name

@description('Workspace Customer ID (used for KQL queries)')
output customerId string = workspace.properties.customerId
