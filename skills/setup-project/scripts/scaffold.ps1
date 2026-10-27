<#
.SYNOPSIS
    Scaffolds a Power Platform / Dynamics 365 CE repository from the harness templates.

.DESCRIPTION
    Copies every file under templates/ into -TargetPath, replacing the template tokens with the
    values supplied as parameters, and creates the source and ADR folders the standards expect.
    It writes files only: nothing here talks to Dataverse.

    The script never overwrites an existing file unless -Force is supplied: it collects every
    collision first and aborts without touching the working tree. Use -DryRun to print the
    resulting tree without writing anything.

    Also creates the code projects under src/PowerPlatform/: PowerPlatform.sln, the shared
    <ProjectName>.Common plugin library (PluginBase.cs) and the WebResources build project (an
    SDK-style .esproj with Vitest + ESLint tooling), unless -SkipLayout or -SkipCodeProjects is
    supplied.

    Three ways to handle a folder that is not empty:
      - default:      abort and list the collisions, writing nothing.
      - -SkipExisting: write what is missing, leave every existing file untouched. This is the
                       mode for an existing project, where CLAUDE.md already says something the
                       team relies on.
      - -Force:        overwrite. Only after the caller has looked at what is being replaced.

    Run scripts/discover.ps1 first to find out which of the three applies, and to read the
    publisher, prefix, core solution and project name a project already uses.

.EXAMPLE
    ./scripts/scaffold.ps1 -ProjectName Northwind -PublisherUniqueName NorthwindConsulting
        -PublisherPrefix nwc -CoreSolution NorthwindCore
        -ProjectDescription 'Customer Service implementation for Northwind.' -DryRun

.EXAMPLE
    # No core solution: every component lives in the feature solution of its branch.
    ./scripts/scaffold.ps1 -ProjectName Northwind -PublisherUniqueName NorthwindConsulting
        -PublisherPrefix nwc
        -ProjectDescription 'Customer Service implementation for Northwind.' -TargetPath C:\repos\northwind

