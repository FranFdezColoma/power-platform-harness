# Shared by the harness skills' scripts. Every skill carries an identical copy next to its own
# scripts, so a skill installed on its own (npx skills, a loose folder) still finds it beside it.
# Edit one copy, then copy it over the others: tests/Test-Repository.ps1 fails while they differ.
#
# Dot-source it from a script that defines $TimeoutSeconds:  . (Join-Path $PSScriptRoot '_common.ps1')

function Stop-WithError {
    param([string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

# --------------------------------------------------------------------------------------------
# External commands
# --------------------------------------------------------------------------------------------

$script:resolvedTools = @{}
$script:scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pph-discover-$([guid]::NewGuid())"

function Resolve-Tool {
    param([string]$Name)

    if ($script:resolvedTools.ContainsKey($Name)) { return $script:resolvedTools[$Name] }

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    $info = [pscustomobject]@{
        Name       = $Name
        Present    = $false
        Source     = $null
        Kind       = $null
        Executable = $null
        Prefix     = @()
    }

    if ($command) {
        $info.Present = $true
        $info.Source = $command.Source
        $info.Kind = [string]$command.CommandType

        if ($command.CommandType -eq 'Application') {
            $extension = [System.IO.Path]::GetExtension($command.Source)
            if ($extension -in @('.cmd', '.bat')) {
                # CreateProcess cannot launch a batch file directly, and redirecting output forces
                # UseShellExecute = false. npm-installed pac lands here.
                $info.Executable = "$env:SystemRoot\System32\cmd.exe"
                $info.Prefix = @('/c', $command.Source)
            }
            else {
                $info.Executable = $command.Source
            }
        }
        elseif ($command.CommandType -eq 'ExternalScript' -and [System.IO.Path]::GetExtension($command.Source) -eq '.ps1' -and
            (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($command.Source, '.cmd')))) {
            # npm installs a .cmd shim next to every .ps1 one. Running the .cmd saves starting a
            # second PowerShell host per probe, which costs more than the probe itself.
            $info.Executable = "$env:SystemRoot\System32\cmd.exe"
            $info.Prefix = @('/c', [System.IO.Path]::ChangeExtension($command.Source, '.cmd'))
        }
        elseif ($command.CommandType -eq 'ExternalScript' -and [System.IO.Path]::GetExtension($command.Source) -eq '.ps1') {
            # npm installs a .ps1 shim alongside the .cmd/extension-less ones on Windows, and
            # Get-Command resolves the .ps1 first. Without this, every npm-installed CLI whose
            # first match is the .ps1 shim (claude, playwright-cli) would be reported as present
            # but never actually probed.
            $shellCommand = Get-Command -Name pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $shellCommand) { $shellCommand = Get-Command -Name powershell -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if ($shellCommand) {
                $info.Executable = $shellCommand.Source
                $info.Prefix = @('-NoProfile', '-NonInteractive', '-File', $command.Source)
            }
        }
        # Anything else (a function, an alias, or a .ps1 shim when no PowerShell host could be
        # found to run it) is reported as present but is never executed: presence is all this
        # script needs from those.
    }

    $script:resolvedTools[$Name] = $info
    return $info
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)

    if (-not $Arguments) { return '' }

    # CommandLineToArgvW rules: backslashes are literal unless they precede a quote, so the run of
    # backslashes before an embedded quote, and before the closing quote, has to be doubled.
    # Otherwise "C:\My Repo\" ends in \" and the closing quote is read as part of the argument.
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -eq '') { '""' }
        elseif ($argument -match '[\s"]') {
            $escaped = [regex]::Replace($argument, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
            $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
            '"' + $escaped + '"'
        }
        else { $argument }
    }

    return ($quoted -join ' ')
}

