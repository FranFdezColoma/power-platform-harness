<#
.SYNOPSIS
    Starts a unit of work: names its branch and feature solution, checks both, creates the branch.

.DESCRIPTION
    Derives the branch and the feature solution names from one answer, so they can never drift
    apart, checks them against git and DEV, then creates the branch and prints the solution for
    dv-solution to create. docs/development/solutions.md owns the rules; this script is the only
    supported way to derive the names.

      -Type feature -Name lead-scoring-widget
        branch            feature/lead-scoring-widget
        feature solution  feature_LeadScoringWidget, version 1.0.0.0, under the project's publisher

    Every check runs before anything is changed: the branch is free here and on origin, pac
    reaches the DEV environment .power-platform/project.json names and it does not look like
    production or test, the publisher exists there with the expected prefix, and no solution
    already has that unique name. Run with -DryRun first and show the plan to the user: a solution
    unique name cannot be renamed once it exists.

    The script only reads Dataverse: it never creates, imports or deletes anything there, and it
    never deletes anything in git. Re-running it on the branch it created repeats the checks, so
    the solution step can be retried.

.EXAMPLE
    pwsh -NoProfile -File scripts/new-feature.ps1 -Type feature -Name lead-scoring-widget -DryRun

.EXAMPLE
    # Another session is working in this folder: create the branch in a worktree instead.
    pwsh -NoProfile -File scripts/new-feature.ps1 -Type fix -Name invoice-rounding -Worktree

.EXAMPLE
    # Code-only work that touches no Dataverse component: the branch alone.
    pwsh -NoProfile -File scripts/new-feature.ps1 -Type chore -Name bump-eslint -SkipSolution
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('feature', 'fix', 'chore')]
    [string]$Type,

    # Short description in kebab-case: lowercase letters and digits separated by hyphens.
    [Parameter(Mandatory = $true)]
    [string]$Name,

    # Create the branch in ../<repo>.worktrees/<type>/<name> instead of switching this folder.
    [switch]$Worktree,

    # Check and create the branch only. For work that creates or modifies no Dataverse component.
    [switch]$SkipSolution,

    # Run every check and print the plan, changing nothing.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Stop-WithError {
    param([string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

# Native commands write progress to stderr. Windows PowerShell 5.1 turns that into a terminating
# error under -ErrorAction Stop, so each call relaxes it and judges by the exit code instead.
function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)

    $ErrorActionPreference = 'Continue'
    $output = & $Command @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (@($output) -join "`n").Trim()
    }
}

function Get-EnvironmentNameSignal {
    param([string]$Text)

    # Production first: a name containing both is more likely to be production than not.
    if ($Text -match '(?i)(^|[^a-z])(prod|prd|production|live)([^a-z]|$)') { return 'production' }
    if ($Text -match '(?i)(^|[^a-z])(test|tst|qa|uat|sit|stag|staging|stage|preprod|pre-prod)([^a-z]|$)') { return 'test' }
    if ($Text -match '(?i)(^|[^a-z])(dev|develop|development|sandbox|sbx)([^a-z]|$)') { return 'dev' }
    return 'unknown'
}

