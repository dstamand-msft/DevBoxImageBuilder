@sys.description('The location of the resources.')
param location string

@sys.description('The name of the existing virtual network that contains the VMBuilderSubnet.')
param virtualNetworkName string

@sys.description('The name of the resource group that contains the existing virtual network.')
param virtualNetworkResourceGroupName string = resourceGroup().name

@sys.description('The name of the subnet where the debug VM will be deployed.')
param subnetName string = 'VMBuilderSubnet'

@sys.description('The name of the virtual machine.')
@minLength(1)
@maxLength(15)
param vmName string

@sys.description('The size of the virtual machine.')
param vmSize string = 'Standard_D4s_v3'

@sys.description('The admin username for the virtual machine.')
param adminUsername string

@secure()
@sys.description('The admin password for the virtual machine.')
param adminPassword string

@sys.description('The image reference for the virtual machine OS disk.')
param imageReference object = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'windows-11'
  sku: 'win11-25h2-ent'
  version: 'latest'
}

@sys.description('The OS disk type for the virtual machine.')
@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
])
param osDiskType string = 'StandardSSD_LRS'

@sys.description('Whether to enable boot diagnostics with a managed storage account.')
param enableBootDiagnostics bool = false

@sys.description('(Optional) The managed identity definition for the VM. System-assigned is disabled by default.')
param managedIdentities object = {}

@sys.description('(Optional) Tags to apply to all resources.')
param tags object = {}

// Build the subnet resource ID from the existing virtual network
var subnetResourceId = resourceId(virtualNetworkResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)

// Debug virtual machine deployed into the VMBuilderSubnet using AVM module
module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.21.0' = {
  name: vmName
  params: {
    name: vmName
    location: location
    tags: tags
    osType: 'Windows'
    vmSize: vmSize
    availabilityZone: -1
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: imageReference
    osDisk: {
      createOption: 'FromImage'
      deleteOption: 'Delete'
      managedDisk: {
        storageAccountType: osDiskType
      }
    }
    nicConfigurations: [
      {
        deleteOption: 'Delete'
        name: 'nic-${vmName}'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: subnetResourceId
          }
        ]
      }
    ]
    bootDiagnostics: enableBootDiagnostics
    securityType: 'TrustedLaunch'
    secureBootEnabled: true
    vTpmEnabled: true
    managedIdentities: !empty(managedIdentities) ? managedIdentities : null
  }
}

output vmName string = virtualMachine.outputs.name
output vmResourceId string = virtualMachine.outputs.resourceId
