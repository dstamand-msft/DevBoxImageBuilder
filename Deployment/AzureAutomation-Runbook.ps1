<#

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.DESCRIPTION
    An example Azure Automatio runbook which creates and runs an Azure Image Builder Template using the Managed Identity of the Azure Automation Account.
    The bicep template and parameters files are downloaded from a storage account.
.NOTES
    AUTHOR: Dominique St-Amand
#>

#Requires -Modules Az.Accounts, Az.Storage, Az.ImageBuilder
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "The subscription id which the Account should connect to")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true, HelpMessage = "The name of the resource group where the storage account, of the bicep artifacts, is located")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "The name of the storage account where the bicep artifacts reside")]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "The path to the Bicep template file to use as the AIB template in the storage account. Should be container/file.bicep.")]
    [ValidateNotNullOrEmpty()]
    [string]$AIBTemplateBicepTemplatePath,
    [Parameter(Mandatory = $true, HelpMessage = "The path to the Bicep parameters file to use as the AIB template in the storage account. Should be container/file.parameters.json. File should be parametrized with the correct value")]
    [ValidateNotNullOrEmpty()]
    [string]$AIBTemplateBicepParametersPath,
    [Parameter(HelpMessage = "Determines whether the script is ran using ManagedIdentity or not. Default is true.")]
    [bool]$WithManagedIdentity = $true,
    [Parameter(HelpMessage = "Determines whether to keep the image builder template for debugging or not when the image has successfully built. Default is false.")]
    [bool]$KeepImageBuilderTemplate = $false
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

try
{
    if (!(Get-AzContext | Out-Null)) {
        Write-Output "Logging in to Azure..."
        if ($WithManagedIdentity) {
            Connect-AzAccount -Identity
        }
        else {
            Connect-AzAccount
        }
    }
    Write-Output "Logged in to Azure..."
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}
catch {
    Write-Error -Message "Loggging to Azure failed: $($_.Exception)"
    throw $_.Exception
}

# Look into the windows $PATH environment variable to see if bicep is installed.
# if it is not installed, download it from the GitHub release page, https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe and add it to the PATH
if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
    Write-Output "Bicep is not installed. Downloading and installing it..."
    if (!(Test-Path -Path "$env:TEMP/tools")) {
        New-Item -Path "$env:TEMP/tools" -ItemType Directory -Force | Out-Null
    }
    $bicepPath = Join-Path -Path $env:TEMP -ChildPath "tools/bicep.exe"
    Invoke-WebRequest -Uri "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe" -OutFile $bicepPath
    $env:Path = $env:Path + ";" + ([System.IO.Path]::GetDirectoryName($bicepPath))
}

$storageAccountContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount -ErrorAction SilentlyContinue
if ($null -eq $storageAccountContext) {
    Write-Error -Message "The storage account $StorageAccountName was not found in the resource group $ResourceGroupName or you do not have permission to access it."
    throw "The storage account $StorageAccountName was not found in the resource group $ResourceGroupName or you do not have permission to access it."
}

$filesDirectory = [System.IO.Path]::GetTempPath()
$templateContainerName = $AIBTemplateBicepTemplatePath.Split("/")[0]
$templateBlobName = $AIBTemplateBicepTemplatePath.Split("/")[1]
$parametersContainerName = $AIBTemplateBicepParametersPath.Split("/")[0]
$parametersBlobName = $AIBTemplateBicepParametersPath.Split("/")[1]

if ([string]::IsNullOrEmpty($templateContainerName) -or [string]::IsNullOrEmpty($templateBlobName))
{
    Write-Error -Message "The AIBTemplateBicepTemplatePath parameter should be in the format container/blob.bicep"
    throw "The AIBTemplateBicepTemplatePath parameter should be in the format container/blob.bicep"
}

if ([string]::IsNullOrEmpty($parametersContainerName) -or [string]::IsNullOrEmpty($parametersBlobName))
{
    Write-Error -Message "The AIBTemplateBicepParametersPath parameter should be in the format container/blob.parameters.json"
    throw "The AIBTemplateBicepParametersPath parameter should be in the format container/blob.parameters.json"
}

