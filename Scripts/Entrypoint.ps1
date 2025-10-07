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
    [Parameter(HelpMessage = "(Optional) The name of the key vault where the secrets are stored")]
    [string]$KeyVaultName,
    [Parameter(HelpMessage = "(Optional) The secret names to pass to the customization scripts")]
    [Array]$SecretNames
)

$InformationPreference = "Continue"

Write-Verbose "[Entrypoint] Executing the customizations"
    # call your sub customization scripts here with arguments as necessary such as:
    # -SubscriptionId $SubscriptionId -KeyVaultName $KeyVaultName -SecretNames $SecretNames
    # example:
    # & 'C:\installers\artifacts\customization-scripts\ScriptA.ps1' -SubscriptionId $SubscriptionId -KeyVaultName $KeyVaultName -SecretNames $SecretNames
# add any customizations here that should be ran regardless of the image type

try{
    $artifactsPath = "C:\installers\artifacts"
}
catch {
    Write-Error "An error occurred during customization (Entrypoint): $_"
    exit 1
}

Write-Information "[Entrypoint] Customization completed successfully."