<#
.SYNOPSIS
    Read-only check of the developer machine: the tools, skills and plugins the harness and the
    official skills need, and what to do about each gap.

.DESCRIPTION
    Answers the questions the setup-tools skill needs before it proposes anything:

      - Which tools are installed (PowerShell, git, .NET SDK, Node.js, pac, az, gh, Python,
        playwright-cli), and does each meet the minimum and preferred version in catalog.json?
      - How is pac installed: the Windows installer the harness expects, the .NET global tool, or
        both?
      - Which agents are on this machine, and which of the mandatory plugins (model-apps,
        power-automate, Ponytail) each one has, at which version against the latest one?
      - Where are the Dataverse skills installed, how many copies are there, and are they current?
      - Is the default-on telemetry of model-apps and power-automate still undecided?
      - Does every installed copy of an official skill still quote the rule its exception overrides?

    The answers end in `proposals`: every install, update, removal or setting the skill can offer,
    each with its exact commands. A machine that needs nothing has none.

    Everything here reads: tools, files under the user profile and, unless -Offline, GitHub (one
    git tree and one plugin.json per plugin, the way the installers themselves check for updates).
    Output is a single JSON document on stdout; a probe that fails is recorded as a field inside it
    rather than aborting the run.

    Dot-sourced, the script only defines its functions, so tests can call them with fake facts.

.EXAMPLE
    ./check-tools.ps1 -Path .

.EXAMPLE
    # No pac call and no network at all.
    ./check-tools.ps1 -SkipEnvironment -Offline
#>
[CmdletBinding()]
param(
    # Skip the one pac call this script makes (pac auth list), for the authProfile field.
    [switch]$SkipEnvironment,

    # Skip the GitHub requests that detect updates. Everything else is still checked.
    [switch]$Offline,

    # A repository with .power-platform/project.json: its provider decides whether gh or the az
    # azure-devops extension is required. Without it, both are reported as conditional.
    [string]$Path,

    # Per-command timeout. A hung probe must not hang the caller.
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

. (Join-Path $PSScriptRoot '_common.ps1')

# --------------------------------------------------------------------------------------------
# Reading the output of other tools. Each returns $null when the output cannot be read.
# --------------------------------------------------------------------------------------------

function Read-TextFile {
    param([string]$FullPath)

    # A locked or unreadable file is a fact the report can carry, not a reason to stop.
    try { return [System.IO.File]::ReadAllText($FullPath) }
    catch { return $null }
}

function Read-Json {
    param([string]$Json)

    # Windows PowerShell passes a JSON array down the pipeline as one object and pwsh enumerates
    # it, so the items are always returned wrapped: Items is an array either way.
    $result = [pscustomobject]@{ Ok = $false; Items = @() }
    if (-not $Json -or -not $Json.Trim()) { return $result }
    try {
        $value = $Json | ConvertFrom-Json
        $result.Items = @($value | Where-Object { $null -ne $_ })
        $result.Ok = $true
    }
    catch { }
    return $result
}

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

function ConvertFrom-ClaudePluginList {
    param([string]$Json)

    $parsed = Read-Json -Json $Json
    if (-not $parsed.Ok) { return $null }
    return @(foreach ($item in $parsed.Items) {
        if (-not $item.id) { continue }
        [ordered]@{
            id          = [string]$item.id
            version     = $item.version
            scope       = $item.scope
            enabled     = [bool]$item.enabled
            installPath = $item.installPath
        }
    })
}

function ConvertFrom-ClaudeMarketplaceList {
    param([string]$Json)

    $parsed = Read-Json -Json $Json
    if (-not $parsed.Ok) { return $null }
    return @(foreach ($item in $parsed.Items) {
        if (-not $item.name) { continue }
        [ordered]@{ name = [string]$item.name; repo = $(if ($item.source -eq 'github') { $item.repo } else { $null }) }
    })
}

function ConvertFrom-CopilotPluginList {
    param([string]$Text)

    if ($null -eq $Text) { return $null }

    # `copilot plugin list` has no JSON form. Each section starts with an unindented heading, and
    # only "Installed plugins:" holds what was installed: built-in and live plugins are not.
    $plugins = New-Object System.Collections.Generic.List[object]
    $inInstalled = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\S') {
            $inInstalled = $line -match '^Installed plugins:'
            continue
        }
        if (-not $inInstalled) { continue }
        $match = [regex]::Match($line, '^\s+\S\s+(?<id>[^\s@]+@[^\s(]+)\s+\(v(?<version>[^)]+)\)(?<rest>.*)$')
        if ($match.Success) {
            $plugins.Add([ordered]@{
                id      = $match.Groups['id'].Value
                version = $match.Groups['version'].Value
                enabled = $match.Groups['rest'].Value -notmatch '\(disabled\)'
            })
        }
    }
    return $plugins.ToArray()
}

function ConvertFrom-CopilotMarketplaceList {
    param([string]$Text)

    if ($null -eq $Text) { return $null }

    $marketplaces = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s+\S\s+(?<name>\S+)\s+\((?<kind>[A-Za-z]+):\s*(?<source>[^)]+)\)\s*$')
        if ($match.Success) {
            $repo = $null
            if ($match.Groups['kind'].Value -eq 'GitHub') { $repo = $match.Groups['source'].Value.Trim() }
            $marketplaces.Add([ordered]@{ name = $match.Groups['name'].Value; repo = $repo })
        }
    }
    return $marketplaces.ToArray()
}

function ConvertFrom-AzExtensionList {
    param([string]$Json)

    $parsed = Read-Json -Json $Json
    if (-not $parsed.Ok) { return $null }
    return @(foreach ($item in $parsed.Items) { if ($item.name) { [string]$item.name } })
}