try {
    # download the bicep template files and overwrite if they already exist locally
    Get-AzStorageBlobContent -Blob $templateBlobName -Container $templateContainerName -Destination $filesDirectory -Context $storageAccountContext -Force | Out-Null
    $moduleTemplateBlobName = "$([System.IO.Path]::GetFileNameWithoutExtension($templateBlobName)).module.bicep"
    Get-AzStorageBlobContent -Blob $moduleTemplateBlobName -Container $templateContainerName -Destination $filesDirectory -Context $storageAccountContext -Force | Out-Null
}
catch {
    Write-Error -Message "Failed to download the Bicep template files from the storage account: $($_.Exception)"
    throw $_.Exception
}

try {
    Get-AzStorageBlobContent -Blob $parametersBlobName -Container $parametersContainerName -Destination $filesDirectory -Context $storageAccountContext -Force | Out-Null
}
catch {
    Write-Error -Message "Failed to download the Bicep parameters file from the storage account: $($_.Exception)"
    throw $_.Exception
}

$aibTemplatePath = Join-Path -Path $filesDirectory -ChildPath $templateBlobName
$aibParametersTemplatePath = Join-Path -Path $filesDirectory -ChildPath $parametersBlobName

Write-Debug "Checking if the ImageTemplate already exist, if so deleting it..."
$imageTemplate = Get-AzImageBuilderTemplate -Name $imageTemplateName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ($null -ne $imageTemplate) {
    Write-Output "ImageTemplate already exists. Deleting it..."
    Remove-AzImageBuilderTemplate -Name $imageTemplateName -ResourceGroupName $ResourceGroupName | Out-Null
}

Write-Output "Provisioning resources..."
$deployment = New-AzResourceGroupDeployment -Name "WVDImageTemplate-$ImageType" `
                              -ResourceGroupName $ResourceGroupName `
                              -TemplateFile $aibTemplatePath `
                              -TemplateParameterFile $aibParametersTemplatePath `
                              -Verbose `
                              -ErrorAction Stop

Write-Output "Resources provisioned"

$imageTemplateName = $deployment.Outputs.imageTemplateName.Value

Write-Output "Running image template..."
Invoke-AzResourceAction `
   -ResourceName $imageTemplateName `
   -ResourceGroupName $ResourceGroupName `
   -ResourceType Microsoft.VirtualMachineImages/imageTemplates `
   -ApiVersion "2024-02-01" `
   -Action Run `
   -Force

# Wait for the template to be done and then delete the template resource
while ($true) {
    $output = Get-AzImageBuilderTemplate -Name $imageTemplateName -ResourceGroupName $ResourceGroupName | Select-Object -Property Name, LastRunStatusRunState, LastRunStatusRunSubState, LastRunStatusMessage
    if ($output.LastRunStatusRunState -eq "Succeeded") {
        if ($KeepImageBuilderTemplate) {
            Write-Output "Image template has succeeded. Keeping the image template..."
        }
        else {
            Write-Output "Image template has succeeded. Removing the image template..."
            Remove-AzImageBuilderTemplate -Name $imageTemplateName -ResourceGroupName $ResourceGroupName | Out-Null
        }
        break
    }
    elseif ($output.LastRunStatusRunState -eq "Failed") {
        Write-Error "Image template has failed. Message: $($output.LastRunStatusMessage)"
        throw "Image template has failed. Message: $($output.LastRunStatusMessage)"
    }
    elseif ($output.LastRunStatusRunState -eq "Canceled") {
        Write-Error "Image template has been canceled."
        throw "Image template has been canceled."
    }
    
    Write-Output "Image template is still running with status: '$($output.LastRunStatusRunState) - $($output.LastRunStatusRunSubState)'. Sleeping for 5 minutes..."
    Start-Sleep -Seconds 300
}