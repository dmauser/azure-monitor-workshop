// =============================================================================
// infra/main.bicep
// Scope: subscription
//
// Entry point for the azure-monitor-workshop infrastructure.
// Provisions:
//   - Resource Group
//   - Log Analytics Workspace
//   - Data Collection Endpoint (DCE)
//
// TODO(tank): custom-table, data-collection-rule, workbook, scheduled-query-alert modules
// TODO(trinity): role assignments (Monitor Metrics Publisher) once Tank's DCR outputs are wired
//
// Validated API versions (learn.microsoft.com, 2026-07-15):
//   Microsoft.OperationalInsights/workspaces      2023-09-01
//   Microsoft.Insights/dataCollectionEndpoints    2023-03-11
//   Microsoft.Insights/dataCollectionRules        2023-03-11  (Tank's module)
//   Microsoft.OperationalInsights/workspaces/tables 2023-09-01 (Tank's module)
// =============================================================================

targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources. Defaults to southcentralus.')
param location string = 'southcentralus'

@description('Short prefix used to build all resource names. Keep ≤ 8 chars.')
@maxLength(8)
param namePrefix string = 'amlab'

@description('AAD principal ID to grant Monitoring Metrics Publisher on each DCR. Leave empty to skip role assignment.')
param principalId string = ''

@description('Ordered list of scenario short-keys. Controls which DCRs and tables are created.')
#disable-next-line no-unused-params
param scenarios array = [
  'virtualmachines'
  'appservice'
  'aks'
  'azuresql'
  'apm'
]

@description('Deploy Azure Monitor Workbooks for all 6 scenarios. Set false to skip.')
param deployWorkbooks bool = true

@description('Deploy Scheduled Query Alert rules for all 5 scenarios. Set false to skip.')
param deployAlerts bool = true

@description('Deploy the Azure Policy governance demo (DeployIfNotExists diagnostic settings for Key Vault → Log Analytics). Set false to skip.')
param deployPolicy bool = true

// ---------------------------------------------------------------------------
// Naming — deterministic, stable across re-deployments
// ---------------------------------------------------------------------------

// 6-char hex suffix derived from subscription ID + prefix (idempotent)
var uniqueSuffix = take(uniqueString(subscription().id, namePrefix), 6)

var rgName        = 'rg-${namePrefix}'
var workspaceName = 'law-${namePrefix}-${uniqueSuffix}'
var dceName       = 'dce-${namePrefix}-${uniqueSuffix}'

