<#
.SYNOPSIS
    Static checks over this plugin repository: the invariants no single script can check on itself.

.DESCRIPTION
    - Every copy of a shared helper (_common.ps1, _dataverse.ps1, _environment.ps1) is identical.
      Each skill carries its own copy so it works when installed on its own; they must not drift.
    - Every entry in setup-tools' catalog.json still quotes text that is in the file it points at,
      so a version changed in toolchain.md without the catalog fails here instead of silently.
    - Every exception in setup-tools' skill-exceptions.json is quoted, in double quotes, by the
      exceptions document the templates ship, so the check and the document cannot drift apart.
    - Every PowerShell script parses, and uses none of the syntax Windows PowerShell 5.1 rejects.

    Read-only. Exits 1 and lists every failure, or prints a one-line summary.

.EXAMPLE
    pwsh -NoProfile -File tests/Test-Repository.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillsRoot = Join-Path $repoRoot 'skills'
$failures = New-Object System.Collections.Generic.List[string]
$checks = 0

function Get-Relative {
    param([string]$FullPath)
    return $FullPath.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
}

# ---- shared helpers are identical ----------------------------------------------------------

foreach ($helper in @('_common.ps1', '_dataverse.ps1', '_environment.ps1')) {
    $copies = @(Get-ChildItem -LiteralPath $skillsRoot -Recurse -File -Filter $helper |
        Where-Object { $_.FullName -notmatch '[\\/]templates[\\/]' })
    $checks++
    if ($copies.Count -lt 2) {
        $failures.Add("$helper exists in $($copies.Count) skill(s); a shared helper is expected in at least two.")
        continue
    }
    $reference = [System.IO.File]::ReadAllText($copies[0].FullName)
    foreach ($copy in $copies | Select-Object -Skip 1) {
        if ([System.IO.File]::ReadAllText($copy.FullName) -cne $reference) {
            $failures.Add("$(Get-Relative $copy.FullName) differs from $(Get-Relative $copies[0].FullName). Edit one copy, then copy it over the others.")
        }
    }
}

# ---- the catalog still matches toolchain.md ------------------------------------------------

$catalogPath = Join-Path $skillsRoot 'setup-tools/scripts/catalog.json'
$setupProjectRoot = Join-Path $skillsRoot 'setup-project'
$catalog = [System.IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
foreach ($entry in $catalog.assertions) {
    if (-not $entry.assertedIn -or -not $entry.assertedText) { continue }
    $checks++
    $file = Join-Path $setupProjectRoot $entry.assertedIn
    if (-not (Test-Path -LiteralPath $file)) {
        $failures.Add("catalog.json $($entry.id) points at $($entry.assertedIn), which does not exist under skills/setup-project.")
    }
    elseif (-not ([System.IO.File]::ReadAllText($file)).Contains($entry.assertedText)) {
        $failures.Add("catalog.json $($entry.id) quotes text that is no longer in $($entry.assertedIn): $($entry.assertedText)")
    }
}

# ---- the exceptions document quotes what skill-exceptions.json checks ---------------------

$exceptionsPath = Join-Path $skillsRoot 'setup-tools/scripts/skill-exceptions.json'
$exceptions = [System.IO.File]::ReadAllText($exceptionsPath) | ConvertFrom-Json
foreach ($entry in $exceptions.exceptions) {
    $checks++
    $file = Join-Path $setupProjectRoot $entry.documentedIn
    if (-not (Test-Path -LiteralPath $file)) {
        $failures.Add("skill-exceptions.json $($entry.id) points at $($entry.documentedIn), which does not exist under skills/setup-project.")
    }
    elseif (-not ([System.IO.File]::ReadAllText($file)).Contains("`"$($entry.quote)`"")) {
        $failures.Add("skill-exceptions.json $($entry.id) quotes text that $($entry.documentedIn) no longer quotes: $($entry.quote)")
    }
}

# ---- every script parses and stays Windows PowerShell 5.1 compatible -----------------------

# Syntax pwsh 7 accepts and 5.1 rejects. The scripts ship into projects that may be stuck on 5.1.
$incompatible = @(
    @{ Pattern = '\?\?=?'; Name = 'the null-coalescing operator' }
    @{ Pattern = '\?\.'; Name = 'the null-conditional operator' }
    @{ Pattern = 'ForEach-Object\s+-Parallel'; Name = 'ForEach-Object -Parallel' }
    @{ Pattern = '\.ArgumentList\.Add'; Name = 'ProcessStartInfo.ArgumentList' }
    @{ Pattern = '\s\?\s[^:]+\s:\s'; Name = 'the ternary operator' }
)

$scripts = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|bin|obj|\.git)[\\/]' })
foreach ($script in $scripts) {
    $checks++
    $relative = Get-Relative $script.FullName
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $failures.Add("${relative}:$($parseError.Extent.StartLineNumber) does not parse: $($parseError.Message)")
    }

    # Only code tokens are checked: the same characters inside a string or a comment are harmless.
    $code = (@($tokens | Where-Object {
        $_.Kind -notin @('Comment', 'StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')
    }) | ForEach-Object { $_.Text }) -join ' '
    foreach ($rule in $incompatible) {
        if ($code -match $rule.Pattern) { $failures.Add("$relative uses $($rule.Name), which Windows PowerShell 5.1 rejects.") }
    }

    # Windows PowerShell 5.1 reads a UTF-8 file without a BOM as ANSI: keep every script ASCII.
    $bytes = [System.IO.File]::ReadAllBytes($script.FullName)
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
        $failures.Add("$relative contains non-ASCII characters; Windows PowerShell 5.1 would misread them.")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "$($failures.Count) failure(s) in $checks check(s)." -ForegroundColor Red
    exit 1
}
Write-Host "All $checks checks passed."
