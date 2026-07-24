// =============================================================================
// infra/modules/resource-group.bicep
// Scope: subscription
//
// Creates the lab resource group.
// API: Microsoft.Resources/resourceGroups@2022-09-01
// =============================================================================

targetScope = 'subscription'

@description('Resource group name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: name
  location: location
  tags: tags
}

output name string = rg.name
output id string = rg.id
