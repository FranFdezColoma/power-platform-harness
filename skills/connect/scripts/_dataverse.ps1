# Shared by the connect and setup-project skills' scripts: reading a Dataverse environment through
# pac. Both skills carry an identical copy; tests/Test-Repository.ps1 fails while they differ.
#
# Dot-source it after _common.ps1.

function Get-SolutionFacts {
    param([string]$Root, [string[]]$SolutionXmlFiles)

    foreach ($relative in $SolutionXmlFiles) {
        $document = Read-XmlFile -FullPath (Join-Path $Root $relative)
        # <folder>/Other/Solution.xml -> <folder>
        $folder = ($relative -replace '/Other/Solution\.xml$', '')

        if (-not $document) {
            [pscustomobject]@{
                folder    = $folder
                manifest  = $relative
                readError = 'Solution.xml could not be parsed.'
            }
            continue
        }

        $manifest = $document.SelectSingleNode('/ImportExportXml/SolutionManifest')
        if (-not $manifest) {
            [pscustomobject]@{ folder = $folder; manifest = $relative; readError = 'No SolutionManifest element.' }
            continue
        }

        $publisher = $manifest.SelectSingleNode('Publisher')
        $publisherDisplay = $null
        if ($publisher) {
            $localized = $publisher.SelectSingleNode('LocalizedNames/LocalizedName')
            if ($localized) { $publisherDisplay = $localized.GetAttribute('description') }
        }

        $solutionDisplay = $null
        $solutionLocalized = $manifest.SelectSingleNode('LocalizedNames/LocalizedName')
        if ($solutionLocalized) { $solutionDisplay = $solutionLocalized.GetAttribute('description') }

        $managedNode = $manifest.SelectSingleNode('Managed')

        [pscustomobject]@{
            folder              = $folder
            manifest            = $relative
            uniqueName          = $(if ($manifest.SelectSingleNode('UniqueName')) { $manifest.SelectSingleNode('UniqueName').InnerText } else { $null })
            displayName         = $solutionDisplay
            version             = $(if ($manifest.SelectSingleNode('Version')) { $manifest.SelectSingleNode('Version').InnerText } else { $null })
            managed             = $(if ($managedNode) { $managedNode.InnerText -eq '1' } else { $null })
            publisherUniqueName = $(if ($publisher -and $publisher.SelectSingleNode('UniqueName')) { $publisher.SelectSingleNode('UniqueName').InnerText } else { $null })
            publisherName       = $publisherDisplay
            publisherPrefix     = $(if ($publisher -and $publisher.SelectSingleNode('CustomizationPrefix')) { $publisher.SelectSingleNode('CustomizationPrefix').InnerText } else { $null })
            readError           = $null
        }
    }
}

function Get-AuthProfiles {
    param([string]$Output)

    # pac auth list prints a fixed-width table. Column positions move between versions, so take
    # the pieces that have an unambiguous shape instead: the active marker, an email, a url.
    foreach ($line in ($Output -split "`r?`n")) {
        if ($line -notmatch '^\s*\[\d+\]') { continue }

        $url = [regex]::Match($line, 'https?://[^\s]+')
        $user = [regex]::Match($line, '[^\s]+@[^\s]+')

        [pscustomobject]@{
            index       = [regex]::Match($line, '\[(\d+)\]').Groups[1].Value
            active      = $line -match '^\s*\[\d+\]\s+\*'
            user        = $(if ($user.Success) { $user.Value } else { $null })
            url         = $(if ($url.Success) { $url.Value.TrimEnd('/') } else { $null })
            raw         = $line.Trim()
        }
    }
}

