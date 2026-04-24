function New-DiscoveryContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),

        [string]$RunId
    )

    if (-not $RunId) {
        $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
    }

    $safeScriptName = $ScriptName -replace '[^A-Za-z0-9._-]', '_'
    $runRoot = Join-Path $OutputRoot $RunId
    $artifactRoot = Join-Path $runRoot $safeScriptName

    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

    [pscustomobject]@{
        ScriptName   = $ScriptName
        SafeName     = $safeScriptName
        RunId        = $RunId
        OutputRoot   = $OutputRoot
        RunRoot      = $runRoot
        ArtifactRoot = $artifactRoot
        JsonPath     = Join-Path $artifactRoot "$safeScriptName.json"
        TextPath     = Join-Path $artifactRoot "$safeScriptName.txt"
    }
}

function ConvertTo-DiscoveryDisplayValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [datetime]) {
        return $Value.ToString('o')
    }

    if ($Value -is [timespan]) {
        return $Value.ToString()
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return (($Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return (@($Value | ForEach-Object { ConvertTo-DiscoveryDisplayValue $_ }) -join '; ')
    }

    return [string]$Value
}

function ConvertTo-DiscoveryFlatObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $flat = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $flat[$property.Name] = ConvertTo-DiscoveryDisplayValue $property.Value
    }

    [pscustomobject]$flat
}

function New-DiscoveryMarkdownTable {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [string[]]$Properties,

        [int]$MaxRows = 10
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return @('_(no rows)_')
    }

    $previewRows = @($Rows | Select-Object -First $MaxRows | ForEach-Object { ConvertTo-DiscoveryFlatObject $_ })
    if (-not $Properties -or $Properties.Count -eq 0) {
        $Properties = @($previewRows[0].PSObject.Properties.Name)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('| ' + ($Properties -join ' | ') + ' |')
    $lines.Add('| ' + (($Properties | ForEach-Object { '---' }) -join ' | ') + ' |')

    foreach ($row in $previewRows) {
        $values = foreach ($property in $Properties) {
            $cell = $row.PSObject.Properties[$property].Value
            ConvertTo-DiscoveryDisplayValue $cell
        }
        $lines.Add('| ' + ($values -join ' | ') + ' |')
    }

    if ($Rows.Count -gt $MaxRows) {
        $lines.Add('')
        $lines.Add("... and $($Rows.Count - $MaxRows) more rows.")
    }

    return @($lines)
}

function Write-DiscoveryCsvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object[]]$Rows
    )

    $flatRows = @($Rows | ForEach-Object { ConvertTo-DiscoveryFlatObject $_ })
    if ($flatRows.Count -gt 0) {
        $flatRows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        @() | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }
}

function Test-OptionalModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        Import-Module $Name -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $output = & $FilePath @Arguments 2>&1
    [pscustomobject]@{
        FilePath = $FilePath
        Arguments = $Arguments
        ExitCode = $LASTEXITCODE
        Output = @($output)
    }
}

