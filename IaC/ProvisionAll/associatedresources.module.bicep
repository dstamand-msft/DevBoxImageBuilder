import { galleryImageIdentifierType } from 'shared.bicep'

@description('The location of the resources')
param location string

@description('The storage account that holds the scripts to be provisioned on the VM')
param storageAccountName string

@description('The name of the user assigned identity')
param userIdentityName string

@description('The name of the user assigned identity for the Image builder VM, the user assigned identity for Azure Image Builder must have the "Managed Identity Operator" role assignment on all the user assigned identities for Azure Image Builder to be able to associate them to the build VM.')
param imageBuilderVMUserAssignedIdentityName string

@description('The name of the image definition gallery')
param galleryName string

@description('The name of the image definition')
param imageDefinitionName string

@description('The object representing the identifier properties of the image definition')
param galleryImageIdentifier galleryImageIdentifierType

@description('Whether to enable soft delete on the image gallery')
param softDeleteOnGallery bool = false

@description('The storage account container name where the scripts to run on the build vm are stored')
param scriptsContainerName string = 'scripts'

@description('The storage account container name where the apps to run on the build vm are stored')
param appsContainerName string = 'apps'

@description('Whether to pre-populate the storage account with example scripts for building images')
param prepopulateStorageWithExampleScripts bool = true

@description('Whether to disable public network access on the storage account. When true, the storage account is only accessible via private endpoints.')
param disablePublicNetworkAccess bool = false

@description('The name of the virtual network to use for the image builder VM. When specified, the XX')
param virtualNetworkName string?

@description('The Azure CLI version to use for the deploymentScripts resource')
param azCliVersion string = '2.75.0'

@description('UTC timestamp used to create distinct deployment scripts for each deployment')
param utcValue string = utcNow()

var rbacRoles = loadJsonContent('../rbacRoleIds.json')

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (!empty(virtualNetworkName)) {
  name: virtualNetworkName!
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Cool'
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    allowBlobPublicAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: scriptsContainerName
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource appsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: appsContainerName
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource userImgBuilderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: userIdentityName
  location: location
}

resource vmImgBuilderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: imageBuilderVMUserAssignedIdentityName
  location: location
}

resource azureImageBuilderInjectandDistributeRoleDef 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' = {
  name: guid(subscription().id, resourceGroup().id, 'azureImageBuilderCustomRoleDefinition')
  properties: {
    roleName: 'Custom Role Azure Image Builder Image Gallery Distribute'
    description: 'Allows an identity to inject the images and distribute them to a Shared Image Gallery.'
    type: 'customRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/images/write'
          'Microsoft.Compute/images/read'
          'Microsoft.Compute/images/delete'
          'Microsoft.Compute/galleries/read'
          'Microsoft.Compute/galleries/images/read'
          'Microsoft.Compute/galleries/images/versions/read'
          'Microsoft.Compute/galleries/images/versions/write'
        ]
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

