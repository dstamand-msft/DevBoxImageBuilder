
targetScope = 'subscription'

@description('The location of the resources')
param location string

@description('The name of the resource group to deploy the template into.')
param resourceGroupName string

@description('The name of the resource group that contains the user assigned identity associated with the image builder template.')
param userIdentityResourceGroupName string

@description('The name of the user assigned identity')
param userIdentityName string

@description('The name of the resource group that contains the image definition gallery')
param galleryResourceGroupName string

@description('The name of the image definition gallery')
param galleryName string

@description('The name of the image definition')
param imageDefinitionName string

@description('The name of the image template')
param imageTemplateName string

@description('The resource group that contains the storage account that holds the scripts to be provisioned on the VM')
param storageAccountResourceGroupName string

@description('The storage account that holds the scripts to be provisioned on the VM')
param storageAccountName string

@description('The container in the storage account that holds the scripts to be provisioned on the VM')
param scriptsContainerName string

@description('The name of the resource group that contains the user assigned identity for the Image builder VM, the user assigned identity for Azure Image Builder must have the "Managed Identity Operator" role assignment on all the user assigned identities for Azure Image Builder to be able to associate them to the build VM.')
param imageBuilderVMUserAssignedIdentityResourceGroupName string

@description('The name of the user assigned identity for the Image builder VM, the user assigned identity for Azure Image Builder must have the "Managed Identity Operator" role assignment on all the user assigned identities for Azure Image Builder to be able to associate them to the build VM.')
param imageBuilderVMUserAssignedIdentityName string

@description('The source of the image to be used to create the image template. see https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/imagetemplates?pivots=deployment-language-bicep#imagetemplatesource-objects for more information.')
// example:
// type: 'PlatformImage'
// publisher: 'MicrosoftWindowsDesktop'
// offer: 'windows-ent-cpc'
// sku: 'win11-24h2-ent-cpc'
// version: 'latest'
param imageSource object

@description('	Size of the virtual machine used to build, customize and capture images.')
param vmSkuSize string = 'Standard_D4s_v3'

@description('(Optional) The name of the subnet where the virtual machine will be deployed. This is useful if you need to access private resources or on-premises resources.')
param subnetId string = ''

@description('(Optional) The name of the subnet where the container instance will be deployed. This subnet must allow outbound access to the Internet and to the subnet specified in subnetId and be delegated to the ACI service so that it can be used to deploy ACI resources. The subnet in property subnetId must allow inbound access from this subnet. See https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-json?tabs=bicep%2Cazure-powershell#containerinstancesubnetid-optional')
param containerInstanceSubnetId string = ''

@description('(Optional) The staging resource group id (/subscriptions/\\<subscriptionID>/resourceGroups/\\<stagingResourceGroupName\\>) in the same subscription as the image template that will be used to build the image. If this field is empty, a resource group with a random name will be created. If the resource group specified in this field doesn\'t exist, it will be created with the same name. If the resource group specified exists, it must be empty and in the same region as the image template. The resource group created will be deleted during template deletion if this field is empty or the resource group specified doesn\'t exist, but if the resource group specified exists the resources created in the resource group will be deleted during template deletion and the resource group itself will remain. The user identity deploying the template needs to have Owner role assignment to this resource group. Each image template requires its own staging resource group.')
param stagingResourceGroupId string = ''

@description('Specifies the action to take when an error occurs during the customizer phase of image creation')
@allowed(['abort', 'cleanup'])
param onCustomizerError string = 'abort'

@description('Specifies the action to take when an error occurs during validation of the image template')
@allowed(['abort', 'cleanup'])
param onValidationError string = 'cleanup'

@description('Maximum duration to wait, in minutes, while building the image template (includes all customizations, validations, and distributions). Specify 0 to use the default in the Azure platform (4 hours). Defaults to 6 hours if not specified')
param buildTimeoutInMinutes int = 300

@description('(Optional) The regions where the image will be replicated. The regions should exclude the region where the shared imaged gallery is deployed.')
param imageReplicationRegions array = []

@description('The subscription id where the managed identity of the provisioning VM will connect to.')
param subscriptionId string

@description('The path to the artifacts metadata file in the storage account.')
param artifactsMetadataPath string

@description('(Optional) The tags to be associated with the image template.')
param tags object = {}

@description('(Optional) The tags to be associated with the image that will be created by the image template.')
param imageTags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
  scope: resourceGroup(storageAccountResourceGroupName)
}

resource userImgBuilderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: userIdentityName
  scope: resourceGroup(userIdentityResourceGroupName)
}

resource vmImgBuilderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: imageBuilderVMUserAssignedIdentityName
  scope: resourceGroup(imageBuilderVMUserAssignedIdentityResourceGroupName)
}

resource gallery 'Microsoft.Compute/galleries@2022-08-03' existing = {
  name: galleryName
  scope: resourceGroup(galleryResourceGroupName)
}

resource galleryImage 'Microsoft.Compute/galleries/images@2022-03-03' existing = {
  name: imageDefinitionName
  parent: gallery
}

@description('(Optional) The name of the key vault where the secrets are stored.')
param keyVaultName string = ''

module imageTemplateWithPublicStorage '../aib.module.bicep' = if (empty(subnetId)){
  name: imageTemplateName
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    imageTemplateName: imageTemplateName
    scriptsContainerName: scriptsContainerName
    userImgBuilderIdentityId: userImgBuilderIdentity.id
    imageBuilderVMUserAssignedIdentityId: vmImgBuilderIdentity.id
    imageBuilderVMUserAssignedIdentityClientId: vmImgBuilderIdentity.properties.clientId
    imageSource: imageSource
    vmSkuSize: vmSkuSize
    subnetId: subnetId
    stagingResourceGroupId: stagingResourceGroupId
    onCustomizerError: onCustomizerError
    onValidationError: onValidationError
    buildTimeoutInMinutes: buildTimeoutInMinutes
    storageAccountBlobEndpoint: storageAccount.properties.primaryEndpoints.blob
    galleryImageId: galleryImage.id
    imageReplicationRegions: imageReplicationRegions
    subscriptionId: subscriptionId
    storageAccountName: storageAccountName
    artifactsMetadataPath: artifactsMetadataPath
    tags: tags
    imageTags: imageTags
    keyVaultName: keyVaultName
  }
}

module imageTemplateWithPrivateStorage '../aib.module-private.bicep' = if (!empty(subnetId)) {
  name: imageTemplateName
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    imageTemplateName: imageTemplateName
    scriptsContainerName: scriptsContainerName
    userImgBuilderIdentityId: userImgBuilderIdentity.id
    imageBuilderVMUserAssignedIdentityId: vmImgBuilderIdentity.id
    imageBuilderVMUserAssignedIdentityClientId: vmImgBuilderIdentity.properties.clientId
    imageSource: imageSource
    vmSkuSize: vmSkuSize
    subnetId: subnetId
    containerInstanceSubnetId: containerInstanceSubnetId
    stagingResourceGroupId: stagingResourceGroupId
    onCustomizerError: onCustomizerError
    onValidationError: onValidationError
    buildTimeoutInMinutes: buildTimeoutInMinutes
    storageAccountBlobEndpoint: storageAccount.properties.primaryEndpoints.blob
    galleryImageId: galleryImage.id
    imageReplicationRegions: imageReplicationRegions
    subscriptionId: subscriptionId
    storageAccountName: storageAccountName
    artifactsMetadataPath: artifactsMetadataPath
    tags: tags
    imageTags: imageTags
    keyVaultName: keyVaultName
  }
}

output imageTemplateName string = imageTemplateName
