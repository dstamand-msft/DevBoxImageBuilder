targetScope = 'resourceGroup'

@description('The location of the resources')
param location string

@description('The name of the image template')
param imageTemplateName string

@description('The full resource identifier of the user assigned identity associated to the image template')
param userImgBuilderIdentityId string

@description('Maximum duration to wait, in minutes, while building the image template (includes all customizations, validations, and distributions). Specify 0 to use the default in the Azure platform (4 hours). Defaults to 6 hours if not specified')
param buildTimeoutInMinutes int = 600

@description('	Size of the virtual machine used to build, customize and capture images.')
param vmSkuSize string = 'Standard_D4s_v3'

@description('(Optional) The name of the subnet where the virtual machine will be deployed. This is useful if you need to access private resources or on-premises resources.')
param subnetId string = ''

@description('The resource identifier of the user assigned identity for the Image builder VM, the user assigned identity for Azure Image Builder must have the "Managed Identity Operator" role assignment on all the user assigned identities for Azure Image Builder to be able to associate them to the build VM.')
param imageBuilderVMUserAssignedIdentityId string

@description('The source of the image to be used to create the image template. see https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/imagetemplates?pivots=deployment-language-bicep#imagetemplatesource-objects for more information.')
// example:
// type: 'PlatformImage'
// publisher: 'MicrosoftBizTalkServer'
// offer: 'BizTalk-Server'
// sku: '2020-Standard'
// version: 'latest'
param imageSource object

@description('(Optional) The staging resource group id in the same subscription as the image template that will be used to build the image. If this field is empty, a resource group with a random name will be created. If the resource group specified in this field doesn\'t exist, it will be created with the same name. If the resource group specified exists, it must be empty and in the same region as the image template. The resource group created will be deleted during template deletion if this field is empty or the resource group specified doesn\'t exist, but if the resource group specified exists the resources created in the resource group will be deleted during template deletion and the resource group itself will remain.')
param stagingResourceGroup string = ''

@description('The blob endpoint of the storage account that holds the scripts to be provisioned on the VM')
param storageAccountBlobEndpoint string

@description('The container in the storage account that holds the scripts to be provisioned on the VM')
param scriptContainerName string

@description('The resource identifier of the gallery image where the image will be stored.')
param galleryImageId string

@description('(Optional) The regions where the image will be replicated. The regions should exclude the region where the shared imaged gallery is deployed.')
param imageReplicationRegions array = []

@description('The subscription id where the managed identity of the provisioning VM will connect to.')
param subscriptionId string

@description('The storage account name where the scripts managed identity will connect to.')
param storageAccountName string

@description('The path to the artifacts metadata file in the storage account.')
param artifactsMetadataPath string

@description('(Optional) The name of the key vault where the secrets are stored.')
param keyVaultName string = ''

@description('(Optional) The secret names to be fetch from the keyvault and passed to the entrypoint script.')
param secretNames array = []

@description('(Optional) The tags to be associated with the image template.')
param tags object = {}

@description('(Optional) The tags to be associated with the image that will be created by the image template.')
param imageTags object = {}

