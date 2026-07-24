// =============================================================================
// infra/modules/workbook.bicep
// Scope: resourceGroup
//
// Provisions a shared Azure Monitor Workbook linked to a Log Analytics Workspace.
// API: Microsoft.Insights/workbooks@2023-06-01
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.insights/2023-06-01/workbooks
// =============================================================================

@description('Workbook display name shown in the Azure portal.')
param displayName string

@description('Workbook content as a serialized JSON string (loadTextContent output).')
param serializedData string

@description('Log Analytics Workspace ARM resource ID used as the workbook source.')
param sourceId string

@description('Azure region for the workbook resource.')
param location string

// Deterministic GUID derived from the display name — stable across re-deployments.
var workbookName = guid(displayName)

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookName
  location: location
  kind: 'shared'
  properties: {
    displayName: displayName
    serializedData: serializedData
    sourceId: sourceId
    category: 'workbook'
    version: 'Notebook/1.0'
  }
}

@description('Workbook ARM resource ID.')
output workbookId string = workbook.id

@description('Workbook display name.')
output workbookDisplayName string = workbook.properties.displayName
