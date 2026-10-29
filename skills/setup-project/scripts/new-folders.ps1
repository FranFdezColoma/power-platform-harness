<#
.SYNOPSIS
    Creates the folder tree of a new Power Platform / Dynamics 365 CE repository.

.DESCRIPTION
    Creates the folders the standards expect under -TargetPath, and a .gitkeep in each leaf
    folder that would otherwise stay empty, because git does not track empty folders:

        src/PowerPlatform/Plugins
        src/PowerPlatform/CustomAPIs
        src/PowerPlatform/WebResources/<ProjectName>.WebResources/<prefix>_/src/{js,html,css,icons}

    It only creates folders and empty .gitkeep files. It never overwrites or deletes anything,
    writes no template content and talks to nothing but the file system, so running it twice
    changes nothing the second time.

.EXAMPLE
    ./new-folders.ps1 -ProjectName Northwind -PublisherPrefix nwc -DryRun

.EXAMPLE
    ./new-folders.ps1 -ProjectName Northwind -PublisherPrefix nwc -TargetPath C:\repos\northwind
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherPrefix,

    [string]$TargetPath = (Get-Location).Path,

    # Print what would be created and write nothing.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Failures are one line on stderr with a non-zero exit code: the caller is usually an agent, and
# a PowerShell exception dump buries the actual problem.
function Stop-WithError {
    param([string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

# Validate before touching the file system. -cnotmatch, not -notmatch: PowerShell matches
# case-insensitively by default, which would let an uppercase prefix through.
if ($ProjectName -cnotmatch '^[A-Za-z][A-Za-z0-9]*$') {
    Stop-WithError "ProjectName '$ProjectName' is invalid. It names the WebResources project, so it must start with a letter and contain letters and digits only."
}

if ($PublisherPrefix -cnotmatch '^[a-z][a-z0-9]{1,7}$') {
    Stop-WithError "PublisherPrefix '$PublisherPrefix' is invalid. A Dataverse customization prefix is 2 to 8 lowercase alphanumeric characters and starts with a letter."
}

# Dataverse rejects any prefix that starts with mscrm, not only mscrm itself.
if ($PublisherPrefix.StartsWith('mscrm')) {
    Stop-WithError "PublisherPrefix '$PublisherPrefix' starts with 'mscrm', which Dataverse reserves. Choose another prefix."
}

if (-not (Test-Path -LiteralPath $TargetPath)) {
    Stop-WithError "TargetPath '$TargetPath' does not exist. Create it first, or run against an existing folder."
}
$TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path

$webResources = "src/PowerPlatform/WebResources/$ProjectName.WebResources/${PublisherPrefix}_/src"
$leafFolders = @(
    'src/PowerPlatform/Plugins'
    'src/PowerPlatform/CustomAPIs'
    "$webResources/js"
    "$webResources/html"
    "$webResources/css"
    "$webResources/icons"
)

$created = @()
$present = @()

foreach ($folder in $leafFolders) {
    $path = Join-Path $TargetPath $folder

    if (Test-Path -LiteralPath $path) {
        $present += $folder
    }
    else {
        $created += $folder
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    # A folder that already holds a file is not empty: it needs no .gitkeep.
    if (-not $DryRun -and -not (Get-ChildItem -LiteralPath $path -Force | Select-Object -First 1)) {
        [System.IO.File]::WriteAllText((Join-Path $path '.gitkeep'), '', (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Host "Target folder: $TargetPath"

if ($DryRun) {
    Write-Host 'Dry run. These folders would be created:'
}
else {
    Write-Host 'Created:'
}
if ($created.Count -eq 0) { Write-Host '  (none)' }
$created | ForEach-Object { Write-Host "  $_" }

if ($present.Count -gt 0) {
    Write-Host 'Already present, left as they are:'
    $present | ForEach-Object { Write-Host "  $_" }
}
