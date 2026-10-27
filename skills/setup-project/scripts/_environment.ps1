# Shared by the connect and setup-project skills' scripts: the environment report. Dot-sourced in
# script scope, after _common.ps1 and _dataverse.ps1. Reads $SkipEnvironment, $EnvironmentUrl,
# $ResolvePublisherFromSolution, $TimeoutSeconds, $tooling.pac and $notes; leaves $environment,
# $allUnmanagedSolutions and $script:solutionPublishers behind for the caller.
# Both skills carry an identical copy; tests/Test-Repository.ps1 fails while they differ.

# ---- environment --------------------------------------------------------------------------

$solutionReportLimit = 100
$allUnmanagedSolutions = @()
$script:solutionPublishers = @{}

$environment = [ordered]@{
    probed             = -not $SkipEnvironment
    authProfiles       = @()
    hasAuthProfile     = $false
    connected          = $false
    org                = $null
    nameSignal         = 'unknown'
    treatAsProduction  = $true
    solutions          = @()
    solutionsTruncated = $false
    solutionCount      = 0
    unmanagedSolutions = 0
    publishers         = @()
    resolvedPublisher  = $null
    errors             = @()
}

if (-not $SkipEnvironment -and $tooling.pac.present) {
    $authRun = Invoke-Tool -Name 'pac' -Arguments @('auth', 'list')
    if ($authRun.Ran -and $authRun.ExitCode -eq 0) {
        $environment['authProfiles'] = @(Get-AuthProfiles -Output $authRun.Stdout)
        $environment['hasAuthProfile'] = @($environment['authProfiles']).Count -gt 0
    }
    else {
        $environment.errors += "pac auth list failed: $(if ($authRun.Error) { $authRun.Error } else { $authRun.Stderr })"
    }

    $whoArguments = @('org', 'who')
    if ($EnvironmentUrl) { $whoArguments += @('--environment', $EnvironmentUrl) }
    $whoRun = Invoke-Tool -Name 'pac' -Arguments $whoArguments -Timeout ([Math]::Max($TimeoutSeconds, 120))

    if ($whoRun.Ran -and $whoRun.ExitCode -eq 0) {
        $org = Get-OrgFacts -Output $whoRun.Stdout
        $environment['connected'] = [bool]$org['url']
        $environment['org'] = $org
        $environment['nameSignal'] = Get-EnvironmentNameSignal -Values @($org['friendlyName'], $org['url'])
        # The standards treat an unverified environment as production. A name that merely looks
        # like a dev environment is a signal, never a verification.
        $environment['treatAsProduction'] = ($environment['nameSignal'] -ne 'dev')
    }
    else {
        $detail = if ($whoRun.Error) { $whoRun.Error } elseif ($whoRun.Stderr) { $whoRun.Stderr } else { $whoRun.Stdout }
        $environment.errors += "pac org who failed: $detail"
        $notes.Add('No Dataverse environment is connected, so the core solution and publisher could not be read from the platform. Authenticate with pac auth create, or supply the values.') | Out-Null
    }

    if ($environment['connected']) {
        $listArguments = @('solution', 'list')
        if ($EnvironmentUrl) { $listArguments += @('--environment', $EnvironmentUrl) }
        $listRun = Invoke-Tool -Name 'pac' -Arguments $listArguments -Timeout ([Math]::Max($TimeoutSeconds, 180))

        if ($listRun.Ran -and $listRun.ExitCode -eq 0) {
            $environmentSolutions = @(Get-EnvironmentSolutions -Output $listRun.Stdout)
            $environment['solutionCount'] = $environmentSolutions.Count
            # Only the unmanaged ones can be a DEV working solution. The core-solution guess below
            # reads every one of them; only the list emitted in the report is capped, because it is
            # long in a mature environment.
            $allUnmanagedSolutions = @($environmentSolutions | Where-Object { -not $_.managed })
            $environment['unmanagedSolutions'] = $allUnmanagedSolutions.Count
            $environment['solutions'] = @($allUnmanagedSolutions | Select-Object -First $solutionReportLimit)
            $environment['solutionsTruncated'] = $allUnmanagedSolutions.Count -gt $solutionReportLimit
            if (@($environmentSolutions | Where-Object { $_.possiblyTruncated }).Count -gt 0) {
                $notes.Add('pac solution list truncates the unique name column, and at least one name reached that width. Confirm a truncated name against the environment before using it as CoreSolution.') | Out-Null
            }
        }
        else {
            $environment.errors += "pac solution list failed: $(if ($listRun.Error) { $listRun.Error } else { $listRun.Stderr })"
        }

        # Publishers a project can own. Read-only ones are Microsoft's and never the project's.
        $publisherQuery = "<fetch><entity name='publisher'><attribute name='publisherid'/><attribute name='uniquename'/><attribute name='friendlyname'/><attribute name='customizationprefix'/><filter><condition attribute='isreadonly' operator='eq' value='0'/><condition attribute='customizationprefix' operator='not-null'/></filter><order attribute='uniquename'/></entity></fetch>"
        $publisherRun = Invoke-FetchXml -FetchXml $publisherQuery -Columns @('uniquename', 'friendlyname', 'customizationprefix')
        if ($publisherRun.error) {
            $environment.errors += "pac env fetch (publisher) failed: $($publisherRun.error)"
        }
        else {
            # Every environment carries the Default Publisher (prefix new) and the CDS Default
            # Publisher (prefix cr + hex). Their ids are fixed; their unique names are not.
            $defaultPublisherIds = @('d21aab71-79e7-11dd-8874-00188b01e34f', '00000001-0000-0000-0000-00000000005a')
            # pac pages the query and does not keep the order across pages: sort here.
            $environment['publishers'] = @($publisherRun.rows | Where-Object { $_.customizationprefix } | Sort-Object uniquename | ForEach-Object {
                [ordered]@{
                    uniqueName   = $_.uniquename
                    friendlyName = $_.friendlyname
                    prefix       = $_.customizationprefix
                    isDefault    = ($defaultPublisherIds -contains $_.publisherid) -or ($_.uniquename -match '^DefaultPublisher')
                }
            })
        }

        # The publisher of every unmanaged solution, so the core solution's publisher is one query
        # away instead of a full solution export.
        $solutionPublisherQuery = "<fetch><entity name='solution'><attribute name='uniquename'/><filter><condition attribute='ismanaged' operator='eq' value='0'/><condition attribute='isvisible' operator='eq' value='1'/></filter><link-entity name='publisher' from='publisherid' to='publisherid' alias='pub'><attribute name='uniquename'/><attribute name='customizationprefix'/></link-entity></entity></fetch>"
        $solutionPublisherRun = Invoke-FetchXml -FetchXml $solutionPublisherQuery -Columns @('uniquename', 'pub.uniquename', 'pub.customizationprefix')
        if ($solutionPublisherRun.error) {
            $environment.errors += "pac env fetch (solution publisher) failed: $($solutionPublisherRun.error)"
        }
        else {
            foreach ($row in $solutionPublisherRun.rows) {
                $script:solutionPublishers[$row.uniquename] = [ordered]@{
                    publisherUniqueName = $row.'pub.uniquename'
                    publisherPrefix     = $row.'pub.customizationprefix'
                }
            }
        }
    }

    if ($ResolvePublisherFromSolution -and $environment['connected']) {
        $exportRoot = Join-Path $script:scratchRoot 'publisher'
        New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
        $zipPath = Join-Path $exportRoot "$ResolvePublisherFromSolution.zip"

        $exportArguments = @('solution', 'export', '--name', $ResolvePublisherFromSolution, '--path', $zipPath, '--overwrite')
        if ($EnvironmentUrl) { $exportArguments += @('--environment', $EnvironmentUrl) }
        $exportRun = Invoke-Tool -Name 'pac' -Arguments $exportArguments -Timeout ([Math]::Max($TimeoutSeconds, 600))

        if ($exportRun.Ran -and $exportRun.ExitCode -eq 0 -and (Test-Path -LiteralPath $zipPath)) {
            $extractRoot = Join-Path $exportRoot 'unzipped'
            try {
                Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
                $solutionXml = Get-ChildItem -LiteralPath $extractRoot -Filter 'solution.xml' -Recurse -File |
                    Select-Object -First 1
                if ($solutionXml) {
                    $facts = @(Get-SolutionFacts -Root $extractRoot -SolutionXmlFiles @(
                        ($solutionXml.FullName.Substring($extractRoot.Length).TrimStart('\', '/') -replace '\\', '/')
                    ))
                    # The archive keeps solution.xml at the root, not under Other/, so parse it directly.
                    if (-not $facts -or -not $facts[0].uniqueName) {
                        $document = Read-XmlFile -FullPath $solutionXml.FullName
                        $manifest = if ($document) { $document.SelectSingleNode('/ImportExportXml/SolutionManifest') } else { $null }
                        if ($manifest) {
                            $publisher = $manifest.SelectSingleNode('Publisher')
                            $localized = if ($publisher) { $publisher.SelectSingleNode('LocalizedNames/LocalizedName') } else { $null }
                            $environment['resolvedPublisher'] = [ordered]@{
                                solutionUniqueName  = $(if ($manifest.SelectSingleNode('UniqueName')) { $manifest.SelectSingleNode('UniqueName').InnerText } else { $null })
                                publisherUniqueName = $(if ($publisher -and $publisher.SelectSingleNode('UniqueName')) { $publisher.SelectSingleNode('UniqueName').InnerText } else { $null })
                                publisherName       = $(if ($localized) { $localized.GetAttribute('description') } else { $null })
                                publisherPrefix     = $(if ($publisher -and $publisher.SelectSingleNode('CustomizationPrefix')) { $publisher.SelectSingleNode('CustomizationPrefix').InnerText } else { $null })
                                source              = "pac solution export $ResolvePublisherFromSolution"
                            }
                        }
                    }
                    else {
                        $environment['resolvedPublisher'] = [ordered]@{
                            solutionUniqueName  = $facts[0].uniqueName
                            publisherUniqueName = $facts[0].publisherUniqueName
                            publisherName       = $facts[0].publisherName
                            publisherPrefix     = $facts[0].publisherPrefix
                            source              = "pac solution export $ResolvePublisherFromSolution"
                        }
                    }
                }
                else {
                    $environment.errors += 'The exported solution archive contained no solution.xml.'
                }
            }
            catch {
                $environment.errors += "The exported solution archive could not be read: $($_.Exception.Message)"
            }
        }
        else {
            $detail = if ($exportRun.Error) { $exportRun.Error } elseif ($exportRun.Stderr) { $exportRun.Stderr } else { $exportRun.Stdout }
            $environment.errors += "pac solution export '$ResolvePublisherFromSolution' failed: $detail"
        }
    }
}
elseif (-not $SkipEnvironment) {
    $environment['probed'] = $false
    $environment.errors += 'pac is not installed; no environment fact was read.'
}
