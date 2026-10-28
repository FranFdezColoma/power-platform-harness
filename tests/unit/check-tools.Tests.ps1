#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Behaviour of the pure part of skills/setup-tools/scripts/check-tools.ps1.

.DESCRIPTION
    check-tools.ps1 gathers facts from the machine and hands them to pure functions. These tests
    load the functions in-process by dot-sourcing the script, which then returns before probing
    anything, and judge three seams by their return values only:

      - Get-MachineAssessment: facts in, requirements, installs, plugin rows and proposals out.
      - The adapters that turn CLI text and JSON output into facts.
      - Get-VersionStatus in _common.ps1.

    No child process, no real tool and no network. The catalog is the real catalog.json, so a
    catalog change that alters a proposal shows up here. Every path, user and repository below is
    made up: this repository is public.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester -Path tests/unit/check-tools.Tests.ps1 -Output Detailed"
#>

Describe 'check-tools.ps1' {

    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $scriptsFolder = Join-Path $script:repoRoot 'skills/setup-tools/scripts'
        $script:catalog = [System.IO.File]::ReadAllText((Join-Path $scriptsFolder 'catalog.json')) | ConvertFrom-Json

        # Dot-sourcing defines the functions and returns before any probe. The empty PATH is a
        # safety net: should the script ever run its probes when dot-sourced, no tool resolves and
        # nothing is started. The preferences the script sets would leak into this scope.
        $savedPath = $env:PATH
        $savedPreference = $ErrorActionPreference
        try {
            $env:PATH = ''
            . (Join-Path $scriptsFolder 'check-tools.ps1') -SkipEnvironment | Out-Null
        }
        finally {
            $env:PATH = $savedPath
            $ErrorActionPreference = $savedPreference
        }

        $script:bullet = [string][char]0x2022
        $script:diamond = [string][char]0x25C6

        $script:dataverseSource = 'microsoft/Dataverse-skills'
        $script:dataverseSkillNames = @('dv-admin', 'dv-connect', 'dv-data', 'dv-metadata', 'dv-overview',
            'dv-query', 'dv-security', 'dv-solution', 'erp-xpp')
        $script:pacDotnetToolPath = 'C:\Users\dev\.dotnet\tools\pac.exe'
        $script:pacMsiRoot = 'C:\Users\dev\AppData\Local\Microsoft\PowerAppsCLI'
        $script:pacMsiPath = 'C:\Users\dev\AppData\Local\Microsoft\PowerAppsCLI\pac.cmd'
        $script:looseFolder = 'C:\Users\dev\.claude\plugins\dataverse'

        function New-Tool {
            param([string]$Version, [string]$Source = 'C:\Users\dev\bin\tool.exe')
            return @{ present = $true; version = $Version; source = $Source }
        }

        function New-AbsentTool {
            return @{ present = $false; version = $null; source = $null }
        }

        function New-NpxSkill {
            param([string]$Name, [string]$Hash = "sha-$Name")
            return @{
                name            = $Name
                source          = $script:dataverseSource
                skillPath       = ".github/plugins/dataverse/skills/$Name/SKILL.md"
                skillFolderHash = $Hash
            }
        }

        # The upstream folder hashes of the Dataverse skills, equal to what New-NpxSkill installs.
        function New-UpstreamSkillHashes {
            $folders = @{}
            foreach ($name in $script:dataverseSkillNames) { $folders[".github/plugins/dataverse/skills/$name"] = "sha-$name" }
            return @{ $script:dataverseSource = $folders }
        }

        # Scenario 1: the machine the harness is developed on. pac is the .NET global tool and too
        # old, Claude has no user-scope plugin, Copilot has old plugins and a second Dataverse copy.
        function New-ReferenceFacts {
            return @{
                Catalog               = $script:catalog
                Tooling               = @{
                    pwsh              = New-Tool '7.6.7'
                    powershell        = New-Tool '5.1'
                    currentPowerShell = New-Tool '7.6.7'
                    git               = New-Tool '2.53.0.windows.1'
                    pac               = New-Tool '2.9.3+ga17df1d' $script:pacDotnetToolPath
                    dotnet            = New-Tool '10.0.300'
                    node              = New-Tool '26.7.0'
                    npm               = New-Tool '11.6.0'
                    gh                = New-Tool '2.87.3'
                    python            = New-Tool '3.13.12'
                    az                = New-Tool '2.87.0'
                    playwrightCli     = New-Tool '0.1.21'
                    claude            = New-Tool '2.1.0'
                    copilot           = New-Tool '1.0.101'
                    codex             = New-AbsentTool
                    vscode            = New-Tool '1.142.0'
                }
                Environment           = @{ probed = $true; hasAuthProfile = $true }
                PacCommandPaths       = @($script:pacDotnetToolPath)
                DotnetToolIds         = @('coverlet.console', 'microsoft.powerapps.cli.tool')
                PacMsiRoot            = $script:pacMsiRoot
                PacMsiRootExists      = $false
                AzExtensions          = @()
                RepositoryProvider    = 'github'
                ClaudePlugins         = @(
                    @{ id = 'power-platform-harness@power-platform-harness'; version = '2.0.0'; scope = 'local'; enabled = $true; installPath = 'C:\Users\dev\.claude\plugins\cache\power-platform-harness' }
                )
                ClaudeMarketplaces    = @(
                    @{ name = 'power-platform-skills'; repo = 'microsoft/power-platform-skills' }
                    @{ name = 'power-platform-harness'; repo = $null }
                )
                CopilotPlugins        = @(
                    @{ id = 'dataverse@dataverse-skills'; version = '1.5.0'; enabled = $true }
                    @{ id = 'model-apps@power-platform-skills'; version = '2.1.0'; enabled = $true }
                    @{ id = 'power-automate@power-platform-skills'; version = '2.1.0'; enabled = $true }
                    @{ id = 'canvas-apps@power-platform-skills'; version = '2.1.1'; enabled = $true }
                )
                CopilotMarketplaces   = @(
                    @{ name = 'awesome-copilot'; repo = 'github/awesome-copilot' }
                    @{ name = 'dataverse-skills'; repo = 'microsoft/Dataverse-skills' }
                    @{ name = 'power-platform-skills'; repo = 'microsoft/power-platform-skills' }
                )
                NpxSkills             = @($script:dataverseSkillNames | ForEach-Object { New-NpxSkill $_ })
                LooseDataverseFolders = @(@{ path = $script:looseFolder; version = '1.6.0' })
                Upstream              = @{
                    online            = $true
                    pluginVersions    = @{ 'model-apps' = '2.20.2'; 'power-automate' = '3.2.10'; 'ponytail' = '5.3.2' }
                    skillFolderHashes = New-UpstreamSkillHashes
                }
                TelemetryEnv          = @{}
                TelemetryConfig       = $null
                SkillExceptions       = @()
            }
        }

        # Scenario 2: everything installed, current and decided. Nothing is left to propose.
        function New-FullySetUpFacts {
            $facts = New-ReferenceFacts
            $facts.Tooling.pac = New-Tool '2.14.1' $script:pacMsiPath
            $facts.Tooling.node = New-Tool '24.11.0'
            $facts.Tooling.codex = New-Tool '0.50.0'
            $facts.PacCommandPaths = @($script:pacMsiPath)
            $facts.DotnetToolIds = @('coverlet.console')
            $facts.PacMsiRootExists = $true
            $plugins = @(
                @{ id = 'model-apps@power-platform-skills'; version = '2.20.2' }
                @{ id = 'power-automate@power-platform-skills'; version = '3.2.10' }
                @{ id = 'ponytail@ponytail'; version = '5.3.2' }
            )
            $facts.ClaudePlugins = @($plugins | ForEach-Object {
                @{ id = $_.id; version = $_.version; scope = 'user'; enabled = $true; installPath = "C:\Users\dev\.claude\plugins\cache\$($_.id)" }
            })
            $facts.CopilotPlugins = @($plugins | ForEach-Object { @{ id = $_.id; version = $_.version; enabled = $true } })
            $ponytail = @{ name = 'ponytail'; repo = 'DietrichGebert/ponytail' }
            $facts.ClaudeMarketplaces = @($facts.ClaudeMarketplaces) + @($ponytail)
            $facts.CopilotMarketplaces = @($facts.CopilotMarketplaces) + @($ponytail)
            $facts.LooseDataverseFolders = @()
            $facts.TelemetryEnv = @{ POWER_PLATFORM_SKILLS_TELEMETRY_MODEL_APPS_OPTOUT = '1' }
            $facts.TelemetryConfig = '{"telemetry":{"power-automate":"on"}}' | ConvertFrom-Json
            return $facts
        }

        function Get-Requirement {
            param($Assessment, [string]$Id)
            return @($Assessment.toolchain.requirements | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
        }

        function Get-Repository {
            param($Assessment, [string]$Id)
            return @($Assessment.toolchain.repository | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
        }

        function Get-PluginRow {
            param($Assessment, [string]$Agent, [string]$Plugin)
            return @($Assessment.plugins | Where-Object { $_.agent -eq $Agent -and $_.plugin -eq $Plugin }) | Select-Object -First 1
        }

        function Get-Telemetry {
            param($Assessment, [string]$Plugin)
            return @($Assessment.telemetry | Where-Object { $_.plugin -eq $Plugin }) | Select-Object -First 1
        }

        function Get-Proposal {
            param($Assessment, [string]$Id)
            return @($Assessment.proposals | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
        }

        # Proposal ids in order, one per line, so a failure shows the whole list.
        function Get-ProposalIds {
            param($Assessment)
            return (@($Assessment.proposals | ForEach-Object { $_.id }) -join "`n")
        }

        function Join-Lines {
            param($Values)
            return (@($Values) -join "`n")
        }
    }

    Context 'Get-MachineAssessment: shape' {

        It 'returns the eight sections in order' {
            $assessment = Get-MachineAssessment -Facts (New-ReferenceFacts)

            Join-Lines @($assessment.Keys) | Should -Be (Join-Lines @('toolchain', 'pac', 'agents', 'plugins', 'dataverseSkills', 'telemetry', 'proposals', 'notes'))
        }

        It 'lists one requirement per machine assertion, in catalog order, with the catalog topic as tool' {
            $assessment = Get-MachineAssessment -Facts (New-ReferenceFacts)

            Join-Lines @($assessment.toolchain.requirements | ForEach-Object { $_.id }) |
                Should -Be (Join-Lines @('machine.powershell', 'machine.git', 'machine.dotnet', 'machine.node', 'machine.pac', 'machine.python', 'machine.az'))
            (Get-Requirement $assessment 'machine.node').tool | Should -Be 'Node.js'
            (Get-Requirement $assessment 'machine.pac').minimum | Should -Be '2.10.0'
            (Get-Requirement $assessment 'machine.pac').minimumExclusive | Should -BeTrue
            (Get-Requirement $assessment 'machine.pac').minimumSource | Should -Be 'documented'
        }

        It 'lists one agent per catalog agent with its presence and plugin support' {
            $assessment = Get-MachineAssessment -Facts (New-ReferenceFacts)

            Join-Lines @($assessment.agents | ForEach-Object { $_.id }) | Should -Be (Join-Lines @('claude', 'copilot', 'codex', 'vscode'))
            Join-Lines @($assessment.agents | ForEach-Object { $_.present }) | Should -Be (Join-Lines @($true, $true, $false, $true))
            $assessment.agents[0].label | Should -Be 'Claude Code'
            $assessment.agents[3].plugins | Should -Be 'unverified'
        }
    }

    Context 'Get-MachineAssessment: the reference machine' {

        BeforeAll {
            $script:reference = Get-MachineAssessment -Facts (New-ReferenceFacts)
        }

        It 'proposes exactly these changes, in this order' {
            Get-ProposalIds $script:reference | Should -Be (Join-Lines @(
                'install:pac-msi'
                'uninstall:pac-dotnet-tool'
                'uninstall:dataverse@copilot'
                'delete-folder:C:\Users\dev\.claude\plugins\dataverse'
                'install:model-apps@claude'
                'install:power-automate@claude'
                'install:ponytail@claude'
                'update:model-apps@copilot'
                'update:power-automate@copilot'
                'install:ponytail@copilot'
                'configure:telemetry-model-apps'
                'configure:telemetry-power-automate'
            ))
        }

        It 'reports PowerShell as the highest version available' {
            $requirement = Get-Requirement $script:reference 'machine.powershell'

            $requirement.present | Should -BeTrue
            $requirement.version | Should -Be '7.6.7'
            $requirement.status | Should -Be 'ok'
        }

        It 'accepts Node 26 without a warning' {
            $requirement = Get-Requirement $script:reference 'machine.node'

            $requirement.status | Should -Be 'ok'
            $requirement['warning'] | Should -BeNullOrEmpty
        }

        It 'reports pac 2.9.3 as below the minimum, with the authentication profile' {
            $requirement = Get-Requirement $script:reference 'machine.pac'

            $requirement.version | Should -Be '2.9.3+ga17df1d'
            $requirement.status | Should -Be 'below-minimum'
            $requirement.authProfile | Should -BeTrue
        }

        It 'finds one pac install, the .NET global tool on PATH' {
            $pac = $script:reference.pac

            @($pac.installs) | Should -HaveCount 1
            $pac.installs[0].kind | Should -Be 'dotnet-tool'
            $pac.installs[0].path | Should -Be 'C:\Users\dev\.dotnet\tools\pac.exe'
            $pac.installs[0].onPath | Should -BeTrue
            $pac.active | Should -Be 'dotnet-tool'
            $pac.duplicate | Should -BeFalse
        }

        It 'proposes the pac installer as required, then removing the global tool after it' {
            $install = Get-Proposal $script:reference 'install:pac-msi'
            $uninstall = Get-Proposal $script:reference 'uninstall:pac-dotnet-tool'

            $install.action | Should -Be 'install'
            $install.severity | Should -Be 'required'
            Join-Lines $install.commands | Should -Be 'winget install --id Microsoft.PowerAppsCLI --source winget'
            $uninstall.action | Should -Be 'uninstall'
            $uninstall.severity | Should -Be 'recommended'
            Join-Lines $uninstall.commands | Should -Be 'dotnet tool uninstall --global Microsoft.PowerApps.CLI.Tool'
            $uninstall.dependsOn | Should -Be 'install:pac-msi'
        }

        It 'applies gh to a GitHub repository and not the azure-devops extension' {
            $gh = Get-Repository $script:reference 'repository.gh'
            $azureDevOps = Get-Repository $script:reference 'repository.azure-devops'

            $gh.tool | Should -Be 'GitHub CLI (gh)'
            $gh.applies | Should -BeTrue
            $gh.status | Should -Be 'ok'
            $azureDevOps.applies | Should -BeFalse
            $azureDevOps.status | Should -Be 'not-applicable'
        }

        It 'reports playwright-cli as installed' {
            $recommended = @($script:reference.toolchain.recommended)

            $recommended | Should -HaveCount 1
            $recommended[0].id | Should -Be 'recommended.playwright-cli'
            $recommended[0].installed | Should -BeTrue
            $recommended[0].version | Should -Be '0.1.21'
        }

        It 'reports three Dataverse copies with npx as the primary' {
            $dataverse = $script:reference.dataverseSkills

            $dataverse.status | Should -Be 'duplicates'
            Join-Lines @($dataverse.copies | ForEach-Object { $_.kind }) | Should -Be (Join-Lines @('npx', 'copilot-plugin', 'loose-folder'))
            $dataverse.primary.kind | Should -Be 'npx'
            Join-Lines @($dataverse.primary.skills) | Should -Be (Join-Lines $script:dataverseSkillNames)
            @($dataverse.outdated) | Should -HaveCount 0
            $dataverse.updatesKnown | Should -BeTrue
        }

        It 'proposes removing the Copilot Dataverse plugin and the loose folder' {
            $uninstall = Get-Proposal $script:reference 'uninstall:dataverse@copilot'
            $delete = Get-Proposal $script:reference 'delete-folder:C:\Users\dev\.claude\plugins\dataverse'

            $uninstall.severity | Should -Be 'recommended'
            Join-Lines $uninstall.commands | Should -Be 'copilot plugin uninstall dataverse@dataverse-skills'
            $delete.action | Should -Be 'delete-folder'
            $delete.severity | Should -Be 'recommended'
            Join-Lines $delete.commands | Should -Be "Remove-Item -LiteralPath 'C:\Users\dev\.claude\plugins\dataverse' -Recurse -Force"
        }

        It 'has plugin rows for Claude and Copilot only' {
            Join-Lines @($script:reference.plugins | ForEach-Object { "$($_.agent)/$($_.plugin)" }) | Should -Be (Join-Lines @(
                'claude/model-apps', 'claude/power-automate', 'claude/ponytail',
                'copilot/model-apps', 'copilot/power-automate', 'copilot/ponytail'))
        }

        It 'sees an older Copilot plugin as update-available against upstream' {
            $row = Get-PluginRow $script:reference 'copilot' 'model-apps'

            $row.installed | Should -BeTrue
            $row.version | Should -Be '2.1.0'
            $row.latest | Should -Be '2.20.2'
            $row.status | Should -Be 'update-available'
            Join-Lines (Get-Proposal $script:reference 'update:model-apps@copilot').commands |
                Should -Be 'copilot plugin update model-apps@power-platform-skills'
            (Get-Proposal $script:reference 'update:model-apps@copilot').severity | Should -Be 'recommended'
        }

        It 'installs from a registered marketplace without adding it again' {
            $proposal = Get-Proposal $script:reference 'install:model-apps@claude'

            $proposal.severity | Should -Be 'required'
            $proposal.agent | Should -Be 'claude'
            Join-Lines $proposal.commands | Should -Be 'claude plugin install model-apps@power-platform-skills'
        }

        It 'adds the ponytail marketplace before installing from it' {
            Join-Lines (Get-Proposal $script:reference 'install:ponytail@claude').commands | Should -Be (Join-Lines @(
                'claude plugin marketplace add DietrichGebert/ponytail'
                'claude plugin install ponytail@ponytail'))
        }

        It 'reports telemetry on by default for model-apps and power-automate' {
            Join-Lines @($script:reference.telemetry | ForEach-Object { "$($_.plugin)=$($_.state)/$($_.source)" }) |
                Should -Be (Join-Lines @('model-apps=default-on/default', 'power-automate=default-on/default'))
            (Get-Telemetry $script:reference 'power-automate').envVar | Should -Be 'POWER_PLATFORM_SKILLS_TELEMETRY_POWER_AUTOMATE_OPTOUT'
        }

        It 'offers turning telemetry off as a choice' {
            $proposal = Get-Proposal $script:reference 'configure:telemetry-power-automate'

            $proposal.action | Should -Be 'configure'
            $proposal.severity | Should -Be 'choice'
            Join-Lines $proposal.commands | Should -Be (Join-Lines @(
                '/power-automate:telemetry off'
                "[Environment]::SetEnvironmentVariable('POWER_PLATFORM_SKILLS_TELEMETRY_POWER_AUTOMATE_OPTOUT', '1', 'User')"))
        }
    }

    Context 'Get-MachineAssessment: a fully set-up machine' {

        It 'proposes nothing' {
            $assessment = Get-MachineAssessment -Facts (New-FullySetUpFacts)

            Get-ProposalIds $assessment | Should -Be ''
        }

        It 'sees the installer as the one active pac' {
            $pac = (Get-MachineAssessment -Facts (New-FullySetUpFacts)).pac

            Join-Lines @($pac.installs | ForEach-Object { "$($_.kind)|$($_.onPath)" }) | Should -Be 'msi|True'
            $pac.active | Should -Be 'msi'
            $pac.duplicate | Should -BeFalse
        }

        It 'reads the telemetry decisions from the environment and the config file' {
            $assessment = Get-MachineAssessment -Facts (New-FullySetUpFacts)

            Join-Lines @($assessment.telemetry | ForEach-Object { "$($_.plugin)=$($_.state)/$($_.source)" }) |
                Should -Be (Join-Lines @('model-apps=off/env', 'power-automate=on/config'))
        }

        It 'reports Dataverse from npx alone as ok' {
            $dataverse = (Get-MachineAssessment -Facts (New-FullySetUpFacts)).dataverseSkills

            $dataverse.status | Should -Be 'ok'
            @($dataverse.copies) | Should -HaveCount 1
        }
    }

    Context 'Get-MachineAssessment: toolchain requirements' {

        It 'treats a pac equal to the exclusive minimum as below it' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.pac = New-Tool '2.10.0' $script:pacMsiPath

            (Get-Requirement (Get-MachineAssessment -Facts $facts) 'machine.pac').status | Should -Be 'below-minimum'
        }

        It 'accepts a pac just above the exclusive minimum' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.pac = New-Tool '2.10.1' $script:pacMsiPath

            (Get-Requirement (Get-MachineAssessment -Facts $facts) 'machine.pac').status | Should -Be 'ok'
        }

        It 'warns about an odd Node major and recommends reinstalling Node' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.node = New-Tool '25.1.0'
            $assessment = Get-MachineAssessment -Facts $facts
            $requirement = Get-Requirement $assessment 'machine.node'

            $requirement.status | Should -Be 'ok'
            $requirement.warning | Should -Match 'odd-numbered'
            Get-ProposalIds $assessment | Should -Be 'install:node'
            (Get-Proposal $assessment 'install:node').severity | Should -Be 'recommended'
            Join-Lines (Get-Proposal $assessment 'install:node').commands | Should -Be 'winget install --id OpenJS.NodeJS.LTS --source winget'
        }

        It 'recommends PowerShell 7 when only Windows PowerShell is there' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.pwsh = New-AbsentTool
            $facts.Tooling.currentPowerShell = New-Tool '5.1'
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Requirement $assessment 'machine.powershell').version | Should -Be '5.1'
            (Get-Requirement $assessment 'machine.powershell').status | Should -Be 'below-preferred'
            Get-ProposalIds $assessment | Should -Be 'install:powershell'
            (Get-Proposal $assessment 'install:powershell').severity | Should -Be 'recommended'
        }

        It 'requires a missing tool' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.dotnet = New-AbsentTool
            $assessment = Get-MachineAssessment -Facts $facts

            Get-ProposalIds $assessment | Should -Be 'install:dotnet'
            (Get-Proposal $assessment 'install:dotnet').severity | Should -Be 'required'
            Join-Lines (Get-Proposal $assessment 'install:dotnet').commands | Should -Be 'winget install --id Microsoft.DotNet.SDK.10 --source winget'
        }

        It 'proposes nothing for a missing Python, which has no install command, and leaves a note' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.python = New-AbsentTool
            $baseNotes = @((Get-MachineAssessment -Facts (New-FullySetUpFacts)).notes).Count
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Requirement $assessment 'machine.python').status | Should -Be 'missing'
            Get-ProposalIds $assessment | Should -Be ''
            @($assessment.notes).Count | Should -BeGreaterThan $baseNotes
        }

        It 'leaves the authentication profile unknown when the environment was not probed' {
            $facts = New-FullySetUpFacts
            $facts.Environment = @{ probed = $false; hasAuthProfile = $false }

            (Get-Requirement (Get-MachineAssessment -Facts $facts) 'machine.pac').authProfile | Should -BeNullOrEmpty
        }

        It 'proposes playwright-cli when it is not installed' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.playwrightCli = New-AbsentTool
            $assessment = Get-MachineAssessment -Facts $facts

            $assessment.toolchain.recommended[0].installed | Should -BeFalse
            Get-ProposalIds $assessment | Should -Be 'install:playwrightCli'
            (Get-Proposal $assessment 'install:playwrightCli').severity | Should -Be 'recommended'
            Join-Lines (Get-Proposal $assessment 'install:playwrightCli').commands | Should -Be 'npm install -g @playwright/cli@latest'
        }
    }

    Context 'Get-MachineAssessment: pac installs' {

        It 'flags the global tool next to the installer as a duplicate, removable without installing anything' {
            $facts = New-FullySetUpFacts
            $facts.PacCommandPaths = @($script:pacDotnetToolPath, $script:pacMsiPath)
            $facts.DotnetToolIds = @('coverlet.console', 'microsoft.powerapps.cli.tool')
            $assessment = Get-MachineAssessment -Facts $facts

            Join-Lines @($assessment.pac.installs | ForEach-Object { $_.kind }) | Should -Be (Join-Lines @('dotnet-tool', 'msi'))
            $assessment.pac.active | Should -Be 'dotnet-tool'
            $assessment.pac.duplicate | Should -BeTrue
            Get-ProposalIds $assessment | Should -Be 'uninstall:pac-dotnet-tool'
            (Get-Proposal $assessment 'uninstall:pac-dotnet-tool').dependsOn | Should -BeNullOrEmpty
        }

        It 'updates an active installer below the minimum with pac install latest' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.pac = New-Tool '2.9.3+ga17df1d' $script:pacMsiPath
            $assessment = Get-MachineAssessment -Facts $facts

            Get-ProposalIds $assessment | Should -Be 'update:pac'
            (Get-Proposal $assessment 'update:pac').severity | Should -Be 'required'
            Join-Lines (Get-Proposal $assessment 'update:pac').commands | Should -Be 'pac install latest'
        }

        It 'requires only the installer when pac is missing' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.pac = New-AbsentTool
            $facts.PacCommandPaths = @()
            $facts.PacMsiRootExists = $false
            $assessment = Get-MachineAssessment -Facts $facts

            @($assessment.pac.installs) | Should -HaveCount 0
            $assessment.pac.active | Should -BeNullOrEmpty
            Get-ProposalIds $assessment | Should -Be 'install:pac-msi'
            (Get-Proposal $assessment 'install:pac-msi').severity | Should -Be 'required'
        }

        It 'counts an installer folder and a global tool that are not on PATH' {
            $facts = New-FullySetUpFacts
            $facts.PacCommandPaths = @('C:\Users\dev\tools\pac.exe')
            $facts.DotnetToolIds = @('microsoft.powerapps.cli.tool')
            $assessment = Get-MachineAssessment -Facts $facts

            Join-Lines @($assessment.pac.installs | ForEach-Object { "$($_.kind)|$($_.path)|$($_.onPath)" }) | Should -Be (Join-Lines @(
                'other|C:\Users\dev\tools\pac.exe|True'
                'msi|C:\Users\dev\AppData\Local\Microsoft\PowerAppsCLI|False'
                'dotnet-tool||False'))
            $assessment.pac.active | Should -Be 'other'
            $assessment.pac.duplicate | Should -BeTrue
        }

        It 'classifies the VS Code extension pac by its path' {
            $facts = New-FullySetUpFacts
            $facts.PacCommandPaths = @('C:/Users/dev/AppData/Roaming/Code/User/globalStorage/microsoft-isvexptools.powerplatform-vscode/pac/tools/pac.exe')
            $facts.PacMsiRootExists = $false

            (Get-MachineAssessment -Facts $facts).pac.installs[0].kind | Should -Be 'vscode-extension'
        }
    }

    Context 'Get-MachineAssessment: repository tools' {

        It 'marks both repository tools conditional when the provider is unknown' {
            $facts = New-FullySetUpFacts
            $facts.RepositoryProvider = $null
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Repository $assessment 'repository.gh').status | Should -Be 'conditional'
            (Get-Repository $assessment 'repository.gh').applies | Should -BeNullOrEmpty
            (Get-Repository $assessment 'repository.azure-devops').status | Should -Be 'conditional'
            Get-ProposalIds $assessment | Should -Be ''
        }

        It 'requires the azure-devops extension for a repository on Azure DevOps' {
            $facts = New-FullySetUpFacts
            $facts.RepositoryProvider = 'azure-devops'
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Repository $assessment 'repository.azure-devops').status | Should -Be 'missing'
            (Get-Repository $assessment 'repository.gh').status | Should -Be 'not-applicable'
            Get-ProposalIds $assessment | Should -Be 'install:azureDevOpsExtension'
            (Get-Proposal $assessment 'install:azureDevOpsExtension').severity | Should -Be 'required'
            Join-Lines (Get-Proposal $assessment 'install:azureDevOpsExtension').commands | Should -Be 'az extension add --name azure-devops'
            (Get-Proposal $assessment 'install:azureDevOpsExtension').dependsOn | Should -BeNullOrEmpty
        }

        It 'reports the extension unknown when az is there but its extensions could not be read' {
            $facts = New-FullySetUpFacts
            $facts.RepositoryProvider = 'azure-devops'
            $facts.AzExtensions = $null
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Repository $assessment 'repository.azure-devops').status | Should -Be 'unknown'
            Get-ProposalIds $assessment | Should -Be ''
        }

        It 'installs az before the extension when az is missing' {
            $facts = New-FullySetUpFacts
            $facts.RepositoryProvider = 'azure-devops'
            $facts.Tooling.az = New-AbsentTool
            $facts.AzExtensions = $null
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Repository $assessment 'repository.azure-devops').status | Should -Be 'missing'
            Get-ProposalIds $assessment | Should -Be (Join-Lines @('install:az', 'install:azureDevOpsExtension'))
            (Get-Proposal $assessment 'install:azureDevOpsExtension').dependsOn | Should -Be 'install:az'
        }

        It 'requires gh for a GitHub repository without it' {
            $facts = New-FullySetUpFacts
            $facts.Tooling.gh = New-AbsentTool
            $assessment = Get-MachineAssessment -Facts $facts

            Get-ProposalIds $assessment | Should -Be 'install:gh'
            Join-Lines (Get-Proposal $assessment 'install:gh').commands | Should -Be 'winget install --id GitHub.cli --source winget'
        }
    }

    Context 'Get-MachineAssessment: Dataverse skills' {

        It 'requires the npx install when there is no copy at all' {
            $facts = New-FullySetUpFacts
            $facts.NpxSkills = @()
            $assessment = Get-MachineAssessment -Facts $facts

            $assessment.dataverseSkills.status | Should -Be 'missing'
            $assessment.dataverseSkills.primary | Should -BeNullOrEmpty
            Get-ProposalIds $assessment | Should -Be 'install:dataverse-skills'
            (Get-Proposal $assessment 'install:dataverse-skills').severity | Should -Be 'required'
            Join-Lines (Get-Proposal $assessment 'install:dataverse-skills').commands | Should -Be 'npx skills add microsoft/Dataverse-skills -s "*" -g'
        }

        It 'accepts a single Copilot plugin copy as plugin-only, without proposing anything' {
            $facts = New-FullySetUpFacts
            $facts.NpxSkills = @()
            $facts.CopilotPlugins = @($facts.CopilotPlugins) + @(@{ id = 'dataverse@dataverse-skills'; version = '1.5.0'; enabled = $true })
            $assessment = Get-MachineAssessment -Facts $facts

            $assessment.dataverseSkills.status | Should -Be 'plugin-only'
            $assessment.dataverseSkills.primary.kind | Should -Be 'copilot-plugin'
            $assessment.dataverseSkills.primary.id | Should -Be 'dataverse@dataverse-skills'
            Get-ProposalIds $assessment | Should -Be ''
        }

        # No agent loads a loose folder, so it is never an installed copy, only something to delete.
        It 'requires the npx install when the only copy is a loose folder, and deletes the folder' {
            $facts = New-FullySetUpFacts
            $facts.NpxSkills = @()
            $facts.LooseDataverseFolders = @(@{ path = 'C:\Users\dev\.claude\plugins\dataverse'; version = '1.6.0' })
            $assessment = Get-MachineAssessment -Facts $facts

            $assessment.dataverseSkills.status | Should -Be 'missing'
            $assessment.dataverseSkills.primary | Should -BeNullOrEmpty
            Get-ProposalIds $assessment | Should -Be (Join-Lines @(
                'install:dataverse-skills'
                'delete-folder:C:\Users\dev\.claude\plugins\dataverse'))
            (Get-Proposal $assessment 'install:dataverse-skills').severity | Should -Be 'required'
        }

        It 'proposes updating only the skill whose folder changed upstream' {
            $facts = New-FullySetUpFacts
            $facts.NpxSkills = @($script:dataverseSkillNames | ForEach-Object {
                if ($_ -eq 'dv-query') { New-NpxSkill $_ 'sha-older' } else { New-NpxSkill $_ }
            })
            $assessment = Get-MachineAssessment -Facts $facts

            Join-Lines $assessment.dataverseSkills.outdated | Should -Be 'dv-query'
            Get-ProposalIds $assessment | Should -Be 'update:dataverse-skills'
            (Get-Proposal $assessment 'update:dataverse-skills').severity | Should -Be 'recommended'
            Join-Lines (Get-Proposal $assessment 'update:dataverse-skills').commands | Should -Be 'npx skills update dv-query -g -y'
        }

        It 'proposes removing a user-scope Claude plugin copy next to npx' {
            $facts = New-FullySetUpFacts
            $facts.ClaudePlugins = @($facts.ClaudePlugins) + @(@{ id = 'dataverse@dataverse-skills'; version = '1.6.0'; scope = 'user'; enabled = $true; installPath = 'C:\Users\dev\.claude\plugins\cache\dataverse' })
            $assessment = Get-MachineAssessment -Facts $facts

            $assessment.dataverseSkills.status | Should -Be 'duplicates'
            Get-ProposalIds $assessment | Should -Be 'uninstall:dataverse@claude'
            Join-Lines (Get-Proposal $assessment 'uninstall:dataverse@claude').commands | Should -Be 'claude plugin uninstall dataverse@dataverse-skills'
        }
    }

    Context 'Get-MachineAssessment: agent plugins' {

        It 'proposes no update when upstream is offline' {
            $facts = New-ReferenceFacts
            $facts.Upstream = @{ online = $false; pluginVersions = @{}; skillFolderHashes = @{} }
            $assessment = Get-MachineAssessment -Facts $facts

            @($assessment.proposals | Where-Object { $_.id -like 'update:*' }) | Should -HaveCount 0
            (Get-PluginRow $assessment 'copilot' 'model-apps').latest | Should -BeNullOrEmpty
            (Get-PluginRow $assessment 'copilot' 'model-apps').status | Should -Be 'ok'
            $assessment.dataverseSkills.updatesKnown | Should -BeFalse
        }

        It 'does not count a project-scope Claude plugin as installed' {
            $facts = New-FullySetUpFacts
            $facts.ClaudePlugins[0].scope = 'project'
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-PluginRow $assessment 'claude' 'model-apps').installed | Should -BeFalse
            (Get-PluginRow $assessment 'claude' 'model-apps').status | Should -Be 'missing'
            Get-ProposalIds $assessment | Should -Be 'install:model-apps@claude'
        }

        It 'has no rows for an agent whose plugins could not be read, and leaves a note' {
            $facts = New-FullySetUpFacts
            $facts.ClaudePlugins = $null
            $baseNotes = @((Get-MachineAssessment -Facts (New-FullySetUpFacts)).notes).Count
            $assessment = Get-MachineAssessment -Facts $facts

            @($assessment.plugins | Where-Object { $_.agent -eq 'claude' }) | Should -HaveCount 0
            @($assessment.plugins | Where-Object { $_.agent -eq 'copilot' }) | Should -HaveCount 3
            Get-ProposalIds $assessment | Should -Be ''
            @($assessment.notes).Count | Should -BeGreaterThan $baseNotes
        }

        It 'installs from a marketplace registered under another name, matching its repo case-insensitively' {
            $facts = New-FullySetUpFacts
            $facts.ClaudePlugins = @($facts.ClaudePlugins | Where-Object { $_.id -ne 'model-apps@power-platform-skills' })
            $facts.ClaudeMarketplaces = @(
                @{ name = 'pps'; repo = 'Microsoft/Power-Platform-Skills' }
                @{ name = 'ponytail'; repo = 'DietrichGebert/ponytail' }
            )
            $assessment = Get-MachineAssessment -Facts $facts

            Join-Lines (Get-Proposal $assessment 'install:model-apps@claude').commands | Should -Be 'claude plugin install model-apps@pps'
        }
    }

    Context 'Get-MachineAssessment: telemetry' {

        It 'does not take an opt-out value of 0 as opting out' {
            $facts = New-FullySetUpFacts
            $facts.TelemetryEnv = @{ POWER_PLATFORM_SKILLS_TELEMETRY_MODEL_APPS_OPTOUT = '0' }
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Telemetry $assessment 'model-apps').state | Should -Be 'default-on'
            Get-ProposalIds $assessment | Should -Be 'configure:telemetry-model-apps'
        }

        It 'takes an opt-out value of TRUE as opting out' {
            $facts = New-FullySetUpFacts
            $facts.TelemetryEnv = @{ POWER_PLATFORM_SKILLS_TELEMETRY_MODEL_APPS_OPTOUT = 'TRUE' }
            $assessment = Get-MachineAssessment -Facts $facts

            (Get-Telemetry $assessment 'model-apps').state | Should -Be 'off'
            (Get-Telemetry $assessment 'model-apps').source | Should -Be 'env'
            Get-ProposalIds $assessment | Should -Be ''
        }

        It 'reports no telemetry for a plugin installed in no agent' {
            $facts = New-FullySetUpFacts
            $facts.ClaudePlugins = @($facts.ClaudePlugins | Where-Object { $_.id -notlike 'model-apps@*' })
            $facts.CopilotPlugins = @($facts.CopilotPlugins | Where-Object { $_.id -notlike 'model-apps@*' })
            $assessment = Get-MachineAssessment -Facts $facts

            Join-Lines @($assessment.telemetry | ForEach-Object { $_.plugin }) | Should -Be 'power-automate'
        }
    }

    Context 'adapters of CLI output' {

        BeforeAll {
            $b = $script:bullet
            $script:copilotPluginText = @(
                'Built-in plugins:'
                "  $b browser-use (v0.0.4) [disabled]"
                ''
                'Installed plugins:'
                "  $b dataverse@dataverse-skills (v1.5.0)"
                "  $b model-apps@power-platform-skills (v2.1.0)"
                "  $b power-automate@power-platform-skills (v2.1.0) (disabled)"
                ''
                'Live Plugins (loaded from a local marketplace directory, never copied):'
                "  $b bizapps-solutioning@bizapps-skills (v0.1.0) (disabled)"
                '      from C:\src\bizapps-skills'
            ) -join "`n"

            $script:copilotMarketplaceText = @(
                'Included with GitHub Copilot:'
                "  $($script:diamond) awesome-copilot (GitHub: github/awesome-copilot)"
                ''
                'Registered marketplaces:'
                "  $b dataverse-skills (GitHub: microsoft/Dataverse-skills)"
                "  $b power-platform-skills (GitHub: microsoft/power-platform-skills)"
                "  $b bizapps-skills (Local: C:\src\bizapps-skills)"
            ) -join "`n"
        }

        It 'reads the installed Copilot plugins and nothing from the other sections' {
            $plugins = @(ConvertFrom-CopilotPluginList -Text $script:copilotPluginText)

            Join-Lines @($plugins | ForEach-Object { "$($_.id)|$($_.version)|$($_.enabled)" }) | Should -Be (Join-Lines @(
                'dataverse@dataverse-skills|1.5.0|True'
                'model-apps@power-platform-skills|2.1.0|True'
                'power-automate@power-platform-skills|2.1.0|False'))
        }

        It 'reads the same Copilot plugins from CRLF output' {
            $plugins = @(ConvertFrom-CopilotPluginList -Text ($script:copilotPluginText -replace "`n", "`r`n"))

            Join-Lines @($plugins | ForEach-Object { "$($_.id)|$($_.version)|$($_.enabled)" }) | Should -Be (Join-Lines @(
                'dataverse@dataverse-skills|1.5.0|True'
                'model-apps@power-platform-skills|2.1.0|True'
                'power-automate@power-platform-skills|2.1.0|False'))
        }

        It 'returns no Copilot plugin when there is no Installed plugins section' {
            $text = "Built-in plugins:`n  $($script:bullet) browser-use (v0.0.4) [disabled]"

            Get-Command ConvertFrom-CopilotPluginList -ErrorAction Stop | Out-Null
            @(ConvertFrom-CopilotPluginList -Text $text) | Should -HaveCount 0
        }

        It 'reads every Copilot marketplace, with no repo for a local one' {
            $marketplaces = @(ConvertFrom-CopilotMarketplaceList -Text $script:copilotMarketplaceText)

            Join-Lines @($marketplaces | ForEach-Object { "$($_.name)|$($_.repo)" }) | Should -Be (Join-Lines @(
                'awesome-copilot|github/awesome-copilot'
                'dataverse-skills|microsoft/Dataverse-skills'
                'power-platform-skills|microsoft/power-platform-skills'
                'bizapps-skills|'))
            $marketplaces[3].repo | Should -BeNullOrEmpty
        }

        It 'does not throw on Copilot text it does not recognise' {
            Get-Command ConvertFrom-CopilotPluginList -ErrorAction Stop | Out-Null
            Get-Command ConvertFrom-CopilotMarketplaceList -ErrorAction Stop | Out-Null
            { ConvertFrom-CopilotPluginList -Text 'error: unknown command "plugin"' } | Should -Not -Throw
            { ConvertFrom-CopilotMarketplaceList -Text 'error: unknown command "plugin"' } | Should -Not -Throw
        }

        It 'reads the Claude plugin list' {
            $json = '[{"id":"x@m","version":"0.1.0","scope":"local","enabled":false,"installPath":"C:\\Users\\dev\\.claude\\plugins\\cache\\x","projectPath":"C:\\src\\project"},' +
                '{"id":"model-apps@power-platform-skills","version":"2.20.2","scope":"user","enabled":true,"installPath":"C:\\Users\\dev\\.claude\\plugins\\cache\\model-apps"}]'
            $plugins = @(ConvertFrom-ClaudePluginList -Json $json)

            Join-Lines @($plugins | ForEach-Object { "$($_.id)|$($_.version)|$($_.scope)|$($_.enabled)|$($_.installPath)" }) | Should -Be (Join-Lines @(
                'x@m|0.1.0|local|False|C:\Users\dev\.claude\plugins\cache\x'
                'model-apps@power-platform-skills|2.20.2|user|True|C:\Users\dev\.claude\plugins\cache\model-apps'))
        }

        It 'reads the Claude marketplace list, with no repo for a directory source' {
            $json = '[{"name":"power-platform-skills","source":"github","repo":"microsoft/power-platform-skills","installLocation":"C:\\Users\\dev\\.claude\\plugins\\marketplaces\\pps"},' +
                '{"name":"b","source":"directory","path":"C:\\src\\b"}]'
            $marketplaces = @(ConvertFrom-ClaudeMarketplaceList -Json $json)

            Join-Lines @($marketplaces | ForEach-Object { "$($_.name)|$($_.repo)" }) | Should -Be (Join-Lines @(
                'power-platform-skills|microsoft/power-platform-skills'
                'b|'))
            $marketplaces[1].repo | Should -BeNullOrEmpty
        }

        It 'reads the az extension names' {
            $json = '[{"name":"azure-devops","version":"1.0.2"},{"name":"ml","version":"2.30.0"}]'

            Join-Lines @(ConvertFrom-AzExtensionList -Json $json) | Should -Be (Join-Lines @('azure-devops', 'ml'))
        }

        It 'reads no az extension from an empty list' {
            Get-Command ConvertFrom-AzExtensionList -ErrorAction Stop | Out-Null
            @(ConvertFrom-AzExtensionList -Json '[]') | Should -HaveCount 0
        }

        It 'reads the repository provider <expected> from project.json' -ForEach @(
            @{ provider = 'github'; expected = 'github' }
            @{ provider = 'azure-devops'; expected = 'azure-devops' }
        ) {
            $json = '{"connections":{"repository":{"provider":"' + $provider + '","url":null}}}'

            Get-RepositoryProvider -ProjectJson $json | Should -Be $expected
        }

        It 'reads no repository provider from <case>' -ForEach @(
            @{ case = 'a null provider'; json = '{"connections":{"repository":{"provider":null}}}' }
            @{ case = 'another provider'; json = '{"connections":{"repository":{"provider":"gitlab"}}}' }
            @{ case = 'missing keys'; json = '{"identity":{}}' }
            @{ case = 'invalid JSON'; json = '{"connections":' }
        ) {
            Get-Command Get-RepositoryProvider -ErrorAction Stop | Out-Null
            { Get-RepositoryProvider -ProjectJson $json } | Should -Not -Throw
            Get-RepositoryProvider -ProjectJson $json | Should -BeNullOrEmpty
        }

        It 'maps every folder of a git tree to its sha, ignoring files' {
            $json = '{"sha":"root","tree":[' +
                '{"path":".github","mode":"040000","type":"tree","sha":"sha-github"},' +
                '{"path":".github/plugins/dataverse/skills/dv-query","mode":"040000","type":"tree","sha":"sha-dv-query"},' +
                '{"path":".github/plugins/dataverse/skills/dv-query/SKILL.md","mode":"100644","type":"blob","sha":"sha-file"}' +
                '],"truncated":false}'
            $tree = ConvertFrom-GitTree -Json $json

            $tree | Should -BeOfType [hashtable]
            Join-Lines @($tree.Keys | Sort-Object) | Should -Be (Join-Lines @('.github', '.github/plugins/dataverse/skills/dv-query'))
            $tree['.github/plugins/dataverse/skills/dv-query'] | Should -Be 'sha-dv-query'
        }

        It 'reads the version of a plugin manifest' {
            Get-ManifestVersion -Json '{"name":"model-apps","version":"2.20.2","description":"x"}' | Should -Be '2.20.2'
        }

        It 'reads no version from a manifest without one' {
            Get-Command Get-ManifestVersion -ErrorAction Stop | Out-Null
            Get-ManifestVersion -Json '{"name":"model-apps"}' | Should -BeNullOrEmpty
        }

        It '<command> returns nothing for invalid JSON, without throwing' -ForEach @(
            @{ command = 'ConvertFrom-ClaudePluginList' }
            @{ command = 'ConvertFrom-ClaudeMarketplaceList' }
            @{ command = 'ConvertFrom-AzExtensionList' }
            @{ command = 'ConvertFrom-GitTree' }
            @{ command = 'Get-ManifestVersion' }
        ) {
            Get-Command $command -ErrorAction Stop | Out-Null
            { & $command -Json 'not json {' } | Should -Not -Throw
            & $command -Json 'not json {' | Should -BeNullOrEmpty
        }
    }

    Context 'Get-VersionStatus' {

        BeforeAll {
            # A plain function ignores a switch it does not declare, so without this check a test
            # that expects the same answer with and without -MinimumExclusive would pass for the
            # wrong reason.
            function Assert-MinimumExclusiveSwitch {
                (Get-Command Get-VersionStatus).Parameters.ContainsKey('MinimumExclusive') |
                    Should -BeTrue -Because 'Get-VersionStatus must declare -MinimumExclusive'
            }
        }

        It 'treats a version equal to an exclusive minimum as below it' {
            Assert-MinimumExclusiveSwitch
            Get-VersionStatus -Present $true -Version '2.10.0' -Minimum '2.10.0' -Preferred $null -MinimumExclusive | Should -Be 'below-minimum'
        }

        It 'accepts a version above an exclusive minimum' {
            Assert-MinimumExclusiveSwitch
            Get-VersionStatus -Present $true -Version '2.10.1' -Minimum '2.10.0' -Preferred $null -MinimumExclusive | Should -Be 'ok'
        }

        It 'compares a version with build metadata on its leading numbers, against an exclusive minimum' {
            Assert-MinimumExclusiveSwitch
            Get-VersionStatus -Present $true -Version '2.9.3+ga17df1d' -Minimum '2.10.0' -Preferred $null -MinimumExclusive | Should -Be 'below-minimum'
            Get-VersionStatus -Present $true -Version '2.10.0+gabc1234' -Minimum '2.10.0' -Preferred $null -MinimumExclusive | Should -Be 'below-minimum'
        }

        It 'still reports below-preferred above an exclusive minimum' {
            Assert-MinimumExclusiveSwitch
            Get-VersionStatus -Present $true -Version '2.10.1' -Minimum '2.10.0' -Preferred '3' -MinimumExclusive | Should -Be 'below-preferred'
        }

        It 'reports a missing tool as missing with an exclusive minimum' {
            Assert-MinimumExclusiveSwitch
            Get-VersionStatus -Present $false -Version $null -Minimum '2.10.0' -Preferred $null -MinimumExclusive | Should -Be 'missing'
        }

        # Behaviour without the switch, which already exists and must not change.

        It 'accepts a version equal to an inclusive minimum' {
            Get-VersionStatus -Present $true -Version '22.13.0' -Minimum '22.13' -Preferred $null | Should -Be 'ok'
        }

        It 'compares a git version on its leading numbers' {
            Get-VersionStatus -Present $true -Version '2.53.0.windows.1' -Minimum '2.40' -Preferred $null | Should -Be 'ok'
        }

        It 'reports <expected> for <version> against minimum 8 and preferred 10' -ForEach @(
            @{ version = '6.0.428'; expected = 'below-minimum' }
            @{ version = '8.0.100'; expected = 'below-preferred' }
            @{ version = '10.0.300'; expected = 'ok' }
            @{ version = 'not a version'; expected = 'unknown' }
        ) {
            Get-VersionStatus -Present $true -Version $version -Minimum '8' -Preferred '10' | Should -Be $expected
        }

        It 'reports a missing tool as missing' {
            Get-VersionStatus -Present $false -Version $null -Minimum '8' -Preferred '10' | Should -Be 'missing'
        }

        It 'accepts any version when there is neither a minimum nor a preferred version' {
            Get-VersionStatus -Present $true -Version 'whatever' -Minimum $null -Preferred $null | Should -Be 'ok'
        }
    }
}
