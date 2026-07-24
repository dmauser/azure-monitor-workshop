// =============================================================================
// infra/modules/data-collection-rule.bicep
// Scope: resourceGroup
//
// Provisions a Data Collection Rule (DCR) that routes data from the Logs
// Ingestion API through a custom stream into a custom Log Analytics table.
// API: Microsoft.Insights/dataCollectionRules@2023-03-11
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.insights/datacollectionrules?pivots=deployment-language-bicep
// =============================================================================

@description('DCR resource name, e.g. dcr-amlab-virtualmachines-abc123')
param dcrName string

@description('Azure region')
param location string

@description('Log Analytics Workspace ARM resource ID')
param workspaceResourceId string

@description('Data Collection Endpoint ARM resource ID')
param dceId string

@description('Stream name, e.g. Custom-VirtualMachines_CL')
param streamName string

@description('Custom table name, e.g. VirtualMachines_CL')
param tableName string

@description('Column definitions — array of { name: string, type: string }')
param columns array

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  properties: {
    dataCollectionEndpointId: dceId
    streamDeclarations: {
      '${streamName}': {
        columns: columns
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'law-dest'
        }
      ]
    }
    dataFlows: [
      {
        streams: [streamName]
        destinations: ['law-dest']
        transformKql: 'source'
        outputStream: 'Custom-${tableName}'
      }
    ]
  }
}

@description('DCR immutable ID — used by generator as DCR_IMMUTABLE_ID_<SCENARIO>')
output immutableId string = dcr.properties.immutableId

@description('DCR ARM resource ID')
output dcrId string = dcr.id