function Save-DiscoveryArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [object]$Data,

        [string[]]$SummaryLines = @(),

        [string[]]$Warnings = @(),

        [System.Collections.IDictionary]$Tables = @{},

        [System.Collections.IDictionary]$TextAttachments = @{}
    )

    $json = $Data | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $Context.JsonPath -Encoding UTF8

    $csvFiles = New-Object System.Collections.Generic.List[object]
    if ($Tables) {
        foreach ($entry in $Tables.GetEnumerator()) {
            $tableName = [string]$entry.Key
            $safeTableName = $tableName -replace '[^A-Za-z0-9._-]', '_'
            $csvPath = Join-Path $Context.ArtifactRoot "$($Context.SafeName)-$safeTableName.csv"
            $rows = @($entry.Value)
            Write-DiscoveryCsvFile -Path $csvPath -Rows $rows
            $csvFiles.Add([pscustomobject]@{
                TableName = $tableName
                Path = $csvPath
                RowCount = $rows.Count
            })
        }
    }

    $attachmentFiles = New-Object System.Collections.Generic.List[object]
    if ($TextAttachments) {
        foreach ($entry in $TextAttachments.GetEnumerator()) {
            $attachmentName = [string]$entry.Key
            $safeAttachmentName = $attachmentName -replace '[^A-Za-z0-9._-]', '_'
            $attachmentPath = Join-Path $Context.ArtifactRoot "$($Context.SafeName)-$safeAttachmentName.txt"
            $lines = @($entry.Value)
            $lines | Set-Content -Path $attachmentPath -Encoding UTF8
            $attachmentFiles.Add([pscustomobject]@{
                Name = $attachmentName
                Path = $attachmentPath
                LineCount = $lines.Count
            })
        }
    }

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add("# $($Context.ScriptName)")
    $report.Add("RunId: $($Context.RunId)")
    $report.Add("RunRoot: $($Context.RunRoot)")
    $report.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $report.Add("")

    if ($SummaryLines.Count -gt 0) {
        $report.Add("## Summary")
        foreach ($line in $SummaryLines) {
            $report.Add("- $line")
        }
        $report.Add("")
    }

    if ($Warnings.Count -gt 0) {
        $report.Add("## Warnings")
        foreach ($line in $Warnings) {
            $report.Add("- $line")
        }
        $report.Add("")
    }

    if ($csvFiles.Count -gt 0) {
        $report.Add("## Detailed Tables")
        foreach ($table in $csvFiles) {
            $report.Add("### $($table.TableName)")
            $report.Add("- Rows: $($table.RowCount)")
            $report.Add("- CSV: $($table.Path)")
            $report.Add("")

            if ($table.RowCount -gt 0 -and $Tables.Contains($table.TableName)) {
                $preview = New-DiscoveryMarkdownTable -Rows @($Tables[$table.TableName]) -MaxRows 5
                foreach ($line in $preview) {
                    $report.Add($line)
                }
                $report.Add("")
            }
        }
    }

    if ($attachmentFiles.Count -gt 0) {
        $report.Add("## Attachments")
        foreach ($attachment in $attachmentFiles) {
            $report.Add("- $($attachment.Name): $($attachment.Path)")
        }
        $report.Add("")
    }

    $report.Add("## JSON")
    $report.Add($Context.JsonPath)

    $report | Set-Content -Path $Context.TextPath -Encoding UTF8

    [pscustomobject]@{
        Context = $Context
        JsonPath = $Context.JsonPath
        TextPath = $Context.TextPath
        Data = $Data
        SummaryLines = $SummaryLines
        Warnings = $Warnings
        CsvFiles = @($csvFiles)
        AttachmentFiles = @($attachmentFiles)
    }
}

function Save-DiscoveryRunReport {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [object[]]$ScriptResults,

        [string]$ReportTitle = 'Discovery Run Report'
    )

    $reportPath = Join-Path $Context.RunRoot 'Discovery-Report.md'
    $indexPath = Join-Path $Context.RunRoot 'Discovery-Index.csv'

    $indexRows = @()
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $ReportTitle")
    $lines.Add("RunId: $($Context.RunId)")
    $lines.Add("RunRoot: $($Context.RunRoot)")
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("")
    $lines.Add("## Script Index")

    foreach ($result in $ScriptResults) {
        $csvPaths = @()
        if ($result.CsvFiles) {
            $csvPaths = @($result.CsvFiles | ForEach-Object { $_.Path })
        }

        $indexRows += [pscustomobject]@{
            ScriptName = $result.ScriptName
            TextPath = $result.TextPath
            JsonPath = $result.JsonPath
            CsvCount = @($csvPaths).Count
            CsvPaths = @($csvPaths) -join '; '
        }

        $lines.Add("- $($result.ScriptName)")
        $lines.Add("  - Report: $($result.TextPath)")
        $lines.Add("  - JSON: $($result.JsonPath)")
        if ($csvPaths.Count -gt 0) {
            $lines.Add("  - CSVs:")
            foreach ($csvPath in $csvPaths) {
                $lines.Add("    - $csvPath")
            }
        }
    }

    $lines.Add("")
    $lines.Add("## Script Reports")
    foreach ($result in $ScriptResults) {
        $lines.Add("")
        $lines.Add("## $($result.ScriptName)")
        $lines.Add("")
        if (Test-Path $result.TextPath) {
            $lines.AddRange(@(Get-Content -Path $result.TextPath))
        }
        else {
            $lines.Add("_Missing report file: $($result.TextPath)_")
        }
    }

    $lines | Set-Content -Path $reportPath -Encoding UTF8
    $indexRows | Export-Csv -Path $indexPath -NoTypeInformation -Encoding UTF8

    [pscustomobject]@{
        ReportPath = $reportPath
        IndexPath = $indexPath
        ScriptCount = $ScriptResults.Count
    }
}

function Get-PrincipalDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $Name
    }

    return $Name.Split('\')[-1]
}
