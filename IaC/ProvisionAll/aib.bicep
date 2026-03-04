import { galleryImageIdentifierType } from 'shared.bicep'

targetScope = 'subscription'

@description('The location of the resources')
param location string

@description('The name of the resource group to deploy the template into.')
param resourceGroupName string

@description('The name of the user assigned identity')
param userIdentityName string

@description('The name of the image definition gallery')
param galleryName string

@description('The name of the image definition')
param imageDefinitionName string

@description('The name of the image template')
param imageTemplateName string

@description('The object representing the identifier properties of the image definition')
param galleryImageIdentifier galleryImageIdentifierType

@description('Whether to enable soft delete on the image gallery')
param softDeleteOnGallery bool = false

@description('The storage account that holds the scripts to be provisioned on the VM')
param storageAccountName string

@description('The storage account container name where the scripts to run on the build vm are stored')
param scriptsContainerName string = 'scripts'

@description('The storage account container name where the apps to run on the build vm are stored')
param appsContainerName string = 'apps'

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

@description('(Optional) The name of the virtual network to create. Required when subnetId is not provided and you want the networking module to provision all networking resources.')
param virtualNetworkName string = ''

@description('(Optional) The name of the subnet where the virtual machine will be deployed. When provided, it indicates that you are bringing your own virtual network. When empty and virtualNetworkName is provided, the networking.bicep module provisions all networking resources and the subnet IDs are inferred from its outputs.')
param subnetId string = ''

@description('(Optional) The name of the subnet where the container instance will be deployed. Used when subnetId is provided (bring-your-own VNet). This subnet must allow outbound access to the Internet and to the subnet specified in subnetId and be delegated to the ACI service so that it can be used to deploy ACI resources. The subnet in property subnetId must allow inbound access from this subnet. See https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-json?tabs=bicep%2Cazure-powershell#containerinstancesubnetid-optional')
param containerInstanceSubnetId string = ''

@description('(Optional) Whether to deploy an Azure Bastion host. When false, the Bastion host, its NSG, and the AzureBastionSubnet are not created. Used only when virtualNetworkName is provided.')
param deployBastion bool = false

@description('(Optional) The SKU of the Azure Bastion host. Developer SKU is free-tier and does not require a public IP or dedicated subnet, but should NOT be used in production. Used only when virtualNetworkName is provided.')
@allowed(['Basic', 'Standard', 'Developer'])
param bastionSkuName string = 'Basic'

@description('(Optional) List of CIDR ranges allowed to connect to Azure Bastion on port 443. Defaults to all Internet traffic. Used only when virtualNetworkName is provided.')
param bastionAllowedCIDRs array = []

@description('(Optional) The staging resource group name that will be in the same subscription as the image template that will be used to build the image. If this field is empty, a resource group with a random name will be created. If the resource group specified in this field doesn\'t exist, it will be created with the same name. If the resource group specified exists, it must be empty and in the same region as the image template. The resource group created will be deleted during template deletion if this field is empty or the resource group specified doesn\'t exist, but if the resource group specified exists the resources created in the resource group will be deleted during template deletion and the resource group itself will remain. The user identity deploying the template needs to have Owner role assignment to this resource group. Each image template requires its own staging resource group.')
param stagingResourceGroupName string = ''

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

@description('Whether to pre-populate the storage account with example scripts for building images. When true, the deployment script uploads the example Entrypoint, Exitpoint, DeprovisioningScript, DownloadArtifacts and artifactsmetadata files to the scripts container.')
param prepopulateStorageWithExampleScripts bool = false

@description('(Optional) The name of the key vault where the secrets are stored.')
param keyVaultName string = ''

@description('(Optional) The names of the secrets stored in the key vault that you want to retrieve.')
param keyVaultSecretNames array = []

// Determine whether to use a VNet (either bring-your-own or provisioned)
var usePrivateNetworking = !empty(subnetId) || !empty(virtualNetworkName)
var provisionNetworking = empty(subnetId) && !empty(virtualNetworkName)

// Disable public network access on the storage account when private networking is used and example scripts are not pre-populated
var disableStoragePublicAccess = (usePrivateNetworking || provisionNetworking) && !prepopulateStorageWithExampleScripts

// When subnetId is provided (BYOV), use the provided parameters; otherwise, use the networking module outputs
var effectiveSubnetId = !empty(subnetId) ? subnetId : (provisionNetworking ? networking!.outputs.vmBuilderSubnetId : '')
var effectiveContainerInstanceSubnetId = !empty(subnetId)
  ? containerInstanceSubnetId
  : (provisionNetworking ? networking!.outputs.aciSubnetId : '')

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
}

resource stagingResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = if (!empty(stagingResourceGroupName)) {
  name: stagingResourceGroupName
  location: location
}

