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

@description('Whether the Azure Image Builder will use a subnet for the build VM')
param isUsingSubnetForAIB bool = false

@description('Whether to enable soft delete on the image gallery')
param softDeleteOnGallery bool = false

@description('The storage account container name where the scripts to run on the build vm are stored')
param scriptsContainerName string = 'scripts'

@description('The storage account container name where the apps to run on the build vm are stored')
param appsContainerName string = 'apps'

@description('The Azure CLI version to use for the deploymentScripts resource')
param azCliVersion string = '2.75.0'

// @description('UTC timestamp used to create distinct deployment scripts for each deployment')
// param utcValue string = utcNow()

var rbacRoles = loadJsonContent('../rbacRoleIds.json')

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

resource storageBlobDataReaderRBACAIBIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (isUsingSubnetForAIB) {
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

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
name: 'deployscript-upload-blob'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userImgBuilderIdentity.id}': {}
    }
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
