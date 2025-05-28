<#
.SYNOPSIS
    Automates post-setup tasks for DevBox environments by creating and registering a scheduled task that runs a setup script at user logon.

.DESCRIPTION
    This script creates a folder in ProgramData for the specified organization, writes a post-setup PowerShell script to that folder, and registers a scheduled task to execute the script at user logon with SYSTEM privileges. The setup script adds the current user to the 'docker-users' group, logs actions, deletes the scheduled task after execution, notifies the user, and logs off the user to complete setup.

.PARAMETER OrganizationName
    The name of your organization. Used to create a folder in ProgramData for storing post-setup scripts and logs. This parameter is mandatory.

.EXAMPLE
    .\DevBoxPostSetupTasks.ps1 -OrganizationName "Contoso"

    Runs the script, creating the necessary folder and scheduled task for the organization "Contoso".

.NOTES
    - Requires administrative privileges.
    - The scheduled task runs as SYSTEM at user logon and deletes itself after execution.
    - The user will be logged off 30 seconds after the script runs to complete system setup.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Your organization name. Used to create the folder in ProgramData for the post-setup scripts and logs.")]
    [string]$OrganizationName = "MyOrganization"
)

$taskName = "DevBoxPostSetup"

$programDataOrgPath = Join-Path -Path $env:ProgramData -ChildPath $OrganizationName
$scriptPath = Join-Path -Path $programDataOrgPath -ChildPath "$taskName.ps1"

if (!(Test-Path -Path $programDataOrgPath)) {
    New-Item -Path $programDataOrgPath -ItemType Directory -Force | Out-Null
}

# Write your setup script
@"
`$logFile = `$(Join-Path `"$programDataOrgPath`" "DevBoxPostSetup.log")
Start-Transcript -Path `$logFile -IncludeInvocationHeader

`Write-Output "[`$(Get-Date -Format `"yyyy-MM-dd HH:mm:ss`")] Adding user `$env:USERNAME to docker-users group`"
Add-LocalGroupMember -Group `"docker-users`" -Member `$env:USERNAME

# Delete the task after execution
Unregister-ScheduledTask -TaskName `"$taskName`" -Confirm:`$false

`Write-Output "[`$(Get-Date -Format `"yyyy-MM-dd HH:mm:ss`")] Setup script executed for user: `$env:USERNAME`"

cmd /c msg * "You will be logged off in 30 seconds to complete system setup. Please log in again."
Start-Sleep -Seconds 30
Stop-Transcript

shutdown /l
"@ | Set-Content -Path $scriptPath -Encoding UTF8 -Force

Write-Output ">>> Post-setup script created at: $scriptPath"

Write-Output ">>> Scheduled task `"$taskName`" will run the script at user logon."
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -NonInteractive"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal
Write-Output ">>> Scheduled task `"$taskName`" registered successfully."