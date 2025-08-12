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

var rbacRoles = loadJsonContent('rbacRoleIds.json')

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: 'scripts'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource appsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: 'apps'
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

resource storageBlobDataReaderRBACAIBIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, userImgBuilderIdentity.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.storageBlobDataReader)
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

resource userImgBuilderIdentityRBAC 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userImgBuilderIdentity.id, vmImgBuilderIdentity.id, 'Managed Identity Operator')
  scope: vmImgBuilderIdentity
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.managedIdentityOperator)
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

output userImgBuilderIdentityIdResourceId string = userImgBuilderIdentity.id
output userImgBuilderIdentityPrincipalId string = userImgBuilderIdentity.properties.principalId
output vmImgBuilderIdentityResourceId string = vmImgBuilderIdentity.id
output vmImgBuilderIdentityClientId string = vmImgBuilderIdentity.properties.clientId
output StorageAccountPrimaryEndpointsBlob string = storageAccount.properties.primaryEndpoints.blob
output galleryImageResourceId string = galleryImage.id
