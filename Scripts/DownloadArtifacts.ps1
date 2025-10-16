<#

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.DESCRIPTION
    An example on how to download through a managed identity the artifacts required to build an image.
.NOTES
    AUTHOR: Dominique St-Amand
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The subscription id which the Image Builder VM Managed Identity should connect to")]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true, HelpMessage = "The client id of the image builder VM Managed Identity")]
    [string]$IdentityClientId,        
    [Parameter(Mandatory = $true, HelpMessage = "The name of the storage account where the artifacts are located")]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "The path to the file containing the list of artifacts to download. Should follow the convention of container/file.ext")]
    [string]$ArtifactsMetadataPath,
    [Parameter(HelpMessage = "The path where the artifacts should be downloaded to")]
    [string]$ArtifactsDownloadPath = "c:\installers\artifacts"
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

if (Get-Module -Name Az.Accounts, Az.Storage -ListAvailable) {
    Write-Information "Az module is installed, importing..."
    Import-Module -Name Az.Accounts, Az.Storage
} else {
    Write-Information "Installing the Az module..."
    # PowerShellGet requires NuGet provider version '2.8.5.201' or newer to interact with NuGet-based repositories
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module -Name Az.Accounts, Az.Storage -AllowClobber -Scope CurrentUser -Repository PSGallery -Force
    Import-Module -Name Az.Accounts, Az.Storage
    Write-Information "Az module installed..."
}

try
{
    # Ensures that any credentials apply only to the execution of this script
    Disable-AzContextAutosave -Scope Process | Out-Null

    Write-Information "Logging in to Azure..."
    Connect-AzAccount -Identity -AccountId $IdentityClientId | Out-Null
    Set-AzContext -Subscription $SubscriptionId | Out-Null
    Write-Information "Logged in to Azure..."
}
catch {
    Write-Error -Message "Logging to Azure failed: $($_.Exception)"
    throw $_.Exception
}

if ((Test-Path -Path $ArtifactsDownloadPath) -eq $false) {
    New-Item -Path $ArtifactsDownloadPath -ItemType Directory | Out-Null
}

$storageAccountContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount -ErrorAction SilentlyContinue
if ($null -eq $storageAccountContext) {
    Write-Error -Message "The storage account $StorageAccountName was not found in the resource group $StorageAccountResourceGroupName or you do not have permission to access it."
    throw "The storage account $StorageAccountName was not found in the resource group $StorageAccountResourceGroupName or you do not have permission to access it."
}

$artifactsMetadataContainerName = $ArtifactsMetadataPath.Split("/")[0]
$artifactsMetadataBlobName = $ArtifactsMetadataPath.Split("/")[1]
if ([string]::IsNullOrEmpty($artifactsMetadataContainerName) -or [string]::IsNullOrEmpty($artifactsMetadataBlobName))
{
    Write-Error -Message "The ArtifactsMetadataPath parameter should be in the format container/blob.bicep"
    throw "The ArtifactsMetadataPath parameter should be in the format container/blob.bicep"
}

try {
    Write-Information "Downloading artifacts metadata..."
    Get-AzStorageBlobContent -Blob $artifactsMetadataBlobName `
                             -Container $artifactsMetadataContainerName `
                             -Destination $ArtifactsDownloadPath `
                             -Context $storageAccountContext `
                             -Force | Out-Null
}
catch {
    Write-Error -Message "Failed to download $ArtifactsMetadataPath from the storage account: $($_.Exception)"
    throw $_.Exception
}

# consider switching the approach to use AzCopy with Managed Identity if this becomes a bottleneck
# see https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-authorize-azure-active-directory#authorize-a-managed-identity
Write-Information "Downloading artifacts..."
$filesToDownload = Get-Content -Path (Join-Path -Path $ArtifactsDownloadPath -ChildPath $artifactsMetadataBlobName)
foreach ($item in $filesToDownload) {
    # skip comments
    if ($item.StartsWith("#")) {
        continue
    }
    $firstSlashIndex = $item.IndexOf("/")
    $containerName = $item.Substring(0, $firstSlashIndex)
    $blobName = $item.Substring($firstSlashIndex+1)

    try {
        # If the blobName is a wildcard, download all blobs in the container
        if ($blobName.EndsWith("*")) {
            if ($blobName.Length -eq 1 -and $blobName -eq "*") {
                $blobs = Get-AzStorageBlob -Container $containerName -Context $storageAccountContext
            }
            else {
                # blob supports wildcard (*) search, so we need to get all blobs that match the pattern
                $blobs = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $storageAccountContext
            }
            foreach ($blob in $blobs) {
                $actualBlobName = $blob.Name
                $destionationDirectory = [System.IO.Path]::GetDirectoryName("$ArtifactsDownloadPath\$containerName\$actualBlobName")
                if ((Test-Path -Path $destionationDirectory) -eq $false) {
                    New-Item -Path $destionationDirectory -ItemType Directory | Out-Null
                }
                Get-AzStorageBlobContent -Blob $actualBlobName `
                                        -Container $containerName `
                                        -Destination "$ArtifactsDownloadPath\$containerName\$actualBlobName" `
                                        -Context $storageAccountContext `
                                        -Force | Out-Null
                Write-Information "Downloaded $containerName/$actualBlobName"
            }
        }
        else {
            $actualBlobName = $blobName
            $destionationDirectory = [System.IO.Path]::GetDirectoryName("$ArtifactsDownloadPath\$containerName\$actualBlobName")
            if ((Test-Path -Path $destionationDirectory) -eq $false) {
                New-Item -Path $destionationDirectory -ItemType Directory | Out-Null
            }
            Get-AzStorageBlobContent -Blob $blobName `
                                    -Container $containerName `
                                    -Destination "$ArtifactsDownloadPath\$containerName\$actualBlobName" `
                                    -Context $storageAccountContext `
                                    -Force | Out-Null
            Write-Information "Downloaded $containerName/$blobName"
        }
    }
    catch {
        Write-Error -Message "Failed to download the file $containerName/$actualBlobName from the storage account: $($_.Exception)"
        throw $_.Exception
    }
}