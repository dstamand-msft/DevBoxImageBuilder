[CmdLetBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage = "The path to the bicep deployment file.")]
    [ValidateNotNullOrWhiteSpace()]
    [string]$DeploymentBicepFilePath,
    [Parameter(Mandatory=$true, HelpMessage = "The path to the bicep parameters file.")]
    [ValidateNotNullOrWhiteSpace()]
    [string]$ParametersFilePath,
    [Parameter(Mandatory=$true, HelpMessage = "The path to the git repository to compare against.")]
    [ValidateNotNullOrWhiteSpace()]
    [string]$GitRepositoryPath
)

try {
    $deploymentARMFileProcess = Start-Process -FilePath "bicep" -ArgumentList "build `"$DeploymentBicepFilePath`" --outdir `"$env:TEMP`"" -NoNewWindow -PassThru -Wait
    if ($deploymentARMFileProcess.ExitCode -ne 0) {
        throw "Bicep build failed with exit code $($deploymentARMFileProcess.ExitCode)"
    }

    $deploymentARMFile = Join-Path -Path $env:TEMP -ChildPath $([System.IO.Path]::GetFileNameWithoutExtension($DeploymentBicepFilePath) + ".json")

    $arm = Get-Content -Raw $deploymentARMFile | ConvertFrom-Json

    $filesToVerify = @($DeploymentBicepFilePath)
    $vmImageTemplate = $arm.resources[0].properties.template.resources | Where-Object { $_.type -eq "Microsoft.VirtualMachineImages/imageTemplates" }
    $fileCustomizations = $vmImageTemplate.properties.customize | Where-Object { $_.type -eq "File" }
    $fileCustomizationsDestinations = $fileCustomizations | Select-Object -ExpandProperty destination | ForEach-Object { [System.IO.Path]::GetFileName($_) }
    foreach ($fileName in $fileCustomizationsDestinations) {
        $filesToVerify += $fileName
    }

    # check if the current commit has changes vs the last commit in the git repository
    $gitDiff = & git -C `"$GitRepositoryPath`" diff --name-only HEAD~1 HEAD
    if ($gitDiff.Length -ne 0) {
        Write-Host "The following files have changes compared to the last commit:"
        Write-Host $gitDiff

        # NOTE: the script does not take in considering files that have the same name but reside in different directories.
        $changedFiles = @()
        foreach ($fileToVerify in $filesToVerify) {
            if ($gitDiff -contains $fileToVerify) {
                $changedFiles += $fileToVerify
            }
        }

        if ($changedFiles.Length -gt 0) {
            Write-Host "The following files from the deployment have changes compared to the last commit:"
            Write-Host $changedFiles

            return $TRUE
        }
        else {
            Write-Host "No changes detected in the specified files ($($filesToVerify -join ',')) compared to the last commit."
        }
    }
    else {
        Write-Host "No changes detected in the specified files ($($filesToVerify -join ',')) compared to the last commit."
    }

    return $FALSE
}
catch {
    Write-Error "An error occurred while getting validating the changes: $($_.Exception.Message)"
    exit 1
}