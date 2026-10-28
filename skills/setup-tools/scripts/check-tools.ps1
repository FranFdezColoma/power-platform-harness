<#
.SYNOPSIS
    Read-only check of the developer machine: the tools the harness and the official skills need.

.DESCRIPTION
    Answers the questions the setup-tools skill needs before it proposes an install:

      - Which tools are installed (PowerShell, git, .NET SDK, Node.js, pac, gh, playwright-cli),
        and does each meet the minimum and preferred version in catalog.json?
      - Which recommended CLIs are installed? MCP servers registered with the agent are not
        visible from here: the agent checks its own.

    Everything here reads. Output is a single JSON document on stdout; a probe that fails is
    recorded as a field inside it rather than aborting the run.

.EXAMPLE
    ./check-tools.ps1

.EXAMPLE
    # No pac call at all, not even to see whether an authentication profile exists.
    ./check-tools.ps1 -SkipEnvironment
#>
[CmdletBinding()]
param(
    # Skip the one pac call this script makes (pac auth list), for the authProfile field.
    [switch]$SkipEnvironment,

    # Per-command timeout. A hung probe must not hang the caller.
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

. (Join-Path $PSScriptRoot '_common.ps1')

function Get-DotnetGlobalToolIds {
    param([bool]$DotnetPresent, [int]$Timeout = 30, $Run = $null)

    $result = [ordered]@{ packageIds = @(); error = $null }
    if (-not $DotnetPresent) {
        $result.error = "'dotnet' was not found on PATH."
        return $result
    }

    $run = $Run
    if (-not $run) { $run = Invoke-Tool -Name 'dotnet' -Arguments @('tool', 'list', '--global') -Timeout $Timeout }
    if (-not $run.Ran -or $run.ExitCode -ne 0) {
        $result.error = if ($run.Error) { $run.Error } elseif ($run.Stderr) { $run.Stderr } else { $run.Stdout }
        return $result
    }

    # `dotnet tool list` prints a fixed-width table with the package id in the first column.
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($run.Stdout -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed -match '^(Package Id|-{3,})') { continue }
        $columns = $trimmed -split '\s{2,}'
        if ($columns.Count -ge 1 -and $columns[0]) { $ids.Add($columns[0].ToLowerInvariant()) }
    }
    $result.packageIds = @($ids)
    return $result
}

function Get-DotnetSdkReport {
    param($Report, $Run = $null)

    # `dotnet --version` reports the SDK a global.json pins, not the newest one installed, so a
    # repository pinned to 6 would hide an installed 10. List the SDKs and take the highest.
    if (-not $Report['present']) { return $Report }

    $run = $Run
    if (-not $run) { $run = Invoke-Tool -Name 'dotnet' -Arguments @('--list-sdks') -Timeout 30 }
    if ($run.Ran -and $run.ExitCode -eq 0) {
        $versions = @(foreach ($line in ($run.Stdout -split "`r?`n")) {
            $match = [regex]::Match($line, '^\s*(\d+\.\d+\.\d+)')
            if ($match.Success) { [version]$match.Groups[1].Value }
        })
        if ($versions.Count -gt 0) {
            $Report['version'] = ($versions | Sort-Object -Descending | Select-Object -First 1).ToString()
            $Report['note'] = $null
        }
        else {
            $Report['version'] = $null
            $Report['note'] = 'dotnet is installed but reports no SDK, only a runtime.'
        }
    }
    return $Report
}

function Get-SkillExceptionReport {
    param($Exceptions)

    # Where each agent keeps the skills it installed: npx skills (shared by every Agent Skills
    # agent), then the plugin folders of Claude Code, Copilot CLI and Codex. Marketplace folders
    # hold the catalogues plugins are installed from, not installed skills, so they are skipped.
    $roots = @(
        (Join-Path $HOME '.agents/skills')
        (Join-Path $HOME '.claude/plugins')
        (Join-Path $HOME '.copilot/installed-plugins')
        (Join-Path $HOME '.codex/plugins')
        (Join-Path $HOME '.codex/skills')
    )
    $skillNames = @($Exceptions | ForEach-Object { $_.skill } | Select-Object -Unique)

    $copies = @{}
    foreach ($name in $skillNames) { $copies[$name] = New-Object System.Collections.Generic.List[string] }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $folders = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('marketplaces', 'marketplace-cache') })
        foreach ($folder in $folders) {
            foreach ($file in @(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Depth 6 -File -Filter 'SKILL.md' -Force -ErrorAction SilentlyContinue)) {
                $skill = Split-Path -Leaf (Split-Path -Parent $file.FullName)
                if ($copies.ContainsKey($skill)) { $copies[$skill].Add($file.FullName) }
            }
        }
    }

    foreach ($exception in $Exceptions) {
        $checked = @(foreach ($path in $copies[$exception.skill]) {
            $text = [System.IO.File]::ReadAllText($path)
            [ordered]@{ path = $path; containsQuote = $text.Contains($exception.quote) }
        })
        $quoting = @($checked | Where-Object { $_.containsQuote }).Count

        # stale: no copy has the rule any more, so the exception overrides something that changed.
        # mixed: copies of different versions disagree; the old ones are duplicates to remove.
        $status = 'ok'
        if ($checked.Count -eq 0) { $status = 'not-installed' }
        elseif ($quoting -eq 0) { $status = 'stale' }
        elseif ($quoting -lt $checked.Count) { $status = 'mixed' }

        [ordered]@{
            id     = $exception.id
            skill  = $exception.skill
            source = $exception.source
            quote  = $exception.quote
            status = $status
            copies = $checked
        }
    }
}

