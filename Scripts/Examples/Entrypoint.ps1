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

$artifactsPath = "C:\installers\artifacts"
$toolsPath = "C:\Tools"

. "$artifactsPath\scripts\HelperFunctions.ps1"

Write-Verbose "[Entrypoint] Setting the Tools directory"
New-Item -Path $toolsPath -ItemType Directory -Force | Out-Null

$bicepCLI = Join-Path $artifactsPath "apps\Bicep\Bicep-v0.35.1.exe"
$bicepProductVersion = (Get-Item $bicepCLI).VersionInfo.ProductVersion
Write-Verbose "[Entrypoint] Copying Bicep CLI (version $bicepProductVersion)"
Copy-Item $bicepCLI -Destination (Join-Path $toolsPath "Bicep.exe") -Force
Unblock-File -Path (Join-Path $toolsPath "Bicep.exe") -Force

Write-Verbose "[Entrypoint] Install Git for Windows (latest version)"
$git_url = "https://api.github.com/repos/git-for-windows/git/releases/latest"
$gitItems = Invoke-RestMethod -Method Get -Uri $git_url
$gitArtifact = $gitItems | Foreach-Object { $item = $_; $item.assets | Where-Object { $_.name -like "*64-bit.exe"} | Select-Object name, browser_download_url }
$installer = Join-Path $artifactsPath "apps\git\$($gitArtifact.name)"
Invoke-WebRequest -Uri $gitArtifact.browser_download_url -OutFile $installer

# see https://gitforwindows.org/silent-or-unattended-installation.html
$gitSetupIniContent = @"
[Setup]
Lang=default
Dir=C:\Program Files\Git
Group=Git
NoIcons=0
SetupType=default
Components=gitlfs,assoc,assoc_sh,windowsterminal
Tasks=
EditorOption=Notepad
CustomEditorPath=
DefaultBranchOption=main
PathOption=Cmd
SSHOption=OpenSSH
TortoiseOption=false
CURLOption=WinSSL
CRLFOption=CRLFCommitAsIs
BashTerminalOption=MinTTY
GitPullBehaviorOption=Merge
UseCredentialManager=Enabled
PerformanceTweaksFSCache=Enabled
EnableSymlinks=Disabled
EnablePseudoConsoleSupport=Disabled
EnableFSMonitor=Disabled
"@
Write-Output $gitSetupIniContent | Out-File -FilePath "$(Join-Path $artifactsPath "apps\git\git-install-options.ini")" -Encoding ASCII
Start-ProcessForInstall -InstallerPath $installer -ArgumentList "/VERYSILENT /NOCANCEL /NORESTART /LOADINF=$(Join-Path $artifactsPath "apps\git\git-install-options.ini")"

$dockerDesktopInstaller = Join-Path $artifactsPath "apps\Docker\DockerDesktopInstaller-v4.41.2.191736.exe"
$dockerProductVersion = (Get-Item $dockerDesktopInstaller).VersionInfo.ProductVersion
Write-Verbose "[Entrypoint] Install Docker Desktop (version $dockerProductVersion)"
Start-Process $dockerDesktopInstaller -ArgumentList "install", "--accept-license", "--quiet", "--always-run-service" -Wait

[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";C:\Tools",
    [EnvironmentVariableTarget]::Machine
)

Write-Information "[Entrypoint] Customization completed successfully."