<#
.SYNOPSIS
    Starts a unit of work: creates its branch and, in DEV, its feature solution.

.DESCRIPTION
    Derives the branch and the feature solution names from one answer, so they can never drift
    apart, then creates both. docs/development/solutions.md owns the rules; this script is the
    only supported way to apply them.

      -Type feature -Name lead-scoring-widget
        branch            feature/lead-scoring-widget
        feature solution  feature_LeadScoringWidget, version 1.0.0.0, publisher {{publisher_unique_name}}

    Every check runs before anything is changed: the branch is free, pac points at an
    environment that does not look like production or test, the publisher exists there with
    the expected prefix, and no solution already has that unique name. Run with -DryRun first
    and show the plan to the user: a solution unique name cannot be renamed once it exists.

    Re-running on the branch it created skips the branch and only creates the solution, so a
    failed import can be retried. The script never deletes anything, in git or in Dataverse.

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

    # Create the branch only. For work that creates or modifies no Dataverse component.
    [switch]$SkipSolution,

    # Run every check and print the plan, changing nothing.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Resolved by the harness scaffold. Change them only together with docs/development/solutions.md.
$publisherUniqueName = '{{publisher_unique_name}}'
$publisherPrefix = '{{publisher_prefix}}'
$coreSolution = '{{core_solution}}'

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
    $run = Invoke-Native -Command 'pac' -Arguments @('env', 'fetch', '--xmlFile', $queryFile)
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

function Get-Solution {
    param([string]$UniqueName)

    # Unique names are validated to letters, digits and underscores: safe inside the XML as is.
    $fetch = "<fetch><entity name=`"solution`"><attribute name=`"uniquename`" /><attribute name=`"version`" /><filter><condition attribute=`"uniquename`" operator=`"eq`" value=`"$UniqueName`" /></filter></entity></fetch>"
    return @(Invoke-Fetch -FetchXml $fetch -Columns @('uniquename', 'version'))
}

# ---- names --------------------------------------------------------------------------------

if ($Name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Stop-WithError "Name '$Name' is invalid. Use a short kebab-case description: lowercase letters and digits separated by single hyphens, e.g. lead-scoring-widget."
}

if (-not $SkipSolution) {
    if ($publisherUniqueName -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $publisherPrefix -cnotmatch '^[a-z][a-z0-9]{1,7}$') {
        Stop-WithError "The publisher values in this script are invalid ('$publisherUniqueName', '$publisherPrefix'). They are set when the harness is installed; fix them together with docs/development/solutions.md."
    }
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
if (-not $git) { Stop-WithError 'git was not found on PATH. docs/agents/toolchain.md has the install command.' }

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
    Stop-WithError "This folder is already on '$branch': there is no branch to create in a worktree. Re-run without -Worktree to create only the feature solution."
}

$isDirty = [bool](Invoke-Native -Command 'git' -Arguments @('status', '--porcelain')).Output

# ---- environment --------------------------------------------------------------------------

$environmentName = $null
$environmentUrl = $null
$script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "new-feature-$([guid]::NewGuid().ToString('n'))"

