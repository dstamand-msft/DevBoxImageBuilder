# Azure Image Builder solution for creating custom VM images for Dev Box

## Architecture

![Architecture](Architecture.png "Architecture")

## Pre-requesites

- You need to have the resource provider `Microsoft.VirtualMachineImages` on the subscription enabled
- Bicep to deploy the resources
- If you are providing a subnet:
  - please make sure the user managed identity of the image builder has the following [permissions](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-permissions-powershell#permission-to-customize-images-on-your-virtual-networks) for the vnet:
     - Microsoft.Network/virtualNetworks/read
     - Microsoft.Network/virtualNetworks/subnets/join/action
  - Disable the Private Service Policy on the subnet. See the [documentation](https://learn.microsoft.com/en-us/azure/private-link/disable-private-link-service-network-policy?tabs=private-link-network-policy-powershell) for more information.
    ```powershell
    $subnet = 'default'

    $net = @{
        Name = 'myVnet'
        ResourceGroupName = 'myResourceGroup'
    }
    $vnet = Get-AzVirtualNetwork @net

    ($vnet | Select -ExpandProperty subnets | Where-Object {$_.Name -eq $subnet}).privateLinkServiceNetworkPolicies = "Disabled"

    $vnet | Set-AzVirtualNetwork
    ```
- The proper [permissions](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-permissions-powershell#allow-vm-image-builder-to-distribute-images) to distribute images on the compute gallery (formally known as Shared Image Gallery (SIG))

## Determining the images

Dev Box requires images. For ease of use, you can start with the base images that are available within dev box.<br/>
To list available images in Dev Box, use the following command:

```shell
az devcenter admin image list --dev-center-name name --resource-group rgname --query "[].name"
```

The output should be something like the following:

```json
[
  "microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc-os",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc-m365",
  "microsoftwindowsdesktop_windows-ent-cpc_win10-22h2-ent-cpc-m365",
  "microsoftvisualstudio_visualstudio2019plustools_vs-2019-ent-general-win11-m365-gen2",
  "microsoftvisualstudio_visualstudio2019plustools_vs-2019-pro-general-win11-m365-gen2",
  "microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win11-m365-gen2",
  "microsoftvisualstudio_visualstudioplustools_vs-2022-pro-general-win11-m365-gen2",
  "microsoftvisualstudio_visualstudio2019plustools_vs-2019-ent-general-win10-m365-gen2",
  "microsoftvisualstudio_visualstudio2019plustools_vs-2019-pro-general-win10-m365-gen2",
  "microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win10-m365-gen2",
  "microsoftvisualstudio_visualstudioplustools_vs-2022-pro-general-win10-m365-gen2",
  "microsoftvisualstudio_windowsplustools_base-win11-gen2",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-23h2-ent-cpc-m365",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-23h2-ent-cpc",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc",
  "microsoftwindowsdesktop_windows-ent-cpc_win10-22h2-ent-cpc",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-24h2-ent-cpc-m365",
  "microsoftwindowsdesktop_windows-ent-cpc_win11-24h2-ent-cpc"
]
```

To use the Image Builder, you do need to translate this to the equivalent "ARM" object, that is an [ImageTemplateSource](https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/imagetemplates?pivots=deployment-language-bicep#imagetemplatesource-objects). You can use the `HelperScripts/Get-AzImageInfo.ps1` PowerShell script to help you with this.<br/>

### Example:
For instance, if you would want to convert the Dev Box image `microsoftwindowsdesktop_windows-ent-cpc_win11-24h2-ent-cpc`, the ImageSourceTemplate equivalent would be:

```json
{
  "sku": "win11-24h2-ent-cpc",
  "publisher": "MicrosoftWindowsDesktop",
  "version": "latest",
  "offer": "windows-ent-cpc"
}
```

## Customizers tweaks

You may want to add the `sha256Checksum` property to the customizers in `aib.module.bicep` to make sure that your scripts aren't tempered with. To get the hash, you can use the following PowerShell CmdLet:

```powershell
(Get-FileHash -Path .\Scripts\DownloadArtifacts.ps1 -Algorithm Sha256).Hash
```

## Deployment

You can deploy this solution using 3 ways:
- Azure DevOps, using the `azure-pipeline.yaml` file
- GitHub Actions, using the `github-action.yaml`
- Azure Automation Account, using the `AzureAutomation-Runbook.ps1` file