function Get-RepositoryProvider {
    param([string]$ProjectJson)

    $parsed = Read-Json -Json $ProjectJson
    if (-not $parsed.Ok -or $parsed.Items.Count -ne 1) { return $null }
    $provider = $parsed.Items[0].connections.repository.provider
    if ($provider -is [string] -and $provider -in @('github', 'azure-devops')) { return $provider.ToLowerInvariant() }
    return $null
}

function ConvertFrom-GitTree {
    param([string]$Json)

    $parsed = Read-Json -Json $Json
    # A truncated tree lacks folders that still exist upstream: treat it as unknown.
    if (-not $parsed.Ok -or $parsed.Items.Count -ne 1 -or $null -eq $parsed.Items[0].tree -or $parsed.Items[0].truncated) { return $null }
    $hashes = @{}
    foreach ($entry in @($parsed.Items[0].tree)) {
        if ($entry.type -eq 'tree' -and $entry.path) { $hashes[[string]$entry.path] = [string]$entry.sha }
    }
    return $hashes
}

function Get-ManifestVersion {
    param([string]$Json)

    $parsed = Read-Json -Json $Json
    if (-not $parsed.Ok -or $parsed.Items.Count -ne 1) { return $null }
    $version = $parsed.Items[0].version
    if ($version) { return [string]$version }
    return $null
}

# --------------------------------------------------------------------------------------------
# Assessment: facts in, report and proposals out. Pure, so it is tested with fake facts.
# --------------------------------------------------------------------------------------------

function Get-TelemetryEnvVarName {
    param([string]$Plugin)

    # The plugins' own rule (shared/telemetry user-config.js): upper-cased, every run of
    # non-alphanumerics replaced by an underscore.
    return 'POWER_PLATFORM_SKILLS_TELEMETRY_' + [regex]::Replace($Plugin.ToUpperInvariant(), '[^A-Z0-9]+', '_') + '_OPTOUT'
}

function Get-PacInstallKind {
    param([string]$CommandPath)

    $normalized = $CommandPath -replace '/', '\'
    if ($normalized -match '\\\.dotnet\\tools\\') { return 'dotnet-tool' }
    if ($normalized -match '\\Microsoft\\PowerAppsCLI\\') { return 'msi' }
    if ($normalized -match 'powerplatform-vscode') { return 'vscode-extension' }
    return 'other'
}

function Get-PluginName {
    param([string]$Id)
    return ($Id -split '@')[0]
}

function Format-AgentCommand {
    param([string]$Template, [string]$Plugin, [string]$Marketplace)
    return $Template.Replace('{plugin}', $Plugin).Replace('{marketplace}', $Marketplace)
}

function New-Proposal {
    param(
        [string]$Id,
        [string]$Action,
        [string]$Target,
        $Agent = $null,
        [string]$Severity,
        [string]$Reason,
        [string[]]$Commands,
        $DependsOn = $null
    )

    return [ordered]@{
        id        = $Id
        action    = $Action
        target    = $Target
        agent     = $Agent
        severity  = $Severity
        reason    = $Reason
        commands  = @($Commands)
        dependsOn = $DependsOn
    }
}