resource azureImageBuilderUseVNetRoleDef 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' = if (!empty(virtualNetworkName)) {
  name: guid(subscription().id, resourceGroup().id, 'azureImageBuilderUseVNetCustomRoleRoleDef')
  properties: {
    roleName: 'Custom Role Use and Deploy VM into a VNet'
    description: 'Allows an identity to use and deploy a VM into a Virtual Network.'
    type: 'customRole'
    permissions: [
      {
        actions: [
          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/virtualNetworks/subnets/join/action'
        ]
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

resource storageBlobDataReaderRBACAIBIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (prepopulateStorageWithExampleScripts) {
  name: guid(storageAccount.id, userImgBuilderIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    // contributor because of the fact that we need to programmatically upload files to the storage account upon deployment (see deploymentScript resource)
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.storageBlobDataContributor)
    principalId: userImgBuilderIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobDataReaderRBACAIBVMIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, vmImgBuilderIdentity.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.storageBlobDataReader)
    principalId: vmImgBuilderIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource managedIdentityOperatorUserImgBuilderIdentityRBAC 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userImgBuilderIdentity.id, vmImgBuilderIdentity.id, 'Managed Identity Operator')
  scope: vmImgBuilderIdentity
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.managedIdentityOperator)
    principalId: userImgBuilderIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource customRoleAIBImageDistributionUserImgBuilderIdentityRBAC 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userImgBuilderIdentity.id, 'Custom AIB Role Image distribution')
  scope: galleryImage
  properties: {
    roleDefinitionId: azureImageBuilderInjectandDistributeRoleDef.id
    principalId: userImgBuilderIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource customRoleUseVnetRBACAIBIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(virtualNetworkName)) {
  name: guid(storageAccount.id, userImgBuilderIdentity.id, 'Custom Role Use and Deploy VM into a VNet')
  scope: virtualNetwork
  properties: {
    roleDefinitionId: azureImageBuilderUseVNetRoleDef.id
    principalId: userImgBuilderIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource gallery 'Microsoft.Compute/galleries@2024-03-03' = {
  name: galleryName
  location: location
  properties: {
    softDeletePolicy: {
      isSoftDeleteEnabled: softDeleteOnGallery
    }
  }
}

resource galleryImage 'Microsoft.Compute/galleries/images@2024-03-03' = {
  name: imageDefinitionName
  parent: gallery
  location: location
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    identifier: {
      publisher: galleryImageIdentifier.publisher
      offer: galleryImageIdentifier.offer
      sku: galleryImageIdentifier.sku
    }
    hyperVGeneration: 'V2'
    architecture: 'x64'
    features: [
      {
        name: 'SecurityType'
        value: 'TrustedLaunch'
      }
      {
        name: 'IsHibernateSupported'
        value: 'True'
      }
    ]
  }
}

// The deploymentScripts resource creates a temporary storage account (managed by the platform) that requires
// allowSharedKeyAccess to be enabled because Azure Container Instances (ACI) can only mount file shares via access keys.
// See https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-script-bicep#use-existing-storage-accounts
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (prepopulateStorageWithExampleScripts) {
#disable-next-line use-stable-resource-identifiers
  name: 'deployscript-upload-blob-${utcValue}'
  dependsOn: [
    storageBlobDataReaderRBACAIBIdentity
  ]
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userImgBuilderIdentity.id}': {}
    }
  }
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    azCliVersion: azCliVersion
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storageAccount.name
      }
      // usually storage keys are disabled
      // {
      //   name: 'AZURE_STORAGE_KEY'
      //   secureValue: storageAccount.listKeys().keys[0].value
      // }
      {
        name: 'CONTENT_ENTRYPOINT'
        value: loadTextContent('../../Scripts/Entrypoint.ps1')
      }
      {
        name: 'CONTENT_EXITPOINT'
        value: loadTextContent('../../Scripts/Exitpoint.ps1')
      }
      {
        name: 'CONTENT_DEPROVISIONING'
        value: loadTextContent('../../Scripts/DeprovisioningScript.ps1')
      }
      {
        name: 'CONTENT_DOWNLOADARTIFACTS'
        value: loadTextContent('../../Scripts/DownloadArtifacts.ps1')
      }
      {
        name: 'CONTENT_ARTIFACTSMETADATA'
        value: loadTextContent('../../Scripts/artifactsmetadata.txt')
      }
    ]
// Interpolation isn't currently supported in multi-line strings.
// Because of this limitation, you need to use the concat function instead of using interpolation.
#disable-next-line prefer-interpolation
    scriptContent: concat(
      '#!/bin/bash\n',
      'set -e\n',
      'echo "$CONTENT_ENTRYPOINT" > Entrypoint.ps1 && az storage blob upload --auth-mode login --overwrite true -f Entrypoint.ps1 -c ', scriptsContainerName, ' -n Entrypoint.ps1\n',
      'echo "$CONTENT_EXITPOINT" > Exitpoint.ps1 && az storage blob upload --auth-mode login --overwrite true -f Exitpoint.ps1 -c ', scriptsContainerName, ' -n Exitpoint.ps1\n',
      'echo "$CONTENT_DEPROVISIONING" > DeprovisioningScript.ps1 && az storage blob upload --auth-mode login --overwrite true -f DeprovisioningScript.ps1 -c ', scriptsContainerName, ' -n DeprovisioningScript.ps1\n',
      'echo "$CONTENT_DOWNLOADARTIFACTS" > DownloadArtifacts.ps1 && az storage blob upload --auth-mode login --overwrite true -f DownloadArtifacts.ps1 -c ', scriptsContainerName, ' -n DownloadArtifacts.ps1\n',
      'echo "$CONTENT_ARTIFACTSMETADATA" > artifactsmetadata.txt && az storage blob upload --auth-mode login --overwrite true -f artifactsmetadata.txt -c ', scriptsContainerName, ' -n artifactsmetadata.txt\n'
    )
  }
}

output userImgBuilderIdentityIdResourceId string = userImgBuilderIdentity.id
output userImgBuilderIdentityPrincipalId string = userImgBuilderIdentity.properties.principalId
output vmImgBuilderIdentityResourceId string = vmImgBuilderIdentity.id
output vmImgBuilderIdentityClientId string = vmImgBuilderIdentity.properties.clientId
output storageAccountPrimaryEndpointsBlob string = storageAccount.properties.primaryEndpoints.blob
output galleryImageResourceId string = galleryImage.id