# Starts a command and returns at once, so independent probes can run side by side: launched one
# after another, a dozen cold process starts (pac, dotnet, two PowerShell hosts) add up to seconds.
# Wait-Tool collects the result. Invoke-Tool does both, for calls that need the answer right away.
function Start-Tool {
    param(
        [string]$Name,
        [string[]]$Arguments = @(),
        [int]$Timeout = 0
    )

    if ($Timeout -le 0) { $Timeout = $TimeoutSeconds }

    $result = [pscustomobject]@{
        Command  = "$Name $($Arguments -join ' ')".Trim()
        Ran      = $false
        ExitCode = $null
        Stdout   = ''
        Stderr   = ''
        TimedOut = $false
        Error    = $null
    }
    $job = [pscustomobject]@{
        Result  = $result
        Process = $null
        OutFile = $null
        ErrFile = $null
        Timeout = $Timeout
        Clock   = $null
    }

    $tool = Resolve-Tool -Name $Name
    if (-not $tool.Present) {
        $result.Error = "'$Name' was not found on PATH."
        return $job
    }
    if (-not $tool.Executable) {
        $result.Error = "'$Name' resolves to $($tool.Kind) at $($tool.Source), which this script does not execute."
        return $job
    }

    if (-not (Test-Path -LiteralPath $script:scratchRoot)) {
        New-Item -ItemType Directory -Path $script:scratchRoot -Force | Out-Null
    }

    # Every child gets an empty stdin instead of inheriting this script's. When an agent runs
    # discovery, stdin is a pipe that never closes, and npm's PowerShell shims (npm.ps1,
    # playwright-cli.ps1) treat an open stdin as pipeline input and wait for it until the timeout.
    $emptyInput = Join-Path $script:scratchRoot 'empty.in'
    if (-not (Test-Path -LiteralPath $emptyInput)) { [System.IO.File]::WriteAllText($emptyInput, '') }

    $stamp = [guid]::NewGuid().ToString('n')
    $job.OutFile = Join-Path $script:scratchRoot "$stamp.out"
    $job.ErrFile = Join-Path $script:scratchRoot "$stamp.err"

    # Output goes to files rather than pipes: a pipe that fills while nobody reads it deadlocks,
    # and pac is chatty. WaitForExit with a timeout then bounds the whole call.
    try {
        $argumentString = ConvertTo-ArgumentString -Arguments (@($tool.Prefix) + @($Arguments))
        $startArguments = @{
            FilePath               = $tool.Executable
            NoNewWindow            = $true
            PassThru               = $true
            RedirectStandardInput  = $emptyInput
            RedirectStandardOutput = $job.OutFile
            RedirectStandardError  = $job.ErrFile
        }
        if ($argumentString) { $startArguments['ArgumentList'] = $argumentString }

        $job.Clock = [System.Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process @startArguments

        # Reading .Handle caches it, which is what makes .ExitCode readable afterwards. Without
        # this, Start-Process -PassThru leaves ExitCode empty and every call looks like a failure.
        $null = $process.Handle
        $job.Process = $process
    }
    catch {
        $result.Error = "'$($result.Command)' could not be started: $($_.Exception.Message)"
    }

    return $job
}

function Wait-Tool {
    param($Job)

    $result = $Job.Result
    $process = $Job.Process

    if ($process) {
        # The timeout counts from the start, not from this call: a probe that ran while others
        # were being collected has already used part of it.
        $remaining = [int][Math]::Max(0, ($Job.Timeout * 1000) - $Job.Clock.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            $result.TimedOut = $true
            $result.Error = "'$($result.Command)' did not finish within $($Job.Timeout) seconds and was stopped."
            try { $process.Kill() } catch { }
            $process.WaitForExit(5000) | Out-Null
        }
        else {
            # The timed overload can return before the exit state is processed; the parameterless
            # call returns immediately once exited and guarantees ExitCode is populated.
            $process.WaitForExit()
            $result.Ran = $true
            $result.ExitCode = $process.ExitCode
        }
    }

    foreach ($pair in @(@{ File = $Job.OutFile; Property = 'Stdout' }, @{ File = $Job.ErrFile; Property = 'Stderr' })) {
        if ($pair.File -and (Test-Path -LiteralPath $pair.File)) {
            $text = [System.IO.File]::ReadAllText($pair.File)
            $result.($pair.Property) = $text.TrimEnd("`r", "`n")
            Remove-Item -LiteralPath $pair.File -Force -ErrorAction SilentlyContinue
        }
    }

    return $result
}

function Invoke-Tool {
    param(
        [string]$Name,
        [string[]]$Arguments = @(),
        [int]$Timeout = 0
    )

    return Wait-Tool -Job (Start-Tool -Name $Name -Arguments $Arguments -Timeout $Timeout)
}

function Get-ToolReport {
    param(
        [string]$Name,
        [string[]]$VersionArguments = @('--version'),
        [int]$Timeout = 30,
        # The result of a probe already started with Start-Tool; without it, the probe runs here.
        $Run = $null
    )

    $tool = Resolve-Tool -Name $Name
    $report = [ordered]@{
        present = $tool.Present
        source  = $tool.Source
        version = $null
        note    = $null
    }

    if (-not $tool.Present) { return $report }

    if (-not $tool.Executable) {
        $report['note'] = "Resolves to $($tool.Kind); version not probed."
        return $report
    }

    $run = $Run
    if (-not $run) { $run = Invoke-Tool -Name $Name -Arguments $VersionArguments -Timeout $Timeout }
    $output = "$($run.Stdout)`n$($run.Stderr)".Trim()

    # pac prints a banner and then exits 1 on --version, so a version that was printed is worth
    # more than the exit code. Only report a note when nothing recognisable came back.
    $match = [regex]::Match($output, '(\d+\.\d+[\w.+-]*)')
    if ($match.Success) {
        $report['version'] = $match.Value
    }
    elseif ($run.Error) {
        $report['note'] = $run.Error
    }
    elseif ($output) {
        $report['version'] = ($output -split "`n" | Select-Object -First 1).Trim()
    }
    else {
        $report['note'] = "No version output; exited with code $($run.ExitCode)."
    }

    return $report
}

function Read-XmlFile {
    param([string]$FullPath)

    try {
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $false
        # Solution.xml and ControlManifest.Input.xml are repository content, but treat them as
        # untrusted input anyway: no DTD resolution, no external entities.
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($FullPath, $settings)
        try { $document.Load($reader) } finally { $reader.Dispose() }
        return $document
    }
    catch {
        return $null
    }
}

function ConvertTo-ComparableVersion {
    param([string]$Text)

    if (-not $Text) { return $null }
    $match = [regex]::Match($Text, '(\d+)(\.(\d+))?(\.(\d+))?')
    if (-not $match.Success) { return $null }

    $major = [int]$match.Groups[1].Value
    $minor = if ($match.Groups[3].Success) { [int]$match.Groups[3].Value } else { 0 }
    $build = if ($match.Groups[5].Success) { [int]$match.Groups[5].Value } else { 0 }
    return New-Object System.Version($major, $minor, $build)
}

function Get-VersionStatus {
    param([bool]$Present, [string]$Version, [string]$Minimum, [string]$Preferred)

    if (-not $Present) { return 'missing' }
    if (-not $Minimum -and -not $Preferred) { return 'ok' }

    $actual = ConvertTo-ComparableVersion -Text $Version
    if (-not $actual) { return 'unknown' }

    if ($Minimum -and $actual -lt (ConvertTo-ComparableVersion -Text $Minimum)) { return 'below-minimum' }
    if ($Preferred -and $actual -lt (ConvertTo-ComparableVersion -Text $Preferred)) { return 'below-preferred' }
    return 'ok'
}