function Get-OrgFacts {
    param([string]$Output)

    $facts = [ordered]@{
        connectedAs   = $null
        friendlyName  = $null
        uniqueName    = $null
        url           = $null
        orgId         = $null
        environmentId = $null
        userEmail     = $null
    }

    $map = @{
        'Org ID'        = 'orgId'
        'Unique Name'   = 'uniqueName'
        'Friendly Name' = 'friendlyName'
        'Org URL'       = 'url'
        'User Email'    = 'userEmail'
        'Environment ID' = 'environmentId'
    }

    foreach ($line in ($Output -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*([A-Za-z ]+?):\s+(.+?)\s*$')
        if ($match.Success -and $map.ContainsKey($match.Groups[1].Value)) {
            $facts[$map[$match.Groups[1].Value]] = $match.Groups[2].Value
        }
        elseif ($line -match '^\s*Connected as\s+(.+?)\s*$') {
            $facts['connectedAs'] = $Matches[1]
        }
    }

    if ($facts['url']) { $facts['url'] = $facts['url'].TrimEnd('/') }
    return $facts
}

function Get-EnvironmentNameSignal {
    param([string[]]$Values)

    $text = (@($Values) -join ' ')
    if (-not $text) { return 'unknown' }

    # Production first: a name containing both is more likely to be production than not.
    if ($text -match '(?i)(^|[^a-z])(prod|prd|production|live)([^a-z]|$)') { return 'production' }
    if ($text -match '(?i)(^|[^a-z])(test|tst|qa|uat|sit|stag|staging|stage|preprod|pre-prod)([^a-z]|$)') { return 'test' }
    if ($text -match '(?i)(^|[^a-z])(dev|develop|development|sandbox|sbx)([^a-z]|$)') { return 'dev' }
    return 'unknown'
}

function Get-EnvironmentSolutions {
    param([string]$Output)

    $started = $false
    foreach ($line in ($Output -split "`r?`n")) {
        if ($line -match '^\s*Unique Name\s+Friendly Name\s+Version\s+Managed') { $started = $true; continue }
        if (-not $started) { continue }
        if (-not $line.Trim()) { continue }

        $match = [regex]::Match($line, '^(?<unique>\S+)\s+(?<rest>.*?)\s+(?<version>\d+(\.\d+){1,3})\s+(?<managed>True|False)\s*$')
        if (-not $match.Success) { continue }

        $unique = $match.Groups['unique'].Value
        [pscustomobject]@{
            uniqueName   = $unique
            friendlyName = $match.Groups['rest'].Value.Trim()
            version      = $match.Groups['version'].Value
            managed      = $match.Groups['managed'].Value -eq 'True'
            # pac pads the unique name column to a fixed width and cuts anything longer. A name at
            # exactly the limit may be a truncation, and a truncated unique name passed to
            # pac solution export fails or, worse, matches the wrong solution.
            possiblyTruncated = $unique.Length -ge 48
        }
    }
}

function Invoke-FetchXml {
    param([string]$FetchXml, [string[]]$Columns)

    # Runs a read-only FetchXML query through pac env fetch and parses the fixed-width table it
    # prints. Returns @{ rows; error }. The query goes through --xmlFile rather than --xml: a
    # command line full of quotes and angle brackets does not survive the cmd.exe shim that an
    # npm-installed pac runs behind.
    $result = [ordered]@{ rows = @(); error = $null }

    if (-not (Test-Path -LiteralPath $script:scratchRoot)) {
        New-Item -ItemType Directory -Path $script:scratchRoot -Force | Out-Null
    }
    $queryFile = Join-Path $script:scratchRoot "$([guid]::NewGuid().ToString('n')).xml"
    [System.IO.File]::WriteAllText($queryFile, $FetchXml)

    $arguments = @('env', 'fetch', '--xmlFile', $queryFile)
    if ($EnvironmentUrl) { $arguments += @('--environment', $EnvironmentUrl) }
    $run = Invoke-Tool -Name 'pac' -Arguments $arguments -Timeout ([Math]::Max($TimeoutSeconds, 120))
    Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue

    if (-not $run.Ran -or $run.ExitCode -ne 0) {
        $result.error = if ($run.Error) { $run.Error } elseif ($run.Stderr) { $run.Stderr } else { $run.Stdout }
        return $result
    }

    # pac sizes each column to its widest value and may add columns (the primary key) that were
    # not asked for, in any order. Cut every row at the header's column offsets: values such as a
    # friendly name contain spaces, so splitting on whitespace would misalign them.
    $lines = @($run.Stdout -split "`r?`n")
    $headerIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $tokens = @($lines[$index].Trim() -split '\s+')
        if (@($Columns | Where-Object { $tokens -notcontains $_ }).Count -eq 0) { $headerIndex = $index; break }
    }
    if ($headerIndex -lt 0) {
        # No header means no rows: pac prints nothing but the banner for an empty result.
        return $result
    }

    $header = $lines[$headerIndex]
    $offsets = @([regex]::Matches($header, '\S+') | ForEach-Object { [pscustomobject]@{ Name = $_.Value; Start = $_.Index } })
    $rows = New-Object System.Collections.Generic.List[object]
    for ($index = $headerIndex + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if (-not $line.Trim()) { continue }
        $row = [ordered]@{}
        for ($column = 0; $column -lt $offsets.Count; $column++) {
            $start = $offsets[$column].Start
            $end = if ($column + 1 -lt $offsets.Count) { $offsets[$column + 1].Start } else { [Math]::Max($line.Length, $start) }
            $value = if ($start -lt $line.Length) { $line.Substring($start, [Math]::Min($end, $line.Length) - $start).Trim() } else { '' }
            $row[$offsets[$column].Name] = $value
        }
        $rows.Add([pscustomobject]$row)
    }
    $result['rows'] = $rows.ToArray()
    return $result
}
