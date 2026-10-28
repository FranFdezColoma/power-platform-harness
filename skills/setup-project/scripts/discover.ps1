<#
.SYNOPSIS
    Read-only discovery of a repository and, optionally, the connected Dataverse environment.

.DESCRIPTION
    Answers the questions the setup-project skill needs before it writes anything:

      - Is this folder empty, or an existing project the harness has to adapt to?
      - Which publisher, prefix, core solution and namespace does the project already use?
      - Which versions and frameworks does it actually use, and where do those differ from the
        versions the shipped standards assert (standards-baseline.json)?
      - Through pac, which publishers and unmanaged solutions exist in the connected environment,
        so the project's identity can be read rather than asked for?

    The machine's tools are the setup-tools skill's question, and whether the connection points
    at the right environment is the connect skill's: this script answers neither.

    Everything here reads. Nothing is created, modified or deleted, in the repository or in the
    environment. Output is a single JSON document on stdout so the caller does not have to parse
    prose; per-probe failures are recorded as fields inside it rather than aborting the run, so a
    missing pac still yields a usable repository report.

.EXAMPLE
    ./scripts/discover.ps1 -Path C:\repos\northwind

.EXAMPLE
    # Repository only: no network, no pac calls.
    ./scripts/discover.ps1 -SkipEnvironment

.EXAMPLE
    # The user gave only the prefix: look up the publisher that owns it in the environment.
    ./scripts/discover.ps1 -PublisherPrefix nwc

.EXAMPLE
    # Read the real publisher and prefix out of a solution that exists in the environment but has
    # never been unpacked into the repository. Exports to a temp folder and deletes it afterwards.
    ./scripts/discover.ps1 -ResolvePublisherFromSolution NorthwindCore
