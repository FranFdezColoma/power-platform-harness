<#
.SYNOPSIS
    Read-only check of the project's connections: the pac profile and the Dataverse environment.

.DESCRIPTION
    Answers the questions the connect skill needs before it changes anything:

      - Does pac have an authentication profile, which environment does it point at, and does the
        name look like DEV?
      - Which unmanaged solutions and which publishers exist there, and which feature solutions?

    Everything here reads, in the environment as on the machine. Output is a single JSON document
    on stdout; a probe that fails is recorded as a field inside it rather than aborting the run.

.EXAMPLE
    ./check-connections.ps1

.EXAMPLE
    # Report on an environment other than the active pac profile's.
    ./check-connections.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
#>
[CmdletBinding()]
param(
    # Environment to report on, when it is not the active pac profile's.
    [string]$EnvironmentUrl,

    # Per-command timeout. A hung pac call must not hang the caller.
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_dataverse.ps1')

$SkipEnvironment = $false
$ResolvePublisherFromSolution = $null
$notes = New-Object System.Collections.Generic.List[string]

try {

$tooling = [ordered]@{ pac = [ordered]@{ present = (Resolve-Tool -Name 'pac').Present } }

. (Join-Path $PSScriptRoot '_environment.ps1')

# Feature solutions are named <type>_<Name> after their branch.
$featureSolutionsInEnvironment = @($allUnmanagedSolutions | Where-Object { $_.uniqueName -match '^(feature|fix|chore)_' } | ForEach-Object { $_.uniqueName })

$report = [ordered]@{
    schemaVersion                 = 1
    generatedAt                   = (Get-Date).ToString('o')
    environment                   = $environment
    featureSolutionsInEnvironment = $featureSolutionsInEnvironment
    notes                         = @($notes)
}

$report | ConvertTo-Json -Depth 12

}
finally {
    if (Test-Path -LiteralPath $script:scratchRoot) {
        Remove-Item -LiteralPath $script:scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