.EXAMPLE
    # Adopt the harness into an existing repository: add the missing docs, touch nothing else.
    ./scripts/scaffold.ps1 -ProjectName Acme -PublisherUniqueName AcmeConsulting -PublisherPrefix acme
        -CoreSolution AcmeCore -ProjectDescription 'Customer Service for Acme.'
        -TargetPath C:\repos\acme -SkipExisting -SkipLayout -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherUniqueName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherPrefix,

    [Parameter(Mandatory = $true)]
    [string]$ProjectDescription,

    # Unique name of the core solution in DEV, or 'none' when the project has no core solution and
    # every component lives in the feature solution of the branch that created it.
    [string]$CoreSolution = 'none',

    [string]$TargetPath = (Get-Location).Path,

    [switch]$DryRun,

    [switch]$Force,

    # Existing projects: write the files the repository is missing and leave the rest alone,
    # instead of aborting on the first collision. An existing CLAUDE.md is the usual reason.
    [switch]$SkipExisting,

    # Do not create the src/PowerPlatform/ and docs/adr/ folders. An existing project already has a
    # layout; adding a second one next to it leaves two conventions in one repository.
    [switch]$SkipLayout,

    # Do not create the code projects under src/PowerPlatform/: PowerPlatform.sln, the shared Common
    # plugin library and the WebResources build project (.esproj + package.json + Vitest/ESLint config).
    # Use for an existing project: they introduce a target framework and a test runner, and the
    # harness must never impose either on a project that has not already chosen them. -SkipLayout
    # implies this.
    [switch]$SkipCodeProjects,

    # Emit a JSON summary instead of the human-readable report, for callers that parse the result.
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Failures are reported as a single line on stderr with a non-zero exit code: the caller is
# usually an agent, and a PowerShell exception dump buries the actual problem.
function Stop-WithError {
    param([string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

if ($Force -and $SkipExisting) {
    Stop-WithError '-Force and -SkipExisting ask for opposite things. Choose one: overwrite the existing files, or keep them.'
}

# Folders the standards expect to exist. Git does not track empty folders, so each one that no
# template file lands in gets a .gitkeep.
$keepDirectories = @(
    'src/PowerPlatform/Plugins'
    'src/PowerPlatform/CustomAPIs'
    'src/PowerPlatform/WebResources'
    'docs/adr'
)

# The WebResources build project's own source folders. Empty until the first web resource is
# added, so each one needs a .gitkeep like $keepDirectories above.
$webResourcesProjectFolder = "src/PowerPlatform/WebResources/$ProjectName.WebResources"
$webResourcesKeepDirectories = @(
    "$webResourcesProjectFolder/${PublisherPrefix}_/src/js"
    "$webResourcesProjectFolder/${PublisherPrefix}_/src/html"
    "$webResourcesProjectFolder/${PublisherPrefix}_/src/css"
    "$webResourcesProjectFolder/${PublisherPrefix}_/src/icons"
)

function Assert-Value {
    param(
        [string]$Name,
        [string]$Value,
        [string]$Pattern,
        [string]$Requirement
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Stop-WithError "$Name is required. $Requirement"
    }

    # -cnotmatch, not -notmatch: PowerShell matches case-insensitively by default, which would
    # let an uppercase publisher prefix through.
    if ($Pattern -and $Value -cnotmatch $Pattern) {
        Stop-WithError "$Name '$Value' is invalid. $Requirement"
    }
}

# Validate every value before touching the working tree: a rejected prefix after a partial copy
# would leave a half-scaffolded repository behind.
Assert-Value -Name 'ProjectName' -Value $ProjectName -Pattern '^[A-Za-z][A-Za-z0-9]*$' `
    -Requirement 'It is the root .NET namespace and names the JavaScript form API namespace and the WebResources project, so it must start with a letter and contain letters and digits only.'

Assert-Value -Name 'PublisherUniqueName' -Value $PublisherUniqueName -Pattern '^[A-Za-z_][A-Za-z0-9_]*$' `
    -Requirement 'Use the publisher unique name, not its display name: pac solution init needs it to create feature solutions. Letters, digits and underscores only.'

Assert-Value -Name 'PublisherPrefix' -Value $PublisherPrefix -Pattern '^[a-z][a-z0-9]{1,7}$' `
    -Requirement 'A Dataverse customization prefix is 2 to 8 lowercase alphanumeric characters and starts with a letter.'

# Dataverse rejects any prefix that starts with mscrm, not only mscrm itself.
if ($PublisherPrefix.StartsWith('mscrm')) {
    Stop-WithError "PublisherPrefix '$PublisherPrefix' starts with 'mscrm', which Dataverse reserves. Choose another prefix."
}

Assert-Value -Name 'CoreSolution' -Value $CoreSolution -Pattern '^[A-Za-z_][A-Za-z0-9_]*$' `
    -Requirement "Use the core solution unique name, not its display name: no spaces or punctuation. Use 'none' when the project has no core solution."

Assert-Value -Name 'ProjectDescription' -Value $ProjectDescription `
    -Requirement 'One or two sentences describing what the project delivers. It becomes the Description section of CLAUDE.md.'

$templatesRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'
if (-not (Test-Path -LiteralPath $templatesRoot)) {
    Stop-WithError "Templates folder not found at $templatesRoot. The plugin installation looks incomplete."
}
$templatesRoot = (Resolve-Path -LiteralPath $templatesRoot).Path

if (-not (Test-Path -LiteralPath $TargetPath)) {
    if ($DryRun) {
        Stop-WithError "TargetPath '$TargetPath' does not exist. Create it first, or run against an existing folder."
    }
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}
$TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path

$tokens = [ordered]@{
    '{{project_name}}'          = $ProjectName
    '{{publisher_unique_name}}' = $PublisherUniqueName
    '{{publisher_prefix}}'      = $PublisherPrefix
    '{{core_solution}}'         = $CoreSolution
    '{{project_description}}'   = $ProjectDescription
}

# Build and restore output is never template content. Opening or building a template project in
# an IDE regenerates bin/ and obj/ inside templates/, and git ignores them, so only this filter
# keeps them (machine-specific paths and caches included) out of a scaffolded repository.
$buildOutputPattern = '(^|/)(bin|obj|node_modules)/'

$plannedFiles = Get-ChildItem -LiteralPath $templatesRoot -Recurse -File -Force |
    ForEach-Object {
        $templateRelative = ($_.FullName.Substring($templatesRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
        if ($templateRelative -match $buildOutputPattern) { return }

        # A template's own folder or file name can carry a token too (the WebResources project is
        # named after the project), so resolve it the same way file content is resolved.
        $destinationRelative = $templateRelative
        foreach ($token in $tokens.Keys) {
            $destinationRelative = $destinationRelative.Replace($token, $tokens[$token])
        }

        [pscustomobject]@{
            Source      = $_.FullName
            Relative    = $destinationRelative
            Destination = Join-Path $TargetPath $destinationRelative
        }
    }

if (-not $plannedFiles) {
    Stop-WithError "No template files found under $templatesRoot."
}

# The code projects (everything under src/PowerPlatform/: the solution, the Common library and the
# WebResources project) are planned separately: -SkipLayout suppresses them because they assume the
# standard src/PowerPlatform layout, and -SkipCodeProjects suppresses them on its own, for an existing
# project that has not chosen this framework and tooling.
$codeProjectsPattern = '^src/PowerPlatform/'
$codeProjectFiles = @($plannedFiles | Where-Object { $_.Relative -match $codeProjectsPattern })
$plannedFiles = @($plannedFiles | Where-Object { $_.Relative -notmatch $codeProjectsPattern })

if (-not $SkipLayout -and -not $SkipCodeProjects) {
    $plannedFiles = @($plannedFiles) + @($codeProjectFiles)
}

$plannedKeeps = @()
if (-not $SkipLayout) {
    $plannedKeeps = $keepDirectories | ForEach-Object {
        [pscustomobject]@{
            Relative    = "$_/.gitkeep"
            Destination = Join-Path $TargetPath (Join-Path $_ '.gitkeep')
        }
    }

    if (-not $SkipCodeProjects) {
        $plannedKeeps = @($plannedKeeps) + @($webResourcesKeepDirectories | ForEach-Object {
            [pscustomobject]@{
                Relative    = "$_/.gitkeep"
                Destination = Join-Path $TargetPath (Join-Path $_ '.gitkeep')
            }
        })
    }

    # A folder a template file already lands in is not empty: it needs no .gitkeep.
    $plannedKeeps = @($plannedKeeps | Where-Object {
        $folder = $_.Relative.Substring(0, $_.Relative.Length - '/.gitkeep'.Length)
        $prefix = "$folder/"
        -not @($plannedFiles | Where-Object { $_.Relative.StartsWith($prefix) }).Count
    })
}

$allPlanned = @($plannedFiles) + @($plannedKeeps)

$collisions = @($allPlanned |
    Where-Object { Test-Path -LiteralPath $_.Destination } |
    ForEach-Object { $_.Relative })

if ($collisions.Count -gt 0 -and -not $Force -and -not $SkipExisting) {
    Write-Host 'These files already exist in the target folder:' -ForegroundColor Red
    $collisions | ForEach-Object { Write-Host "  $_" }
    Stop-WithError 'Nothing was written. Re-run with -SkipExisting to add only what is missing, or with -Force to overwrite the files above.'
}

# -SkipExisting narrows the plan instead of aborting: what the repository already has is its own,
# and an existing CLAUDE.md usually carries instructions this scaffold must not silently replace.
$skipped = @()
if ($SkipExisting -and $collisions.Count -gt 0) {
    $skipped = $collisions
    $plannedFiles = @($plannedFiles | Where-Object { -not (Test-Path -LiteralPath $_.Destination) })
    $plannedKeeps = @($plannedKeeps | Where-Object { -not (Test-Path -LiteralPath $_.Destination) })
}

$written = @($plannedFiles) + @($plannedKeeps)

function Write-Report {
    param(
        [string]$Outcome,
        [string[]]$Created = @(),
        [string[]]$Skipped = @(),
        [string[]]$Overwritten = @(),
        [string[]]$Planned = @()
    )

    if ($Json) {
        $payload = [ordered]@{
            outcome     = $Outcome
            targetPath  = $TargetPath
            values      = [ordered]@{
                projectName         = $ProjectName
                publisherUniqueName = $PublisherUniqueName
                publisherPrefix     = $PublisherPrefix
                coreSolution        = $CoreSolution
                projectDescription  = $ProjectDescription
            }
            mode        = [ordered]@{
                dryRun                  = [bool]$DryRun
                force                   = [bool]$Force
                skipExisting            = [bool]$SkipExisting
                skipLayout              = [bool]$SkipLayout
                skipCodeProjects        = [bool]$SkipCodeProjects
            }
            planned     = @($Planned | Sort-Object)
            created     = @($Created | Sort-Object)
            skipped     = @($Skipped | Sort-Object)
            overwritten = @($Overwritten | Sort-Object)
        }
        $payload | ConvertTo-Json -Depth 6
        return
    }

    Write-Host "Target folder: $TargetPath" -ForegroundColor Cyan

    if ($Outcome -eq 'dry-run') {
        Write-Host 'Dry run. These files would be written:' -ForegroundColor Cyan
        $Planned | Sort-Object | ForEach-Object { Write-Host "  $_" }
        if ($Skipped.Count -gt 0) {
            Write-Host 'Left untouched because they already exist:' -ForegroundColor Yellow
            $Skipped | Sort-Object | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host 'Nothing was written.' -ForegroundColor Cyan
        return
    }

    if ($Overwritten.Count -gt 0) {
        Write-Host "Overwrote $($Overwritten.Count) existing file(s) because -Force was supplied." -ForegroundColor Yellow
    }

    if ($Created.Count -gt 0) {
        Write-Host 'Created:' -ForegroundColor Green
        $Created | Sort-Object | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host 'Nothing to create: every file the harness installs is already present.' -ForegroundColor Yellow
    }

    if ($Skipped.Count -gt 0) {
        Write-Host 'Left untouched because they already exist:' -ForegroundColor Yellow
        $Skipped | Sort-Object | ForEach-Object { Write-Host "  $_" }
        Write-Host 'Compare each one against the template before assuming the harness is current.' -ForegroundColor Yellow
    }
}

if ($DryRun) {
    Write-Report -Outcome 'dry-run' `
        -Planned @($written | ForEach-Object { $_.Relative }) `
        -Skipped $skipped `
        -Overwritten @(if ($Force) { $collisions } else { @() })
    return
}

if ($written.Count -eq 0) {
    Write-Report -Outcome 'nothing-to-do' -Skipped $skipped
    return
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Substitution is textual, so a token landing inside a JSON string needs the value JSON-escaped:
# a description with a quote or a backslash would otherwise break package.json. ConvertTo-Json of
# a bare string yields the quoted, escaped literal; the outer quotes are the template's own.
$jsonTokens = [ordered]@{}
foreach ($token in $tokens.Keys) {
    $literal = ConvertTo-Json -InputObject ([string]$tokens[$token]) -Compress
    $jsonTokens[$token] = $literal.Substring(1, $literal.Length - 2)
}

# Render everything before writing anything: a generated file that does not parse must abort the
# scaffold, not leave a half-written repository behind.
$rendered = foreach ($file in $plannedFiles) {
    $isJson = $file.Relative -match '(?i)\.json$'
    $values = if ($isJson) { $jsonTokens } else { $tokens }

    $content = [System.IO.File]::ReadAllText($file.Source)
    foreach ($token in $values.Keys) {
        $content = $content.Replace($token, $values[$token])
    }

    [pscustomobject]@{ File = $file; Content = $content; IsJson = $isJson }
}

$invalidJson = foreach ($item in @($rendered | Where-Object { $_.IsJson })) {
    try { $item.Content | ConvertFrom-Json | Out-Null }
    catch { "$($item.File.Relative): $($_.Exception.Message)" }
}

if ($invalidJson) {
    Write-Host 'These generated JSON files do not parse:' -ForegroundColor Red
    $invalidJson | ForEach-Object { Write-Host "  $_" }
    Stop-WithError 'Nothing was written. Report the file and the value that broke it instead of hand-editing the output.'
}

foreach ($item in $rendered) {
    $destinationDirectory = Split-Path -Parent $item.File.Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($item.File.Destination, $item.Content, $utf8NoBom)
}

foreach ($keep in $plannedKeeps) {
    $destinationDirectory = Split-Path -Parent $keep.Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($keep.Destination, '', $utf8NoBom)
}

# The scaffold is only done when no token survived the substitution.
$unresolved = foreach ($file in $plannedFiles) {
    $found = Select-String -LiteralPath $file.Destination -Pattern '\{\{[a-z_]+\}\}' -AllMatches
    foreach ($line in $found) {
        "$($file.Relative):$($line.LineNumber): $(($line.Matches.Value | Select-Object -Unique) -join ', ')"
    }
}

if ($unresolved) {
    Write-Host 'Unresolved tokens remain in the generated files:' -ForegroundColor Red
    $unresolved | ForEach-Object { Write-Host "  $_" }
    Stop-WithError 'The scaffold is incomplete. Report these tokens instead of hand-editing the output.'
}

Write-Report -Outcome 'written' `
    -Created @($written | ForEach-Object { $_.Relative }) `
    -Skipped $skipped `
    -Overwritten @(if ($Force) { $collisions } else { @() })

if (-not $Json) {
    Write-Host ''
    Write-Host "Project:   $ProjectName" -ForegroundColor Cyan
    Write-Host "Publisher: $PublisherUniqueName ($PublisherPrefix)" -ForegroundColor Cyan
    Write-Host "Core:      $CoreSolution" -ForegroundColor Cyan
}