#>
[CmdletBinding()]
param(
    # Repository to inspect. Defaults to the current folder.
    [string]$Path = (Get-Location).Path,

    # Skip every pac call. Use when offline, or when the environment is irrelevant to the question.
    [switch]$SkipEnvironment,

    # Environment to report on, when it is not the active pac profile's.
    [string]$EnvironmentUrl,

    # Export this solution to a temp folder to read its real publisher name and customization
    # prefix. Read-only against Dataverse, but it transfers the whole solution: opt in explicitly.
    [string]$ResolvePublisherFromSolution,

    # Customization prefix the user already gave. Matched against the publishers in the connected
    # environment so the publisher unique name does not have to be asked for as well.
    [string]$PublisherPrefix,

    # Per-command timeout. A hung pac call must not hang the caller.
    [int]$TimeoutSeconds = 90,

    # Upper bound on the file walk, so a repository with a huge build cache still returns.
    [int]$MaxFiles = 20000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_dataverse.ps1')

# --------------------------------------------------------------------------------------------
# Repository walk
# --------------------------------------------------------------------------------------------

# Folders that hold build output, caches or dependencies. Descending into them is slow enough to
# look like a hang (a uv or NuGet cache is tens of thousands of files) and tells us nothing.
$prunedFolders = @(
    '.git', '.svn', '.hg', 'node_modules', 'bin', 'obj', '.vs', 'packages', 'out', 'dist',
    'TestResults', '.build-cache', '.nuget', '.idea', 'coverage', '.venv', 'venv', '__pycache__',
    '.next', '.gradle', '.terraform', 'generated', 'Generated'
)

function Get-RepoInventory {
    param([string]$Root, [int]$Limit)

    $files = New-Object System.Collections.Generic.List[string]
    $pruned = New-Object System.Collections.Generic.HashSet[string]
    $directories = New-Object System.Collections.Generic.List[string]
    $truncated = $false

    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Root)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()

        try {
            $entries = [System.IO.Directory]::GetFileSystemEntries($current)
        }
        catch {
            continue
        }

        foreach ($entry in $entries) {
            $name = [System.IO.Path]::GetFileName($entry)
            $isDirectory = $false
            try { $isDirectory = ([System.IO.File]::GetAttributes($entry) -band [System.IO.FileAttributes]::Directory) -ne 0 } catch { continue }

            if ($isDirectory) {
                if ($prunedFolders -contains $name) {
                    $relative = $entry.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
                    $pruned.Add($relative) | Out-Null
                    continue
                }
                $directories.Add(($entry.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')) | Out-Null
                $pending.Push($entry)
            }
            else {
                if ($files.Count -ge $Limit) {
                    $truncated = $true
                    continue
                }
                $files.Add(($entry.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        Files       = $files
        Directories = $directories
        Pruned      = @($pruned)
        Truncated   = $truncated
    }
}

function Select-Files {
    param(
        [System.Collections.Generic.List[string]]$Files,
        [string]$Pattern,
        [int]$Limit = 200
    )

    # The leading comma stops PowerShell unrolling the array on return: without it, no match comes
    # back as null and one match as a bare string, and the JSON report changes type with the count.
    $matched = @($Files | Where-Object { $_ -match $Pattern })
    if ($matched.Count -gt $Limit) { return ,@($matched | Select-Object -First $Limit) }
    return ,$matched
}

function Get-ItemMetadata {
    param([System.Xml.XmlElement]$Node, [string]$Name)

    # MSBuild accepts item metadata as an attribute or as a child element.
    $value = $Node.GetAttribute($Name)
    if (-not $value) {
        $child = $Node.SelectSingleNode("*[local-name()='$Name']")
        if ($child) { $value = $child.InnerText.Trim() }
    }
    # A version written as an MSBuild property, $(XunitVersion), cannot be resolved by reading XML.
    if (-not $value -or $value -match '\$\(') { return $null }
    return $value
}

$script:centralVersionsCache = @{}

function Get-CentralPackageVersions {
    param([string]$Root, [string]$ProjectFolder)

    # Central Package Management: MSBuild imports the Directory.Packages.props nearest to the
    # project, walking up the folders. Stop at the repository root rather than read files outside it.
    $folder = $ProjectFolder
    $propsFile = $null
    while ($folder) {
        $candidate = Join-Path $folder 'Directory.Packages.props'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $propsFile = $candidate; break }
        if ($folder.TrimEnd('\', '/') -eq $Root.TrimEnd('\', '/')) { break }
        $parent = Split-Path -Parent $folder
        if (-not $parent -or $parent -eq $folder -or -not $parent.StartsWith($Root.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $folder = $parent
    }

    if (-not $propsFile) { return @{} }
    if ($script:centralVersionsCache.ContainsKey($propsFile)) { return $script:centralVersionsCache[$propsFile] }

    $versions = @{}
    $document = Read-XmlFile -FullPath $propsFile
    if ($document) {
        foreach ($node in $document.DocumentElement.SelectNodes('//*[local-name()="PackageVersion"]')) {
            $id = $node.GetAttribute('Include')
            if (-not $id) { $id = $node.GetAttribute('Update') }
            if ($id -and -not $versions.ContainsKey($id)) { $versions[$id] = Get-ItemMetadata -Node $node -Name 'Version' }
        }
    }
    $script:centralVersionsCache[$propsFile] = $versions
    return $versions
}

function Get-ProjectFacts {
    param([string]$Root, [string[]]$ProjectFiles)

    foreach ($relative in $ProjectFiles) {
        $fullPath = Join-Path $Root $relative
        $projectFolder = Split-Path -Parent $fullPath
        $document = Read-XmlFile -FullPath $fullPath

        if (-not $document) {
            [pscustomobject]@{ path = $relative; readError = 'Project file could not be parsed.' }
            continue
        }

        $projectElement = $document.DocumentElement
        $sdkStyle = $projectElement.HasAttribute('Sdk')

        $properties = @{}
        foreach ($node in $projectElement.SelectNodes('//*[local-name()="PropertyGroup"]/*')) {
            if (-not $properties.ContainsKey($node.LocalName)) { $properties[$node.LocalName] = $node.InnerText.Trim() }
        }

        $centralVersions = Get-CentralPackageVersions -Root $Root -ProjectFolder $projectFolder
        $packages = foreach ($node in $projectElement.SelectNodes('//*[local-name()="PackageReference"]')) {
            $id = $node.GetAttribute('Include')
            if (-not $id) { $id = $node.GetAttribute('Update') }
            # VersionOverride beats the central version; a version on the reference itself means the
            # project does not use Central Package Management for that package.
            $version = Get-ItemMetadata -Node $node -Name 'VersionOverride'
            if (-not $version) { $version = Get-ItemMetadata -Node $node -Name 'Version' }
            if (-not $version -and $id -and $centralVersions.ContainsKey($id)) { $version = $centralVersions[$id] }
            if ($id) { [pscustomobject]@{ id = $id; version = $version } }
        }
        $packages = @($packages)

        # Legacy projects list their NuGet packages in packages.config next to the project file.
        $packagesConfig = Join-Path $projectFolder 'packages.config'
        if (Test-Path -LiteralPath $packagesConfig -PathType Leaf) {
            $configDocument = Read-XmlFile -FullPath $packagesConfig
            if ($configDocument) {
                foreach ($node in $configDocument.SelectNodes('/packages/package')) {
                    $id = $node.GetAttribute('id')
                    if ($id -and -not ($packages | Where-Object { $_.id -eq $id })) {
                        $packages += [pscustomobject]@{ id = $id; version = $(if ($node.GetAttribute('version')) { $node.GetAttribute('version') } else { $null }) }
                    }
                }
            }
        }

        # Projects this one references, as repository-relative paths, so a test project can be tied
        # to the plugin project it tests.
        $projectReferences = @(foreach ($node in $projectElement.SelectNodes('//*[local-name()="ProjectReference"]')) {
            $include = $node.GetAttribute('Include')
            if (-not $include) { continue }
            try {
                $referenced = [System.IO.Path]::GetFullPath((Join-Path $projectFolder ($include -replace '\\', [System.IO.Path]::DirectorySeparatorChar)))
                if ($referenced.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $referenced.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
                }
            }
            catch { }
        })
        $assemblyReferences = @(foreach ($node in $projectElement.SelectNodes('//*[local-name()="Reference"]')) { $node.GetAttribute('Include') })

        $frameworks = @()
        if ($properties.ContainsKey('TargetFramework') -and $properties['TargetFramework']) {
            $frameworks += $properties['TargetFramework']
        }
        if ($properties.ContainsKey('TargetFrameworks') -and $properties['TargetFrameworks']) {
            $frameworks += ($properties['TargetFrameworks'] -split ';' | Where-Object { $_ })
        }
        if (-not $frameworks -and $properties.ContainsKey('TargetFrameworkVersion')) {
            # Legacy csproj: v4.6.2 -> net462
            $frameworks += ('net' + ($properties['TargetFrameworkVersion'] -replace '^v', '' -replace '\.', ''))
        }

        $packageIds = @($packages | ForEach-Object { $_.id })
        $isTest =
            $relative -match '(?i)(\.tests?|\.unittests?)\.csproj$' -or
            $relative -match '(?i)(^|/)tests?/' -or
            ($packageIds | Where-Object { $_ -match '(?i)^(xunit|nunit|mstest\.testframework|microsoft\.net\.test\.sdk)' })

        # A plugin or custom API implements IPlugin, so it references the Dataverse SDK: as a
        # Microsoft.CrmSdk package, or as Microsoft.Xrm.Sdk in a legacy <Reference>. XrmTooling
        # alone is a client that connects from outside, and an executable is never loaded by
        # Dataverse, so neither counts as plugin code.
        $referencesSdk =
            [bool]($packageIds | Where-Object { $_ -match '(?i)^microsoft\.crmsdk\.(coreassemblies|workflow)' }) -or
            [bool]($assemblyReferences | Where-Object { $_ -match '(?i)^microsoft\.xrm\.sdk(\.workflow)?(,|$)' })
        $isExecutable = $properties.ContainsKey('OutputType') -and $properties['OutputType'] -match '(?i)^(exe|winexe)$'
        $inPluginFolder = $relative -match '(?i)(^|/)(plugins?|customapis?)(/|$)'

        $role = 'other'
        if ($isTest) { $role = 'test' }
        elseif ($isExecutable) { $role = 'other' }
        elseif ($referencesSdk -or $inPluginFolder) { $role = 'dataverse' }

        # SignAssembly decides; a key file alone signs nothing when SignAssembly is explicitly false.
        $signs = $false
        if ($properties.ContainsKey('SignAssembly') -and $properties['SignAssembly']) {
            $signs = $properties['SignAssembly'] -match '(?i)^true$'
        }
        elseif ($properties.ContainsKey('AssemblyOriginatorKeyFile') -and $properties['AssemblyOriginatorKeyFile']) {
            $signs = $true
        }

        [pscustomobject]@{
            path              = $relative
            role              = $role
            sdkStyle          = $sdkStyle
            targetFrameworks  = @($frameworks | Select-Object -Unique)
            rootNamespace     = $(if ($properties.ContainsKey('RootNamespace')) { $properties['RootNamespace'] } else { $null })
            assemblyName      = $(if ($properties.ContainsKey('AssemblyName')) { $properties['AssemblyName'] } else { $null })
            signAssembly      = [bool]$signs
            # Whether this project touches the Dataverse SDK or FakeXrmEasy, or sits in a plugin
            # folder: a test project with none of these does not test plugins.
            dataverseSignals  = $referencesSdk -or $inPluginFolder -or [bool]($packageIds | Where-Object { $_ -match '(?i)^FakeXrmEasy' })
            projectReferences = $projectReferences
            packages          = $packages
            readError         = $null
        }
    }
}

function Get-PackageJsonFacts {
    param([string]$Root, [string[]]$PackageFiles)

    foreach ($relative in $PackageFiles) {
        try {
            $json = [System.IO.File]::ReadAllText((Join-Path $Root $relative)) | ConvertFrom-Json
        }
        catch {
            [pscustomobject]@{ path = $relative; readError = 'package.json could not be parsed.' }
            continue
        }

        $dependencies = [ordered]@{}
        foreach ($section in @('dependencies', 'devDependencies', 'peerDependencies')) {
            if ($json.PSObject.Properties.Name -contains $section -and $json.$section) {
                foreach ($property in $json.$section.PSObject.Properties) {
                    $dependencies[$property.Name] = [string]$property.Value
                }
            }
        }

        [pscustomobject]@{
            path         = $relative
            name         = $json.name
            version      = $json.version
            private      = $json.private
            scripts      = $(if ($json.scripts) { @($json.scripts.PSObject.Properties.Name) } else { @() })
            dependencies = $dependencies
            readError    = $null
        }
    }
}

function Get-PcfFacts {
    param([string]$Root, [string[]]$ManifestFiles)

    foreach ($relative in $ManifestFiles) {
        $document = Read-XmlFile -FullPath (Join-Path $Root $relative)
        if (-not $document) {
            [pscustomobject]@{ manifest = $relative; readError = 'ControlManifest could not be parsed.' }
            continue
        }

        $control = $document.SelectSingleNode('/manifest/control')
        if (-not $control) {
            [pscustomobject]@{ manifest = $relative; readError = 'No control element.' }
            continue
        }

        $libraries = foreach ($node in $document.SelectNodes('/manifest/control/resources/platform-library')) {
            [pscustomobject]@{ name = $node.GetAttribute('name'); version = $node.GetAttribute('version') }
        }

        [pscustomobject]@{
            manifest         = $relative
            namespace        = $control.GetAttribute('namespace')
            constructor      = $control.GetAttribute('constructor')
            version          = $control.GetAttribute('version')
            controlType      = $control.GetAttribute('control-type')
            platformLibraries = @($libraries)
            readError        = $null
        }
    }
}

# --------------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path)) {
    Stop-WithError "Path '$Path' does not exist."
}
$Path = (Resolve-Path -LiteralPath $Path).Path
# C:\repo\ and C:\repo are the same folder; keep the form without the separator, except at a root.
$trimmedPath = $Path.TrimEnd('\', '/')
if ($trimmedPath -and $trimmedPath -notmatch '^[A-Za-z]:$') { $Path = $trimmedPath }

$skillRoot = Split-Path -Parent $PSScriptRoot
$templatesRoot = Join-Path $skillRoot 'templates'
$baselinePath = Join-Path $PSScriptRoot 'standards-baseline.json'

$notes = New-Object System.Collections.Generic.List[string]

try {

# Presence only: which tools exist is the setup-tools skill's report, not this one's.
$tooling = [ordered]@{
    git = [ordered]@{ present = (Resolve-Tool -Name 'git').Present }
    pac = [ordered]@{ present = (Resolve-Tool -Name 'pac').Present }
}

# ---- repository ---------------------------------------------------------------------------

$inventory = Get-RepoInventory -Root $Path -Limit $MaxFiles
if ($inventory.Truncated) {
    $notes.Add("The file walk stopped at $MaxFiles files; counts below are lower bounds.") | Out-Null
}

$files = $inventory.Files

# The harness is exactly what templates/ holds, so ask templates/ rather than hardcoding a list
# that drifts the next time a standards file is added.
$harnessFiles = @()
if (Test-Path -LiteralPath $templatesRoot) {
    $templatesRootFull = (Resolve-Path -LiteralPath $templatesRoot).Path
    $harnessFiles = @(Get-ChildItem -LiteralPath $templatesRootFull -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($templatesRootFull.Length).TrimStart('\', '/') -replace '\\', '/' } |
        # Build output an IDE leaves inside templates/ is never scaffolded: same filter as scaffold.ps1.
        Where-Object { $_ -notmatch '(^|/)(bin|obj|node_modules)/' })
}
else {
    $notes.Add("templates/ was not found at $templatesRoot; the plugin installation looks incomplete.") | Out-Null
}

# A template path can carry a token ({{project_name}}.Common), and the values are not known yet: a
# scaffolded Northwind.Common satisfies it. Each token matches one path segment's worth of name.
$present = New-Object System.Collections.Generic.List[string]
$missing = New-Object System.Collections.Generic.List[string]
foreach ($harnessFile in $harnessFiles) {
    $pattern = '^' + ([regex]::Escape($harnessFile) -replace '\\\{\\\{[a-z_]+}}', '[A-Za-z_][A-Za-z0-9_]*') + '$'
    $found = @($files | Where-Object { $_ -cmatch $pattern })
    if ($found.Count -gt 0) { $found | ForEach-Object { $present.Add($_) } }
    else { $missing.Add($harnessFile) }
}
$present = @($present)
$missing = @($missing)

# The three files the harness cannot merge into silently. .gitignore is excluded on purpose: an
# existing .gitignore is a collision to resolve, not evidence that the harness is installed.
$harnessMarkers = @('CLAUDE.md', 'docs/agents/development-standards.md')
$markersPresent = @($harnessMarkers | Where-Object { $files -contains $_ })

$solutionXmlFiles = Select-Files -Files $files -Pattern '(?i)(^|/)Other/Solution\.xml$' -Limit 50
$projectFiles = Select-Files -Files $files -Pattern '(?i)\.csproj$' -Limit 100
$packageJsonFiles = Select-Files -Files $files -Pattern '(?i)(^|/)package\.json$' -Limit 50
$pcfManifestFiles = Select-Files -Files $files -Pattern '(?i)(^|/)ControlManifest\.Input\.xml$' -Limit 50
$esprojFiles = Select-Files -Files $files -Pattern '(?i)\.esproj$' -Limit 50

$solutions = @(Get-SolutionFacts -Root $Path -SolutionXmlFiles $solutionXmlFiles)
$projects = @(Get-ProjectFacts -Root $Path -ProjectFiles $projectFiles)
$packages = @(Get-PackageJsonFacts -Root $Path -PackageFiles $packageJsonFiles)
$pcfControls = @(Get-PcfFacts -Root $Path -ManifestFiles $pcfManifestFiles)

$allNodeDependencies = @{}
foreach ($package in $packages) {
    if ($package.dependencies) {
        foreach ($key in $package.dependencies.Keys) {
            if (-not $allNodeDependencies.ContainsKey($key)) { $allNodeDependencies[$key] = $package.dependencies[$key] }
        }
    }
}

$codeArtifacts = @($files | Where-Object {
    $_ -match '(?i)\.(cs|csproj|sln|js|mjs|cjs|ts|tsx|jsx)$' -or
    $_ -match '(?i)(^|/)(package\.json|Solution\.xml|ControlManifest\.Input\.xml)$'
})

$classification = if ($markersPresent.Count -eq 0 -and $codeArtifacts.Count -eq 0) { 'greenfield' } else { 'existing' }

$git = [ordered]@{
    isRepository = $false
    branch       = $null
    commitCount  = $null
    remoteUrl    = $null
    isDirty      = $null
}
if ($tooling.git.present) {
    # --no-optional-locks: git status otherwise refreshes the stat cache and rewrites .git/index,
    # and discovery must not write to the repository it inspects.
    $insideRun = Invoke-Tool -Name 'git' -Arguments @('--no-optional-locks', '-C', $Path, 'rev-parse', '--is-inside-work-tree') -Timeout 20
    if ($insideRun.Ran -and $insideRun.ExitCode -eq 0 -and $insideRun.Stdout.Trim() -eq 'true') {
        $git['isRepository'] = $true

        $branchRun = Invoke-Tool -Name 'git' -Arguments @('--no-optional-locks', '-C', $Path, 'rev-parse', '--abbrev-ref', 'HEAD') -Timeout 20
        if ($branchRun.ExitCode -eq 0) { $git['branch'] = $branchRun.Stdout.Trim() }

        $countRun = Invoke-Tool -Name 'git' -Arguments @('--no-optional-locks', '-C', $Path, 'rev-list', '--count', 'HEAD') -Timeout 20
        if ($countRun.ExitCode -eq 0) { $git['commitCount'] = [int]$countRun.Stdout.Trim() } else { $git['commitCount'] = 0 }

        $remoteRun = Invoke-Tool -Name 'git' -Arguments @('--no-optional-locks', '-C', $Path, 'remote', 'get-url', 'origin') -Timeout 20
        if ($remoteRun.ExitCode -eq 0) { $git['remoteUrl'] = $remoteRun.Stdout.Trim() }

        $statusRun = Invoke-Tool -Name 'git' -Arguments @('--no-optional-locks', '-C', $Path, 'status', '--porcelain') -Timeout 30
        if ($statusRun.ExitCode -eq 0) { $git['isDirty'] = [bool]$statusRun.Stdout.Trim() }
    }
}

$repository = [ordered]@{
    path           = $Path
    classification = $classification
    fileCount      = $files.Count
    walkTruncated  = $inventory.Truncated
    prunedFolders  = @($inventory.Pruned | Sort-Object)
    git            = $git
    harness        = [ordered]@{
        installed    = $markersPresent.Count -gt 0
        markers      = $markersPresent
        presentFiles = $present
        missingFiles = $missing
    }
    agentDocs      = [ordered]@{
        claudeMd        = $files -contains 'CLAUDE.md'
        agentsMd        = $files -contains 'AGENTS.md'
        copilotMd       = @($files | Where-Object { $_ -match '(?i)^\.github/copilot-instructions\.md$' }).Count -gt 0
        cursorRules     = @($files | Where-Object { $_ -match '(?i)^\.cursor' }).Count -gt 0
        claudeMdFiles   = Select-Files -Files $files -Pattern '(?i)(^|/)CLAUDE\.md$' -Limit 20
        docsAgents      = Select-Files -Files $files -Pattern '(?i)^docs/agents/' -Limit 30
        docsDevelopment = Select-Files -Files $files -Pattern '(?i)^docs/development/' -Limit 30
        adrs            = Select-Files -Files $files -Pattern '(?i)^docs/adr/' -Limit 50
    }
    layout         = [ordered]@{
        expected = [ordered]@{}
        actual   = [ordered]@{
            solutionFolders   = @($solutions | ForEach-Object { $_.folder })
            pluginFolders     = @($inventory.Directories | Where-Object { $_ -match '(?i)(^|/)plugins?$' } | Select-Object -First 20)
            customApiFolders  = @($inventory.Directories | Where-Object { $_ -match '(?i)(^|/)customapis?$' } | Select-Object -First 20)
            webResourceFolders = @($inventory.Directories | Where-Object { $_ -match '(?i)(^|/)webresources?$' } | Select-Object -First 20)
            testFolders       = @($inventory.Directories | Where-Object { $_ -match '(?i)^tests?(/|$)' } | Select-Object -First 20)
        }
    }
    pipelines      = [ordered]@{
        githubWorkflows = Select-Files -Files $files -Pattern '(?i)^\.github/workflows/.+\.(yml|yaml)$' -Limit 30
        azurePipelines  = Select-Files -Files $files -Pattern '(?i)(^|/)azure-pipelines.*\.(yml|yaml)$' -Limit 30
    }
    counts         = [ordered]@{
        csharp        = @($files | Where-Object { $_ -match '(?i)\.cs$' }).Count
        javascript    = @($files | Where-Object { $_ -match '(?i)\.(js|mjs|cjs)$' }).Count
        typescript    = @($files | Where-Object { $_ -match '(?i)\.(ts|tsx)$' }).Count
        codeArtifacts = $codeArtifacts.Count
    }
}

foreach ($expected in @('src/PowerPlatform/Plugins', 'src/PowerPlatform/CustomAPIs', 'src/PowerPlatform/WebResources', 'docs/adr')) {
    $repository.layout.expected[$expected] = ($inventory.Directories -contains $expected)
}

$dotnet = [ordered]@{
    solutionFiles = Select-Files -Files $files -Pattern '(?i)\.slnx?$' -Limit 20
    projects      = $projects
    projectCount  = $projects.Count
    esprojFiles   = $esprojFiles
}

$node = [ordered]@{
    packages       = $packages
    eslintFlat     = Select-Files -Files $files -Pattern '(?i)(^|/)eslint\.config\.(js|mjs|cjs|ts)$' -Limit 20
    eslintLegacy   = Select-Files -Files $files -Pattern '(?i)(^|/)\.eslintrc(\..+)?$' -Limit 20
    tsconfigs      = Select-Files -Files $files -Pattern '(?i)(^|/)tsconfig.*\.json$' -Limit 20
    vitestConfigs  = Select-Files -Files $files -Pattern '(?i)(^|/)vitest\.config\.(js|mjs|cjs|ts)$' -Limit 20
    jestConfigs    = Select-Files -Files $files -Pattern '(?i)(^|/)jest\.config\.(js|mjs|cjs|ts|json)$' -Limit 20
}


. (Join-Path $PSScriptRoot '_environment.ps1')

# ---- deviations from the shipped standards -------------------------------------------------

$baseline = $null
if (Test-Path -LiteralPath $baselinePath) {
    try { $baseline = [System.IO.File]::ReadAllText($baselinePath) | ConvertFrom-Json }
    catch { $notes.Add("standards-baseline.json could not be parsed: $($_.Exception.Message)") | Out-Null }
}
else {
    $notes.Add("standards-baseline.json was not found at $baselinePath; no deviation check ran.") | Out-Null
}

function Get-NodeDependency {
    param([string]$Name)

    if ($allNodeDependencies.ContainsKey($Name)) { return $allNodeDependencies[$Name] }
    return $null
}

function Get-PackageVersions {
    param([string]$Id, $Projects = $projects)

    $found = @()
    foreach ($project in @($Projects)) {
        foreach ($package in @($project.packages)) {
            if ($package.id -and $package.id -eq $Id) {
                $found += [pscustomobject]@{ version = $package.version; project = $project.path }
            }
        }
    }
    return $found
}

function New-Assessment {
    param(
        $Assertion,
        [string]$Status,
        $Detected,
        [string[]]$Evidence = @(),
        [string]$Detail
    )

    return [ordered]@{
        id            = $Assertion.id
        kind          = $Assertion.kind
        topic         = $Assertion.topic
        standard      = $Assertion.standard
        standardLabel = $Assertion.standardLabel
        targetFile    = $Assertion.targetFile
        status        = $Status
        detected      = $Detected
        detail        = $Detail
        evidence      = @($Evidence | Select-Object -First 10)
        guidance      = $Assertion.guidance
    }
}

$assessments = @()
$staleBaseline = @()

function Test-AllVersionsAre {
    param($Versions, [string]$Expected)

    # A version that could not be read is never a match: it is reported as unknown instead.
    return (@($Versions | Where-Object { $_ -ne $Expected }).Count -eq 0)
}

if ($baseline) {
    # The plugins.* standards govern Dataverse plugin code only. A console tool, an Azure Function
    # or any other C# project in the same repository follows its own rules and is never judged here.
    $pluginProjects = @($projects | Where-Object { $_.role -eq 'dataverse' })
    $otherCSharpProjects = @($projects | Where-Object { $_.role -eq 'other' })
    $pluginProjectPaths = @($pluginProjects | ForEach-Object { $_.path })
    # Plugin tests: a test project that touches the Dataverse SDK or FakeXrmEasy, sits in a plugin
    # folder, or references a plugin project.
    $testProjects = @($projects | Where-Object {
        $_.role -eq 'test' -and (
            $_.dataverseSignals -or
            @($_.projectReferences | Where-Object { $pluginProjectPaths -contains $_ }).Count -gt 0
        )
    })
    $otherTestProjects = @($projects | Where-Object { $_.role -eq 'test' -and $testProjects -notcontains $_ })

    $noPluginDetail = 'No Dataverse plugin project in the repository.'
    if ($otherCSharpProjects.Count -gt 0) {
        $noPluginDetail = 'C# projects exist, but none references the Dataverse SDK or sits in a plugins/ or customapis/ folder, so none is plugin code. Confirm with the user if one of them is.'
    }
    $noPluginTestDetail = 'No plugin test project in the repository.'
    if ($otherTestProjects.Count -gt 0) {
        $noPluginTestDetail = 'Test projects exist, but none references a plugin project, FakeXrmEasy or the Dataverse SDK, so none tests plugins.'
    }

    foreach ($assertion in $baseline.assertions) {
        # The baseline is only trustworthy while the text it quotes is still in the template it
        # points at. Check that before using the assertion to judge somebody's repository.
        if ($assertion.assertedIn -and $assertion.assertedText) {
            $assertedFile = Join-Path $skillRoot ($assertion.assertedIn -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -LiteralPath $assertedFile) {
                $content = [System.IO.File]::ReadAllText($assertedFile)
                if (-not $content.Contains($assertion.assertedText)) {
                    $staleBaseline += [ordered]@{
                        id       = $assertion.id
                        file     = $assertion.assertedIn
                        expected = $assertion.assertedText
                        detail   = 'The baseline quotes text that is no longer in that file. Update scripts/standards-baseline.json.'
                    }
                }
            }
            else {
                $staleBaseline += [ordered]@{
                    id       = $assertion.id
                    file     = $assertion.assertedIn
                    expected = $assertion.assertedText
                    detail   = 'The file the baseline points at does not exist.'
                }
            }
        }

        switch ($assertion.id) {

            'plugins.targetFramework' {
                $frameworks = @($pluginProjects | ForEach-Object { $_.targetFrameworks } | Where-Object { $_ } | Select-Object -Unique)
                if (-not $pluginProjects) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail $noPluginDetail -Evidence @($otherCSharpProjects | ForEach-Object { $_.path }) }
                elseif (-not $frameworks) { $assessments += New-Assessment -Assertion $assertion -Status 'unknown' -Detected $null -Detail 'Plugin projects exist but declare no target framework this script could read.' -Evidence @($pluginProjects | ForEach-Object { $_.path }) }
                else {
                    $offenders = @($pluginProjects | Where-Object { @($_.targetFrameworks) -notcontains 'net462' })
                    $status = if ($offenders.Count -eq 0) { 'match' } else { 'deviates' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected $frameworks -Evidence @($offenders | ForEach-Object { "$($_.path) -> $(@($_.targetFrameworks) -join ', ')" })
                }
            }

            'plugins.sdkStyle' {
                if (-not $pluginProjects) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail $noPluginDetail -Evidence @($otherCSharpProjects | ForEach-Object { $_.path }) }
                else {
                    $legacy = @($pluginProjects | Where-Object { -not $_.sdkStyle })
                    $status = if ($legacy.Count -eq 0) { 'match' } else { 'deviates' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected $(if ($legacy.Count -eq 0) { 'sdk-style' } else { 'legacy csproj' }) -Evidence @($legacy | ForEach-Object { $_.path })
                }
            }

            'plugins.strongNaming' {
                if (-not $pluginProjects) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail $noPluginDetail -Evidence @($otherCSharpProjects | ForEach-Object { $_.path }) }
                else {
                    # The project files decide. A key file lying in the repository is evidence worth
                    # showing, but signs nothing unless a project uses it.
                    $signed = @($pluginProjects | Where-Object { $_.signAssembly })
                    # Select-Files already returns an array; wrapping it in @() would turn an empty
                    # result into a one-element array and report key files that do not exist.
                    $snkFiles = Select-Files -Files $files -Pattern '(?i)\.snk$' -Limit 10
                    $status = if ($signed.Count -eq 0) { 'match' } else { 'deviates' }
                    $detail = $null
                    if ($status -eq 'match' -and $snkFiles.Count -gt 0) { $detail = 'Key files exist in the repository, but no plugin project signs with one.' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected $(if ($status -eq 'match') { 'unsigned' } else { 'strong-named' }) -Detail $detail -Evidence (@($signed | ForEach-Object { $_.path }) + $snkFiles)
                }
            }

            'plugins.test.xunit' {
                $found = Get-PackageVersions -Id 'xunit' -Projects $testProjects
                $otherRunners = @()
                foreach ($runner in @('nunit', 'MSTest.TestFramework', 'xunit.v3')) {
                    $otherRunners += Get-PackageVersions -Id $runner -Projects $testProjects | ForEach-Object { "$runner $($_.version) ($($_.project))" }
                }
                if (-not $testProjects) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail $noPluginTestDetail -Evidence @($otherTestProjects | ForEach-Object { $_.path }) }
                elseif ($otherRunners.Count -gt 0 -and $found.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected $otherRunners -Detail 'The repository uses a different test runner.' -Evidence @($testProjects | ForEach-Object { $_.path }) }
                elseif ($found.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'unknown' -Detected $null -Detail 'Test projects exist but reference no runner this script recognises.' -Evidence @($testProjects | ForEach-Object { $_.path }) }
                else {
                    $versions = @($found | ForEach-Object { $_.version } | Select-Object -Unique)
                    $unresolved = @($found | Where-Object { -not $_.version })
                    if ($unresolved.Count -gt 0) { $status = 'unknown'; $detail = 'xunit is referenced without a version this script could resolve (no Version, VersionOverride or Directory.Packages.props entry).' }
                    else { $status = if (Test-AllVersionsAre -Versions $versions -Expected '2.9.3') { 'match' } else { 'deviates' }; $detail = $null }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected @($versions | Where-Object { $_ }) -Detail $detail -Evidence @($found | ForEach-Object { "$($_.project) -> xunit $(if ($_.version) { $_.version } else { '(version unresolved)' })" })
                }
            }

            'plugins.test.fakeXrmEasyPlugins' {
                $found = @()
                foreach ($project in $testProjects) {
                    foreach ($package in @($project.packages)) {
                        if ($package.id -match '(?i)^FakeXrmEasy') { $found += [pscustomobject]@{ id = $package.id; version = $package.version; project = $project.path } }
                    }
                }
                if (-not $testProjects) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail $noPluginTestDetail -Evidence @($otherTestProjects | ForEach-Object { $_.path }) }
                elseif ($found.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected $null -Detail 'No FakeXrmEasy package is referenced, so plugin tests either do not exist or use another approach.' -Evidence @($testProjects | ForEach-Object { $_.path }) }
                else {
                    $pluginPackage = @($found | Where-Object { $_.id -match '(?i)^FakeXrmEasy\.Plugins\.v9$' })
                    $detail = $null
                    if ($pluginPackage.Count -eq 0) { $status = 'deviates' }
                    elseif (@($pluginPackage | Where-Object { -not $_.version }).Count -gt 0) { $status = 'unknown'; $detail = 'FakeXrmEasy.Plugins.v9 is referenced without a version this script could resolve (no Version, VersionOverride or Directory.Packages.props entry).' }
                    elseif (Test-AllVersionsAre -Versions @($pluginPackage | ForEach-Object { $_.version }) -Expected '2.9.4') { $status = 'match' }
                    else { $status = 'deviates' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected @($found | ForEach-Object { "$($_.id) $(if ($_.version) { $_.version } else { '(version unresolved)' })" } | Select-Object -Unique) -Detail $detail -Evidence @($found | ForEach-Object { "$($_.project) -> $($_.id) $(if ($_.version) { $_.version } else { '(version unresolved)' })" })
                }
            }

            'plugins.test.fakeXrmEasyMessages' {
                $found = Get-PackageVersions -Id 'FakeXrmEasy.Messages.v9' -Projects $testProjects
                if ($found.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'The package is optional and is not referenced.' }
                else {
                    $versions = @($found | ForEach-Object { $_.version } | Select-Object -Unique)
                    $detail = $null
                    if (@($found | Where-Object { -not $_.version }).Count -gt 0) { $status = 'unknown'; $detail = 'FakeXrmEasy.Messages.v9 is referenced without a version this script could resolve (no Version, VersionOverride or Directory.Packages.props entry).' }
                    elseif (Test-AllVersionsAre -Versions $versions -Expected '2.9.4') { $status = 'match' }
                    else { $status = 'deviates' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected @($versions | Where-Object { $_ }) -Detail $detail -Evidence @($found | ForEach-Object { "$($_.project) -> $(if ($_.version) { $_.version } else { '(version unresolved)' })" })
                }
            }

            'pcf.controlType' {
                if (-not $pcfControls) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No PCF controls in the repository.' }
                else {
                    $types = @($pcfControls | ForEach-Object { if ($_.controlType) { $_.controlType } else { 'standard' } } | Select-Object -Unique)
                    $status = if (@($types | Where-Object { $_ -ne 'virtual' }).Count -eq 0) { 'match' } else { 'deviates' }
                    $assessments += New-Assessment -Assertion $assertion -Status $status -Detected $types -Evidence @($pcfControls | ForEach-Object { "$($_.manifest) -> control-type=$(if ($_.controlType) { $_.controlType } else { 'standard (default)' })" })
                }
            }

            { $_ -in @('pcf.platformLibrary.react', 'pcf.platformLibrary.fluent') } {
                if (-not $pcfControls) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No PCF controls in the repository.' }
                else {
                    $libraryName = $assertion.platformLibrary
                    $found = @()
                    foreach ($control in $pcfControls) {
                        foreach ($library in @($control.platformLibraries)) {
                            if ($library.name -and $library.name -match "(?i)^$libraryName") {
                                $found += [pscustomobject]@{ version = $library.version; manifest = $control.manifest }
                            }
                        }
                    }
                    if ($found.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected $null -Detail "No $libraryName platform library is declared, so the control bundles its own copy." -Evidence @($pcfControls | ForEach-Object { $_.manifest }) }
                    else {
                        $versions = @($found | ForEach-Object { $_.version } | Select-Object -Unique)
                        $status = if (@($versions | Where-Object { $_ -ne $assertion.standard }).Count -eq 0) { 'match' } else { 'deviates' }
                        $assessments += New-Assessment -Assertion $assertion -Status $status -Detected $versions -Evidence @($found | ForEach-Object { "$($_.manifest) -> $libraryName $($_.version)" })
                    }
                }
            }

            { $_ -in @('pcf.test', 'javascript.test') } {
                $applies = if ($assertion.id -eq 'pcf.test') { [bool]$pcfControls } else { $repository.counts.javascript -gt 0 }
                if (-not $applies -or -not $packages) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No relevant JavaScript or PCF code with a package.json.' }
                else {
                    $vitest = Get-NodeDependency -Name 'vitest'
                    $jest = Get-NodeDependency -Name 'jest'
                    if ($vitest -and -not $jest) { $assessments += New-Assessment -Assertion $assertion -Status 'match' -Detected "vitest $vitest" -Evidence $node.vitestConfigs }
                    elseif ($jest) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected "jest $jest" -Detail 'The repository tests with Jest.' -Evidence (@($node.jestConfigs) + @($packages | ForEach-Object { $_.path })) }
                    else { $assessments += New-Assessment -Assertion $assertion -Status 'unknown' -Detected $null -Detail 'No JavaScript test runner is declared in any package.json.' -Evidence @($packages | ForEach-Object { $_.path }) }
                }
            }

            'javascript.lint' {
                if (-not $packages) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No package.json in the repository.' }
                else {
                    $eslint = Get-NodeDependency -Name 'eslint'
                    $flat = @($node.eslintFlat).Count -gt 0
                    $legacy = @($node.eslintLegacy).Count -gt 0
                    $major = if ($eslint) { [regex]::Match($eslint, '(\d+)').Groups[1].Value } else { $null }
                    if (-not $eslint) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected $null -Detail 'ESLint is not a dependency of any package.json.' -Evidence @($packages | ForEach-Object { $_.path }) }
                    elseif ($major -eq '10' -and $flat -and -not $legacy) { $assessments += New-Assessment -Assertion $assertion -Status 'match' -Detected "eslint $eslint (flat config)" -Evidence $node.eslintFlat }
                    else { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected "eslint $eslint$(if ($legacy) { ' (.eslintrc)' } elseif ($flat) { ' (flat config)' } else { ' (no config file found)' })" -Evidence (@($node.eslintLegacy) + @($node.eslintFlat)) }
                }
            }

            'javascript.language' {
                $webResourceFolders = @($repository.layout.actual.webResourceFolders)
                $typescriptInWebResources = @($files | Where-Object {
                    $_ -match '(?i)\.tsx?$' -and $_ -match '(?i)(^|/)webresources?/'
                })
                $bundlers = @('webpack', 'rollup', 'vite', 'esbuild', 'parcel') | Where-Object { Get-NodeDependency -Name $_ }

                if (-not $webResourceFolders -and $repository.counts.javascript -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No web resources in the repository.' }
                elseif ($typescriptInWebResources.Count -gt 0) { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected 'TypeScript web resources' -Detail 'Web resources are authored in TypeScript, so the committed file is not the deployed file.' -Evidence $typescriptInWebResources }
                elseif ($bundlers) { $assessments += New-Assessment -Assertion $assertion -Status 'unknown' -Detected "bundler present: $($bundlers -join ', ')" -Detail 'A bundler is a dependency. Confirm whether web resources go through it, or only PCF does.' -Evidence @($packages | ForEach-Object { $_.path }) }
                else { $assessments += New-Assessment -Assertion $assertion -Status 'match' -Detected 'plain JavaScript' -Evidence $webResourceFolders }
            }

            'webresources.buildProject' {
                $hasWebResources = @($repository.layout.actual.webResourceFolders).Count -gt 0 -or $repository.counts.javascript -gt 0
                if ($classification -eq 'greenfield' -or -not $hasWebResources) {
                    $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'No web resources in the repository, or the scaffold will create the project.'
                }
                else {
                    $webResourcesPackageJson = @($packages | Where-Object { $_.path -match '(?i)(^|/)webresources?/' })
                    if ($esprojFiles.Count -gt 0) {
                        $assessments += New-Assessment -Assertion $assertion -Status 'match' -Detected 'esproj build project present' -Evidence $esprojFiles
                    }
                    elseif ($webResourcesPackageJson.Count -gt 0) {
                        $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected 'package.json without an .esproj' -Detail 'Web resources have test/lint tooling but no SDK-style project file.' -Evidence @($webResourcesPackageJson | ForEach-Object { $_.path })
                    }
                    else {
                        $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected $null -Detail 'No WebResources build/test project exists yet.' -Evidence @($repository.layout.actual.webResourceFolders)
                    }
                }
            }

            'layout.folders' {
                $missingFolders = @($repository.layout.expected.Keys | Where-Object { -not $repository.layout.expected[$_] })
                $alternatives = @()
                foreach ($group in @(
                    @{ Expected = 'src/PowerPlatform/Plugins'; Found = $repository.layout.actual.pluginFolders },
                    @{ Expected = 'src/PowerPlatform/CustomAPIs'; Found = $repository.layout.actual.customApiFolders },
                    @{ Expected = 'src/PowerPlatform/WebResources'; Found = $repository.layout.actual.webResourceFolders }
                )) {
                    foreach ($found in @($group.Found)) {
                        if ($found -and $found -notlike "$($group.Expected)*") { $alternatives += "$found (the standard references $($group.Expected))" }
                    }
                }
                if ($classification -eq 'greenfield') { $assessments += New-Assessment -Assertion $assertion -Status 'not-applicable' -Detected $null -Detail 'Empty folder: the scaffold creates the layout.' }
                elseif ($alternatives.Count -eq 0 -and $missingFolders.Count -eq 0) { $assessments += New-Assessment -Assertion $assertion -Status 'match' -Detected 'the expected layout' }
                else { $assessments += New-Assessment -Assertion $assertion -Status 'deviates' -Detected @($alternatives | Select-Object -Unique) -Detail "Missing from the expected layout: $(@($missingFolders) -join ', ')" -Evidence @($alternatives | Select-Object -Unique) }
            }

            default {
                $assessments += New-Assessment -Assertion $assertion -Status 'unknown' -Detected $null -Detail 'No detection is implemented for this assertion.'
            }
        }
    }
}

# ---- proposed values -----------------------------------------------------------------------

function New-Proposal {
    param([string]$Value, [string]$Source, [string]$Confidence, [string[]]$Alternatives = @())

    return [ordered]@{
        value        = $Value
        source       = $Source
        confidence   = $Confidence
        alternatives = @($Alternatives | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 10)
    }
}

# Feature solutions are named <type>_<Name> after their branch. They are never the core solution,
# so they are left out of every core-solution guess below.
$featureSolutionPattern = '^(feature|fix|chore)_'
$committedCore = @($solutions | Where-Object { $_.managed -ne $true -and $_.uniqueName -and $_.uniqueName -notmatch $featureSolutionPattern })
$environmentCore = @($allUnmanagedSolutions | Where-Object { $_.uniqueName -notmatch $featureSolutionPattern -and $_.uniqueName -notin @('Default', 'Active') })
$featureSolutionsInEnvironment = @($allUnmanagedSolutions | Where-Object { $_.uniqueName -match $featureSolutionPattern } | ForEach-Object { $_.uniqueName })
$primarySolution = $committedCore | Select-Object -First 1
$resolved = $environment['resolvedPublisher']

# CoreSolution. Optional: 'none' is a valid answer, but only the user can give it.
$coreCandidates = @($environmentCore | Where-Object { $_.uniqueName -match '(?i)core' })
if ($primarySolution) {
    $coreProposal = New-Proposal -Value $primarySolution.uniqueName -Source "$($primarySolution.manifest) (committed solution manifest)" -Confidence 'high' -Alternatives @($committedCore | ForEach-Object { $_.uniqueName })
}
elseif ($resolved -and $resolved['solutionUniqueName']) {
    $coreProposal = New-Proposal -Value $resolved['solutionUniqueName'] -Source $resolved['source'] -Confidence 'high'
}
elseif ($coreCandidates.Count -eq 1) {
    $coreProposal = New-Proposal -Value $coreCandidates[0].uniqueName -Source 'pac solution list (the only unmanaged solution whose name contains Core)' -Confidence 'medium' -Alternatives @($environmentCore | ForEach-Object { $_.uniqueName })
}
elseif ($environmentCore.Count -gt 0) {
    $coreProposal = New-Proposal -Value $null -Source "pac solution list returned unmanaged solutions, none clearly the core one. Ask which one is the core solution, or 'none'." -Confidence 'none' -Alternatives @($environmentCore | ForEach-Object { $_.uniqueName })
}
else {
    $coreProposal = New-Proposal -Value $null -Source "No committed solution and no environment solution list. Ask for the core solution unique name, or 'none'." -Confidence 'none'
}

# Publisher unique name and prefix
$recommendationWarnings = New-Object System.Collections.Generic.List[string]
$publisherUniqueNameProposal = New-Proposal -Value $null -Source 'Not derivable: no committed solution manifest and no exported solution' -Confidence 'none'
$publisherPrefixProposal = New-Proposal -Value $null -Source 'Not derivable: no committed solution manifest and no exported solution' -Confidence 'none'

if ($primarySolution -and $primarySolution.publisherPrefix) {
    $publisherUniqueNameProposal = New-Proposal -Value $primarySolution.publisherUniqueName -Source "$($primarySolution.manifest) (committed solution manifest)" -Confidence 'high' -Alternatives @($solutions | ForEach-Object { $_.publisherUniqueName })
    $publisherPrefixProposal = New-Proposal -Value $primarySolution.publisherPrefix -Source "$($primarySolution.manifest) (committed solution manifest)" -Confidence 'high' -Alternatives @($solutions | ForEach-Object { $_.publisherPrefix })
}
elseif ($resolved -and $resolved['publisherPrefix']) {
    $publisherUniqueNameProposal = New-Proposal -Value $resolved['publisherUniqueName'] -Source $resolved['source'] -Confidence 'high'
    $publisherPrefixProposal = New-Proposal -Value $resolved['publisherPrefix'] -Source $resolved['source'] -Confidence 'high'
}
elseif ($environment['connected']) {
    $environmentPublishers = @($environment['publishers'])
    $customPublishers = @($environmentPublishers | Where-Object { -not $_['isDefault'] })
    $corePublisher = $null
    if ($coreProposal['value'] -and $script:solutionPublishers.ContainsKey($coreProposal['value'])) {
        $corePublisher = $script:solutionPublishers[$coreProposal['value']]
    }

    if ($PublisherPrefix) {
        # The user gave the prefix. The environment decides which publisher owns it.
        $owners = @($environmentPublishers | Where-Object { $_['prefix'] -eq $PublisherPrefix })
        $publisherPrefixProposal = New-Proposal -Value $PublisherPrefix -Source 'Given by the user' -Confidence 'high'
        if ($owners.Count -eq 1) {
            $publisherUniqueNameProposal = New-Proposal -Value $owners[0]['uniqueName'] -Source "The only publisher in the connected environment with prefix $PublisherPrefix (pac env fetch)" -Confidence 'high'
            if ($owners[0]['isDefault']) {
                $recommendationWarnings.Add("Prefix $PublisherPrefix belongs to the environment's default publisher ($($owners[0]['uniqueName'])). Projects should use their own publisher; confirm this is intended.") | Out-Null
            }
        }
        elseif ($owners.Count -gt 1) {
            $publisherUniqueNameProposal = New-Proposal -Value $null -Source "$($owners.Count) publishers in the connected environment share prefix $PublisherPrefix. Ask which one, from the alternatives." -Confidence 'none' -Alternatives @($owners | ForEach-Object { $_['uniqueName'] })
        }
        else {
            $publisherUniqueNameProposal = New-Proposal -Value $null -Source "No publisher in the connected environment has prefix $PublisherPrefix. It does not exist yet: ask for the unique name it will be created with, and confirm the prefix." -Confidence 'none' -Alternatives @($customPublishers | ForEach-Object { $_['uniqueName'] })
            $recommendationWarnings.Add("No publisher in the connected environment has prefix $PublisherPrefix. Existing custom publishers: $(@($customPublishers | ForEach-Object { "$($_['uniqueName']) ($($_['prefix']))" }) -join ', '). Confirm the prefix before anything is created with it: it cannot be changed later.") | Out-Null
        }
    }
    elseif ($corePublisher -and $corePublisher['publisherPrefix']) {
        $source = "Publisher of the core solution $($coreProposal['value']) in the connected environment (pac env fetch)"
        $publisherUniqueNameProposal = New-Proposal -Value $corePublisher['publisherUniqueName'] -Source $source -Confidence $coreProposal['confidence']
        $publisherPrefixProposal = New-Proposal -Value $corePublisher['publisherPrefix'] -Source $source -Confidence $coreProposal['confidence']
    }
    elseif ($customPublishers.Count -eq 1) {
        $source = 'The only custom publisher in the connected environment (pac env fetch)'
        $publisherUniqueNameProposal = New-Proposal -Value $customPublishers[0]['uniqueName'] -Source $source -Confidence 'medium'
        $publisherPrefixProposal = New-Proposal -Value $customPublishers[0]['prefix'] -Source $source -Confidence 'medium'
    }
    elseif ($customPublishers.Count -gt 1) {
        $source = "$($customPublishers.Count) custom publishers in the connected environment. Ask which one the project uses, from the alternatives."
        $publisherUniqueNameProposal = New-Proposal -Value $null -Source $source -Confidence 'none' -Alternatives @($customPublishers | ForEach-Object { $_['uniqueName'] })
        $publisherPrefixProposal = New-Proposal -Value $null -Source $source -Confidence 'none' -Alternatives @($customPublishers | ForEach-Object { $_['prefix'] })
    }
    else {
        $hint = 'The connected environment has no custom publisher (or it could not be read). Ask the user; re-run with -ResolvePublisherFromSolution <name> if a solution holds it.'
        $publisherUniqueNameProposal = New-Proposal -Value $null -Source $hint -Confidence 'none'
        $publisherPrefixProposal = New-Proposal -Value $null -Source $hint -Confidence 'none'
    }
}
elseif ($PublisherPrefix) {
    $publisherPrefixProposal = New-Proposal -Value $PublisherPrefix -Source 'Given by the user; not checked against an environment' -Confidence 'medium'
}

# Prefix evidence from existing component names: nwc_accountform.js, prefix_table, and so on.
$prefixCandidates = @{}
foreach ($file in @($files | Where-Object { $_ -match '(?i)(^|/)[a-z][a-z0-9]{1,7}_[a-z0-9]' })) {
    $leaf = [System.IO.Path]::GetFileName($file)
    $match = [regex]::Match($leaf, '^([a-z][a-z0-9]{1,7})_')
    if ($match.Success) {
        $candidate = $match.Groups[1].Value
        if ($candidate -in @('mscrm', 'msdyn', 'msdynce', 'test', 'adx')) { continue }
        if (-not $prefixCandidates.ContainsKey($candidate)) { $prefixCandidates[$candidate] = 0 }
        $prefixCandidates[$candidate] = $prefixCandidates[$candidate] + 1
    }
}
$prefixEvidence = @($prefixCandidates.Keys | Sort-Object { -$prefixCandidates[$_] } | Select-Object -First 5 |
    ForEach-Object { "$_ ($($prefixCandidates[$_]) file name(s))" })

if (-not $publisherPrefixProposal['value'] -and $prefixCandidates.Count -gt 0) {
    $best = @($prefixCandidates.Keys | Sort-Object { -$prefixCandidates[$_] })[0]
    $publisherPrefixProposal = New-Proposal -Value $best -Source "Inferred from component file names ($($prefixCandidates[$best]) match(es)). Confirm against the environment: a wrong prefix cannot be undone." -Confidence 'medium' -Alternatives $prefixEvidence
}

# The project name is also the root .NET namespace. The namespace the existing C# projects share is
# the best evidence for it, so it is worked out first and feeds the ProjectName proposal below.
$namespaceProposal = New-Proposal -Value $null -Source 'No C# project declares a namespace' -Confidence 'none'
# Plugin code carries the namespace the harness extends. Other C# projects (tools, functions) only
# speak for it when there is no plugin project at all.
$namespaceProjects = @($projects | Where-Object { $_.role -eq 'dataverse' })
if ($namespaceProjects.Count -eq 0) { $namespaceProjects = @($projects | Where-Object { $_.role -eq 'other' }) }
$declaredNamespaces = @($namespaceProjects | ForEach-Object {
    if ($_.rootNamespace) { $_.rootNamespace } elseif ($_.assemblyName) { $_.assemblyName } else { [System.IO.Path]::GetFileNameWithoutExtension($_.path) }
} | Where-Object { $_ } | Select-Object -Unique)

if ($declaredNamespaces.Count -gt 0) {
    # The shared root is the longest dotted prefix every project agrees on.
    $segments = @($declaredNamespaces | ForEach-Object { ,@($_ -split '\.') })
    $shared = @()
    for ($index = 0; ; $index++) {
        $current = $null
        $agree = $true
        foreach ($parts in $segments) {
            if ($index -ge $parts.Count) { $agree = $false; break }
            if ($null -eq $current) { $current = $parts[$index] }
            elseif ($parts[$index] -ne $current) { $agree = $false; break }
        }
        if (-not $agree -or $null -eq $current) { break }
        $shared += $current
    }
    $value = if ($shared.Count -gt 0) { $shared -join '.' } else { $declaredNamespaces[0] }
    $confidence = if ($shared.Count -gt 0) { 'high' } else { 'medium' }

    # With a single project the shared prefix is the whole namespace, which usually ends in the
    # layer it implements. The root namespace is what sits above that layer.
    $layerSegments = @('Plugins', 'Plugin', 'CustomAPIs', 'CustomApis', 'CustomApi', 'WebResources', 'Workflows', 'Tests', 'Common', 'Shared', 'Core')
    $trimmed = $value
    while (($trimmed -match '\.') -and ($layerSegments -contains ($trimmed -split '\.')[-1])) {
        $trimmed = ($trimmed -split '\.' | Select-Object -SkipLast 1) -join '.'
    }
    $alternatives = @($declaredNamespaces)
    if ($trimmed -ne $value) { $alternatives = @($value) + $alternatives }

    $namespaceProposal = New-Proposal -Value $trimmed -Source $(if ($trimmed -ne $value) {
        "Shared root namespace of the existing C# projects ($value), with the layer segment removed"
    } else {
        'Shared root namespace of the existing C# projects'
    }) -Confidence $confidence -Alternatives $alternatives
}

# ProjectName
$projectNameProposal = New-Proposal -Value $null -Source 'No evidence in the repository. Ask the user; never derive it from the folder name silently.' -Confidence 'none' -Alternatives @(
    [System.IO.Path]::GetFileName($Path)
)
$solutionFileName = @($dotnet.solutionFiles | Select-Object -First 1)
if ($namespaceProposal['value']) {
    $existingNamespace = $namespaceProposal['value']
    $firstSegment = ($existingNamespace -split '\.')[0]
    if ($existingNamespace -match '^[A-Za-z][A-Za-z0-9]*$') {
        $projectNameProposal = New-Proposal -Value $existingNamespace -Source "$($namespaceProposal['source']). The project name is also the root .NET namespace" -Confidence 'medium' -Alternatives @([System.IO.Path]::GetFileName($Path))
    }
    elseif ($firstSegment -match '^[A-Za-z][A-Za-z0-9]*$') {
        $projectNameProposal = New-Proposal -Value $firstSegment -Source "First segment of the existing root namespace ($existingNamespace)" -Confidence 'medium' -Alternatives @([System.IO.Path]::GetFileName($Path))
        # A project name has no dots, so a dotted namespace cannot be carried over as it is.
        $recommendationWarnings.Add("The existing C# projects use the root namespace $existingNamespace, but the harness uses the project name as the root namespace and a project name cannot contain dots. The generated docs will say $firstSegment.<Entity> and $firstSegment.Common: reconcile them to $existingNamespace after scaffolding.") | Out-Null
    }
}
elseif ($solutionFileName) {
    $candidate = [System.IO.Path]::GetFileNameWithoutExtension($solutionFileName)
    if ($candidate -match '^[A-Za-z][A-Za-z0-9]*$') {
        $projectNameProposal = New-Proposal -Value $candidate -Source "Name of $solutionFileName" -Confidence 'medium' -Alternatives @([System.IO.Path]::GetFileName($Path))
    }
}

# ProjectDescription
$descriptionProposal = New-Proposal -Value $null -Source 'Ask the user: one or two sentences on what the project delivers' -Confidence 'none'
$readme = @($files | Where-Object { $_ -match '(?i)^readme(\.md|\.txt)?$' } | Select-Object -First 1)
if ($readme) {
    try {
        $readmeLines = [System.IO.File]::ReadAllLines((Join-Path $Path $readme[0]))
        $paragraph = @($readmeLines | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*\[!\[' } | Select-Object -First 2)
        if ($paragraph) {
            $descriptionProposal = New-Proposal -Value (($paragraph -join ' ').Trim()) -Source "First paragraph of $($readme[0])" -Confidence 'medium'
        }
    }
    catch { $notes.Add("$($readme[0]) could not be read for ProjectDescription: $($_.Exception.Message)") | Out-Null }
}

$proposedValues = [ordered]@{
    ProjectName         = $projectNameProposal
    PublisherUniqueName = $publisherUniqueNameProposal
    PublisherPrefix     = $publisherPrefixProposal
    CoreSolution        = $coreProposal
    ProjectDescription  = $descriptionProposal
}

$missingValues = @($proposedValues.Keys | Where-Object { -not $proposedValues[$_]['value'] })

# ---- recommendation ------------------------------------------------------------------------

$deviating = @($assessments | Where-Object { $_.status -eq 'deviates' })

$recommendation = [ordered]@{
    mode              = if ($classification -eq 'greenfield') { 'initialise' } else { 'adopt' }
    scaffoldArguments = @()
    askUserFor        = $missingValues
    deviationCount    = $deviating.Count
    warnings          = @($recommendationWarnings)
}

if ($classification -eq 'greenfield') {
    if (@($present).Count -gt 0) {
        $recommendation['scaffoldArguments'] = @('-SkipExisting')
        $recommendation['warnings'] += "The folder is otherwise empty but already contains: $(@($present) -join ', '). Use -SkipExisting, or -Force to overwrite."
    }
}
else {
    $recommendation['scaffoldArguments'] = @('-SkipExisting')
    # Only a layout of the project's own suppresses the standard one. src/PowerPlatform/Plugins is the
    # standard layout itself: a repository the harness scaffolded must not be told to skip it.
    $ownPluginFolders = @($repository.layout.actual.pluginFolders | Where-Object { $_ -notlike 'src/PowerPlatform/*' })
    if (@($repository.layout.actual.solutionFolders).Count -gt 0 -or $ownPluginFolders.Count -gt 0) {
        $recommendation['scaffoldArguments'] += '-SkipLayout'
    }
    # The code projects under src/PowerPlatform/ (PowerPlatform.sln, the Common library, the WebResources
    # build project) introduce a target framework and a test runner (Vitest). Never write them
    # unprompted into an established project: offer them during reconciliation instead, from the
    # webresources.buildProject assessment above, and only add them if the user asks. A repository
    # that already has the harness's PowerPlatform.sln chose them already: -SkipExisting is enough.
    $hasHarnessCodeProjects = $files -contains 'src/PowerPlatform/PowerPlatform.sln'
    if ($recommendation['scaffoldArguments'] -notcontains '-SkipLayout' -and -not $hasHarnessCodeProjects) {
        $recommendation['scaffoldArguments'] += '-SkipCodeProjects'
        $recommendation['warnings'] += 'This is an existing project: the code projects under src/PowerPlatform/ (PowerPlatform.sln, the Common plugin library and the WebResources build project with Vitest/ESLint) are never added automatically. Report the webresources.buildProject assessment and add them only if the user asks.'
    }
    if ($repository.agentDocs.claudeMd) {
        $recommendation['warnings'] += 'CLAUDE.md already exists. The scaffold will skip it with -SkipExisting: merge the harness sections into the existing file rather than overwriting instructions the project already relies on.'
    }
    if (@($repository.harness.presentFiles).Count -gt 0 -and @($repository.harness.missingFiles).Count -gt 0) {
        $recommendation['warnings'] += 'The harness is partially installed. Only the missing files will be written; compare the present ones against the templates before assuming they are current.'
    }
}

if ($environment['treatAsProduction'] -and $environment['connected']) {
    $recommendation['warnings'] += "The connected environment ($($environment.org.friendlyName)) does not look like a DEV environment (name signal: $($environment.nameSignal)). The standards permit write operations in DEV only: confirm it is DEV before the agent writes anything."
}


# ---- output --------------------------------------------------------------------------------

$report = [ordered]@{
    schemaVersion  = 1
    generatedAt    = (Get-Date).ToString('o')
    skillRoot      = $skillRoot
    repository     = $repository
    dotnet         = $dotnet
    node           = $node
    solutions      = $solutions
    pcfControls    = $pcfControls
    environment    = $environment
    featureSolutionsInEnvironment = $featureSolutionsInEnvironment
    standards      = [ordered]@{
        baselineFound = [bool]$baseline
        assessments   = $assessments
        deviations    = @($deviating | ForEach-Object { $_.id })
        staleBaseline = $staleBaseline
    }
    prefixEvidence = $prefixEvidence
    proposedValues = $proposedValues
    recommendation = $recommendation
    notes          = @($notes)
}


$report | ConvertTo-Json -Depth 12

}
finally {
    if (Test-Path -LiteralPath $script:scratchRoot) {
        Remove-Item -LiteralPath $script:scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
