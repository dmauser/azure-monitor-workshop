// =============================================================================
// infra/modules/role-assignment.bicep
// Scope: resourceGroup
//
// Assigns a single RBAC role on one DCR (referenced as an existing resource).
// Called in a loop from main.bicep — one invocation per scenario DCR.
//
// Default role: Monitoring Metrics Publisher
//   ID: 3913510d-42f4-4e42-8a64-420c390055eb
//   Validated: https://learn.microsoft.com/en-us/azure/built-in-roles/monitor
//
// API: Microsoft.Authorization/roleAssignments@2022-04-01
//      Validated: https://learn.microsoft.com/en-us/azure/templates/
//                 microsoft.authorization/roleassignments?pivots=deployment-language-bicep
// =============================================================================

@description('Name of the existing DCR in this resource group.')
param dcrName string

@description('AAD principal ID (object ID) to grant the role.')
param principalId string

@description('Role definition ID. Defaults to Monitoring Metrics Publisher.')
param roleDefinitionId string = '3913510d-42f4-4e42-8a64-420c390055eb'

@description('AAD principal type. Defaults to User (signed-in user OID at deploy time).')
@allowed(['Device', 'ForeignGroup', 'Group', 'ServicePrincipal', 'User'])
param principalType string = 'User'

// Reference the existing DCR so the assignment can be scoped to it
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: dcrName
}

// Assignment name: stable GUID derived from DCR ID + principal + role (idempotent)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, principalId, roleDefinitionId)
  scope: dcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