var entryPointInlineScript = !empty(keyVaultName) && !empty(secretNames) ? '& "C:\\installers\\Entrypoint.ps1" -SubscriptionId ${subscriptionId} -KeyVaultName ${keyVaultName} -SecretNames ${join(secretNames, ',')} -Verbose' : '& "C:\\installers\\Entrypoint.ps1" -SubscriptionId ${subscriptionId} -Verbose'
var exitPointInlineScript = !empty(keyVaultName) && !empty(secretNames) ? '& "C:\\installers\\Exitpoint.ps1" -SubscriptionId ${subscriptionId} -KeyVaultName ${keyVaultName} -SecretNames ${join(secretNames, ',')} -Verbose' : '& "C:\\installers\\Entrypoint.ps1" -SubscriptionId ${subscriptionId} -Verbose'

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' = {
  name: imageTemplateName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userImgBuilderIdentityId}': {}
    }
  }
  properties: {
    // Image build timeout in minutes. Allowed values: 0-960. 0 means the default 240 minutes.
    buildTimeoutInMinutes: buildTimeoutInMinutes
    vmProfile: {
      vmSize: vmSkuSize
      osDiskSizeGB: 256
      // For the Image Builder Build VM to have permissions to authenticate with other services like Azure Key Vault in your subscription,
      // you must create one or more Azure User Assigned Identities that have permissions to the individual resources.
      // Azure Image Builder can then associate these User Assigned Identities with the Build VM. Customizer scripts running inside the Build VM can then fetch tokens
      // for these identities and interact with other Azure resources as needed.
      // Be aware, the user assigned identity for Azure Image Builder must have the "Managed Identity Operator" role assignment on all the user assigned identities
      // for Azure Image Builder to be able to associate them to the build VM.
      // see: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-json?tabs=bicep%2Cazure-powershell#user-assigned-identity-for-the-image-builder-build-vm
      userAssignedIdentities: [
        imageBuilderVMUserAssignedIdentityId
      ]
      vnetConfig: {
        subnetId: !empty(subnetId) ? subnetId : ''
      }
    }
    stagingResourceGroup: !empty(stagingResourceGroup) ? stagingResourceGroup : ''
    source: imageSource
    customize: [
      {
        type: 'File'
        name: 'Download the download artifacts script'
        destination: 'C:\\installers\\DownloadArtifacts.ps1'
        sourceUri: '${storageAccountBlobEndpoint}${scriptContainerName}/DownloadArtifacts.ps1'
      }
      {
        type: 'File'
        name: 'Download the entrypoint script'
        destination: 'C:\\installers\\Entrypoint.ps1'
        sourceUri: '${storageAccountBlobEndpoint}${scriptContainerName}/Entrypoint.ps1'
      }
      {
        type: 'File'
        name: 'Download the exitpoint script'
        destination: 'C:\\installers\\Exitpoint.ps1'
        sourceUri: '${storageAccountBlobEndpoint}${scriptContainerName}/Exitpoint.ps1'
      }
      {
        type: 'File'
        // see https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-json?tabs=json%2Cazure-powershell#generalize for more information
        // remove this customizer the moment the default sysprep command is fixed on the Azure platform in the Azure Image Builder service
        name: 'Override the built-in deprovisioning script as WindowsAzureTelemetryAgent was removed and combined into WindowsAzureGuestAgent'
        destination: 'C:\\DeprovisioningScript.ps1'
        sourceUri: '${storageAccountBlobEndpoint}${scriptContainerName}/DeprovisioningScript.ps1'
      }
      {
        type: 'PowerShell'
        name: 'Run the download artifacts script (entry)'
        inline: [
          '& "C:\\installers\\DownloadArtifacts.ps1" -SubscriptionId ${subscriptionId} -StorageAccountName ${storageAccountName} -ArtifactsMetadataPath ${artifactsMetadataPath}'
        ]
      }
      {
        type: 'PowerShell'
        name: 'Run VM customization script'
        inline: [
          entryPointInlineScript
        ]
        runElevated: true
        runAsSystem: true
        validExitCodes: [
          0
          // represents that a reboot is necessary
          3010
        ]
      }
      // example on how to filter the updates to be installed
      // {
      //   type: 'WindowsUpdate'
      //   name: 'Install all available updates excluding preview updates'
      //   searchCriteria: 'IsInstalled=0'
      //   filters: [
      //     'exclude:$_.Title -like \'*Preview*\' -or $_.Title -like \'*KB5040442*\''
      //     'include:$true'
      //   ]
      //   updateLimit: 20
      // }
      {
        type: 'WindowsUpdate'
        name: 'Install all available updates excluding preview updates'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'*Preview*\''
          'include:$true'
        ]
        updateLimit: 20
      }
      {
        type: 'PowerShell'
        name: 'Run VM customization script (exit)'
        inline: [
          exitPointInlineScript
        ]
        runElevated: true
        runAsSystem: true
        validExitCodes: [
          0
          // represents that a reboot is necessary
          3010
        ]
      }
      {
        type: 'PowerShell'
        name: 'Run VM customization before sysprep script'
        inline: [
          exitPointInlineScript
        ]
        runElevated: true
        runAsSystem: true
        validExitCodes: [
          0
          // represents that a reboot is necessary
          3010
        ]
      }
    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: galleryImageId
        runOutputName: '${last(split(galleryImageId, '/'))}-DevBoxGoldenImage'
        artifactTags: imageTags
        replicationRegions: imageReplicationRegions
      }
    ]
  }
}