var commonTags = {
  project: 'azure-monitor-workshop'
  environment: 'lab'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------

module rgModule './modules/resource-group.bicep' = {
  name: 'deploy-rg'
  params: {
    name: rgName
    location: location
    tags: commonTags
  }
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'deploy-law'
  scope: resourceGroup(rgName)
  dependsOn: [rgModule]
  params: {
    name: workspaceName
    location: location
    tags: commonTags
  }
}

// ---------------------------------------------------------------------------
// Data Collection Endpoint
// ---------------------------------------------------------------------------

module dce './modules/data-collection-endpoint.bicep' = {
  name: 'deploy-dce'
  scope: resourceGroup(rgName)
  dependsOn: [rgModule]
  params: {
    name: dceName
    location: location
    tags: commonTags
  }
}

// ---------------------------------------------------------------------------
// Scenario configuration — column schemas (source of truth: mouse-kql-schema.md)
// Type mapping: bool→boolean; int/long/real/string/datetime pass through as-is.
// ---------------------------------------------------------------------------

var scenarioConfigs = [
  {
    key: 'virtualmachines'
    tableName: 'VirtualMachines_CL'
    streamName: 'Custom-VirtualMachines_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Resource', type: 'string' }
      { name: 'ResourceId', type: 'string' }
      { name: 'Environment', type: 'string' }
      { name: 'Region', type: 'string' }
      { name: 'OSType', type: 'string' }
      { name: 'CpuPercent', type: 'real' }
      { name: 'MemoryAvailableMB', type: 'real' }
      { name: 'MemoryTotalMB', type: 'real' }
      { name: 'DiskName', type: 'string' }
      { name: 'DiskFreePercent', type: 'real' }
      { name: 'NetworkInBytes', type: 'long' }
      { name: 'NetworkOutBytes', type: 'long' }
    ]
  }
  {
    key: 'appservice'
    tableName: 'AppService_CL'
    streamName: 'Custom-AppService_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Resource', type: 'string' }
      { name: 'ResourceId', type: 'string' }
      { name: 'Environment', type: 'string' }
      { name: 'Region', type: 'string' }
      { name: 'AppName', type: 'string' }
      { name: 'RequestCount', type: 'long' }
      { name: 'ResponseTimeMs', type: 'real' }
      { name: 'ResponseTimeP95Ms', type: 'real' }
      { name: 'Http2xxCount', type: 'long' }
      { name: 'Http4xxCount', type: 'long' }
      { name: 'Http5xxCount', type: 'long' }
      { name: 'RestartCount', type: 'int' }
      { name: 'PlanCpuPercent', type: 'real' }
      { name: 'PlanMemoryPercent', type: 'real' }
    ]
  }
  {
    key: 'aks'
    tableName: 'AKS_CL'
    streamName: 'Custom-AKS_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Resource', type: 'string' }
      { name: 'ResourceId', type: 'string' }
      { name: 'Environment', type: 'string' }
      { name: 'Region', type: 'string' }
      { name: 'Namespace', type: 'string' }
      { name: 'NodeName', type: 'string' }
      { name: 'PodName', type: 'string' }
      { name: 'ContainerName', type: 'string' }
      { name: 'NodeCpuPercent', type: 'real' }
      { name: 'NodeMemoryPercent', type: 'real' }
      { name: 'PodCpuPercent', type: 'real' }
      { name: 'PodMemoryPercent', type: 'real' }
      { name: 'PodRestartCount', type: 'int' }
      { name: 'PodPhase', type: 'string' }
      { name: 'PodReason', type: 'string' }
      { name: 'NodeStatus', type: 'string' }
      { name: 'PVName', type: 'string' }
      { name: 'PVUsagePercent', type: 'real' }
      { name: 'HpaName', type: 'string' }
      { name: 'HpaCurrentReplicas', type: 'int' }
      { name: 'HpaMaxReplicas', type: 'int' }
    ]
  }
  {
    key: 'azuresql'
    tableName: 'AzureSQL_CL'
    streamName: 'Custom-AzureSQL_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Resource', type: 'string' }
      { name: 'ResourceId', type: 'string' }
      { name: 'Environment', type: 'string' }
      { name: 'Region', type: 'string' }
      { name: 'DatabaseName', type: 'string' }
      { name: 'DtuPercent', type: 'real' }
      { name: 'CpuPercent', type: 'real' }
      { name: 'WorkerPercent', type: 'real' }
      { name: 'ActiveConnections', type: 'int' }
      { name: 'FailedConnections', type: 'int' }
      { name: 'DeadlockCount', type: 'int' }
      { name: 'StoragePercent', type: 'real' }
      { name: 'StorageUsedMB', type: 'long' }
      { name: 'StorageLimitMB', type: 'long' }
      { name: 'QueryDurationMs', type: 'real' }
      { name: 'QueryDurationP95Ms', type: 'real' }
    ]
  }
  {
    key: 'apm'
    tableName: 'APM_CL'
    streamName: 'Custom-APM_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Resource', type: 'string' }
      { name: 'ResourceId', type: 'string' }
      { name: 'Environment', type: 'string' }
      { name: 'Region', type: 'string' }
      { name: 'ItemType', type: 'string' }
      { name: 'OperationName', type: 'string' }
      { name: 'DurationMs', type: 'real' }
      { name: 'IsSuccess', type: 'boolean' }
      { name: 'ExceptionType', type: 'string' }
      { name: 'ExceptionMessage', type: 'string' }
      { name: 'DependencyType', type: 'string' }
      { name: 'DependencyTarget', type: 'string' }
      { name: 'DependencySuccess', type: 'boolean' }
      { name: 'DependencyDurationMs', type: 'real' }
      { name: 'SeverityLevel', type: 'int' }
      { name: 'TraceId', type: 'string' }
      { name: 'SpanId', type: 'string' }
    ]
  }
]

// ---------------------------------------------------------------------------
// Custom Tables — one per scenario
// ---------------------------------------------------------------------------

module customTables './modules/custom-table.bicep' = [for scenario in scenarioConfigs: {
  name: 'deploy-table-${scenario.key}'
  scope: resourceGroup(rgName)
  dependsOn: [logAnalytics]
  params: {
    workspaceName: workspaceName
    tableName: scenario.tableName
    columns: scenario.columns
  }
}]

// ---------------------------------------------------------------------------
// Data Collection Rules — one per scenario
// ---------------------------------------------------------------------------

module dcrs './modules/data-collection-rule.bicep' = [for (scenario, i) in scenarioConfigs: {
  name: 'deploy-dcr-${scenario.key}'
  scope: resourceGroup(rgName)
  dependsOn: [customTables]
  params: {
    dcrName: 'dcr-${namePrefix}-${scenario.key}-${uniqueSuffix}'
    location: location
    workspaceResourceId: logAnalytics.outputs.workspaceId
    dceId: dce.outputs.dceId
    streamName: scenario.streamName
    tableName: scenario.tableName
    columns: scenario.columns
  }
}]

