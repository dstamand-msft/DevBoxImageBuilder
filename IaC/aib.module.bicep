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

@description('The blob endpoint of the storage account that holds the scripts to be provisioned on the VM')
param storageAccountBlobEndpoint string

@description('The container in the storage account that holds the scripts to be provisioned on the VM')
param scriptContainerName string

@description('The resource identifier of the gallery image where the image will be stored.')
param galleryImageId string

@description('The regions where the image will be replicated. Defaults to francecentral, westindia and eastus.')
param imageReplicationRegions array = [
  'francecentral'
  'westindia'
  'eastus'
]

@description('The subscription id where the managed identity of the provisioning VM will connect to.')
param subscriptionId string

@description('The storage account name where the scripts managed identity will connect to.')
param storageAccountName string

@description('The path to the artifacts metadata file in the storage account.')
param artifactsMetadataPath string

@description('The name of the key vault where the secrets are stored.')
param keyVaultName string

@description('The secret names to be fetch from the keyvault and passed to the entrypoint script.')
param secretNames array

@description('The tags to be associated with the image template.')
param tags object = {}

@description('The tags to be associated with the image that will be created by the image template.')
param imageTags object = {}

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2022-02-14' = {
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
    }
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
        // see https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-json?tabs=json%2Cazure-powershell#generalize for more information
        // remove this customizer the moment the default sysprep command is fixed on the Azure platform in the Azure Image Builder service
        name: 'Override the built-in deprovisioning script as WindowsAzureTelemetryAgent was removed and combined into WindowsAzureGuestAgent'
        destination: 'C:\\DeprovisioningScript.ps1'
        sourceUri: '${storageAccountBlobEndpoint}${scriptContainerName}/DeprovisioningScript.ps1'
      }
      {
        type: 'PowerShell'
        name: 'Run the download artifacts script'
        inline: [
          '& "C:\\installers\\DownloadArtifacts.ps1" -SubscriptionId ${subscriptionId} -StorageAccountName ${storageAccountName} -ArtifactsMetadataPath ${artifactsMetadataPath}'
        ]
      }
      {
        type: 'PowerShell'
        name: 'Run VM customization script'
        inline: [
          '& "C:\\installers\\Entrypoint.ps1" -SubscriptionId ${subscriptionId} -KeyVaultName ${keyVaultName} -SecretNames ${join(secretNames, ',')} -Verbose'
        ]
        runElevated: true
        runAsSystem: true
        validExitCodes: [
          0
          // represents that a reboot is necessary
          3010
        ]
      }
      // bug with the AIB Service and Packer. Fix to be expected mid august. Use image version "22631.3737.240611" for windows 11 23h along with the following customizer
      {
        type: 'PowerShell'
        name: 'SetUUSFeatureOverride'
        inline: [
          '$uusKey = "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FeatureManagement\\Overrides\\4\\1931709068"'
          'if (Test-Path $uusKey) {'
          ' if ((Get-ItemProperty -Path $uusKey -Name \'EnabledState\').EnabledState -ne 1) {'
          '   Set-ItemProperty -Path $uusKey -Name \'EnabledState\' -Value 1 -Force'
          '   Write-Output "UUS Feature override (1931709068) EnabledState changed to 1"'
          ' }'
          '}'
        ]
        runAsSystem: true
        runElevated: true
      }
      {
        type: 'WindowsUpdate'
        name: 'Install all available updates excluding preview updates'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'*Preview*\' -or $_.Title -like \'*KB5040442*\''
          'include:$true'
        ]
        updateLimit: 20
      }
      {
        type: 'PowerShell'
        name: 'Remove artifacts and temporary files'
        inline: [
          'Remove-Item -Path "C:\\installers" -Recurse -Force'
          'Remove-Item -Path "C:\\temp" -Recurse -Force'
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