# Runs a read-only FetchXML query and returns its rows. pac prints a fixed-width table sized to
# its content, with columns that may contain spaces, so rows are cut at the header's offsets.
# The query goes through a file: quotes and angle brackets do not survive the cmd.exe shim an
# npm-installed pac runs behind.
function Invoke-Fetch {
    param([string]$FetchXml, [string[]]$Columns)

    $queryFile = Join-Path $script:workRoot "$([guid]::NewGuid().ToString('n')).xml"
    [System.IO.File]::WriteAllText($queryFile, $FetchXml)
    $run = Invoke-Native -Command 'pac' -Arguments (@('env', 'fetch', '--xmlFile', $queryFile) + $script:environmentArguments)
    Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue

    if ($run.ExitCode -ne 0) {
        Stop-WithError "pac env fetch failed. Nothing was changed.`n$($run.Output)"
    }

    $lines = @($run.Output -split "`r?`n")
    $headerIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $tokens = @($lines[$index].Trim() -split '\s+')
        if (@($Columns | Where-Object { $tokens -notcontains $_ }).Count -eq 0) { $headerIndex = $index; break }
    }
    # No header means no rows: pac prints "No results returned." for an empty result.
    if ($headerIndex -lt 0) { return @() }

    $offsets = @([regex]::Matches($lines[$headerIndex], '\S+') | ForEach-Object { [pscustomobject]@{ Name = $_.Value; Start = $_.Index } })
    $rows = @()
    for ($index = $headerIndex + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if (-not $line.Trim()) { continue }
        $row = @{}
        for ($column = 0; $column -lt $offsets.Count; $column++) {
            $start = $offsets[$column].Start
            $end = if ($column + 1 -lt $offsets.Count) { $offsets[$column + 1].Start } else { [Math]::Max($line.Length, $start) }
            $value = ''
            if ($start -lt $line.Length) { $value = $line.Substring($start, [Math]::Min($end, $line.Length) - $start).Trim() }
            $row[$offsets[$column].Name] = $value
        }
        $rows += [pscustomobject]$row
    }
    return $rows
}

# ---- names --------------------------------------------------------------------------------

if ($Name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Stop-WithError "Name '$Name' is invalid. Use a short kebab-case description: lowercase letters and digits separated by single hyphens, e.g. lead-scoring-widget."
}

