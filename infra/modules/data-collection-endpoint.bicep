// =============================================================================
// infra/modules/data-collection-endpoint.bicep
// Scope: resourceGroup
//
// Provisions a Data Collection Endpoint (DCE) for the Logs Ingestion API.
// API: Microsoft.Insights/dataCollectionEndpoints@2023-03-11
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.insights/datacollectionendpoints?pivots=deployment-language-bicep
//      Note: 2023-09-01 does NOT exist for this resource type;
//            latest stable GA is 2023-03-11 (next: 2024-03-11).
// =============================================================================

@description('DCE resource name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: name
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// TODO(tank): DCRs (Microsoft.Insights/dataCollectionRules@2023-03-11) reference this DCE.
//             Pass dceId as input to modules/data-collection-rule.bicep.

@description('Logs Ingestion endpoint URL (https://<id>.<region>.ingest.monitor.azure.com)')
output logsIngestionEndpoint string = dce.properties.logsIngestion.endpoint

@description('DCE ARM resource ID')
output dceId string = dce.id
