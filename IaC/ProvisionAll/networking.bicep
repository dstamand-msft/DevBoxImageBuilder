@description('The location of the resources')
param location string

@description('The name of the virtual network')
param virtualNetworkName string

@description('The storage account that will be used in the solution.')
param storageAccountName string

@description('Tags to apply to the resources')
param tags object = {}

@description('List of CIDR ranges allowed to connect to Azure Bastion on port 443. Defaults to all Internet traffic.')
param bastionAllowedCIDRs array = []

var vmImageBuilderSubnetAddressPrefix = '10.0.0.0/28'
var aciSubnetAddressPrefix = '10.0.0.16/28'
var adoManagedPoolSubnetAddressPrefix = '10.0.0.32/28'
var privateEndpointsSubnetAddressPrefix = '10.0.0.48/28'
var azureBastionSubnetAddressPrefix = '10.0.0.64/26'
var devboxManagementSubnetAddressPrefix = '10.0.0.128/28'

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.2' = {
  params: {
    addressPrefixes: [
      '10.0.0.0/24'
    ]
    name: virtualNetworkName
    location: location
    tags: tags
  }
}

module pipNatVmBuilder 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  params: {
    name: 'pip-nat-vmbuilder'
    location: location
    tags: tags
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
  }
}

module natGatewayVmBuilder 'br/public:avm/res/network/nat-gateway:2.0.1' = {
  params: {
    name: 'nat-vmbuilder'
    location: location
    availabilityZone: -1
    tags: tags
    publicIpResourceIds: [
      pipNatVmBuilder.outputs.resourceId
    ]
  }
}

module pipNatADOManagedPool 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  params: {
    name: 'pip-nat-adomanagedpool'
    location: location
    tags: tags
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
  }
}

module natGatewayADOManagedPool 'br/public:avm/res/network/nat-gateway:2.0.1' = {
  params: {
    name: 'nat-adomanagedpool'
    location: location
    availabilityZone: -1
    tags: tags
    publicIpResourceIds: [
      pipNatADOManagedPool.outputs.resourceId
    ]
  }
}

module pipNatDevBoxSubnet 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  params: {
    name: 'pip-nat-devboxsubnet'
    location: location
    tags: tags
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
  }
}

module natGatewayDevBoxSubnet 'br/public:avm/res/network/nat-gateway:2.0.1' = {
  params: {
    name: 'nat-devboxsubnet'
    location: location
    availabilityZone: -1
    tags: tags
    publicIpResourceIds: [
      pipNatDevBoxSubnet.outputs.resourceId
    ]
  }
}

module nsgImageBuilder 'br/public:avm/res/network/network-security-group:0.5.2' = {
  params: {
    name: 'nsg-imagebuilder'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowToPrivateEndpoints'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefixes: [
            vmImageBuilderSubnetAddressPrefix
            adoManagedPoolSubnetAddressPrefix
            devboxManagementSubnetAddressPrefix
          ]
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-WinRM-HTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: aciSubnetAddressPrefix
          destinationAddressPrefix: vmImageBuilderSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          description: 'Allow connectivity for WinRM for HTTPS'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: devboxManagementSubnetAddressPrefix
          destinationAddressPrefix: vmImageBuilderSubnetAddressPrefix
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyVnetInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// NSG for Azure Bastion - see https://learn.microsoft.com/azure/bastion/bastion-nsg
module nsgBastion 'br/public:avm/res/network/network-security-group:0.5.2' = {
  params: {
    name: 'nsg-bastion'
    location: location
    tags: tags
    securityRules: [
      // Inbound rules
      {
        name: 'AllowHttpsInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefixes: empty(bastionAllowedCIDRs) ? null : bastionAllowedCIDRs
          sourceAddressPrefix: empty(bastionAllowedCIDRs) ? 'Internet' : null
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
          description: 'Allow ingress traffic from public internet on port 443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
          description: 'Allow control plane connectivity from GatewayManager'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 140
          direction: 'Inbound'
          description: 'Allow health probes from Azure Load Balancer'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 150
          direction: 'Inbound'
          description: 'Allow data plane communication between Bastion components'
        }
      }
      // Outbound rules
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
          description: 'Allow SSH and RDP outbound to target VMs'
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
          description: 'Allow outbound to Azure public endpoints for diagnostics and metering'
        }
      }
      {
        name: 'AllowBastionHostCommunicationOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
          description: 'Allow data plane communication between Bastion components'
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
          description: 'Allow outbound to Internet for session, shareable link, and certificate validation'
        }
      }
    ]
  }
}

@description('The subnet that will host the virtual machines used for building the images.')
// Note: When deploying multiple subnets, chain them with dependsOn to avoid
// concurrent modification conflicts on the parent VNet resource.
resource vmBuilderSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/VMBuilderSubnet'
  properties: {
    addressPrefix: vmImageBuilderSubnetAddressPrefix
    natGateway: {
      id: natGatewayVmBuilder.outputs.resourceId
    }
    networkSecurityGroup: {
      id: nsgImageBuilder.outputs.resourceId
    }
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource aciSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/BuilderServiceACISubnet'
  properties: {
    addressPrefix: aciSubnetAddressPrefix
    delegations: [
      {
        name: 'aciSubnetDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
  }
  dependsOn: [
    vmBuilderSubnet
  ]
}

resource adoManagedPoolSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/ADOManagedPoolSubnet'
  properties: {
    addressPrefix: adoManagedPoolSubnetAddressPrefix
    natGateway: {
      id: natGatewayADOManagedPool.outputs.resourceId
    }
  }
  dependsOn: [
    aciSubnet
  ]
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/PrivateEndpointsSubnet'
  properties: {
    addressPrefix: privateEndpointsSubnetAddressPrefix
  }
  dependsOn: [
    adoManagedPoolSubnet
  ]
}

resource azureBastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/AzureBastionSubnet'
  properties: {
    addressPrefix: azureBastionSubnetAddressPrefix
    networkSecurityGroup: {
      id: nsgBastion.outputs.resourceId
    }
  }
  dependsOn: [
    privateEndpointsSubnet
  ]
}

// Azure Bastion host with its own public IP (managed by the AVM module)
module bastionHost 'br/public:avm/res/network/bastion-host:0.8.2' = {
  params: {
    name: 'bas-${virtualNetworkName}'
    location: location
    tags: tags
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    publicIPAddressObject: {
      name: 'pip-bastion'
    }
  }
  dependsOn: [
    azureBastionSubnet
  ]
}

resource devboxManagementSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: '${virtualNetworkName}/DevBoxManagementSubnet'
  properties: {
    addressPrefix: devboxManagementSubnetAddressPrefix
  }
  dependsOn: [
    azureBastionSubnet
  ]
}

module peAzureStorage 'br/public:avm/res/network/private-endpoint:0.11.1' = {
  params: {
    name: 'pe-azurestorage-blob'
    location: location
    subnetResourceId: privateEndpointsSubnet.id
    privateLinkServiceConnections: [
      {
        name: 'connection-to-blob'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
    ipConfigurations: [
      {
        name: 'ipconfig-blob'
        properties: {
          groupId: 'blob'
          memberName: 'blob'
          privateIPAddress: cidrHost(privateEndpointsSubnetAddressPrefix, 3)
        }
      }
    ]
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
        }
      ]
    }
    tags: tags
  }
}

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  params: {
#disable-next-line no-hardcoded-env-urls
    name: 'privatelink.blob.core.windows.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
    tags: tags
  }
}

output vmBuilderSubnetId string = vmBuilderSubnet.id
output aciSubnetId string = aciSubnet.id
