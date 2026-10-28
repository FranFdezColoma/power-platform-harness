<#
.SYNOPSIS
    Stand-in for the Power Platform CLI, for tests that must never reach a real environment.

.DESCRIPTION
    new-feature.Tests.ps1 puts a pac.cmd that forwards here first on PATH. This script imitates
    the output of the read-only commands new-feature.ps1 is allowed to run (pac org who, pac env
    fetch) and refuses everything else, with an exit code the caller cannot mistake for success.

    Behaviour comes from environment variables the test sets before starting the child:

      FAKEPAC_LOG               file that receives one JSON line per invocation (required)
      FAKEPAC_WHO_FAIL          '1': pac org who fails as it does without an auth profile
      FAKEPAC_FRIENDLY_NAME     Friendly Name printed by pac org who
      FAKEPAC_ORG_URL           Org URL printed by pac org who
      FAKEPAC_PUBLISHER_PREFIX  customizationprefix of the publisher; empty: no publisher
      FAKEPAC_PUBLISHER_NAME    publisher uniquename when the query does not filter on it
      FAKEPAC_SOLUTION_EXISTS   '1': the solution query returns a row
      FAKEPAC_SOLUTION_NAME     solution uniquename when the query does not filter on it

    Each log line records the arguments and, for pac env fetch, the entity queried and the value
    of its uniquename condition, read from the --xmlFile before the caller deletes it.
#>

$ErrorActionPreference = 'Stop'

$arguments = @($args | ForEach-Object { [string]$_ })
$entry = [ordered]@{ args = $arguments; entity = $null; value = $null }

function Write-Log {
    if (-not $env:FAKEPAC_LOG) { return }
    $line = ConvertTo-Json -InputObject $entry -Compress -Depth 4
    [System.IO.File]::AppendAllText($env:FAKEPAC_LOG, $line + [Environment]::NewLine)
}

function Get-OptionValue {
    param([string]$Option)

    for ($index = 0; $index -lt $arguments.Count - 1; $index++) {
        if ($arguments[$index] -eq $Option) { return $arguments[$index + 1] }
    }
    return $null
}

# Prints rows the way pac env fetch does: a header of attribute names separated by runs of
# spaces, each value starting at its header's column offset.
function Write-Table {
    param([string[]]$Columns, [hashtable[]]$Rows)

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Output 'No results returned.'
        return
    }

    $widths = @{}
    foreach ($column in $Columns) {
        $width = $column.Length
        foreach ($row in $Rows) {
            if ([string]$row[$column]) { $width = [Math]::Max($width, ([string]$row[$column]).Length) }
        }
        $widths[$column] = $width + 3
    }

    $header = ($Columns | ForEach-Object { $_.PadRight($widths[$_]) }) -join ''
    Write-Output $header.TrimEnd()
    foreach ($row in $Rows) {
        $text = ($Columns | ForEach-Object { ([string]$row[$_]).PadRight($widths[$_]) }) -join ''
        Write-Output $text.TrimEnd()
    }
}

$verb = ($arguments | Select-Object -First 2) -join ' '

if ($arguments.Count -gt 0 -and $arguments[0] -eq 'solution') {
    Write-Log
    [Console]::Error.WriteLine('fake pac: solution commands are not allowed in these tests.')
    exit 42
}

if ($verb -eq 'org who') {
    Write-Log
    if ($env:FAKEPAC_WHO_FAIL -eq '1') {
        Write-Output 'Error: No profiles were found on this computer. Please run pac auth create to create one.'
        exit 1
    }
    Write-Output 'Connected as fake.user@contoso.invalid'
    Write-Output "Connected to... $($env:FAKEPAC_FRIENDLY_NAME)"
    Write-Output ''
    Write-Output '  Organization Information'
    Write-Output '  Org ID:         00000000-0000-0000-0000-000000000001'
    Write-Output '  Unique Name:    unq00000000000000000000000000001'
    Write-Output "  Friendly Name:  $($env:FAKEPAC_FRIENDLY_NAME)"
    Write-Output "  Org URL:        $($env:FAKEPAC_ORG_URL)"
    Write-Output '  User Email:     fake.user@contoso.invalid'
    Write-Output '  User ID:        00000000-0000-0000-0000-000000000002'
    Write-Output '  Environment ID: 00000000-0000-0000-0000-000000000003'
    exit 0
}

if ($verb -eq 'env fetch') {
    $xmlFile = Get-OptionValue -Option '--xmlFile'
    if (-not $xmlFile -or -not (Test-Path -LiteralPath $xmlFile)) {
        Write-Log
        [Console]::Error.WriteLine("fake pac: --xmlFile is missing or points at no file: '$xmlFile'.")
        exit 43
    }

    $query = New-Object System.Xml.XmlDocument
    $query.Load($xmlFile)
    $entityNode = $query.SelectSingleNode('//entity')
    $entity = $entityNode.GetAttribute('name')
    $columns = @($query.SelectNodes('//entity/attribute') | ForEach-Object { $_.GetAttribute('name') })
    if ($columns.Count -eq 0) { $columns = @('uniquename') }
    $condition = $query.SelectSingleNode("//condition[@attribute='uniquename']")
    $value = $null
    if ($condition) { $value = $condition.GetAttribute('value') }

    $entry.entity = $entity
    $entry.value = $value
    Write-Log

    $rows = @()
    if ($entity -eq 'publisher' -and $env:FAKEPAC_PUBLISHER_PREFIX) {
        $name = $value
        if (-not $name) { $name = $env:FAKEPAC_PUBLISHER_NAME }
        $rows = @(@{
            uniquename          = $name
            customizationprefix = $env:FAKEPAC_PUBLISHER_PREFIX
            friendlyname        = 'Fake Publisher'
            publisherid         = '00000000-0000-0000-0000-000000000010'
        })
    }
    elseif ($entity -eq 'solution' -and $env:FAKEPAC_SOLUTION_EXISTS -eq '1') {
        $name = $value
        if (-not $name) { $name = $env:FAKEPAC_SOLUTION_NAME }
        $rows = @(@{
            uniquename   = $name
            version      = '1.0.0.0'
            friendlyname = 'Fake Solution'
            ismanaged    = 'False'
            solutionid   = '00000000-0000-0000-0000-000000000020'
        })
    }

    foreach ($row in $rows) {
        foreach ($column in $columns) {
            if (-not $row.ContainsKey($column)) { $row[$column] = 'fakevalue' }
        }
    }

    Write-Table -Columns $columns -Rows $rows
    exit 0
}

Write-Log
[Console]::Error.WriteLine("fake pac: '$($arguments -join ' ')' is not a command these tests expect.")
exit 44
