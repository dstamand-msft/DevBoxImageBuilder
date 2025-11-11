<#

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.DESCRIPTION
    An example on to call extra customization scripts
.NOTES
    AUTHOR: Dominique St-Amand
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The subscription where to connect to. It is required for customization scripts that need to connect to Azure resources, in case you need to use Azure CmdLets.")]
    [string]$SubscriptionId,    
    [Parameter(HelpMessage = "(Optional) The name of the key vault where the secrets, certificates and keys are stored. Use the KeyVault Az Module to interact with the Key Vault from within the customization scripts.")]
    [string]$KeyVaultName
)

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

try {
    Write-Verbose "[ExitPoint] Executing the customizations"

    $artifactsPath = "C:\installers\artifacts"

    & "$artifactsPath\scripts\DevBoxPostSetupTasks.ps1" -OrganizationName "Contoso"

    Write-Verbose "[ExitPoint] Cleaning up the installers directory"
    Remove-Item -Path "C:\installers" -Recurse -Force

    Write-Information "[ExitPoint] Customization completed successfully."
}
catch {
    Write-Error "An error occurred during cleanup (Exitpoint): $_"
    exit 1
}