// ---------------------------------------------------------------------------
// Azure Monitor Workbooks — one per scenario + overview
// ---------------------------------------------------------------------------
// loadTextContent paths are relative to infra/main.bicep:
//   ../workbooks/<name>.workbook.json → workbooks/<name>.workbook.json at repo root

var workbookConfigs = [
  {
    key: 'overview'
    displayName: 'Azure Monitor Lab — Overview'
    serializedData: loadTextContent('../workbooks/overview.workbook.json')
  }
  {
    key: 'virtual-machines'
    displayName: 'Azure Monitor Lab — Virtual Machines'
    serializedData: loadTextContent('../workbooks/virtual-machines.workbook.json')
  }
  {
    key: 'app-service'
    displayName: 'Azure Monitor Lab — App Service'
    serializedData: loadTextContent('../workbooks/app-service.workbook.json')
  }
  {
    key: 'aks'
    displayName: 'Azure Monitor Lab — AKS'
    serializedData: loadTextContent('../workbooks/aks.workbook.json')
  }
  {
    key: 'azure-sql'
    displayName: 'Azure Monitor Lab — Azure SQL'
    serializedData: loadTextContent('../workbooks/azure-sql.workbook.json')
  }
  {
    key: 'apm'
    displayName: 'Azure Monitor Lab — APM'
    serializedData: loadTextContent('../workbooks/apm.workbook.json')
  }
]

module workbooks './modules/workbook.bicep' = [for wb in workbookConfigs: if (deployWorkbooks) {
  name: 'deploy-workbook-${wb.key}'
  scope: resourceGroup(rgName)
  params: {
    displayName: wb.displayName
    serializedData: wb.serializedData
    sourceId: logAnalytics.outputs.workspaceId
    location: location
  }
}]

// ---------------------------------------------------------------------------
// Scheduled-Query Alert Rules — one module call per scenario
// ---------------------------------------------------------------------------
// Alert Bicep files are at repo root alerts/; paths relative to infra/main.bicep
// are ../alerts/<name>.alerts.bicep.