module networking 'networking.bicep' = if (provisionNetworking) {
  name: 'networking'
  scope: resourceGroup
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    storageAccountName: storageAccountName
    tags: tags
    bastionAllowedCIDRs: bastionAllowedCIDRs
    bastionSkuName: bastionSkuName
    deployBastion: deployBastion
  }
}

module associatedResources 'associatedresources.module.bicep' = {
  name: 'associatedResources'
  scope: resourceGroup
  params: {
    location: location
    storageAccountName: storageAccountName
    scriptsContainerName: scriptsContainerName
    appsContainerName: appsContainerName
    galleryName: galleryName
    imageDefinitionName: imageDefinitionName
    imageBuilderVMUserAssignedIdentityName: imageBuilderVMUserAssignedIdentityName
    galleryImageIdentifier: galleryImageIdentifier
    softDeleteOnGallery: softDeleteOnGallery
    userIdentityName: userIdentityName
    prepopulateStorageWithExampleScripts: prepopulateStorageWithExampleScripts
    disablePublicNetworkAccess: disableStoragePublicAccess
  }
}

module imageTemplateWithPublicStorage '../aib.module.bicep' = if (!usePrivateNetworking) {
  name: imageTemplateName
  scope: resourceGroup
  params: {
    location: location
    imageTemplateName: imageTemplateName
    scriptsContainerName: scriptsContainerName
    userImgBuilderIdentityId: associatedResources.outputs.userImgBuilderIdentityIdResourceId
    imageBuilderVMUserAssignedIdentityId: associatedResources.outputs.vmImgBuilderIdentityResourceId
    imageBuilderVMUserAssignedIdentityClientId: associatedResources.outputs.vmImgBuilderIdentityClientId
    imageSource: imageSource
    vmSkuSize: vmSkuSize
    subnetId: effectiveSubnetId
    stagingResourceGroupId: stagingResourceGroup.id
    onCustomizerError: onCustomizerError
    onValidationError: onValidationError
    buildTimeoutInMinutes: buildTimeoutInMinutes
    storageAccountBlobEndpoint: associatedResources.outputs.storageAccountPrimaryEndpointsBlob
    galleryImageId: associatedResources.outputs.galleryImageResourceId
    imageReplicationRegions: imageReplicationRegions
    subscriptionId: subscriptionId
    storageAccountName: storageAccountName
    artifactsMetadataPath: artifactsMetadataPath
    tags: tags
    imageTags: imageTags
    keyVaultName: keyVaultName
    keyVaultSecretNames: keyVaultSecretNames
  }
}

module imageTemplateWithPrivateStorage '../aib.module-private.bicep' = if (usePrivateNetworking) {
  name: imageTemplateName
  scope: resourceGroup
  params: {
    location: location
    imageTemplateName: imageTemplateName
    scriptsContainerName: scriptsContainerName
    userImgBuilderIdentityId: associatedResources.outputs.userImgBuilderIdentityIdResourceId
    imageBuilderVMUserAssignedIdentityId: associatedResources.outputs.vmImgBuilderIdentityResourceId
    imageBuilderVMUserAssignedIdentityClientId: associatedResources.outputs.vmImgBuilderIdentityClientId
    imageSource: imageSource
    vmSkuSize: vmSkuSize
    subnetId: effectiveSubnetId
    containerInstanceSubnetId: effectiveContainerInstanceSubnetId
    stagingResourceGroupId: stagingResourceGroup.id
    onCustomizerError: onCustomizerError
    onValidationError: onValidationError
    buildTimeoutInMinutes: buildTimeoutInMinutes
    storageAccountBlobEndpoint: associatedResources.outputs.storageAccountPrimaryEndpointsBlob
    galleryImageId: associatedResources.outputs.galleryImageResourceId
    imageReplicationRegions: imageReplicationRegions
    subscriptionId: subscriptionId
    storageAccountName: storageAccountName
    artifactsMetadataPath: artifactsMetadataPath
    tags: tags
    imageTags: imageTags
    keyVaultName: keyVaultName
    keyVaultSecretNames: keyVaultSecretNames
  }
}

module stagingResources 'stagingresources.module.bicep' = if (!empty(stagingResourceGroupName)) {
  name: 'stagingResources'
  scope: stagingResourceGroup
  params: {
    userImgBuilderIdentityIdResourceId: associatedResources.outputs.userImgBuilderIdentityIdResourceId
    userImgBuilderIdentityPrincipalId: associatedResources.outputs.userImgBuilderIdentityPrincipalId
    vmImgBuilderIdentityResourceId: associatedResources.outputs.vmImgBuilderIdentityResourceId
  }
}

output imageTemplateName string = imageTemplateName
