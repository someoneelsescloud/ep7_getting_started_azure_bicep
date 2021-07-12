@minLength(12)
@description('Password for the Virtual Machine.')
@secure()
param adminPassword string

@description('Unique Identifier used for Resource Names')
param uniqueName string

@description('location for all resources')
param location string = resourceGroup().location

@description('Requires current user ObjectId to create KeyVault access policy')
param userObjectId string

// Virtual Machine Configuration
var storageAccountName = 'storage${uniqueString(resourceGroup().id)}'
var virtualMachineName = '${uniqueName}-vm-1'
var virtualMachineNicName = '${uniqueName}-nic-1'
var publicIpName = '${uniqueName}-vm-public-1'
var dnsLabelPrefix = toLower('${virtualMachineName}-${uniqueString(resourceGroup().id, virtualMachineName)}')

// Log Analytics Workspace Configuration
var workspaceName = '${uniqueName}-workspace-1'
var keyVaultName = '${uniqueName}-kv-1'
param eventLevel array = [
  'Error'
  'Warning'
  'Information'
]

// Networking Configuration
var virtualNetworkName = '${uniqueName}-vnet-1'
var subnetName = '${uniqueName}-subnet-1'
var virtualNetworkPrefix = '10.0.0.0/16'
var subnetPrefix = '10.0.0.0/24'
var networkSecurityGroupName = '${uniqueName}-nsg-1'
var subnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)

// Lookup Workspace Key using Log Analytics Workspace Id
// var workspaceKey =  'listKeys(variables({law_resource.id})).primarySharedKey'

resource vnet_resource 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg_resource.id
          }
        }
      }
    ]
  }
}

resource nsg_resource 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-3389'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nic_resource 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: virtualMachineNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: virtualMachineNicName
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicip_resource.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
  dependsOn: [
     vnet_resource
  ]
}

resource publicip_resource 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}


resource vm_resource 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: virtualMachineName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2_v3'
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: 'localadmin'
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: '${virtualMachineName}-osdisk-1'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic_resource.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: sa_resource.properties.primaryEndpoints.blob
      }
    }
  }
}

resource sa_resource 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
}

// resource vmlawagent_resource 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
//   parent: vm_resource
//   name: 'Microsoft.Insights.LogAnalyticsAgent'
//   location: location
//   properties: {
//     publisher: 'Microsoft.EnterpriseCloud.Monitoring'
//     type: 'MicrosoftMonitoringAgent'
//     typeHandlerVersion: '1.0'
//     autoUpgradeMinorVersion: true
//     settings: {
//       workspaceId: law_resource.properties.customerId
//     }
//     protectedSettings: {
//       workspaceKey: workspaceKey
//         }
//   }
//   dependsOn: [
//     law_resource
//   ]
// }

resource law_resource 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'Free'
    }
  }
}

resource perfdiskdata_resource 'Microsoft.OperationalInsights/workspaces/dataSources@2020-08-01' = {
  name: '${law_resource.name}/perfcounter1'
  kind: 'WindowsPerformanceCounter'
  properties: {
    objectName: 'LogicalDisk'
    instanceName: 'C:'
    intervalSeconds: 60
    counterName: '% Free Space'
  }
  dependsOn: [
    law_resource
  ]
}

resource windowsevent_resource 'Microsoft.OperationalInsights/workspaces/datasources@2020-08-01' = {
  name: '${law_resource.name}/WindowsEvent'
  kind: 'WindowsEvent'
  properties: {
    eventLogName: 'System'
    eventTypes: [for Level in eventLevel: {
      eventType: Level
   }]
  }
  dependsOn: [
    law_resource
  ]
}

resource keyvault_resource 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: userObjectId
        permissions: {
          keys: [
            'get'
          ]
          secrets: [
            'list'
            'get'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource keyvaultsecret_resource 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${keyVaultName}/${virtualMachineName}'
  properties: {
    value: adminPassword
  }
  dependsOn: [
    keyvault_resource
  ]
}