function Get-MachineAssessment {
    param($Facts)

    $catalog = $Facts.Catalog
    $tooling = $Facts.Tooling
    $notes = New-Object System.Collections.Generic.List[string]
    $proposals = New-Object System.Collections.Generic.List[object]
    $proposalIds = @{}

    # ---- machine tools -------------------------------------------------------------------

    # Either PowerShell satisfies the requirement, so report the newest one available. This
    # script is itself running in one of them.
    $powerShellVersion = $null
    foreach ($key in @('currentPowerShell', 'pwsh', 'powershell')) {
        $candidate = $tooling[$key]
        if (-not ($candidate -and $candidate.present -and $candidate.version)) { continue }
        $candidateVersion = ConvertTo-ComparableVersion -Text $candidate.version
        if ($candidateVersion -and (-not $powerShellVersion -or $candidateVersion -gt (ConvertTo-ComparableVersion -Text $powerShellVersion))) {
            $powerShellVersion = $candidate.version
        }
    }

    $requirements = New-Object System.Collections.Generic.List[object]
    $pacAssertion = $null
    $pacRequirement = $null
    foreach ($assertion in @($catalog.assertions | Where-Object { $_.kind -eq 'machine' })) {
        if ($assertion.tool -eq 'powershell') {
            $present = $true
            $version = $powerShellVersion
        }
        else {
            $report = $tooling[$assertion.tool]
            $present = [bool]($report -and $report.present)
            $version = if ($report) { $report.version } else { $null }
        }

        $requirement = [ordered]@{
            id               = $assertion.id
            tool             = $assertion.topic
            tier             = $assertion.tier
            present          = $present
            version          = $version
            minimum          = $assertion.minimum
            minimumExclusive = [bool]$assertion.minimumExclusive
            minimumSource    = $assertion.minimumSource
            documented       = @($assertion.documented)
            preferred        = $assertion.preferred
            status           = Get-VersionStatus -Present $present -Version $version -Minimum $assertion.minimum -Preferred $assertion.preferred -MinimumExclusive:([bool]$assertion.minimumExclusive)
            install          = $assertion.install
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
            # pac without an authentication profile cannot generate early-bound classes or read the
            # environment, so the profile is part of the requirement. dv-connect creates it.
            $requirement['authProfile'] = if ($Facts.Environment -and $Facts.Environment.probed) { [bool]$Facts.Environment.hasAuthProfile } else { $null }
            $pacAssertion = $assertion
            $pacRequirement = $requirement
        }
        $requirements.Add($requirement)

        # pac has its own proposals below: which install to keep matters more than the version.
        if ($assertion.tool -eq 'pac') { continue }
        $severity = $null
        if ($requirement['status'] -in @('missing', 'below-minimum')) { $severity = 'required' }
        elseif ($requirement['status'] -eq 'below-preferred' -or $requirement['warning']) { $severity = 'recommended' }
        if (-not $severity) { continue }
        if (-not $assertion.install) {
            $notes.Add("$($assertion.topic) is $($requirement['status']). $($assertion.guidance)")
            continue
        }
        $reason = if ($requirement['warning']) { $requirement['warning'] } else { "$($assertion.topic) is $($requirement['status'])." }
        $proposal = New-Proposal -Id "install:$($assertion.tool)" -Action 'install' -Target $assertion.topic -Severity $severity -Reason $reason -Commands @($assertion.install)
        $proposals.Add($proposal)
        $proposalIds[$proposal.id] = $true
    }

    # ---- pac installs --------------------------------------------------------------------

    $installs = New-Object System.Collections.Generic.List[object]
    foreach ($commandPath in @($Facts.PacCommandPaths)) {
        if (-not $commandPath) { continue }
        $installs.Add([ordered]@{ kind = (Get-PacInstallKind -CommandPath $commandPath); path = $commandPath; onPath = $true })
    }
    if ($Facts.PacMsiRootExists -and -not @($installs | Where-Object { $_.kind -eq 'msi' }).Count) {
        $installs.Add([ordered]@{ kind = 'msi'; path = $Facts.PacMsiRoot; onPath = $false })
    }
    if (@($Facts.DotnetToolIds) -contains 'microsoft.powerapps.cli.tool' -and -not @($installs | Where-Object { $_.kind -eq 'dotnet-tool' }).Count) {
        $installs.Add([ordered]@{ kind = 'dotnet-tool'; path = $null; onPath = $false })
    }
    $active = @($installs | Where-Object { $_.onPath } | Select-Object -First 1)
    $pac = [ordered]@{
        installs  = $installs.ToArray()
        active    = $(if ($active.Count) { $active[0].kind } else { $null })
        duplicate = $installs.Count -gt 1
    }

    if ($pacAssertion) {
        $pacStatus = $pacRequirement['status']
        $hasMsi = @($installs | Where-Object { $_.kind -eq 'msi' }).Count -gt 0
        if (-not $hasMsi) {
            $severity = if ($pacStatus -in @('missing', 'below-minimum')) { 'required' } else { 'recommended' }
            $proposal = New-Proposal -Id 'install:pac-msi' -Action 'install' -Target $pacAssertion.topic -Severity $severity `
                -Reason "The harness uses pac from the Windows installer; pac is $pacStatus." -Commands @($pacAssertion.install)
            $proposals.Add($proposal)
            $proposalIds[$proposal.id] = $true
        }
        elseif ($pac.active -eq 'msi' -and $pacStatus -eq 'below-minimum') {
            $proposals.Add((New-Proposal -Id 'update:pac' -Action 'update' -Target $pacAssertion.topic -Severity 'required' `
                -Reason "pac $($pacRequirement['version']) is below the minimum: above $($pacAssertion.minimum)." -Commands @($pacAssertion.update)))
        }
        if (@($installs | Where-Object { $_.kind -eq 'dotnet-tool' }).Count) {
            $dependsOn = if ($proposalIds.ContainsKey('install:pac-msi')) { 'install:pac-msi' } else { $null }
            $proposals.Add((New-Proposal -Id 'uninstall:pac-dotnet-tool' -Action 'uninstall' -Target 'pac (.NET global tool)' -Severity 'recommended' `
                -Reason 'pac is installed as a .NET global tool, which shadows the Windows installer on PATH and does not keep versions side by side.' `
                -Commands @($pacAssertion.removeDotnetTool) -DependsOn $dependsOn))
        }
    }

    # ---- per-repository tools ------------------------------------------------------------

    $provider = $Facts.RepositoryProvider
    $repositoryTools = New-Object System.Collections.Generic.List[object]
    foreach ($assertion in @($catalog.assertions | Where-Object { $_.kind -eq 'repository' })) {
        $extensionsUnknown = $false
        if ($assertion.tool -eq 'azureDevOpsExtension') {
            $present = ($null -ne $Facts.AzExtensions) -and (@($Facts.AzExtensions) -contains 'azure-devops')
            $extensionsUnknown = ($null -eq $Facts.AzExtensions) -and [bool]($tooling['az'] -and $tooling['az'].present)
        }
        else {
            $report = $tooling[$assertion.tool]
            $present = [bool]($report -and $report.present)
        }

        if (-not $provider) { $applies = $null; $status = 'conditional' }
        elseif ($provider -eq $assertion.provider) {
            $applies = $true
            $status = if ($present) { 'ok' } elseif ($extensionsUnknown) { 'unknown' } else { 'missing' }
        }
        else { $applies = $false; $status = 'not-applicable' }

        $repositoryTools.Add([ordered]@{
            id       = $assertion.id
            tool     = $assertion.topic
            provider = $assertion.provider
            applies  = $applies
            present  = $present
            status   = $status
            install  = $assertion.install
        })

        if ($status -eq 'unknown') { $notes.Add("The az extensions could not be listed, so $($assertion.topic) was not checked.") }
        if ($status -ne 'missing') { continue }
        $dependsOn = $null
        if ($assertion.requires -and $proposalIds.ContainsKey("install:$($assertion.requires)")) { $dependsOn = "install:$($assertion.requires)" }
        $proposal = New-Proposal -Id "install:$($assertion.tool)" -Action 'install' -Target $assertion.topic -Severity 'required' `
            -Reason "The repository is on $($assertion.provider). $($assertion.guidance)" -Commands @($assertion.install) -DependsOn $dependsOn
        $proposals.Add($proposal)
        $proposalIds[$proposal.id] = $true
    }

    # ---- recommended tools ---------------------------------------------------------------

    $recommended = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($catalog.recommended)) {
        $report = $tooling[$entry.tool]
        $installed = [bool]($report -and $report.present)
        $recommended.Add([ordered]@{
            id        = $entry.id
            tool      = $entry.topic
            installed = $installed
            version   = $(if ($report) { $report.version } else { $null })
            install   = $entry.install
        })
        if (-not $installed) {
            $proposals.Add((New-Proposal -Id "install:$($entry.tool)" -Action 'install' -Target $entry.topic -Severity 'recommended' -Reason $entry.guidance -Commands @($entry.install)))
        }
    }

    # ---- agents and their plugins ----------------------------------------------------------

    # Claude Code installs a plugin per user or per project; only the user's install is this
    # machine's. Project and local installs belong to the folders they were made in.
    $claudeUserPlugins = $null
    if ($null -ne $Facts.ClaudePlugins) { $claudeUserPlugins = @($Facts.ClaudePlugins | Where-Object { $_.scope -eq 'user' }) }
    $installedByAgent = @{ claude = $claudeUserPlugins; copilot = $(if ($null -ne $Facts.CopilotPlugins) { @($Facts.CopilotPlugins) } else { $null }) }
    $marketplacesByAgent = @{ claude = $Facts.ClaudeMarketplaces; copilot = $Facts.CopilotMarketplaces }

    $agents = New-Object System.Collections.Generic.List[object]
    $pluginRows = New-Object System.Collections.Generic.List[object]
    # Added after the Dataverse proposals: the skills come first, then each agent's plugins.
    $pluginProposals = New-Object System.Collections.Generic.List[object]
    $latestVersions = $null
    if ($Facts.Upstream) { $latestVersions = $Facts.Upstream.pluginVersions }

    foreach ($agent in @($catalog.agents)) {
        $report = $tooling[$agent.id]
        $present = [bool]($report -and $report.present)
        $agents.Add([ordered]@{
            id      = $agent.id
            label   = $agent.label
            present = $present
            version = $(if ($report) { $report.version } else { $null })
            plugins = $agent.plugins
            note    = $agent.note
        })
        if (-not $present -or $agent.plugins -ne 'verified') { continue }

        $installedPlugins = $installedByAgent[$agent.id]
        if ($null -eq $installedPlugins) {
            $notes.Add("$($agent.label) is installed, but its plugin list could not be read: its plugins were not checked.")
            continue
        }

        foreach ($plugin in @($catalog.plugins)) {
            $installed = @($installedPlugins | Where-Object { (Get-PluginName -Id $_.id) -eq $plugin.name } | Select-Object -First 1)
            $version = if ($installed.Count) { $installed[0].version } else { $null }
            $latest = if ($latestVersions) { $latestVersions[$plugin.name] } else { $null }

            $status = 'missing'
            if ($installed.Count) {
                $status = 'ok'
                $installedVersion = ConvertTo-ComparableVersion -Text $version
                $latestVersion = ConvertTo-ComparableVersion -Text $latest
                if ($installedVersion -and $latestVersion -and $latestVersion -gt $installedVersion) { $status = 'update-available' }
            }
            $pluginRows.Add([ordered]@{
                agent       = $agent.id
                plugin      = $plugin.name
                marketplace = $plugin.marketplace
                installed   = [bool]$installed.Count
                version     = $version
                latest      = $latest
                status      = $status
            })

            if ($status -eq 'missing') {
                # The install names the plugin by the marketplace's local name, which is whatever
                # the user registered the repository as. Register it only when it is not there yet.
                $registered = @(@($marketplacesByAgent[$agent.id]) | Where-Object { $_ -and $_.repo -and $_.repo -eq $plugin.marketplaceSource } | Select-Object -First 1)
                $commands = @()
                $marketplaceName = $plugin.marketplace
                if ($registered.Count) { $marketplaceName = $registered[0].name }
                else { $commands += $agent.addMarketplace.Replace('{source}', $plugin.marketplaceSource) }
                $commands += Format-AgentCommand -Template $agent.install -Plugin $plugin.name -Marketplace $marketplaceName
                $pluginProposals.Add((New-Proposal -Id "install:$($plugin.name)@$($agent.id)" -Action 'install' -Target $plugin.name -Agent $agent.id -Severity 'required' `
                    -Reason "$($plugin.name) is mandatory for the harness and is not installed in $($agent.label)." -Commands $commands))
            }
            elseif ($status -eq 'update-available') {
                $marketplaceName = ($installed[0].id -split '@', 2)[1]
                $pluginProposals.Add((New-Proposal -Id "update:$($plugin.name)@$($agent.id)" -Action 'update' -Target $plugin.name -Agent $agent.id -Severity 'recommended' `
                    -Reason "$($agent.label) has $($plugin.name) $version; $latest is available." `
                    -Commands @(Format-AgentCommand -Template $agent.update -Plugin $plugin.name -Marketplace $marketplaceName)))
            }
        }
    }

    # ---- Dataverse skills ----------------------------------------------------------------

    $package = @($catalog.skillPackages)[0]
    $copies = New-Object System.Collections.Generic.List[object]
    $npxSkills = @($Facts.NpxSkills | Where-Object { $_ -and $_.source -eq $package.source })
    if ($npxSkills.Count) {
        $copies.Add([ordered]@{ kind = 'npx'; agent = $null; id = $null; path = $null; version = $null; skills = @($npxSkills | ForEach-Object { $_.name }) })
    }
    foreach ($plugin in @($claudeUserPlugins | Where-Object { $_ -and (Get-PluginName -Id $_.id) -eq $package.pluginName })) {
        $copies.Add([ordered]@{ kind = 'claude-plugin'; agent = 'claude'; id = $plugin.id; path = $plugin.installPath; version = $plugin.version })
    }
    foreach ($plugin in @($Facts.CopilotPlugins | Where-Object { $_ -and (Get-PluginName -Id $_.id) -eq $package.pluginName })) {
        $copies.Add([ordered]@{ kind = 'copilot-plugin'; agent = 'copilot'; id = $plugin.id; path = $null; version = $plugin.version })
    }
    foreach ($folder in @($Facts.LooseDataverseFolders | Where-Object { $_ })) {
        $copies.Add([ordered]@{ kind = 'loose-folder'; agent = $null; id = $null; path = $folder.path; version = $folder.version })
    }

    # The npx copy is the one every Agent Skills agent reads; without it, the newest plugin copy.
    # A loose folder is loaded by no agent, so it is never the copy in use, only one to remove.
    $primaryIndex = -1
    for ($index = 0; $index -lt $copies.Count; $index++) {
        if ($copies[$index].kind -eq 'npx') { $primaryIndex = $index; break }
    }
    if ($primaryIndex -lt 0) {
        for ($index = 0; $index -lt $copies.Count; $index++) {
            if ($copies[$index].kind -eq 'loose-folder') { continue }
            $candidate = ConvertTo-ComparableVersion -Text $copies[$index].version
            $best = if ($primaryIndex -ge 0) { ConvertTo-ComparableVersion -Text $copies[$primaryIndex].version } else { $null }
            if ($primaryIndex -lt 0 -or ($candidate -and (-not $best -or $candidate -gt $best))) { $primaryIndex = $index }
        }
    }

    $dataverseStatus = 'missing'
    if ($primaryIndex -ge 0) {
        if ($copies.Count -gt 1) { $dataverseStatus = 'duplicates' }
        elseif ($copies[0].kind -eq 'npx') { $dataverseStatus = 'ok' }
        else { $dataverseStatus = 'plugin-only' }
    }

    $outdated = New-Object System.Collections.Generic.List[string]
    $upstreamHashes = $null
    if ($Facts.Upstream -and $Facts.Upstream.skillFolderHashes) { $upstreamHashes = $Facts.Upstream.skillFolderHashes[$package.source] }
    if ($upstreamHashes) {
        foreach ($skill in $npxSkills) {
            $folder = ($skill.skillPath -replace '\\', '/') -replace '/?SKILL\.md$', ''
            $latestHash = $upstreamHashes[$folder]
            if (-not $latestHash) { $notes.Add("$($skill.name) is no longer in $($package.source); npx skills update leaves it as it is."); continue }
            if ($latestHash -ne $skill.skillFolderHash) { $outdated.Add($skill.name) }
        }
    }

    $dataverseSkills = [ordered]@{
        status       = $dataverseStatus
        primary      = $(if ($primaryIndex -ge 0) { $copies[$primaryIndex] } else { $null })
        copies       = $copies.ToArray()
        outdated     = $outdated.ToArray()
        updatesKnown = [bool]$upstreamHashes
    }

    if ($dataverseStatus -eq 'missing') {
        $proposals.Add((New-Proposal -Id 'install:dataverse-skills' -Action 'install' -Target $package.topic -Severity 'required' -Reason $package.guidance -Commands @($package.install)))
    }
    if ($dataverseStatus -eq 'plugin-only') {
        $notes.Add("The Dataverse skills are installed only as a $($copies[0].kind); accepted, but the harness expects them from npx skills.")
    }
    $agentsById = @{}
    foreach ($agent in @($catalog.agents)) { $agentsById[$agent.id] = $agent }
    for ($index = 0; $index -lt $copies.Count; $index++) {
        if ($index -eq $primaryIndex) { continue }
        $copy = $copies[$index]
        $reason = "A second copy of the Dataverse skills ($($copy.kind)$(if ($copy.version) { " $($copy.version)" })) next to the one in use; agents may load either."
        switch ($copy.kind) {
            { $_ -in @('claude-plugin', 'copilot-plugin') } {
                $plugin, $marketplace = $copy.id -split '@', 2
                $command = Format-AgentCommand -Template $agentsById[$copy.agent].uninstall -Plugin $plugin -Marketplace $marketplace
                $proposals.Add((New-Proposal -Id "uninstall:dataverse@$($copy.agent)" -Action 'uninstall' -Target $copy.id -Agent $copy.agent -Severity 'recommended' -Reason $reason -Commands @($command)))
            }
            'loose-folder' {
                $proposals.Add((New-Proposal -Id "delete-folder:$($copy.path)" -Action 'delete-folder' -Target $copy.path -Severity 'recommended' `
                    -Reason "$reason No agent registered this folder, so no uninstall command removes it." -Commands @("Remove-Item -LiteralPath '$($copy.path -replace "'", "''")' -Recurse -Force")))
            }
        }
    }
    if ($outdated.Count) {
        $proposals.Add((New-Proposal -Id 'update:dataverse-skills' -Action 'update' -Target $package.topic -Severity 'recommended' `
            -Reason "Newer versions are available for: $($outdated -join ', ')." -Commands @($package.update.Replace('{skills}', ($outdated -join ' ')))))
    }

    foreach ($proposal in $pluginProposals) { $proposals.Add($proposal) }

    # ---- telemetry -----------------------------------------------------------------------

    $installedNames = @(@($claudeUserPlugins) + @($Facts.CopilotPlugins) | Where-Object { $_ } | ForEach-Object { Get-PluginName -Id $_.id })
    $telemetry = New-Object System.Collections.Generic.List[object]
    foreach ($plugin in @($catalog.plugins | Where-Object { $_.telemetry })) {
        if ($installedNames -notcontains $plugin.name) { continue }

        # The plugins' own precedence: the environment opt-out, then the choice saved by
        # /<plugin>:telemetry, then on by default.
        $envVar = Get-TelemetryEnvVarName -Plugin $plugin.name
        $envValue = $null
        if ($Facts.TelemetryEnv) { $envValue = $Facts.TelemetryEnv[$envVar] }
        $choice = $null
        if ($Facts.TelemetryConfig -and $Facts.TelemetryConfig.telemetry) { $choice = $Facts.TelemetryConfig.telemetry.($plugin.name) }

        if ("$envValue".Trim() -in @('1', 'true')) { $state = 'off'; $source = 'env' }
        elseif ($choice -ceq 'on' -or $choice -ceq 'off') { $state = $choice; $source = 'config' }
        else { $state = 'default-on'; $source = 'default' }

        $telemetry.Add([ordered]@{ plugin = $plugin.name; state = $state; source = $source; envVar = $envVar })
        if ($state -eq 'default-on') {
            $proposals.Add((New-Proposal -Id "configure:telemetry-$($plugin.name)" -Action 'configure' -Target $plugin.name -Severity 'choice' `
                -Reason "$($plugin.name) sends usage telemetry by default; the user decides whether to keep it." `
                -Commands @("/$($plugin.name):telemetry off", "[Environment]::SetEnvironmentVariable('$envVar', '1', 'User')")))
        }
    }

    return [ordered]@{
        toolchain       = [ordered]@{
            requirements = $requirements.ToArray()
            repository   = $repositoryTools.ToArray()
            recommended  = $recommended.ToArray()
        }
        pac             = $pac
        agents          = $agents.ToArray()
        plugins         = $pluginRows.ToArray()
        dataverseSkills = $dataverseSkills
        telemetry       = $telemetry.ToArray()
        proposals       = $proposals.ToArray()
        notes           = @($notes)
    }
}

# --------------------------------------------------------------------------------------------
# Facts that live in files under the user profile
# --------------------------------------------------------------------------------------------

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
            $text = Read-TextFile -FullPath $path
            [ordered]@{ path = $path; containsQuote = [bool]($text -and $text.Contains($exception.quote)) }
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

function Get-NpxSkills {
    # npx skills records what it installed in a lock file next to the skills; an entry whose
    # folder is gone was removed by hand and is no copy at all.
    $lockPath = Join-Path $HOME '.agents/.skill-lock.json'
    if (-not (Test-Path -LiteralPath $lockPath)) { return }
    $parsed = Read-Json -Json (Read-TextFile -FullPath $lockPath)
    if (-not $parsed.Ok -or -not $parsed.Items[0].skills) { return }
    return @(foreach ($property in $parsed.Items[0].skills.PSObject.Properties) {
        if (-not (Test-Path -LiteralPath (Join-Path $HOME ".agents/skills/$($property.Name)"))) { continue }
        [ordered]@{
            name            = $property.Name
            source          = $property.Value.source
            skillPath       = $property.Value.skillPath
            skillFolderHash = $property.Value.skillFolderHash
        }
    })
}

function Get-LoosePluginFolders {
    param([string]$PluginName, $ClaudePlugins)

    # A plugin copied straight into ~/.claude/plugins/<name> is no install Claude Code knows of:
    # it is not in its plugin list, and only its folder can be removed.
    $root = Join-Path $HOME '.claude/plugins'
    if (-not (Test-Path -LiteralPath $root)) { return }
    $registered = @(@($ClaudePlugins) | Where-Object { $_ -and $_.installPath } | ForEach-Object { $_.installPath.TrimEnd('\', '/') })
    return @(foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
        $manifest = Join-Path $folder.FullName '.claude-plugin/plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $parsed = Read-Json -Json (Read-TextFile -FullPath $manifest)
        if (-not $parsed.Ok -or $parsed.Items[0].name -ne $PluginName) { continue }
        if ($registered -contains $folder.FullName) { continue }
        [ordered]@{ path = $folder.FullName; version = $parsed.Items[0].version }
    })
}

function Get-PacMsiInstall {
    param([string]$DataRoot)

    # The data root alone proves nothing: every pac, the .NET tool included, keeps its
    # authentication profiles and token cache there. The installer registers itself with Windows
    # Installer, which is also how winget list finds it.
    $uninstallKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallKeys) {
        $entry = @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Power ?Apps CLI|Power Platform CLI' } | Select-Object -First 1)
        if ($entry.Count) {
            if ($entry[0].InstallLocation) { return [string]$entry[0].InstallLocation }
            return $DataRoot
        }
    }

    # pac install latest unpacks each version into its own Microsoft.PowerApps.CLI.<version> folder.
    if ($DataRoot -and (Test-Path -LiteralPath $DataRoot)) {
        $versions = @(Get-ChildItem -LiteralPath $DataRoot -Directory -Filter 'Microsoft.PowerApps.CLI.*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'tools\pac.exe') })
        if ($versions.Count) { return $DataRoot }
    }
    return $null
}

# A list the tool printed, even an empty one, is a fact; a tool that failed, is missing or printed
# something unreadable is $null, which the assessment reports as unknown instead of as nothing
# installed.
function Get-RunList {
    param($Run, [scriptblock]$Convert, [switch]$Json)

    if (-not ($Run -and $Run.Ran -and $Run.ExitCode -eq 0)) { return $null }
    if ($Json -and -not (Read-Json -Json $Run.Stdout).Ok) { return $null }
    return , @(& $Convert $Run.Stdout | Where-Object { $null -ne $_ })
}

function Get-WebText {
    param([string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'power-platform-harness' }
        return [pscustomobject]@{ Text = [string]$response.Content; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Text = $null; Error = $_.Exception.Message }
    }
}

# Dot-sourced: the functions are all a caller wanted.
if ($MyInvocation.InvocationName -eq '.') { return }

# --------------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------------

$catalogPath = Join-Path $PSScriptRoot 'catalog.json'
$exceptionsPath = Join-Path $PSScriptRoot 'skill-exceptions.json'
$notes = New-Object System.Collections.Generic.List[string]

try {

$catalog = $null
try { $catalog = [System.IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json }
catch { Stop-WithError "catalog.json could not be read at ${catalogPath}: $($_.Exception.Message)" }

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
foreach ($agent in @($catalog.agents)) {
    $versionProbes += @{ Key = $agent.id; Name = $agent.command; Arguments = @('--version') }
}

# Every probe is independent, so all of them start before any is waited for: the check takes as
# long as the slowest one (usually az) instead of the sum of all of them.
$jobs = @{}
foreach ($probe in $versionProbes) {
    $jobs[$probe.Key] = Start-Tool -Name $probe.Name -Arguments $probe.Arguments -Timeout 30
}
$jobs['dotnetSdks'] = Start-Tool -Name 'dotnet' -Arguments @('--list-sdks') -Timeout 30
$jobs['dotnetTools'] = Start-Tool -Name 'dotnet' -Arguments @('tool', 'list', '--global') -Timeout 30
$jobs['claudePlugins'] = Start-Tool -Name 'claude' -Arguments @('plugin', 'list', '--json') -Timeout 30
$jobs['claudeMarketplaces'] = Start-Tool -Name 'claude' -Arguments @('plugin', 'marketplace', 'list', '--json') -Timeout 30
$jobs['copilotPlugins'] = Start-Tool -Name 'copilot' -Arguments @('plugin', 'list') -Timeout 30
$jobs['copilotMarketplaces'] = Start-Tool -Name 'copilot' -Arguments @('plugin', 'marketplace', 'list') -Timeout 30
# az devops offers to install its extension interactively; listing extensions never asks.
$jobs['azExtensions'] = Start-Tool -Name 'az' -Arguments @('extension', 'list', '--output', 'json') -Timeout 60

# ---- upstream versions, while the probes run --------------------------------------------

$upstream = @{ online = -not $Offline; pluginVersions = @{}; skillFolderHashes = @{} }
if (-not $Offline) {
    # Only what the installers compare: npx skills update matches each skill folder's git tree
    # hash, and a plugin update fetches plugin.json from the marketplace's default branch.
    # Invoke-WebRequest's progress bar costs seconds per request on Windows PowerShell.
    $ProgressPreference = 'SilentlyContinue'
    if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    foreach ($plugin in @($catalog.plugins)) {
        $fetched = Get-WebText -Uri "https://raw.githubusercontent.com/$($plugin.marketplaceSource)/HEAD/$($plugin.manifest)"
        $version = Get-ManifestVersion -Json $fetched.Text
        if ($version) { $upstream.pluginVersions[$plugin.name] = $version }
        else { $notes.Add("The latest version of $($plugin.name) could not be read from $($plugin.marketplaceSource): $($fetched.Error)") | Out-Null }
    }
    foreach ($package in @($catalog.skillPackages)) {
        $fetched = Get-WebText -Uri "https://api.github.com/repos/$($package.source)/git/trees/HEAD?recursive=1"
        $hashes = ConvertFrom-GitTree -Json $fetched.Text
        if ($hashes) { $upstream.skillFolderHashes[$package.source] = $hashes }
        else { $notes.Add("The skill hashes of $($package.source) could not be read from GitHub: $($fetched.Error)") | Out-Null }
    }
}

$runs = @{}
foreach ($key in @($jobs.Keys)) { $runs[$key] = Wait-Tool -Job $jobs[$key] }


$tooling = [ordered]@{}
foreach ($probe in $versionProbes) {
    $tooling[$probe.Key] = Get-ToolReport -Name $probe.Name -Run $runs[$probe.Key]
}
$tooling['dotnet'] = Get-DotnetSdkReport -Report $tooling['dotnet'] -Run $runs['dotnetSdks']
$tooling['currentPowerShell'] = [ordered]@{
    present = $true
    version = $PSVersionTable.PSVersion.ToString()
    edition = [string]$PSVersionTable.PSEdition
}

$dotnetGlobalTools = Get-DotnetGlobalToolIds -DotnetPresent $tooling.dotnet.present -Run $runs['dotnetTools']

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

# ---- facts from files ------------------------------------------------------------------------

$repositoryProvider = $null
if ($Path) {
    $projectJson = Join-Path $Path '.power-platform/project.json'
    if (Test-Path -LiteralPath $projectJson) {
        $repositoryProvider = Get-RepositoryProvider -ProjectJson (Read-TextFile -FullPath $projectJson)
        if (-not $repositoryProvider) { $notes.Add("$projectJson names no repository provider; gh and the azure-devops extension are reported as conditional.") | Out-Null }
    }
    else {
        $notes.Add("$Path has no .power-platform/project.json; gh and the azure-devops extension are reported as conditional.") | Out-Null
    }
}

$claudePlugins = $null
if ($tooling.claude.present) {
    $claudePlugins = Get-RunList -Run $runs['claudePlugins'] -Json { param($o) ConvertFrom-ClaudePluginList -Json $o }
}

$telemetryEnv = @{}
foreach ($plugin in @($catalog.plugins | Where-Object { $_.telemetry })) {
    # A variable set for the user reaches agents started afterwards, not this process.
    # An opt-out in either scope counts, so a process value of 0 does not hide the user's 1.
    $name = Get-TelemetryEnvVarName -Plugin $plugin.name
    $values = @([Environment]::GetEnvironmentVariable($name, 'Process'), [Environment]::GetEnvironmentVariable($name, 'User')) | Where-Object { $_ }
    $optOut = @($values | Where-Object { "$_".Trim() -in @('1', 'true') } | Select-Object -First 1)
    if ($optOut.Count) { $telemetryEnv[$name] = $optOut[0] }
    elseif (@($values).Count) { $telemetryEnv[$name] = @($values)[0] }
}
$telemetryConfig = $null
$configDir = $env:POWER_PLATFORM_SKILLS_CONFIG_DIR
if (-not $configDir) { $configDir = Join-Path $HOME '.power-platform-skills' }
$configPath = Join-Path $configDir 'config.json'
if (Test-Path -LiteralPath $configPath) {
    $parsedConfig = Read-Json -Json (Read-TextFile -FullPath $configPath)
    if ($parsedConfig.Ok -and $parsedConfig.Items.Count -eq 1) { $telemetryConfig = $parsedConfig.Items[0] }
}

$pacDataRoot = $null
if ($env:LOCALAPPDATA) { $pacDataRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI' }
$pacMsiRoot = Get-PacMsiInstall -DataRoot $pacDataRoot

$skillExceptions = @()
if (Test-Path -LiteralPath $exceptionsPath) {
    try { $skillExceptions = @(Get-SkillExceptionReport -Exceptions ([System.IO.File]::ReadAllText($exceptionsPath) | ConvertFrom-Json).exceptions) }
    catch { $notes.Add("skill-exceptions.json could not be read: $($_.Exception.Message)") | Out-Null }
}
else {
    $notes.Add("skill-exceptions.json was not found at $exceptionsPath; no exception was checked.") | Out-Null
}

$facts = @{
    Catalog               = $catalog
    Tooling               = $tooling
    Environment           = $environment
    PacCommandPaths       = @(Get-Command -Name pac -All -ErrorAction SilentlyContinue | Where-Object { $_.Source } | ForEach-Object { $_.Source })
    DotnetToolIds         = $(if ($dotnetGlobalTools.error) { $null } else { @($dotnetGlobalTools.packageIds) })
    PacMsiRoot            = $(if ($pacMsiRoot) { $pacMsiRoot } else { $pacDataRoot })
    PacMsiRootExists      = [bool]$pacMsiRoot
    AzExtensions          = $(if ($tooling.az.present) { Get-RunList -Run $runs['azExtensions'] -Json { param($o) ConvertFrom-AzExtensionList -Json $o } } else { $null })
    RepositoryProvider    = $repositoryProvider
    ClaudePlugins         = $claudePlugins
    ClaudeMarketplaces    = $(if ($tooling.claude.present) { Get-RunList -Run $runs['claudeMarketplaces'] -Json { param($o) ConvertFrom-ClaudeMarketplaceList -Json $o } } else { $null })
    CopilotPlugins        = $(if ($tooling.copilot.present) { Get-RunList -Run $runs['copilotPlugins'] { param($o) ConvertFrom-CopilotPluginList -Text $o } } else { $null })
    CopilotMarketplaces   = $(if ($tooling.copilot.present) { Get-RunList -Run $runs['copilotMarketplaces'] { param($o) ConvertFrom-CopilotMarketplaceList -Text $o } } else { $null })
    NpxSkills             = @(Get-NpxSkills)
    LooseDataverseFolders = @(Get-LoosePluginFolders -PluginName (@($catalog.skillPackages)[0].pluginName) -ClaudePlugins $claudePlugins)
    Upstream              = $upstream
    TelemetryEnv          = $telemetryEnv
    TelemetryConfig       = $telemetryConfig
}

$assessment = Get-MachineAssessment -Facts $facts
foreach ($note in $assessment.notes) { $notes.Add($note) | Out-Null }
if (@($assessment.pac.installs | Where-Object { $_.kind -eq 'msi' }).Count) {
    $notes.Add('pac from the Windows installer is recognised by its Windows Installer entry, its versions folder or a PATH entry under Microsoft\PowerAppsCLI: conventions seen in practice, not documented by Microsoft.') | Out-Null
}

# ---- output --------------------------------------------------------------------------------

$report = [ordered]@{
    schemaVersion   = 2
    generatedAt     = (Get-Date).ToString('o')
    options         = [ordered]@{ path = $Path; repositoryProvider = $repositoryProvider; offline = [bool]$Offline; skipEnvironment = [bool]$SkipEnvironment }
    tooling         = $tooling
    toolchain       = $assessment.toolchain
    pac             = $assessment.pac
    agents          = $assessment.agents
    plugins         = $assessment.plugins
    dataverseSkills = $assessment.dataverseSkills
    telemetry       = $assessment.telemetry
    skillExceptions = $skillExceptions
    proposals       = $assessment.proposals
    notes           = @($notes)
}

$report | ConvertTo-Json -Depth 12

}
finally {
    if (Test-Path -LiteralPath $script:scratchRoot) {
        Remove-Item -LiteralPath $script:scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
