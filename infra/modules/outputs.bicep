// =============================================================================
// infra/modules/outputs.bicep
// Scope: subscription (pass-through — no resources)
//
// Canonical lab.env contract module. Receives all deployment data as params
// and re-emits them as individually named outputs. This is the single source
// of truth for the variable names that scripts/deploy writes to config/lab.env.
//
// Output → lab.env mapping (deploy script reads via `az deployment sub show`):
//   location                      → LAB_LOCATION
//   resourceGroupName             → LAB_RESOURCE_GROUP
//   workspaceName                 → LAW_NAME
//   workspaceCustomerId           → LAW_ID          (workspace GUID for KQL)
//   workspaceResourceId           → LAW_RESOURCE_ID (ARM resource ID)
//   dceLogsIngestionEndpoint      → DCE_LOGS_INGESTION_ENDPOINT
//   dcrImmutableIdVirtualMachines → DCR_IMMUTABLE_ID_VIRTUAL_MACHINES
//   dcrImmutableIdAppService      → DCR_IMMUTABLE_ID_APP_SERVICE
//   dcrImmutableIdAks             → DCR_IMMUTABLE_ID_AKS
//   dcrImmutableIdAzureSql        → DCR_IMMUTABLE_ID_AZURE_SQL
//   dcrImmutableIdApm             → DCR_IMMUTABLE_ID_APM
//   streamVirtualMachines         → STREAM_VIRTUAL_MACHINES
//   streamAppService              → STREAM_APP_SERVICE
//   streamAks                     → STREAM_AKS
//   streamAzureSql                → STREAM_AZURE_SQL
//   streamApm                     → STREAM_APM
//   tableVirtualMachines          → TABLE_VIRTUAL_MACHINES
//   tableAppService               → TABLE_APP_SERVICE
//   tableAks                      → TABLE_AKS
//   tableAzureSql                 → TABLE_AZURE_SQL
//   tableApm                      → TABLE_APM
// =============================================================================

targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Base infrastructure inputs
// ---------------------------------------------------------------------------

@description('Deployment location (LAB_LOCATION)')
param inLocation string

@description('Resource group name (LAB_RESOURCE_GROUP)')
param inResourceGroupName string

@description('Log Analytics Workspace name (LAW_NAME)')
param inWorkspaceName string

@description('Workspace customer ID / GUID used in KQL queries (LAW_ID)')
param inWorkspaceCustomerId string

@description('Workspace ARM resource ID (LAW_RESOURCE_ID)')
param inWorkspaceResourceId string

@description('DCE Logs Ingestion endpoint URL (DCE_LOGS_INGESTION_ENDPOINT)')
param inDceLogsIngestionEndpoint string

// ---------------------------------------------------------------------------
// Per-scenario DCR immutable IDs (ordered: vm, appservice, aks, azuresql, apm)
// ---------------------------------------------------------------------------

@description('DCR immutable ID — virtualmachines scenario')
param inDcrImmutableIdVirtualMachines string

@description('DCR immutable ID — appservice scenario')
param inDcrImmutableIdAppService string

@description('DCR immutable ID — aks scenario')
param inDcrImmutableIdAks string

@description('DCR immutable ID — azuresql scenario')
param inDcrImmutableIdAzureSql string

@description('DCR immutable ID — apm scenario')
param inDcrImmutableIdApm string

// ---------------------------------------------------------------------------
// Base infrastructure outputs
// ---------------------------------------------------------------------------

@description('Deployment location → LAB_LOCATION')
output location string = inLocation

@description('Resource group name → LAB_RESOURCE_GROUP')
output resourceGroupName string = inResourceGroupName

@description('Log Analytics Workspace name → LAW_NAME')
output workspaceName string = inWorkspaceName

@description('Workspace customer ID (GUID) used in KQL → LAW_ID')
output workspaceCustomerId string = inWorkspaceCustomerId

@description('Workspace ARM resource ID → LAW_RESOURCE_ID')
output workspaceResourceId string = inWorkspaceResourceId

@description('DCE Logs Ingestion endpoint URL → DCE_LOGS_INGESTION_ENDPOINT')
output dceLogsIngestionEndpoint string = inDceLogsIngestionEndpoint

// ---------------------------------------------------------------------------
// Per-scenario DCR immutable ID outputs → DCR_IMMUTABLE_ID_<UPPER_SNAKE>
// ---------------------------------------------------------------------------

@description('DCR immutable ID — virtualmachines → DCR_IMMUTABLE_ID_VIRTUAL_MACHINES')
output dcrImmutableIdVirtualMachines string = inDcrImmutableIdVirtualMachines

@description('DCR immutable ID — appservice → DCR_IMMUTABLE_ID_APP_SERVICE')
output dcrImmutableIdAppService string = inDcrImmutableIdAppService

@description('DCR immutable ID — aks → DCR_IMMUTABLE_ID_AKS')
output dcrImmutableIdAks string = inDcrImmutableIdAks

@description('DCR immutable ID — azuresql → DCR_IMMUTABLE_ID_AZURE_SQL')
output dcrImmutableIdAzureSql string = inDcrImmutableIdAzureSql

@description('DCR immutable ID — apm → DCR_IMMUTABLE_ID_APM')
output dcrImmutableIdApm string = inDcrImmutableIdApm

// ---------------------------------------------------------------------------
// Per-scenario stream name outputs → STREAM_<UPPER_SNAKE>
// Static — derived from convention (Custom-<PascalCase>_CL)
// ---------------------------------------------------------------------------

@description('Stream name → STREAM_VIRTUAL_MACHINES')
output streamVirtualMachines string = 'Custom-VirtualMachines_CL'

@description('Stream name → STREAM_APP_SERVICE')
output streamAppService string = 'Custom-AppService_CL'

@description('Stream name → STREAM_AKS')
output streamAks string = 'Custom-AKS_CL'

@description('Stream name → STREAM_AZURE_SQL')
output streamAzureSql string = 'Custom-AzureSQL_CL'

@description('Stream name → STREAM_APM')
output streamApm string = 'Custom-APM_CL'

// ---------------------------------------------------------------------------
// Per-scenario table name outputs → TABLE_<UPPER_SNAKE>
// Static — derived from convention (<PascalCase>_CL)
// ---------------------------------------------------------------------------

@description('Table name → TABLE_VIRTUAL_MACHINES')
output tableVirtualMachines string = 'VirtualMachines_CL'

@description('Table name → TABLE_APP_SERVICE')
output tableAppService string = 'AppService_CL'

@description('Table name → TABLE_AKS')
output tableAks string = 'AKS_CL'

@description('Table name → TABLE_AZURE_SQL')
output tableAzureSql string = 'AzureSQL_CL'

@description('Table name → TABLE_APM')
output tableApm string = 'APM_CL'
