<#
.SYNOPSIS
    Compares what the discovery scripts report against recorded golden output.

.DESCRIPTION
    Runs every discovery script over each fixture repository and compares the sections it reports
    with the golden file recorded for that fixture. A refactor that changes no behaviour leaves
    every section identical; a deliberate change is recorded with -Update and reviewed in the diff.

    Fixtures are the folders under fixtures/, plus two built on the fly: an empty folder, and a
    fresh scaffold of the harness templates.

    Committed golden files hold repository-derived sections only, and run with -SkipEnvironment:
    the tooling on this machine and the facts of a real environment do not belong in a public
    repository. -Local adds them, against the connected environment, into the gitignored .local/
    folder, for checking a change on one machine before and after.

.EXAMPLE
    pwsh -NoProfile -File tests/discovery/Compare-Discovery.ps1

.EXAMPLE
    # Record the current output as the new golden files, after a deliberate change.
    pwsh -NoProfile -File tests/discovery/Compare-Discovery.ps1 -Update
#>
[CmdletBinding()]
param(
    # Rewrite the golden files from the current output instead of comparing.
    [switch]$Update,

    # Include machine tooling and the connected environment, in the gitignored .local/ folder.
    [switch]$Local
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$goldenRoot = if ($Local) { Join-Path $PSScriptRoot '.local' } else { Join-Path $PSScriptRoot 'golden' }

# Which top-level sections each script reports. A section several scripts report is compared
# field by field: each script must agree with the golden file on every field it emits.
$scripts = @(
    @{ Path = 'scripts/discover.ps1'; Sections = @('tooling', 'toolchain', 'repository', 'dotnet', 'node', 'solutions', 'pcfControls', 'environment', 'featureSolutionsInEnvironment', 'standards', 'prefixEvidence', 'proposedValues', 'recommendation', 'notes') }
)

# Sections that describe the machine running the script, not the repository it inspects.
$machineSections = @('tooling', 'toolchain')

function Get-NormalizedJson {
    param([string]$Text, [string]$FixturePath)

    # Absolute paths differ per machine and per run: replace them, in their JSON-escaped form.
    foreach ($pair in @(
        @{ Value = $FixturePath; Token = '<fixture>' },
        @{ Value = $repoRoot; Token = '<plugin>' },
        @{ Value = [System.IO.Path]::GetTempPath().TrimEnd('\'); Token = '<temp>' },
        @{ Value = $HOME; Token = '<home>' }
    )) {
        $escaped = $pair.Value -replace '\\', '\\'
        $Text = $Text.Replace($escaped, $pair.Token)
    }
    return $Text | ConvertFrom-Json
}

function ConvertTo-Comparable {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 20 -Compress)
}

function Invoke-Discovery {
    param([string]$Script, [string]$FixturePath)

    $arguments = @('-NoProfile', '-File', (Join-Path $repoRoot $Script), '-Path', $FixturePath)
    if (-not $Local) { $arguments += '-SkipEnvironment' }
    $output = & pwsh @arguments
    if ($LASTEXITCODE -ne 0) { throw "$Script failed on $FixturePath with exit code $LASTEXITCODE." }
    return Get-NormalizedJson -Text ($output -join "`n") -FixturePath $FixturePath
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "pph-golden-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    $fixtures = [ordered]@{}
    foreach ($folder in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'fixtures') -Directory) {
        $fixtures[$folder.Name] = $folder.FullName
    }

    $empty = Join-Path $scratch 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $fixtures['empty'] = $empty

    $scaffolded = Join-Path $scratch 'scaffolded'
    $scaffold = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter 'scaffold.ps1' |
        Where-Object { $_.FullName -notmatch '\\tests\\' } | Select-Object -First 1
    & pwsh -NoProfile -File $scaffold.FullName -ProjectName Northwind -PublisherUniqueName NorthwindConsulting `
        -PublisherPrefix nwc -CoreSolution NorthwindCore -ProjectDescription 'Test scaffold.' -TargetPath $scaffolded -Json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "scaffold.ps1 failed with exit code $LASTEXITCODE." }
    $fixtures['scaffolded'] = $scaffolded

    New-Item -ItemType Directory -Path $goldenRoot -Force | Out-Null
    $failures = New-Object System.Collections.Generic.List[string]

    foreach ($name in $fixtures.Keys) {
        $goldenFile = Join-Path $goldenRoot "$name.json"

        if ($Update) {
            $combined = [ordered]@{}
            foreach ($script in $scripts) {
                $result = Invoke-Discovery -Script $script.Path -FixturePath $fixtures[$name]
                foreach ($section in $script.Sections) {
                    if (-not $Local -and $machineSections -contains $section) { continue }
                    if (-not $combined.Contains($section)) { $combined[$section] = $result.$section }
                }
            }
            [System.IO.File]::WriteAllText($goldenFile, ($combined | ConvertTo-Json -Depth 20) + "`n")
            Write-Host "recorded $name"
            continue
        }

        if (-not (Test-Path -LiteralPath $goldenFile)) {
            $failures.Add("${name}: no golden file. Run with -Update to record one.")
            continue
        }
        $golden = [System.IO.File]::ReadAllText($goldenFile) | ConvertFrom-Json

        $covered = @{}
        foreach ($script in $scripts) {
            $result = Invoke-Discovery -Script $script.Path -FixturePath $fixtures[$name]
            foreach ($section in $script.Sections) {
                if (-not $Local -and $machineSections -contains $section) { continue }
                $covered[$section] = $true
                $actual = $result.$section
                $expected = $golden.$section

                if ($actual -is [System.Management.Automation.PSCustomObject] -and $expected -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($property in $actual.PSObject.Properties) {
                        if ((ConvertTo-Comparable $property.Value) -ne (ConvertTo-Comparable $expected.($property.Name))) {
                            $failures.Add("${name}: $($script.Path) $section.$($property.Name) differs.`n    expected $(ConvertTo-Comparable $expected.($property.Name))`n    actual   $(ConvertTo-Comparable $property.Value)")
                        }
                    }
                }
                elseif ((ConvertTo-Comparable $actual) -ne (ConvertTo-Comparable $expected)) {
                    $failures.Add("${name}: $($script.Path) $section differs.`n    expected $(ConvertTo-Comparable $expected)`n    actual   $(ConvertTo-Comparable $actual)")
                }
            }
        }

        foreach ($section in $golden.PSObject.Properties.Name) {
            if (-not $covered.ContainsKey($section)) { $failures.Add("${name}: no script reports $section any more.") }
        }
    }

    if ($Update) { return }
    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "$($failures.Count) difference(s)." -ForegroundColor Red
        exit 1
    }
    Write-Host "All $($fixtures.Count) fixtures match the golden output."
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
