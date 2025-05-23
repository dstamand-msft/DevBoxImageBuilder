<#

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.DESCRIPTION
    An example PowerShell script which runs an Azure Image Builder Template.
.NOTES
    AUTHOR: Dominique St-Amand
#>

#Requires -Modules Az.Accounts, Az.Storage, Az.ImageBuilder, Az.ContainerInstance
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "The name of the resource group where the image template is deployed")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "The name of the image template, from the template deployment.")]
    [ValidateNotNullOrEmpty()]
    [string]$ImageTemplateName,
    [Parameter(HelpMessage = "Determines whether to output the logs while the image is being built. Default is false.")]
    [switch]$OutputLogs,
    [Parameter(HelpMessage = "Determines whether to keep the image builder template for debugging when the image has successfully built. Default is false.")]
    [bool]$KeepImageBuilderTemplate = $false,
    [Parameter(HelpMessage = "The seconds to wait between each check of the image template status. Default is 300 seconds.")]
    [int]$SleepTime = 300
)

Write-Output "Running image template..."
Invoke-AzResourceAction `
    -ResourceName $ImageTemplateName `
    -ResourceGroupName $ResourceGroupName `
    -ResourceType Microsoft.VirtualMachineImages/imageTemplates `
    -ApiVersion "2024-02-01" `
    -Action Run `
    -Force

$containerName = "packerizercontainer"
$canOutputLogs = $true

# Wait for the template to be done and then delete the template resource
while ($true) {
    $imageBuilderTemplate = Get-AzImageBuilderTemplate -Name $ImageTemplateName -ResourceGroupName $ResourceGroupName
    $output = $imageBuilderTemplate | Select-Object -Property Name, LastRunStatusRunState, LastRunStatusRunSubState, LastRunStatusMessage
    if ($output.LastRunStatusRunState -eq "Succeeded") {
        if ($KeepImageBuilderTemplate) {
            Write-Output "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template has succeeded. Keeping the image template..."
        }
        else {
            Write-Output "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template has succeeded. Removing the image template..."
            Remove-AzImageBuilderTemplate -Name $ImageTemplateName -ResourceGroupName $ResourceGroupName | Out-Null
        }
        break
    }
    elseif ($output.LastRunStatusRunState -eq "Failed") {
        Write-Error "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template has failed. Message: $($output.LastRunStatusMessage)"
        throw "Image template has failed. Message: $($output.LastRunStatusMessage)"
    }
    elseif ($output.LastRunStatusRunState -eq "Canceled") {
        Write-Error "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template has been canceled."
        throw "Image template has been canceled."
    }

    Write-Output "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template is still running with status: '$($output.LastRunStatusRunState)$(![string]::IsNullOrEmpty($output.LastRunStatusRunSubState) ? " - $($output.LastRunStatusRunSubState)" : '')'. Sleeping for $SleepTime seconds..."
    if ($OutputLogs -and $canOutputLogs -and $output.LastRunStatusRunState -eq "Running" -and $output.LastRunStatusRunSubState -eq "Building") {
        if (![string]::IsNullOrEmpty($imageBuilderTemplate.StagingResourceGroup)) {
            $stagingResourceGroupName = $imageBuilderTemplate.StagingResourceGroup.Split("/")[-1]
            $containerInstanceGroup = Get-AzResource -ResourceGroupName $stagingResourceGroupName -ResourceType "Microsoft.ContainerInstance/containerGroups" -ErrorAction SilentlyContinue
            if ($null -eq $containerInstanceGroup) {
                Write-Warning "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] No container instance group found in the staging resource group yet. Log output will not be available yet."
            }
            else {
                $containerInstanceGroupName = $containerInstanceGroup.Name
                $containerInstanceGroup = Get-AzResource -ResourceGroupName $stagingResourceGroupName -ResourceType "Microsoft.ContainerInstance/containerGroups"
                $logs = Get-AzContainerInstanceLog -ResourceGroupName $stagingResourceGroupName -ContainerGroupName $containerInstanceGroupName -ContainerName $containerName -Tail 100 -ErrorAction SilentlyContinue
                if ($null -ne $logs) {
                    Write-Output "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Image template logs:"
                    Write-Output $logs
                }
                else {
                    Write-Output "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] No logs available yet."
                }
            }
        }
        else {
            Write-Warning "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] No staging resource group found. Cannot output logs."
            $canOutputLogs = $false
        }
    }

    Start-Sleep -Seconds $SleepTime
}