$branch = "$Type/$Name"
$pascalName = (($Name -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
$solution = "${Type}_$pascalName"

# Dataverse stores solution unique names in a 65-character column.
if (-not $SkipSolution -and $solution.Length -gt 65) {
    Stop-WithError "The feature solution name '$solution' is $($solution.Length) characters; Dataverse allows 65. Choose a shorter description."
}

# ---- git ----------------------------------------------------------------------------------

$git = Get-Command -Name git -ErrorAction SilentlyContinue
if (-not $git) { Stop-WithError 'git was not found on PATH. The harness setup-tools skill installs it.' }

$topLevel = Invoke-Native -Command 'git' -Arguments @('rev-parse', '--show-toplevel')
if ($topLevel.ExitCode -ne 0) { Stop-WithError 'This folder is not inside a git repository.' }
$repositoryRoot = $topLevel.Output

$currentBranch = (Invoke-Native -Command 'git' -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')).Output
$createBranch = $currentBranch -ne $branch

$worktreePath = $null
if ($createBranch) {
    if ((Invoke-Native -Command 'git' -Arguments @('rev-parse', '--verify', '--quiet', "refs/heads/$branch")).ExitCode -eq 0) {
        Stop-WithError "Branch '$branch' already exists. Switch to it to continue that work, or choose another name. Nothing was changed."
    }
    if ((Invoke-Native -Command 'git' -Arguments @('rev-parse', '--verify', '--quiet', "refs/remotes/origin/$branch")).ExitCode -eq 0) {
        Stop-WithError "Branch '$branch' already exists on origin: someone else may be working on it. Choose another name. Nothing was changed."
    }

    if ($Worktree) {
        $repositoryName = Split-Path -Leaf $repositoryRoot
        $worktreePath = Join-Path (Split-Path -Parent $repositoryRoot) "$repositoryName.worktrees/$Type/$Name"
        if (Test-Path -LiteralPath $worktreePath) {
            Stop-WithError "The worktree folder $worktreePath already exists. Nothing was changed."
        }
    }
}
elseif ($Worktree) {
    Stop-WithError "This folder is already on '$branch': there is no branch to create in a worktree. Re-run without -Worktree to repeat the feature solution checks."
}

$isDirty = [bool](Invoke-Native -Command 'git' -Arguments @('status', '--porcelain')).Output

# ---- project ------------------------------------------------------------------------------

# .power-platform/project.json is the source of truth for the publisher and the DEV environment.
# The branch alone needs neither.
$publisherUniqueName = $null
$publisherPrefix = $null
$coreSolution = 'none'
$devUrl = $null

if (-not $SkipSolution) {
    $projectFile = Join-Path $repositoryRoot '.power-platform/project.json'
    if (-not (Test-Path -LiteralPath $projectFile)) {
        Stop-WithError ".power-platform/project.json was not found. The harness setup-project skill writes it; use -SkipSolution for work that touches no Dataverse component."
    }
    try { $project = [System.IO.File]::ReadAllText($projectFile) | ConvertFrom-Json }
    catch { Stop-WithError ".power-platform/project.json does not parse: $($_.Exception.Message)" }

    $publisherUniqueName = [string]$project.identity.publisherUniqueName
    $publisherPrefix = [string]$project.identity.publisherPrefix
    if ($project.identity.coreSolution) { $coreSolution = [string]$project.identity.coreSolution }
    if ($project.connections.dataverse.devUrl) { $devUrl = ([string]$project.connections.dataverse.devUrl).TrimEnd('/') }

    if ($publisherUniqueName -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Stop-WithError "identity.publisherUniqueName '$publisherUniqueName' in .power-platform/project.json is invalid: use the publisher unique name, letters, digits and underscores only."
    }
    if ($publisherPrefix -cnotmatch '^[a-z][a-z0-9]{1,7}$') {
        Stop-WithError "identity.publisherPrefix '$publisherPrefix' in .power-platform/project.json is invalid: a customization prefix is 2 to 8 lowercase alphanumeric characters and starts with a letter."
    }
    if ($devUrl -and $devUrl -notmatch '^https://[^\s/]+$') {
        Stop-WithError "connections.dataverse.devUrl '$devUrl' in .power-platform/project.json is not an environment url such as https://<org>.crm4.dynamics.com."
    }
}

# ---- environment --------------------------------------------------------------------------

# Every pac call names the DEV environment, so the result never depends on which pac profile is
# active. Without a devUrl, the active profile is used and the name check below is all there is.
$script:environmentArguments = @()
if ($devUrl) { $script:environmentArguments = @('--environment', $devUrl) }

$environmentName = $null
$environmentUrl = $null
$script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "new-feature-$([guid]::NewGuid().ToString('n'))"

try {

if (-not $SkipSolution) {
    if (-not (Get-Command -Name pac -ErrorAction SilentlyContinue)) {
        Stop-WithError 'pac was not found on PATH. The harness setup-tools skill installs it; use -SkipSolution for work that touches no Dataverse component.'
    }

    New-Item -ItemType Directory -Path $script:workRoot -Force | Out-Null

    # Name the environment before any operation against it.
    $who = Invoke-Native -Command 'pac' -Arguments (@('org', 'who') + $script:environmentArguments)
    if ($who.ExitCode -ne 0) {
        Stop-WithError "pac could not reach the environment. The dv-connect skill creates the authentication profile. Nothing was changed.`n$($who.Output)"
    }
    foreach ($line in ($who.Output -split "`r?`n")) {
        if ($line -match '^\s*Friendly Name:\s+(.+?)\s*$') { $environmentName = $Matches[1] }
        elseif ($line -match '^\s*Org URL:\s+(.+?)\s*$') { $environmentUrl = $Matches[1].TrimEnd('/') }
    }

    if ($devUrl -and $environmentUrl -ne $devUrl) {
        Stop-WithError "pac reached '$environmentName' ($environmentUrl), not the DEV environment .power-platform/project.json names ($devUrl). Nothing was changed."
    }

    $signal = Get-EnvironmentNameSignal -Text "$environmentName $environmentUrl"
    if ($signal -eq 'production' -or $signal -eq 'test') {
        Stop-WithError "pac points at '$environmentName' ($environmentUrl), which looks like a $signal environment. Feature solutions are created in DEV only: record the DEV url in .power-platform/project.json with the connect skill. Nothing was changed."
    }

    # Both values are validated to letters, digits and underscores: safe inside the XML as is.
    $publisherFetch = "<fetch><entity name=`"publisher`"><attribute name=`"uniquename`" /><attribute name=`"customizationprefix`" /><filter><condition attribute=`"uniquename`" operator=`"eq`" value=`"$publisherUniqueName`" /></filter></entity></fetch>"
    $publisher = @(Invoke-Fetch -FetchXml $publisherFetch -Columns @('uniquename', 'customizationprefix'))
    if ($publisher.Count -eq 0) {
        Stop-WithError "Publisher '$publisherUniqueName' does not exist in $environmentName. A human creates it, with prefix '$publisherPrefix'. Nothing was changed."
    }
    if ($publisher[0].customizationprefix -cne $publisherPrefix) {
        Stop-WithError "Publisher '$publisherUniqueName' in $environmentName has prefix '$($publisher[0].customizationprefix)', not '$publisherPrefix'. Resolve the mismatch with the team before creating anything. Nothing was changed."
    }

    $solutionFetch = "<fetch><entity name=`"solution`"><attribute name=`"uniquename`" /><attribute name=`"version`" /><filter><condition attribute=`"uniquename`" operator=`"eq`" value=`"$solution`" /></filter></entity></fetch>"
    $existing = @(Invoke-Fetch -FetchXml $solutionFetch -Columns @('uniquename', 'version'))
    if ($existing.Count -gt 0) {
        Stop-WithError "A solution named '$solution' already exists in $environmentName (version $($existing[0].version)). Unique names cannot be reused: choose another description. Nothing was changed."
    }
}

}
finally {
    if (Test-Path -LiteralPath $script:workRoot) {
        Remove-Item -LiteralPath $script:workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- plan ---------------------------------------------------------------------------------

Write-Host 'Plan:' -ForegroundColor Cyan
if (-not $createBranch) { Write-Host "  Branch            $branch (current branch, kept)" }
elseif ($Worktree) { Write-Host "  Branch            $branch, new, in worktree $worktreePath" }
else { Write-Host "  Branch            $branch, new, checked out here from $currentBranch" }

if ($SkipSolution) {
    Write-Host '  Feature solution  none (-SkipSolution)'
}
else {
    Write-Host "  Feature solution  $solution, version 1.0.0.0, unmanaged"
    Write-Host "  Publisher         $publisherUniqueName ($publisherPrefix)"
    Write-Host "  Environment       $environmentName ($environmentUrl)"
    if (-not $devUrl) {
        Write-Host '  Note              .power-platform/project.json names no DEV environment yet, so the active pac profile was used. Run the connect skill to record it.' -ForegroundColor Yellow
    }
}

if ($createBranch -and $isDirty) {
    if ($Worktree) { Write-Host '  Note              this folder has uncommitted changes; they stay here, not in the worktree.' -ForegroundColor Yellow }
    else { Write-Host '  Note              uncommitted changes in this folder move to the new branch.' -ForegroundColor Yellow }
}

if ($DryRun) {
    Write-Host 'Dry run: every check passed and nothing was changed.' -ForegroundColor Cyan
    return
}

# ---- branch -------------------------------------------------------------------------------

if ($createBranch) {
    if ($Worktree) { $run = Invoke-Native -Command 'git' -Arguments @('worktree', 'add', '-b', $branch, $worktreePath) }
    else { $run = Invoke-Native -Command 'git' -Arguments @('switch', '-c', $branch) }

    if ($run.ExitCode -ne 0) { Stop-WithError "Creating branch '$branch' failed. Nothing else was changed.`n$($run.Output)" }
    Write-Host "Created branch $branch." -ForegroundColor Green
}

# ---- next steps ---------------------------------------------------------------------------

Write-Host ''
if ($worktreePath) { Write-Host "Continue inside the worktree: $worktreePath" }
if (-not $SkipSolution) {
    Write-Host 'Next, once the user confirms, create the feature solution with dv-solution:'
    Write-Host "  Unique name       $solution"
    Write-Host '  Version           1.0.0.0, unmanaged'
    Write-Host "  Publisher         $publisherUniqueName ($publisherPrefix)"
    Write-Host "  Environment       $environmentName ($environmentUrl)"
    Write-Host 'Do not publish customizations: in a shared DEV that publishes every colleague''s unpublished work.'
    Write-Host "Then create every component in $solution."
    if ($coreSolution -ne 'none') {
        Write-Host "Add each one to the core solution $coreSolution as it is created: docs/development/solutions.md has the command."
    }
}
