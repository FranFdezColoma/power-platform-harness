#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Behaviour of skills/setup-project/templates/scripts/new-feature.ps1, through its command line.

.DESCRIPTION
    Every test builds a throwaway git repository, copies the template script into its scripts/
    folder, as a scaffold would, and runs it there as a child process. It is judged by what a
    caller sees: the exit code, the single ERROR line on stderr, the plan on stdout, the git state
    and the pac commands it ran.

    The real pac is never reachable. Every child runs with a PATH built here from git, pwsh and
    the Windows folders only, plus, in front, a folder holding a pac.cmd that forwards to
    fake-pac.ps1. The setup proves the real pac is not on that PATH before any test runs. The
    fake logs every call, which is how the tests check that --environment is passed and that no
    pac solution command ever runs.

.EXAMPLE
    pwsh -NoProfile -Command "Invoke-Pester -Path tests/unit/new-feature.Tests.ps1 -Output Detailed"
#>

Describe 'new-feature.ps1' {

    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:template = Join-Path $script:repoRoot 'skills/setup-project/templates/scripts/new-feature.ps1'
        $script:fakePac = Join-Path $PSScriptRoot 'fake-pac.ps1'
        $script:pwsh = (Get-Command -Name pwsh -ErrorAction Stop | Select-Object -First 1).Source
        $script:git = (Get-Command -Name git -ErrorAction Stop | Select-Object -First 1).Source

        $script:suiteRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pph-nf-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
        $fakeBin = Join-Path $script:suiteRoot 'fakebin'
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        $shim = "@`"$script:pwsh`" -NoProfile -NonInteractive -File `"$script:fakePac`" %*`r`n@exit /b %ERRORLEVEL%`r`n"
        [System.IO.File]::WriteAllText((Join-Path $fakeBin 'pac.cmd'), $shim)

        # The smallest PATH the script can work with: git, pwsh (the fake runs on it) and the
        # Windows folders cmd.exe needs. Nothing from the user's PATH, which is where pac lives.
        $directories = @(
            (Split-Path -Parent $script:git)
            (Split-Path -Parent $script:pwsh)
            (Join-Path $env:SystemRoot 'System32')
            $env:SystemRoot
        ) | Select-Object -Unique
        $script:noPacPath = $directories -join ';'
        $script:fakePacPath = (@($fakeBin) + @($directories)) -join ';'

        # Refuse to run anything if the real pac could still be found: it is connected to a real
        # environment, and a test must never reach it.
        $savedPath = $env:PATH
        try {
            $env:PATH = $script:noPacPath
            $realPac = Get-Command -Name pac -ErrorAction SilentlyContinue
            if ($realPac) { throw "pac is still reachable without the fake, at $($realPac.Source). Refusing to run." }
            $env:PATH = $script:fakePacPath
            $resolved = Get-Command -Name pac -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $resolved -or $resolved.Source -ne (Join-Path $fakeBin 'pac.cmd')) {
                throw "pac does not resolve to the fake under the test PATH (got '$($resolved.Source)'). Refusing to run."
            }
        }
        finally {
            $env:PATH = $savedPath
        }

        # A folder that is not a repository must not be mistaken for one because some folder
        # above the temp folder happens to be.
        $script:savedCeiling = $env:GIT_CEILING_DIRECTORIES
        $env:GIT_CEILING_DIRECTORIES = $script:suiteRoot

        $script:fakeVariables = @('FAKEPAC_LOG', 'FAKEPAC_WHO_FAIL', 'FAKEPAC_FRIENDLY_NAME', 'FAKEPAC_ORG_URL',
            'FAKEPAC_PUBLISHER_PREFIX', 'FAKEPAC_PUBLISHER_NAME', 'FAKEPAC_SOLUTION_EXISTS', 'FAKEPAC_SOLUTION_NAME')

        $script:publisherName = 'ContosoConsulting'
        $script:publisherPrefix = 'cnt'
        $script:orgUrl = 'https://contoso-dev.crm4.dynamics.com/'

        function Invoke-Git {
            param([string]$Path, [string[]]$Arguments)

            $output = & $script:git -C $Path @Arguments 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Path}: $($output -join ' ')" }
            return @($output | ForEach-Object { "$_" })
        }

        function Save-Commit {
            param([string]$Message)

            Invoke-Git -Path $script:repo -Arguments @('add', '-A') | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('-c', 'user.name=Pester', '-c', 'user.email=pester@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '--no-verify', '--allow-empty', '-m', $Message) | Out-Null
        }

        # Writes .power-platform/project.json in the shape the scaffold produces, and commits it so
        # the working tree stays clean.
        function Set-ProjectJson {
            param(
                [string]$PublisherUniqueName = $script:publisherName,
                [string]$PublisherPrefix = $script:publisherPrefix,
                $DevUrl = $null
            )

            $project = [ordered]@{
                harnessVersion = '2.0.0'
                identity       = [ordered]@{
                    projectName         = 'Contoso'
                    publisherUniqueName = $PublisherUniqueName
                    publisherPrefix     = $PublisherPrefix
                    coreSolution        = 'none'
                }
                connections    = [ordered]@{
                    dataverse  = [ordered]@{ devUrl = $DevUrl; tenantId = $null }
                    repository = [ordered]@{ provider = 'github'; url = $null }
                    azure      = [ordered]@{ subscriptionId = $null }
                    playwright = [ordered]@{ session = 'Contoso' }
                }
            }
            $folder = Join-Path $script:repo '.power-platform'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $folder 'project.json'), ($project | ConvertTo-Json -Depth 6))
            Save-Commit -Message 'project.json'
        }

        function Remove-ProjectJson {
            Remove-Item -LiteralPath (Join-Path $script:repo '.power-platform') -Recurse -Force
            Save-Commit -Message 'no project.json'
        }

        # Every branch, remote-tracking branch, worktree and HEAD: what an error must leave as it was.
        function Get-GitState {
            $refs = Invoke-Git -Path $script:repo -Arguments @('for-each-ref', '--format=%(refname) %(objectname)')
            $head = Invoke-Git -Path $script:repo -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
            $worktrees = Invoke-Git -Path $script:repo -Arguments @('worktree', 'list', '--porcelain')
            return @($refs) + @("HEAD $head") + @($worktrees)
        }

        function Get-CurrentBranch {
            param([string]$Path = $script:repo)
            return (Invoke-Git -Path $Path -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')) -join ''
        }

        # Runs the script copied into the repository, as a child process, under the test PATH.
        function Invoke-NewFeature {
            param(
                [string[]]$Arguments,
                [string]$WorkingDirectory = $script:repo,
                [string]$PathVariable = $script:fakePacPath
            )

            $scriptPath = Join-Path $WorkingDirectory 'scripts/new-feature.ps1'
            $errorFile = Join-Path $script:testRoot "stderr-$([guid]::NewGuid().ToString('n')).txt"
            $savedPath = $env:PATH
            Push-Location -LiteralPath $WorkingDirectory
            try {
                $env:PATH = $PathVariable
                $stdout = & $script:pwsh -NoProfile -NonInteractive -File $scriptPath @Arguments 2> $errorFile
                $exitCode = $LASTEXITCODE
            }
            finally {
                $env:PATH = $savedPath
                Pop-Location
            }

            $stderr = ''
            if (Test-Path -LiteralPath $errorFile) {
                $stderr = [System.IO.File]::ReadAllText($errorFile).Trim()
                Remove-Item -LiteralPath $errorFile -Force
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                Stdout   = (@($stdout) -join "`n")
                Lines    = @($stdout | ForEach-Object { "$_" })
                Stderr   = $stderr
            }
        }

        # The calls the fake pac received, oldest first.
        function Get-PacCalls {
            if (-not (Test-Path -LiteralPath $script:pacLog)) { return @() }
            return @(Get-Content -LiteralPath $script:pacLog | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        }

        function Test-PacCall {
            param($Call, [string]$Verb)
            return ((@($Call.args) | Select-Object -First 2) -join ' ') -eq $Verb
        }

        function Get-EnvironmentArgument {
            param($Call)

            $arguments = @($Call.args)
            for ($index = 0; $index -lt $arguments.Count; $index++) {
                if ($arguments[$index] -eq '--environment') {
                    if ($index + 1 -lt $arguments.Count) { return $arguments[$index + 1] }
                    return ''
                }
            }
            return $null
        }

        function ConvertTo-ComparableUrl {
            param([string]$Url)
            return $Url.TrimEnd('/').ToLowerInvariant()
        }

        function Assert-NoSolutionCommand {
            $solutionCalls = @(Get-PacCalls | Where-Object { @($_.args) -contains 'solution' })
            $solutionCalls | Should -HaveCount 0 -Because 'new-feature.ps1 must never run a pac solution command'
        }

        # What every error must look like: exit 1, one ERROR line first, and git left as it was.
        function Assert-Rejected {
            param($Run, $GitBefore)

            $Run.ExitCode | Should -Be 1 -Because "stdout: $($Run.Stdout)"
            $Run.Stderr | Should -Match '^ERROR: '
            if ($null -ne $GitBefore) { Get-GitState | Should -Be $GitBefore }
            Assert-NoSolutionCommand
        }

        # The lines around the one naming dv-solution: the next step must name the solution, its
        # version and its publisher together with the skill, not only somewhere in the plan above.
        function Get-NextStep {
            param($Run)

            $lines = @($Run.Lines)
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match 'dv-solution') {
                    $first = [Math]::Max(0, $index - 3)
                    $last = [Math]::Min($lines.Count - 1, $index + 3)
                    return ($lines[$first..$last] -join "`n")
                }
            }
            return ''
        }
    }

    AfterAll {
        $env:GIT_CEILING_DIRECTORIES = $script:savedCeiling
        foreach ($name in $script:fakeVariables) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
        if ($script:suiteRoot -and (Test-Path -LiteralPath $script:suiteRoot)) {
            Remove-Item -LiteralPath $script:suiteRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    BeforeEach {
        $script:testRoot = Join-Path $script:suiteRoot ([guid]::NewGuid().ToString('n').Substring(0, 8))
        $script:repo = Join-Path $script:testRoot 'repo'
        $script:pacLog = Join-Path $script:testRoot 'pac-calls.jsonl'
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'scripts') -Force | Out-Null

        # A DEV environment where everything the script checks is in order.
        $env:FAKEPAC_LOG = $script:pacLog
        $env:FAKEPAC_WHO_FAIL = ''
        $env:FAKEPAC_FRIENDLY_NAME = 'Contoso DEV'
        $env:FAKEPAC_ORG_URL = $script:orgUrl
        $env:FAKEPAC_PUBLISHER_PREFIX = $script:publisherPrefix
        $env:FAKEPAC_PUBLISHER_NAME = $script:publisherName
        $env:FAKEPAC_SOLUTION_EXISTS = ''
        $env:FAKEPAC_SOLUTION_NAME = 'feature_LeadScoring'

        Invoke-Git -Path $script:repo -Arguments @('init', '-b', 'main') | Out-Null
        Copy-Item -LiteralPath $script:template -Destination (Join-Path $script:repo 'scripts/new-feature.ps1')
        Save-Commit -Message 'initial'
        Set-ProjectJson
    }

    AfterEach {
        if ($script:repo -and (Test-Path -LiteralPath $script:repo)) {
            # Worktrees register themselves in the repository; drop them before deleting folders.
            & $script:git -C $script:repo worktree prune 2>&1 | Out-Null
        }
        if ($script:testRoot -and (Test-Path -LiteralPath $script:testRoot)) {
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'names' {

        It 'rejects -Name "<Name>" (<Reason>)' -TestCases @(
            @{ Name = 'Lead-scoring'; Reason = 'uppercase letter' }
            @{ Name = 'LEAD'; Reason = 'all uppercase' }
            @{ Name = 'lead_scoring'; Reason = 'underscore' }
            @{ Name = 'lead--scoring'; Reason = 'double hyphen' }
            @{ Name = 'lead-'; Reason = 'trailing hyphen' }
            @{ Name = 'lead scoring'; Reason = 'space' }
            @{ Name = 'lead.scoring'; Reason = 'dot' }
        ) {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', $Name, '-SkipSolution')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match 'Name'
        }

        It 'derives branch <Branch> and solution <Solution> from -Type <Type> -Name <Name>' -TestCases @(
            @{ Type = 'feature'; Name = 'lead-scoring-widget'; Branch = 'feature/lead-scoring-widget'; Solution = 'feature_LeadScoringWidget' }
            @{ Type = 'feature'; Name = '2fa-login'; Branch = 'feature/2fa-login'; Solution = 'feature_2faLogin' }
            @{ Type = 'fix'; Name = 'a1-b2'; Branch = 'fix/a1-b2'; Solution = 'fix_A1B2' }
            @{ Type = 'chore'; Name = 'bump'; Branch = 'chore/bump'; Solution = 'chore_Bump' }
        ) {
            $env:FAKEPAC_SOLUTION_NAME = $Solution

            $run = Invoke-NewFeature -Arguments @('-Type', $Type, '-Name', $Name, '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $run.Stdout.Contains($Branch) | Should -BeTrue -Because "the plan should name branch $Branch"
            $run.Stdout.Contains($Solution) | Should -BeTrue -Because "the plan should name solution $Solution"
            $solutionQueries = @(Get-PacCalls | Where-Object { $_.entity -eq 'solution' })
            $solutionQueries.Count | Should -BeGreaterThan 0 -Because 'the script must check that the solution name is free'
            @($solutionQueries | Where-Object { $_.value -cne $Solution }) | Should -HaveCount 0
        }

        It 'accepts a solution name of exactly 65 characters' {
            # feature_ (8 characters) + 57: 65.
            $name = 'a' * 57
            $solution = 'feature_A' + ('a' * 56)
            $solution.Length | Should -Be 65
            $env:FAKEPAC_SOLUTION_NAME = $solution

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', $name, '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $run.Stdout.Contains($solution) | Should -BeTrue
        }

        It 'rejects a solution name longer than 65 characters' {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', ('a' * 58))

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match '65'
        }

        It 'accepts a long name with -SkipSolution, where only the branch matters' {
            $name = 'a' * 100

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', $name, '-SkipSolution', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $run.Stdout.Contains("feature/$name") | Should -BeTrue
        }
    }

    Context 'project identity from .power-platform/project.json' {

        It 'fails without project.json unless -SkipSolution' {
            Remove-ProjectJson
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match 'project\.json'
        }

        It 'rejects publisherUniqueName "<Value>"' -TestCases @(
            @{ Value = 'Contoso Consulting' }
            @{ Value = '1Contoso' }
            @{ Value = 'Contoso-Consulting' }
        ) {
            Set-ProjectJson -PublisherUniqueName $Value
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match "publisherUniqueName|$([regex]::Escape($Value))"
        }

        It 'rejects publisherPrefix "<Value>" (<Reason>)' -TestCases @(
            @{ Value = 'CNT'; Reason = 'uppercase' }
            @{ Value = 'c'; Reason = 'too short' }
            @{ Value = 'abcdefghi'; Reason = 'too long' }
            @{ Value = '1cn'; Reason = 'starts with a digit' }
            @{ Value = 'c_t'; Reason = 'underscore' }
        ) {
            Set-ProjectJson -PublisherPrefix $Value
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match "publisherPrefix|'$([regex]::Escape($Value))'"
        }

        It 'creates the branch with -SkipSolution without project.json and without calling pac' {
            Remove-ProjectJson

            $run = Invoke-NewFeature -Arguments @('-Type', 'chore', '-Name', 'bump-eslint', '-SkipSolution')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            Get-CurrentBranch | Should -BeExactly 'chore/bump-eslint'
            $run.Stdout.Contains('none (-SkipSolution)') | Should -BeTrue
            Get-PacCalls | Should -HaveCount 0
        }
    }

    Context 'git checks' {

        It 'fails outside a git repository' {
            $plain = Join-Path $script:testRoot 'plain'
            New-Item -ItemType Directory -Path (Join-Path $plain 'scripts') -Force | Out-Null
            Copy-Item -LiteralPath $script:template -Destination (Join-Path $plain 'scripts/new-feature.ps1')

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-SkipSolution') -WorkingDirectory $plain

            Assert-Rejected -Run $run -GitBefore $null
            Join-Path $plain '.git' | Should -Not -Exist
        }

        It 'fails when the branch already exists locally (<Mode>)' -TestCases @(
            @{ Mode = 'branch only'; Extra = @('-SkipSolution') }
            @{ Mode = 'with solution'; Extra = @('-DryRun') }
        ) {
            Invoke-Git -Path $script:repo -Arguments @('branch', 'feature/lead-scoring') | Out-Null
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments (@('-Type', 'feature', '-Name', 'lead-scoring') + $Extra)

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.Contains('feature/lead-scoring') | Should -BeTrue
        }

        It 'fails when the branch exists on origin' {
            $origin = Join-Path $script:testRoot 'origin.git'
            & $script:git init --bare $origin 2>&1 | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('remote', 'add', 'origin', $origin) | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('branch', 'feature/lead-scoring') | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('push', '--no-verify', 'origin', 'main', 'feature/lead-scoring') | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('branch', '-D', 'feature/lead-scoring') | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('fetch', 'origin') | Out-Null
            Invoke-Git -Path $script:repo -Arguments @('rev-parse', '--verify', 'refs/remotes/origin/feature/lead-scoring') | Out-Null
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-SkipSolution')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.Contains('feature/lead-scoring') | Should -BeTrue
        }

        It 'fails with -Worktree when the worktree folder already exists' {
            $folder = Join-Path $script:testRoot 'repo.worktrees/feature/lead-scoring'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-Worktree', '-SkipSolution')

            Assert-Rejected -Run $run -GitBefore $before
            @(Get-ChildItem -LiteralPath $folder -Force) | Should -HaveCount 0
        }

        It 'fails with -Worktree when already on the target branch' {
            Invoke-Git -Path $script:repo -Arguments @('switch', '-c', 'feature/lead-scoring') | Out-Null
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-Worktree', '-SkipSolution')

            Assert-Rejected -Run $run -GitBefore $before
            Join-Path $script:testRoot 'repo.worktrees' | Should -Not -Exist
        }

        It 'keeps the branch, runs the checks and prints the plan when already on the target branch' {
            Invoke-Git -Path $script:repo -Arguments @('switch', '-c', 'feature/lead-scoring') | Out-Null
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            Get-GitState | Should -Be $before
            Get-CurrentBranch | Should -BeExactly 'feature/lead-scoring'
            $run.Stdout.Contains('feature/lead-scoring') | Should -BeTrue
            $run.Stdout.Contains('feature_LeadScoring') | Should -BeTrue
            $calls = Get-PacCalls
            @($calls | Where-Object { Test-PacCall -Call $_ -Verb 'org who' }).Count | Should -BeGreaterThan 0
            @($calls | Where-Object { $_.entity -eq 'publisher' }).Count | Should -BeGreaterThan 0
            @($calls | Where-Object { $_.entity -eq 'solution' }).Count | Should -BeGreaterThan 0
            Assert-NoSolutionCommand
        }
    }

    Context 'pac checks' {

        It 'fails when pac is not on PATH' {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun') -PathVariable $script:noPacPath

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr | Should -Match '\bpac\b'
        }

        It 'fails when pac org who fails' {
            $env:FAKEPAC_WHO_FAIL = '1'
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            @(Get-PacCalls | Where-Object { Test-PacCall -Call $_ -Verb 'org who' }).Count | Should -BeGreaterThan 0
        }

        It 'passes --environment with the devUrl to every pac call when project.json has a devUrl' {
            # Same environment, written with another case and without the trailing slash.
            $devUrl = 'https://Contoso-Dev.crm4.dynamics.com'
            Set-ProjectJson -DevUrl $devUrl

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $calls = Get-PacCalls
            $calls.Count | Should -BeGreaterOrEqual 3 -Because 'org who, the publisher query and the solution query'
            foreach ($call in $calls) {
                $environment = Get-EnvironmentArgument -Call $call
                $environment | Should -Not -BeNullOrEmpty -Because "every pac call must target DEV: pac $(@($call.args) -join ' ')"
                ConvertTo-ComparableUrl $environment | Should -Be (ConvertTo-ComparableUrl $devUrl)
            }
        }

        It 'fails when pac org who reports another url than devUrl, naming both' {
            $devUrl = 'https://contoso-dev.crm4.dynamics.com/'
            $otherUrl = 'https://fabrikam-dev.crm4.dynamics.com/'
            Set-ProjectJson -DevUrl $devUrl
            $env:FAKEPAC_ORG_URL = $otherUrl
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.ToLowerInvariant().Contains((ConvertTo-ComparableUrl $devUrl)) | Should -BeTrue -Because "stderr should name devUrl: $($run.Stderr)"
            $run.Stderr.ToLowerInvariant().Contains((ConvertTo-ComparableUrl $otherUrl)) | Should -BeTrue -Because "stderr should name the connected url: $($run.Stderr)"
            foreach ($call in Get-PacCalls) { Get-EnvironmentArgument -Call $call | Should -Not -BeNullOrEmpty }
        }

        It 'passes no --environment and points at the connect skill when devUrl is null' {
            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $calls = Get-PacCalls
            $calls.Count | Should -BeGreaterOrEqual 3
            foreach ($call in $calls) {
                Get-EnvironmentArgument -Call $call | Should -BeNullOrEmpty -Because "pac $(@($call.args) -join ' ')"
            }
            $run.Stdout | Should -Match '\bconnect\b'
        }

        It 'refuses an environment that looks like <Kind>: "<FriendlyName>" at <Url>' -TestCases @(
            @{ Kind = 'production'; FriendlyName = 'Contoso PROD'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'production'; FriendlyName = 'Contoso PRD'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'production'; FriendlyName = 'Contoso Production'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'production'; FriendlyName = 'Contoso Live'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'production'; FriendlyName = 'Contoso'; Url = 'https://contoso-prod.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso Test'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso TST'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso QA'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso UAT'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso SIT'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso Stag'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso Staging'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso Stage'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso PreProd'; Url = 'https://contoso.crm4.dynamics.com/' }
            @{ Kind = 'test'; FriendlyName = 'Contoso'; Url = 'https://contoso-uat.crm4.dynamics.com/' }
        ) {
            $env:FAKEPAC_FRIENDLY_NAME = $FriendlyName
            $env:FAKEPAC_ORG_URL = $Url
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            @(Get-PacCalls | Where-Object { Test-PacCall -Call $_ -Verb 'org who' }).Count | Should -BeGreaterThan 0
        }

        It 'refuses a test-looking environment even when it is the devUrl in project.json' {
            $url = 'https://contoso-uat.crm4.dynamics.com/'
            Set-ProjectJson -DevUrl $url
            $env:FAKEPAC_FRIENDLY_NAME = 'Contoso UAT'
            $env:FAKEPAC_ORG_URL = $url
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            @(Get-PacCalls | Where-Object { Test-PacCall -Call $_ -Verb 'org who' }).Count | Should -BeGreaterThan 0
        }

        It 'does not mistake "live" inside a word for production' {
            $env:FAKEPAC_FRIENDLY_NAME = 'Delivery DEV'
            $env:FAKEPAC_ORG_URL = 'https://delivery-dev.crm4.dynamics.com/'

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
        }

        It 'fails when the publisher does not exist' {
            $env:FAKEPAC_PUBLISHER_PREFIX = ''
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.Contains($script:publisherName) | Should -BeTrue
            @(Get-PacCalls | Where-Object { $_.entity -eq 'publisher' -and $_.value -ceq $script:publisherName }).Count | Should -BeGreaterThan 0
        }

        It 'fails when the publisher has prefix "<Actual>" instead of cnt' -TestCases @(
            @{ Actual = 'abc' }
            @{ Actual = 'CNT' }
        ) {
            $env:FAKEPAC_PUBLISHER_PREFIX = $Actual
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.Contains($Actual) | Should -BeTrue -Because "stderr should name the prefix found: $($run.Stderr)"
            @(Get-PacCalls | Where-Object { $_.entity -eq 'publisher' }).Count | Should -BeGreaterThan 0
        }

        It 'fails when a solution with the unique name already exists' {
            $env:FAKEPAC_SOLUTION_EXISTS = '1'
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            Assert-Rejected -Run $run -GitBefore $before
            $run.Stderr.Contains('feature_LeadScoring') | Should -BeTrue
            @(Get-PacCalls | Where-Object { $_.entity -eq 'solution' -and $_.value -ceq 'feature_LeadScoring' }).Count | Should -BeGreaterThan 0
        }
    }

    Context 'plan, dry run and real run' {

        It 'prints the plan and changes nothing with -DryRun' {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            foreach ($expected in @('feature/lead-scoring', 'feature_LeadScoring', '1.0.0.0', $script:publisherName, $script:publisherPrefix, 'Dry run')) {
                $run.Stdout.Contains($expected) | Should -BeTrue -Because "the plan should contain '$expected': $($run.Stdout)"
            }
            $run.Stdout.ToLowerInvariant().Contains((ConvertTo-ComparableUrl $script:orgUrl)) | Should -BeTrue -Because 'the plan should name the environment url'
            Get-GitState | Should -Be $before
            Assert-NoSolutionCommand
        }

        It 'creates no worktree with -Worktree -DryRun' {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-Worktree', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $run.Stdout.Contains('Dry run') | Should -BeTrue
            Get-GitState | Should -Be $before
            Join-Path $script:testRoot 'repo.worktrees' | Should -Not -Exist
        }

        It 'prints none (-SkipSolution) for the solution with -SkipSolution -DryRun' {
            $before = Get-GitState

            $run = Invoke-NewFeature -Arguments @('-Type', 'chore', '-Name', 'bump-eslint', '-SkipSolution', '-DryRun')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $run.Stdout.Contains('chore/bump-eslint') | Should -BeTrue
            $run.Stdout.Contains('none (-SkipSolution)') | Should -BeTrue
            $run.Stdout.Contains('Dry run') | Should -BeTrue
            Get-GitState | Should -Be $before
            Get-PacCalls | Should -HaveCount 0
        }

        It 'creates the branch here and hands the solution to dv-solution' {
            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            Get-CurrentBranch | Should -BeExactly 'feature/lead-scoring'
            $next = Get-NextStep -Run $run
            $next | Should -Not -BeNullOrEmpty -Because "stdout should name dv-solution: $($run.Stdout)"
            foreach ($expected in @('feature_LeadScoring', '1.0.0.0', $script:publisherName)) {
                $next.Contains($expected) | Should -BeTrue -Because "the dv-solution next step should name '$expected': $next"
            }
            Assert-NoSolutionCommand
        }

        It 'creates the branch in a worktree next to the repository with -Worktree' {
            $folder = Join-Path $script:testRoot 'repo.worktrees/feature/lead-scoring'

            $run = Invoke-NewFeature -Arguments @('-Type', 'feature', '-Name', 'lead-scoring', '-Worktree')

            $run.ExitCode | Should -Be 0 -Because $run.Stderr
            $folder | Should -Exist
            Get-CurrentBranch -Path $folder | Should -BeExactly 'feature/lead-scoring'
            Get-CurrentBranch | Should -BeExactly 'main'
            Get-NextStep -Run $run | Should -Not -BeNullOrEmpty
            Assert-NoSolutionCommand
        }
    }
}
