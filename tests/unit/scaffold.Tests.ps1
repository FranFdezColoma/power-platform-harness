#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Behaviour of skills/setup-project/scripts/scaffold.ps1, through its command line.

.DESCRIPTION
    Every test runs the script as a child process against a throwaway folder and judges it by
    what a caller sees: the exit code, the single ERROR line on stderr, the files written and
    their content. Nothing here talks to Dataverse, and nothing is written inside the repository.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester -Path tests/unit/scaffold.Tests.ps1 -Output Detailed"
#>

Describe 'scaffold.ps1' {

    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:scaffold = Join-Path $script:repoRoot 'skills/setup-project/scripts/scaffold.ps1'
        $script:pwsh = (Get-Command -Name pwsh -ErrorAction Stop | Select-Object -First 1).Source

        # The values of a run that must succeed. Each test overrides only what it is about, so a
        # failure points at one value instead of at the combination.
        $script:validValues = [ordered]@{
            ProjectName         = 'Northwind'
            PublisherUniqueName = 'NorthwindConsulting'
            PublisherPrefix     = 'nwc'
            CoreSolution        = 'NorthwindCore'
            ProjectDescription  = 'Customer Service implementation for Northwind.'
            RepositoryProvider  = 'github'
        }

        # Runs scaffold.ps1 in a child process. Values set to $true become switches; a key set to
        # $null is left out, which is how a test exercises a parameter's default.
        function Invoke-Scaffold {
            param([System.Collections.IDictionary]$Values, [string[]]$Switches = @())

            $arguments = @('-NoProfile', '-NonInteractive', '-File', $script:scaffold)
            foreach ($key in $Values.Keys) {
                if ($null -eq $Values[$key]) { continue }
                $arguments += @("-$key", [string]$Values[$key])
            }
            foreach ($switch in $Switches) { $arguments += "-$switch" }

            $errorFile = Join-Path $script:testRoot "stderr-$([guid]::NewGuid().ToString('n')).txt"
            $stdout = & $script:pwsh @arguments 2> $errorFile
            $exitCode = $LASTEXITCODE
            $stderr = ''
            if (Test-Path -LiteralPath $errorFile) {
                $stderr = [System.IO.File]::ReadAllText($errorFile).Trim()
                Remove-Item -LiteralPath $errorFile -Force
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                Stdout   = (@($stdout) -join "`n")
                Stderr   = $stderr
            }
        }

        # The valid values with some overridden, targeting the current test folder.
        function Get-Values {
            param([hashtable]$Override = @{})

            $values = [ordered]@{}
            foreach ($key in $script:validValues.Keys) { $values[$key] = $script:validValues[$key] }
            foreach ($key in $Override.Keys) { $values[$key] = $Override[$key] }
            $values['TargetPath'] = $script:target
            return $values
        }

        # Every file under the target with its length and write time, so a test can prove that a
        # second run changed nothing.
        function Get-TreeSnapshot {
            return @(Get-ChildItem -LiteralPath $script:target -Recurse -Force -File |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" })
        }

        function Get-TargetEntries {
            return @(Get-ChildItem -LiteralPath $script:target -Recurse -Force)
        }
    }

    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pph-scaffold-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
        $script:target = Join-Path $script:testRoot 'target'
        New-Item -ItemType Directory -Path $script:target -Force | Out-Null
    }

    AfterEach {
        if ($script:testRoot -and (Test-Path -LiteralPath $script:testRoot)) {
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'rejects invalid values before writing anything' {

        It 'rejects <Parameter> = "<Value>" (<Reason>)' -TestCases @(
            @{ Parameter = 'ProjectName'; Value = '1Northwind'; Reason = 'starts with a digit' }
            @{ Parameter = 'ProjectName'; Value = 'North-wind'; Reason = 'contains a hyphen' }
            @{ Parameter = 'ProjectName'; Value = 'North wind'; Reason = 'contains a space' }
            @{ Parameter = 'ProjectName'; Value = 'North_wind'; Reason = 'contains an underscore' }
            @{ Parameter = 'PublisherUniqueName'; Value = 'Northwind Consulting'; Reason = 'display name with a space' }
            @{ Parameter = 'PublisherUniqueName'; Value = '1Northwind'; Reason = 'starts with a digit' }
            @{ Parameter = 'PublisherUniqueName'; Value = 'Northwind-Consulting'; Reason = 'contains a hyphen' }
            @{ Parameter = 'PublisherPrefix'; Value = 'NWC'; Reason = 'uppercase' }
            @{ Parameter = 'PublisherPrefix'; Value = 'nWc'; Reason = 'mixed case' }
            @{ Parameter = 'PublisherPrefix'; Value = 'n'; Reason = 'too short' }
            @{ Parameter = 'PublisherPrefix'; Value = 'abcdefghi'; Reason = 'too long, 9 characters' }
            @{ Parameter = 'PublisherPrefix'; Value = '1nw'; Reason = 'starts with a digit' }
            @{ Parameter = 'PublisherPrefix'; Value = 'nw_c'; Reason = 'contains an underscore' }
            @{ Parameter = 'PublisherPrefix'; Value = 'mscrm'; Reason = 'reserved by Dataverse' }
            @{ Parameter = 'PublisherPrefix'; Value = 'mscrmx'; Reason = 'starts with mscrm' }
            @{ Parameter = 'CoreSolution'; Value = 'Northwind Core'; Reason = 'display name with a space' }
            @{ Parameter = 'CoreSolution'; Value = '1Core'; Reason = 'starts with a digit' }
            @{ Parameter = 'CoreSolution'; Value = 'Northwind-Core'; Reason = 'contains a hyphen' }
            @{ Parameter = 'ProjectDescription'; Value = '   '; Reason = 'blank' }
            @{ Parameter = 'RepositoryProvider'; Value = 'GitHub'; Reason = 'not lowercase' }
            @{ Parameter = 'RepositoryProvider'; Value = 'Azure-DevOps'; Reason = 'not lowercase' }
            @{ Parameter = 'RepositoryProvider'; Value = 'gitlab'; Reason = 'unsupported provider' }
            @{ Parameter = 'RepositoryProvider'; Value = 'azure'; Reason = 'unsupported provider' }
            @{ Parameter = 'RepositoryProvider'; Value = 'azuredevops'; Reason = 'missing hyphen' }
            @{ Parameter = 'RepositoryProvider'; Value = '   '; Reason = 'blank' }
        ) {
            $run = Invoke-Scaffold -Values (Get-Values -Override @{ $Parameter = $Value })

            $run.ExitCode | Should -Be 1
            $run.Stderr | Should -Match '^ERROR: '
            $run.Stderr | Should -Match $Parameter
            Get-TargetEntries | Should -HaveCount 0
        }

        It 'rejects -Force together with -SkipExisting' {
            $run = Invoke-Scaffold -Values (Get-Values) -Switches @('Force', 'SkipExisting')

            $run.ExitCode | Should -Be 1
            $run.Stderr | Should -Match '^ERROR: '
            Get-TargetEntries | Should -HaveCount 0
        }
    }

    Context 'writes a complete repository' {

        It 'writes the templates with every token resolved' {
            $run = Invoke-Scaffold -Values (Get-Values)

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            foreach ($relative in @('AGENTS.md', 'CLAUDE.md', '.power-platform/project.json', 'scripts/new-feature.ps1', 'docs/agents/development-standards.md')) {
                Join-Path $script:target $relative | Should -Exist
            }

            # A token can survive in a file's content or in a file or folder name.
            $leftovers = foreach ($entry in Get-TargetEntries) {
                if ($entry.Name -match '\{\{[a-z_]+\}\}') { "name: $($entry.FullName)" }
                if (-not $entry.PSIsContainer) {
                    $found = Select-String -LiteralPath $entry.FullName -Pattern '\{\{[a-z_]+\}\}' -AllMatches
                    foreach ($line in @($found)) { "$($entry.FullName):$($line.LineNumber): $($line.Line.Trim())" }
                }
            }
            @($leftovers) | Should -HaveCount 0 -Because (@($leftovers) -join '; ')
        }

        It 'writes CLAUDE.md as a pointer to AGENTS.md' {
            $run = Invoke-Scaffold -Values (Get-Values)

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            ([System.IO.File]::ReadAllText((Join-Path $script:target 'CLAUDE.md'))).Trim() | Should -BeExactly '@AGENTS.md'
        }

        It 'writes .power-platform/project.json with the identity and the expected connections' {
            $run = Invoke-Scaffold -Values (Get-Values)

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $project = [System.IO.File]::ReadAllText((Join-Path $script:target '.power-platform/project.json')) | ConvertFrom-Json

            $project.identity.projectName | Should -BeExactly 'Northwind'
            $project.identity.publisherUniqueName | Should -BeExactly 'NorthwindConsulting'
            $project.identity.publisherPrefix | Should -BeExactly 'nwc'
            $project.identity.coreSolution | Should -BeExactly 'NorthwindCore'
            $project.connections.repository.provider | Should -BeExactly 'github'
            $project.connections.dataverse.PSObject.Properties.Name | Should -Contain 'devUrl'
            $project.connections.dataverse.devUrl | Should -BeNullOrEmpty
            $project.connections.playwright.session | Should -BeExactly 'Northwind'
        }

        It 'maps -RepositoryProvider <Provider> to the <Cli> CLI' -TestCases @(
            @{ Provider = 'github'; Cli = 'gh'; OtherCli = 'az repos' }
            @{ Provider = 'azure-devops'; Cli = 'az repos'; OtherCli = 'gh' }
        ) {
            $run = Invoke-Scaffold -Values (Get-Values -Override @{ RepositoryProvider = $Provider }) -Switches @('Json')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $summary = $run.Stdout | ConvertFrom-Json
            $summary.values.repositoryProvider | Should -BeExactly $Provider

            $agents = [System.IO.File]::ReadAllText((Join-Path $script:target 'AGENTS.md'))
            $agents.Contains("``$Cli``") | Should -BeTrue -Because "AGENTS.md should name ``$Cli``"
            $agents.Contains("``$OtherCli``") | Should -BeFalse -Because "AGENTS.md should not name ``$OtherCli``"

            $project = [System.IO.File]::ReadAllText((Join-Path $script:target '.power-platform/project.json')) | ConvertFrom-Json
            $project.connections.repository.provider | Should -BeExactly $Provider
        }

        It 'defaults CoreSolution to none' {
            $run = Invoke-Scaffold -Values (Get-Values -Override @{ CoreSolution = $null }) -Switches @('Json')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            ($run.Stdout | ConvertFrom-Json).values.coreSolution | Should -BeExactly 'none'
            $project = [System.IO.File]::ReadAllText((Join-Path $script:target '.power-platform/project.json')) | ConvertFrom-Json
            $project.identity.coreSolution | Should -BeExactly 'none'
        }

        It 'writes nothing with -DryRun' {
            $run = Invoke-Scaffold -Values (Get-Values) -Switches @('DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            Get-TargetEntries | Should -HaveCount 0
        }
    }

    Context 'over a folder that is already scaffolded' {

        BeforeEach {
            $first = Invoke-Scaffold -Values (Get-Values)
            $first.ExitCode | Should -Be 0 -Because "the first scaffold must succeed: $($first.Stderr)"
        }

        It 'aborts a second run without writing anything' {
            # A file the second run would write if it did not abort: proves nothing was written,
            # not only that nothing was overwritten.
            $missing = Join-Path $script:target 'docs/agents/toolchain.md'
            Remove-Item -LiteralPath $missing -Force
            $before = Get-TreeSnapshot

            $run = Invoke-Scaffold -Values (Get-Values)

            $run.ExitCode | Should -Be 1
            $run.Stderr | Should -Match '^ERROR: '
            $missing | Should -Not -Exist
            Get-TreeSnapshot | Should -Be $before
        }

        It 'creates nothing when re-run with -SkipExisting' {
            $before = Get-TreeSnapshot

            $run = Invoke-Scaffold -Values (Get-Values) -Switches @('SkipExisting', 'Json')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            @(($run.Stdout | ConvertFrom-Json).created) | Should -HaveCount 0
            Get-TreeSnapshot | Should -Be $before
        }
    }
}
