<#
.SYNOPSIS
Starts a process to run an installer with optional arguments.

.DESCRIPTION
The Start-ProcessForInstall function is used to execute an installer process. 
It takes the path to the installer and an optional list of arguments to pass to the installer. 
The function waits for the process to complete before returning.

.PARAMETER InstallerPath
The full path to the installer executable. This parameter is mandatory.

.PARAMETER ArgumentList
Optional arguments to pass to the installer. Defaults to an empty string if not provided.

.EXAMPLE
Start-ProcessForInstall -InstallerPath "C:\Installers\setup.exe"

This example runs the installer located at "C:\Installers\setup.exe" without any additional arguments.

.EXAMPLE
Start-ProcessForInstall -InstallerPath "C:\Installers\setup.exe" -ArgumentList "/silent /install"

This example runs the installer located at "C:\Installers\setup.exe" with the arguments "/silent /install".

.NOTES
This function uses the Start-Process cmdlet with the -Wait parameter to ensure the process completes before continuing.
#>
function Start-ProcessForInstall {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "The path to the installer")]
        $InstallerPath,
        [Parameter(HelpMessage = "The arguments to pass to the installer")]
        $ArgumentList = ""
    )

    Start-Process -FilePath $InstallerPath -ArgumentList $ArgumentList -Wait
}