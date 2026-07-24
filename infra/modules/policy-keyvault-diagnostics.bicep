// =============================================================================
// infra/modules/policy-keyvault-diagnostics.bicep
// Scope: resourceGroup
//
// Governance demo: assigns the built-in DeployIfNotExists (DINE) policy that
// auto-configures diagnostic settings on any Key Vault in this resource group
// to stream its logs to the lab's existing Log Analytics workspace.
//
// When a Key Vault is created (or on remediation), the policy deploys a
// diagnostic setting with:
//   logs    : AuditEvent, AzurePolicyEvaluationDetails
//   metrics : AllMetrics
//   → workspaceId = <lab Log Analytics workspace>
//
// The assignment gets a system-assigned managed identity, which the built-in
// definition requires to hold:
//   - Monitoring Contributor      749f88d5-cbae-40b8-bcfc-e573ddc772fa
//   - Log Analytics Contributor   92aaf0da-9dab-42b6-94a3-d43ce8d16293
// Both role assignments are created here at resource-group scope.
//
// Built-in definition (verified via `az policy definition show`, 2026-07-21):
//   "Deploy Diagnostic Settings for Key Vault to Log Analytics workspace"
//   bef3f64c-5290-43b7-85b0-9b254eef4c47   (mode: Indexed, effect: DINE)
//
// Validated API versions (learn.microsoft.com):
//   Microsoft.Authorization/policyAssignments  2024-04-01
//   Microsoft.Authorization/roleAssignments    2022-04-01
// =============================================================================

@description('ARM resource ID of the Log Analytics workspace to send Key Vault logs to.')
param workspaceResourceId string

@description('Azure region. Required because the policy assignment uses a managed identity.')
param location string

@description('Short prefix used to build the assignment name. Keep <= 8 chars.')
@maxLength(8)
param namePrefix string = 'amlab'

@description('Built-in policy definition ID: Deploy Diagnostic Settings for Key Vault to LAW.')
param policyDefinitionId string = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'bef3f64c-5290-43b7-85b0-9b254eef4c47')

// Roles the DINE identity must hold (sourced from the built-in definition's roleDefinitionIds)
var monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'

var assignmentName = 'dep-diag-kv-${namePrefix}'

// ---------------------------------------------------------------------------
// Policy assignment (DeployIfNotExists) with a system-assigned identity
// ---------------------------------------------------------------------------

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: assignmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Deploy diagnostic settings for Key Vault to Log Analytics (lab)'
    description: 'Auto-configures diagnostic settings on Key Vaults in this resource group to send logs to the azure-monitor-lab workspace. Demonstrates Azure Policy DeployIfNotExists governance.'
    policyDefinitionId: policyDefinitionId
    enforcementMode: 'Default'
    parameters: {
      logAnalytics: {
        value: workspaceResourceId
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Role assignments for the policy's managed identity (RG scope)
// Names are stable GUIDs → idempotent across re-deploys.
// ---------------------------------------------------------------------------

resource monitoringContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, assignmentName, monitoringContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRoleId)
    principalId: policyAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalyticsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, assignmentName, logAnalyticsContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsContributorRoleId)
    principalId: policyAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Policy assignment name')
output policyAssignmentName string = policyAssignment.name

@description('Policy assignment ARM resource ID')
output policyAssignmentId string = policyAssignment.id

@description('Principal (object) ID of the policy assignment managed identity')
output identityPrincipalId string = policyAssignment.identity.principalId