try {

if (-not $SkipSolution) {
    if (-not (Get-Command -Name pac -ErrorAction SilentlyContinue)) {
        Stop-WithError 'pac was not found on PATH. Install it (docs/agents/toolchain.md), or use -SkipSolution for work that touches no Dataverse component.'
    }

    New-Item -ItemType Directory -Path $script:workRoot -Force | Out-Null

    # Name the environment before any operation against it.
    $who = Invoke-Native -Command 'pac' -Arguments @('org', 'who')
    if ($who.ExitCode -ne 0) {
        Stop-WithError "pac is not connected to an environment. Create a profile against DEV with pac auth create --environment <dev-url>. Nothing was changed.`n$($who.Output)"
    }
    foreach ($line in ($who.Output -split "`r?`n")) {
        if ($line -match '^\s*Friendly Name:\s+(.+?)\s*$') { $environmentName = $Matches[1] }
        elseif ($line -match '^\s*Org URL:\s+(.+?)\s*$') { $environmentUrl = $Matches[1].TrimEnd('/') }
    }

    $signal = Get-EnvironmentNameSignal -Text "$environmentName $environmentUrl"
    if ($signal -eq 'production' -or $signal -eq 'test') {
        Stop-WithError "pac points at '$environmentName' ($environmentUrl), which looks like a $signal environment. Feature solutions are created in DEV only: select the DEV profile with pac auth select. Nothing was changed."
    }

    $publisherFetch = "<fetch><entity name=`"publisher`"><attribute name=`"uniquename`" /><attribute name=`"customizationprefix`" /><filter><condition attribute=`"uniquename`" operator=`"eq`" value=`"$publisherUniqueName`" /></filter></entity></fetch>"
    $publisher = @(Invoke-Fetch -FetchXml $publisherFetch -Columns @('uniquename', 'customizationprefix'))
    if ($publisher.Count -eq 0) {
        Stop-WithError "Publisher '$publisherUniqueName' does not exist in $environmentName. A human creates it, with prefix '$publisherPrefix'. Nothing was changed."
    }
    if ($publisher[0].customizationprefix -cne $publisherPrefix) {
        Stop-WithError "Publisher '$publisherUniqueName' in $environmentName has prefix '$($publisher[0].customizationprefix)', not '$publisherPrefix'. Resolve the mismatch with the team before creating anything. Nothing was changed."
    }

    $existing = @(Get-Solution -UniqueName $solution)
    if ($existing.Count -gt 0) {
        Stop-WithError "A solution named '$solution' already exists in $environmentName (version $($existing[0].version)). Unique names cannot be reused: choose another description. Nothing was changed."
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

# The branch goes first: it is the cheap, local, reversible step. A solution created for a branch
# that then fails to exist would be the harder half to undo.
if ($createBranch) {
    if ($Worktree) { $run = Invoke-Native -Command 'git' -Arguments @('worktree', 'add', '-b', $branch, $worktreePath) }
    else { $run = Invoke-Native -Command 'git' -Arguments @('switch', '-c', $branch) }

    if ($run.ExitCode -ne 0) { Stop-WithError "Creating branch '$branch' failed. Nothing else was changed.`n$($run.Output)" }
    Write-Host "Created branch $branch." -ForegroundColor Green
}

# ---- feature solution ---------------------------------------------------------------------

if (-not $SkipSolution) {
    $retryHint = "Branch '$branch' exists; re-run this command from it to retry the solution."
    $projectFolder = Join-Path $script:workRoot $solution
    $zipFile = Join-Path $script:workRoot "$solution.zip"

    $run = Invoke-Native -Command 'pac' -Arguments @('solution', 'init', '--publisher-name', $publisherUniqueName, '--publisher-prefix', $publisherPrefix, '--outputDirectory', $projectFolder)
    if ($run.ExitCode -ne 0) { Stop-WithError "pac solution init failed. $retryHint`n$($run.Output)" }

    # pac solution init writes version 1.0, and pac solution version only changes build and
    # revision: every solution starts at 1.0.0.0, so set it here, before packing.
    $manifestPath = Join-Path $projectFolder 'src/Other/Solution.xml'
    $manifest = New-Object System.Xml.XmlDocument
    $manifest.PreserveWhitespace = $true
    $manifest.Load($manifestPath)
    $manifest.ImportExportXml.SolutionManifest.Version = '1.0.0.0'
    $manifest.Save($manifestPath)

    $check = New-Object System.Xml.XmlDocument
    $check.Load($manifestPath)
    if ($check.ImportExportXml.SolutionManifest.Version -ne '1.0.0.0' -or $check.ImportExportXml.SolutionManifest.UniqueName -ne $solution) {
        Stop-WithError "The generated Solution.xml does not hold $solution 1.0.0.0. $retryHint"
    }

    $run = Invoke-Native -Command 'pac' -Arguments @('solution', 'pack', '--folder', (Join-Path $projectFolder 'src'), '--zipfile', $zipFile, '--packagetype', 'Unmanaged')
    if ($run.ExitCode -ne 0) { Stop-WithError "pac solution pack failed. $retryHint`n$($run.Output)" }

    # No --publish-changes: the solution is empty, and publishing in a shared DEV would publish
    # every colleague's unpublished customizations along with it.
    Write-Host "Importing $solution into $environmentName..." -ForegroundColor Cyan
    $run = Invoke-Native -Command 'pac' -Arguments @('solution', 'import', '--path', $zipFile)
    if ($run.ExitCode -ne 0) { Stop-WithError "pac solution import failed. $retryHint`n$($run.Output)" }

    $created = @(Get-Solution -UniqueName $solution)
    if ($created.Count -eq 0) {
        Stop-WithError "The import reported success, but '$solution' is not in $environmentName. Check the maker portal before retrying."
    }
    if ($created[0].version -ne '1.0.0.0') {
        Stop-WithError "'$solution' exists in $environmentName with version $($created[0].version), not 1.0.0.0. Report it instead of retrying."
    }
    Write-Host "Created feature solution $solution 1.0.0.0 in $environmentName." -ForegroundColor Green
}

}
finally {
    if (Test-Path -LiteralPath $script:workRoot) {
        Remove-Item -LiteralPath $script:workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- next steps ---------------------------------------------------------------------------

Write-Host ''
if ($worktreePath) { Write-Host "Continue inside the worktree: $worktreePath" }
if (-not $SkipSolution) {
    Write-Host "Create every component in $solution."
    if ($coreSolution -ne 'none') {
        Write-Host "Then add each one to the core solution $coreSolution, as it is created: docs/development/solutions.md has the command."
    }
}