module alertsVm '../alerts/virtual-machines.alerts.bicep' = if (deployAlerts) {
  name: 'deploy-alerts-virtualmachines'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

module alertsApp '../alerts/app-service.alerts.bicep' = if (deployAlerts) {
  name: 'deploy-alerts-appservice'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

module alertsAks '../alerts/aks.alerts.bicep' = if (deployAlerts) {
  name: 'deploy-alerts-aks'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

module alertsSql '../alerts/azure-sql.alerts.bicep' = if (deployAlerts) {
  name: 'deploy-alerts-azuresql'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

module alertsApm '../alerts/apm.alerts.bicep' = if (deployAlerts) {
  name: 'deploy-alerts-apm'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

// ---------------------------------------------------------------------------
// Azure Policy governance demo — DeployIfNotExists diagnostic settings
// Assigns the built-in "Deploy Diagnostic Settings for Key Vault to Log
// Analytics workspace" policy at the resource-group scope. Any Key Vault
// created in rg-amlab is auto-configured to stream its logs to the lab LAW.
// ---------------------------------------------------------------------------

module policyKeyVaultDiagnostics './modules/policy-keyvault-diagnostics.bicep' = if (deployPolicy) {
  name: 'deploy-policy-kv-diagnostics'
  scope: resourceGroup(rgName)
  params: {
    workspaceResourceId: logAnalytics.outputs.workspaceId
    location: location
    namePrefix: namePrefix
  }
}

// ---------------------------------------------------------------------------
// Role Assignments — Monitoring Metrics Publisher on each DCR
// Skipped when principalId is empty (CI / no-auth runs).
// ---------------------------------------------------------------------------

module roleAssignments './modules/role-assignment.bicep' = [for (scenario, i) in scenarioConfigs: if (!empty(principalId)) {
  name: 'deploy-role-${scenario.key}'
  scope: resourceGroup(rgName)
  dependsOn: [dcrs]
  params: {
    dcrName: 'dcr-${namePrefix}-${scenario.key}-${uniqueSuffix}'
    principalId: principalId
  }
}]

// ---------------------------------------------------------------------------
// Lab Environment Outputs — collected through outputs.bicep module
// ---------------------------------------------------------------------------

module labOutputs './modules/outputs.bicep' = {
  name: 'collect-lab-env-outputs'
  dependsOn: [dcrs]
  params: {
    inLocation: location
    inResourceGroupName: rgModule.outputs.name
    inWorkspaceName: logAnalytics.outputs.workspaceName
    inWorkspaceCustomerId: logAnalytics.outputs.customerId
    inWorkspaceResourceId: logAnalytics.outputs.workspaceId
    inDceLogsIngestionEndpoint: dce.outputs.logsIngestionEndpoint
    inDcrImmutableIdVirtualMachines: dcrs[0].outputs.immutableId
    inDcrImmutableIdAppService: dcrs[1].outputs.immutableId
    inDcrImmutableIdAks: dcrs[2].outputs.immutableId
    inDcrImmutableIdAzureSql: dcrs[3].outputs.immutableId
    inDcrImmutableIdApm: dcrs[4].outputs.immutableId
  }
}

// ---------------------------------------------------------------------------
// Top-level outputs — read by `az deployment sub show` to populate lab.env
// ---------------------------------------------------------------------------

// Base infrastructure
@description('Deployment location → LAB_LOCATION')
output location string = labOutputs.outputs.location

@description('Resource group name → LAB_RESOURCE_GROUP')
output resourceGroupName string = labOutputs.outputs.resourceGroupName

@description('Log Analytics Workspace name → LAW_NAME')
output workspaceName string = labOutputs.outputs.workspaceName

@description('Workspace customer ID (GUID for KQL) → LAW_ID')
output workspaceCustomerId string = labOutputs.outputs.workspaceCustomerId

@description('Workspace ARM resource ID → LAW_RESOURCE_ID')
output workspaceResourceId string = labOutputs.outputs.workspaceResourceId

@description('DCE Logs Ingestion endpoint URL → DCE_LOGS_INGESTION_ENDPOINT')
output dceLogsIngestionEndpoint string = labOutputs.outputs.dceLogsIngestionEndpoint

// Per-scenario DCR immutable IDs → DCR_IMMUTABLE_ID_<UPPER_SNAKE>
@description('DCR immutable ID → DCR_IMMUTABLE_ID_VIRTUAL_MACHINES')
output dcrImmutableIdVirtualMachines string = labOutputs.outputs.dcrImmutableIdVirtualMachines

@description('DCR immutable ID → DCR_IMMUTABLE_ID_APP_SERVICE')
output dcrImmutableIdAppService string = labOutputs.outputs.dcrImmutableIdAppService

@description('DCR immutable ID → DCR_IMMUTABLE_ID_AKS')
output dcrImmutableIdAks string = labOutputs.outputs.dcrImmutableIdAks

@description('DCR immutable ID → DCR_IMMUTABLE_ID_AZURE_SQL')
output dcrImmutableIdAzureSql string = labOutputs.outputs.dcrImmutableIdAzureSql

@description('DCR immutable ID → DCR_IMMUTABLE_ID_APM')
output dcrImmutableIdApm string = labOutputs.outputs.dcrImmutableIdApm

// Per-scenario stream names → STREAM_<UPPER_SNAKE>
@description('Stream name → STREAM_VIRTUAL_MACHINES')
output streamVirtualMachines string = labOutputs.outputs.streamVirtualMachines

@description('Stream name → STREAM_APP_SERVICE')
output streamAppService string = labOutputs.outputs.streamAppService

@description('Stream name → STREAM_AKS')
output streamAks string = labOutputs.outputs.streamAks

@description('Stream name → STREAM_AZURE_SQL')
output streamAzureSql string = labOutputs.outputs.streamAzureSql

@description('Stream name → STREAM_APM')
output streamApm string = labOutputs.outputs.streamApm

// Per-scenario table names → TABLE_<UPPER_SNAKE>
@description('Table name → TABLE_VIRTUAL_MACHINES')
output tableVirtualMachines string = labOutputs.outputs.tableVirtualMachines

@description('Table name → TABLE_APP_SERVICE')
output tableAppService string = labOutputs.outputs.tableAppService

@description('Table name → TABLE_AKS')
output tableAks string = labOutputs.outputs.tableAks

@description('Table name → TABLE_AZURE_SQL')
output tableAzureSql string = labOutputs.outputs.tableAzureSql

@description('Table name → TABLE_APM')
output tableApm string = labOutputs.outputs.tableApm

// Convenience aggregate — deploy script can also iterate this array
@description('Per-scenario DCR data: [{scenario, immutableId, dcrId, streamName, tableName}]')
output dcrOutputs array = [for (scenario, i) in scenarioConfigs: {
  scenario: scenario.key
  immutableId: dcrs[i].outputs.immutableId
  dcrId: dcrs[i].outputs.dcrId
  streamName: scenario.streamName
  tableName: scenario.tableName
}]

// Internal
@description('DCE ARM resource ID (internal)')
output dceId string = dce.outputs.dceId

// Governance demo
@description('Key Vault diagnostics policy assignment name (empty when deployPolicy=false) → POLICY_KV_DIAG_ASSIGNMENT')
output policyKeyVaultDiagnosticsAssignmentName string = deployPolicy ? (policyKeyVaultDiagnostics.?outputs.policyAssignmentName ?? '') : ''

@description('Key Vault diagnostics policy assignment ARM ID (empty when deployPolicy=false)')
output policyKeyVaultDiagnosticsAssignmentId string = deployPolicy ? (policyKeyVaultDiagnostics.?outputs.policyAssignmentId ?? '') : ''
