// =============================================================================
// infra/modules/demo-vm.bicep
// Scope: resourceGroup
//
// Provisions a minimal-cost demo VM for Azure Monitor guest metrics.
// Resources created (all ADDITIVE to the lab — does not touch existing lab
// resources):
//   - NSG (no inbound allow rules; default DenyAllInBound)
//   - VNet 10.10.0.0/24 + subnet snet-vmguest 10.10.0.0/27
//   - NIC (private IP only, no public IP)
//   - VM: Ubuntu 22.04 LTS Gen2, Standard_B2ats_v2, Standard_LRS 30 GB
//   - AMA Linux agent extension (auto-upgrade enabled)
//   - DCR (kind Linux): performanceCounters → Microsoft-InsightsMetrics + Microsoft-Perf
//   - DCRA binding DCR to the VM
//   - DevTestLab auto-shutdown schedule (daily 19:00 CST)
//
// API versions validated against learn.microsoft.com on 2026-07-16:
//   Microsoft.Compute/virtualMachines                   2024-07-01
//     https://learn.microsoft.com/azure/templates/microsoft.compute/2024-07-01/virtualmachines
//   Microsoft.Compute/virtualMachines/extensions        2024-07-01
//     https://learn.microsoft.com/azure/templates/microsoft.compute/2024-07-01/virtualmachines/extensions
//   Microsoft.Network/virtualNetworks                   2023-09-01
//   Microsoft.Network/networkSecurityGroups             2023-09-01
//   Microsoft.Network/networkInterfaces                 2023-09-01
//   Microsoft.Insights/dataCollectionRules              2023-03-11
//     https://learn.microsoft.com/azure/templates/microsoft.insights/2023-03-11/datacollectionrules
//   Microsoft.Insights/dataCollectionRuleAssociations   2023-03-11
//   Microsoft.DevTestLab/schedules                      2018-09-15
//     https://learn.microsoft.com/azure/templates/microsoft.devtestlab/2018-09-15/schedules
// =============================================================================

@description('Azure region — must match the existing lab workspace region')
param location string

@description('Full ARM resource ID of the existing law-amlab-<uid> workspace')
param workspaceResourceId string

@description('VM size. Default: Standard_B2ats_v2 (2 vCPU / 1 GiB, cheapest v2 burstable, unrestricted in southcentralus).')
param vmSize string = 'Standard_B2ats_v2'

@description('VM admin username')
param adminUsername string = 'azureuser'

@description('SSH public key content (RSA or ed25519), passed to authorized_keys')
@secure()
param sshPublicKey string

@description('Auto-shutdown time in HHMM 24h format, Central Standard Time')
param autoShutdownTime string = '1900'

@description('6-char uid derived from uniqueString; controls all resource names')
param uid string = take(uniqueString(resourceGroup().id, 'vmguest'), 6)

@description('Resource tags applied to every resource in this module')
param tags object = {
  lab: 'azure-monitor-lab'
  module: 'demo-vm'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Derived names — deterministic from uid
// ---------------------------------------------------------------------------
var nsgName     = 'nsg-amlab-vmguest-${uid}'
var vnetName    = 'vnet-amlab-${uid}'
var nicName     = 'nic-amlab-${uid}'
var vmName      = 'vm-amlab-${uid}'
var dcrName     = 'dcr-amlab-vmguest-${uid}'
var dcrAssocName = 'dcra-vmguest-${uid}'
var schedName   = 'shutdown-computevm-${vmName}'

// ---------------------------------------------------------------------------
// NSG — no inbound allow rules; rely on default DenyAllInBound
// ---------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// ---------------------------------------------------------------------------
// VNet + subnet (NSG on subnet)
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.10.0.0/24']
    }
    subnets: [
      {
        name: 'snet-vmguest'
        properties: {
          addressPrefix: '10.10.0.0/27'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// NIC — private IP only, no public IP
// ---------------------------------------------------------------------------
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// VM — Ubuntu 22.04 LTS Gen2, Standard_LRS 30 GB, SSH key auth
// Image URN confirmed live in southcentralus on 2026-07-16:
//   Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
// ---------------------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  // System-assigned identity required by AMA to authenticate to IMDS/AAD
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 30
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        // no storageUri → uses managed storage (free)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Azure Monitor Linux Agent — auto-upgrade, no config needed here
// publisher/type validated: https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-manage
// ---------------------------------------------------------------------------
resource amaExt 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
  }
}

// ---------------------------------------------------------------------------
// DCR — kind Linux, lean performanceCounters → InsightsMetrics + Perf
// Counter set validated against:
//   https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-performance
// Streams validated:
//   Microsoft-InsightsMetrics → InsightsMetrics table (VM Insights)
//   Microsoft-Perf            → Perf table (classic perf counter table)
// ---------------------------------------------------------------------------
resource vmGuestDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  kind: 'Linux'
  tags: tags
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounterDataSource60'
          streams: [
            'Microsoft-InsightsMetrics'
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            'Processor(*)\\% Processor Time'
            'Memory(*)\\% Available Memory'
            'Memory(*)\\Available MBytes Memory'
            'LogicalDisk(*)\\% Used Space'
            'LogicalDisk(*)\\Disk Transfers/sec'
            'Network(*)\\Total Bytes'
          ]
        }
      ]
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
        streams: [
          'Microsoft-InsightsMetrics'
          'Microsoft-Perf'
        ]
        destinations: ['law-dest']
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// DCRA — associate the DCR with the VM
// ---------------------------------------------------------------------------
resource dcrAssoc 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: dcrAssocName
  scope: vm
  properties: {
    dataCollectionRuleId: vmGuestDcr.id
    description: 'Associate vmguest DCR with demo VM for AMA guest metrics'
  }
  dependsOn: [amaExt]
}

// ---------------------------------------------------------------------------
// Auto-shutdown schedule — deallocates VM daily at autoShutdownTime (CST)
// Resource type validated:
//   https://learn.microsoft.com/azure/templates/microsoft.devtestlab/2018-09-15/schedules
// The name MUST be shutdown-computevm-<vmName> for Azure to link it in portal
// ---------------------------------------------------------------------------
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: schedName
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: 'Central Standard Time'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('VM resource name, e.g. vm-amlab-<uid>')
output vmName string = vm.name

@description('VM ARM resource ID')
output vmId string = vm.id

@description('VM private IP address (dynamic, known after deployment)')
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress

@description('Guest-metrics DCR ARM resource ID')
output dcrId string = vmGuestDcr.id

@description('NSG ARM resource ID')
output nsgId string = nsg.id

@description('VNet ARM resource ID')
output vnetId string = vnet.id

@description('NIC ARM resource ID')
output nicId string = nic.id

@description('OS disk name (for teardown)')
output osDiskName string = vm.properties.storageProfile.osDisk.name