# --------------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------------

$catalogPath = Join-Path $PSScriptRoot 'catalog.json'
$exceptionsPath = Join-Path $PSScriptRoot 'skill-exceptions.json'
$notes = New-Object System.Collections.Generic.List[string]

try {

# ---- tooling ------------------------------------------------------------------------------

$versionProbes = @(
    @{ Key = 'pwsh'; Name = 'pwsh'; Arguments = @('--version') }
    @{ Key = 'powershell'; Name = 'powershell'; Arguments = @('-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()') }
    @{ Key = 'git'; Name = 'git'; Arguments = @('--version') }
    @{ Key = 'pac'; Name = 'pac'; Arguments = @('--version') }
    @{ Key = 'dotnet'; Name = 'dotnet'; Arguments = @('--version') }
    @{ Key = 'node'; Name = 'node'; Arguments = @('--version') }
    @{ Key = 'npm'; Name = 'npm'; Arguments = @('--version') }
    @{ Key = 'gh'; Name = 'gh'; Arguments = @('--version') }
    @{ Key = 'python'; Name = 'python'; Arguments = @('--version') }
    @{ Key = 'az'; Name = 'az'; Arguments = @('--version') }
    @{ Key = 'playwrightCli'; Name = 'playwright-cli'; Arguments = @('--version') }
)

# Every probe is independent, so all of them start before any is waited for: the toolchain check
# takes as long as the slowest one (usually pac) instead of the sum of all of them.
$probeJobs = @{}
foreach ($probe in $versionProbes) {
    $probeJobs[$probe.Key] = Start-Tool -Name $probe.Name -Arguments $probe.Arguments -Timeout 30
}
$dotnetSdksJob = Start-Tool -Name 'dotnet' -Arguments @('--list-sdks') -Timeout 30
$dotnetToolsJob = Start-Tool -Name 'dotnet' -Arguments @('tool', 'list', '--global') -Timeout 30

$tooling = [ordered]@{}
foreach ($probe in $versionProbes) {
    $tooling[$probe.Key] = Get-ToolReport -Name $probe.Name -Run (Wait-Tool -Job $probeJobs[$probe.Key])
}
$tooling['dotnet'] = Get-DotnetSdkReport -Report $tooling['dotnet'] -Run (Wait-Tool -Job $dotnetSdksJob)
$tooling['currentPowerShell'] = [ordered]@{
    present = $true
    version = $PSVersionTable.PSVersion.ToString()
    edition = [string]$PSVersionTable.PSEdition
}

$dataverseMcpProxyPackageId = 'microsoft.powerplatform.dataverse.mcp'
$dotnetGlobalTools = Get-DotnetGlobalToolIds -DotnetPresent $tooling.dotnet.present -Run (Wait-Tool -Job $dotnetToolsJob)
$dataverseMcpProxyInstalled = @($dotnetGlobalTools.packageIds) -contains $dataverseMcpProxyPackageId


# pac without an authentication profile cannot do anything useful, so the pac requirement reports
# whether one exists. Which environment it points at is the connect skill's question, not this one.
$environment = [ordered]@{ probed = -not $SkipEnvironment; hasAuthProfile = $false }
if (-not $SkipEnvironment -and $tooling.pac.present) {
    $authRun = Invoke-Tool -Name 'pac' -Arguments @('auth', 'list')
    if ($authRun.Ran -and $authRun.ExitCode -eq 0) {
        $environment['hasAuthProfile'] = @($authRun.Stdout -split "`r?`n" | Where-Object { $_ -match '^\s*\[\d+\]' }).Count -gt 0
    }
}
elseif (-not $SkipEnvironment) {
    $environment['probed'] = $false
}

# ---- recommended tools -----------------------------------------------------------------------

# Only the command-line side is visible from a script. Whether a Dataverse or Playwright MCP
# server is registered depends on the agent running the skill, and that agent checks its own
# tools: asking one agent's CLI (claude mcp list) would be wrong for every other agent.
$recommendedTools = [ordered]@{
    playwrightCli = [ordered]@{
        installed = $tooling.playwrightCli.present
        version   = $tooling.playwrightCli.version
        install   = 'npm install -g @playwright/cli@latest'
        mcpAlternative = 'claude mcp add playwright npx @playwright/mcp@latest'
    }
    dataverseMcpProxy = [ordered]@{
        installed = $dataverseMcpProxyInstalled
        install   = 'dotnet tool install --global Microsoft.PowerPlatform.Dataverse.MCP'
        docs      = 'https://learn.microsoft.com/power-apps/maker/data-platform/data-platform-mcp'
        note      = 'The proxy is one of two ways to connect: the remote endpoint needs no local install. Either way the server must be registered with the agent and the feature enabled on the environment.'
    }
}

$baseline = $null
if (Test-Path -LiteralPath $catalogPath) {
    try { $baseline = [System.IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json }
    catch { $notes.Add("catalog.json could not be parsed: $($_.Exception.Message)") | Out-Null }
}
else {
    $notes.Add("catalog.json was not found at $catalogPath; no requirement was checked.") | Out-Null
}

# ---- toolchain -----------------------------------------------------------------------------

# Either PowerShell satisfies the requirement, so report the newest one available: pwsh when it is
# installed, Windows PowerShell otherwise. This script is itself running in one of them.
$powerShellVersion = $tooling.currentPowerShell.version
foreach ($candidate in @($tooling.pwsh, $tooling.powershell)) {
    if ($candidate.present -and $candidate.version) {
        $candidateVersion = ConvertTo-ComparableVersion -Text $candidate.version
        if ($candidateVersion -and $candidateVersion -gt (ConvertTo-ComparableVersion -Text $powerShellVersion)) {
            $powerShellVersion = $candidate.version
        }
    }
}

$requirements = @()
if ($baseline) {
    foreach ($assertion in @($baseline.assertions | Where-Object { $_.kind -eq 'machine' })) {
        if ($assertion.tool -eq 'powershell') {
            $toolPresent = $true
            $version = $powerShellVersion
        }
        else {
            $report = $tooling[$assertion.tool]
            $toolPresent = [bool]($report -and $report.present)
            $version = if ($report) { $report.version } else { $null }
        }

        $requirement = [ordered]@{
            id        = $assertion.id
            tool      = $assertion.topic
            tier      = $assertion.tier
            present   = $toolPresent
            version   = $version
            minimum   = $assertion.minimum
            preferred = $assertion.preferred
            status    = Get-VersionStatus -Present $toolPresent -Version $version -Minimum $assertion.minimum -Preferred $assertion.preferred
            install   = $assertion.install
        }
        if ($assertion.tool -eq 'node' -and $requirement['status'] -eq 'ok') {
            # Vitest only accepts even (LTS-line) Node majors, so 23 or 25 clears the minimum and
            # still cannot run the tests. A warning, not a status: the minimum is unchanged.
            $nodeVersion = ConvertTo-ComparableVersion -Text $version
            if ($nodeVersion -and ($nodeVersion.Major % 2) -eq 1) {
                $requirement['warning'] = "Node $($nodeVersion.Major) is an odd-numbered, non-LTS release: the pinned Vitest does not support it. Use $($assertion.preferred) or another even-numbered major."
            }
        }
        if ($assertion.tool -eq 'pac') {
            # pac without an authentication profile cannot generate early-bound classes, create a
            # feature solution or read the environment, so the profile is part of the requirement.
            $requirement['authProfile'] = if ($environment.probed) { $environment.hasAuthProfile } else { $null }
        }
        $requirements += $requirement
    }
}

# ---- skill exceptions ------------------------------------------------------------------------

$skillExceptions = @()
if (Test-Path -LiteralPath $exceptionsPath) {
    try { $skillExceptions = @(Get-SkillExceptionReport -Exceptions ([System.IO.File]::ReadAllText($exceptionsPath) | ConvertFrom-Json).exceptions) }
    catch { $notes.Add("skill-exceptions.json could not be read: $($_.Exception.Message)") | Out-Null }
}
else {
    $notes.Add("skill-exceptions.json was not found at $exceptionsPath; no exception was checked.") | Out-Null
}

# ---- output --------------------------------------------------------------------------------

$report = [ordered]@{
    schemaVersion   = 1
    generatedAt     = (Get-Date).ToString('o')
    tooling         = $tooling
    toolchain       = [ordered]@{
        requirements = $requirements
        recommended  = $recommendedTools
    }
    skillExceptions = $skillExceptions
    notes           = @($notes)
}

$report | ConvertTo-Json -Depth 12

}
finally {
    if (Test-Path -LiteralPath $script:scratchRoot) {
        Remove-Item -LiteralPath $script:scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
