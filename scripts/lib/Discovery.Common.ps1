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

        [AllowEmptyCollection()]
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

    $json = $Data | ConvertTo-Json -Depth 30
    $json | Set-Content -Path $Context.JsonPath -Encoding UTF8

    $csvFiles = @()
    if ($Tables) {
        foreach ($entry in $Tables.GetEnumerator()) {
            $tableName = [string]$entry.Key
            $safeTableName = $tableName -replace '[^A-Za-z0-9._-]', '_'
            $csvPath = Join-Path $Context.ArtifactRoot "$($Context.SafeName)-$safeTableName.csv"
            $rows = @($entry.Value)
            Write-DiscoveryCsvFile -Path $csvPath -Rows $rows
            $csvFiles += [pscustomobject]@{
                TableName = $tableName
                Path = $csvPath
                RowCount = $rows.Count
            }
        }
    }

    $attachmentFiles = @()
    if ($TextAttachments) {
        foreach ($entry in $TextAttachments.GetEnumerator()) {
            $attachmentName = [string]$entry.Key
            $safeAttachmentName = $attachmentName -replace '[^A-Za-z0-9._-]', '_'
            $attachmentPath = Join-Path $Context.ArtifactRoot "$($Context.SafeName)-$safeAttachmentName.txt"
            $lines = @($entry.Value)
            $lines | Set-Content -Path $attachmentPath -Encoding UTF8
            $attachmentFiles += [pscustomobject]@{
                Name = $attachmentName
                Path = $attachmentPath
                LineCount = $lines.Count
            }
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
    $htmlPath = Join-Path $Context.RunRoot 'Discovery-Report.html'
    $pdfPath = Join-Path $Context.RunRoot 'Discovery-Report.pdf'
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
        $textPath = if ($null -ne $result.TextPath) { [string]$result.TextPath } else { '' }
        $jsonPath = if ($null -ne $result.JsonPath) { [string]$result.JsonPath } else { '' }
        $csvPaths = @()
        if ($result.CsvFiles) {
            $csvPaths = @($result.CsvFiles | ForEach-Object { $_.Path })
        }

        $indexRows += [pscustomobject]@{
            ScriptName = $result.ScriptName
            TextPath = $textPath
            JsonPath = $jsonPath
            CsvCount = @($csvPaths).Count
            CsvPaths = @($csvPaths) -join '; '
        }

        $lines.Add("- $($result.ScriptName)")
        $lines.Add("  - Report: $textPath")
        $lines.Add("  - JSON: $jsonPath")
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
        $textPath = if ($null -ne $result.TextPath) { [string]$result.TextPath } else { '' }
        $lines.Add("")
        $lines.Add("## $($result.ScriptName)")
        $lines.Add("")
        if ($textPath -and (Test-Path -LiteralPath $textPath)) {
            foreach ($reportLine in @(Get-Content -Path $textPath)) {
                $lines.Add([string]$reportLine)
            }
        }
        else {
            $lines.Add("_Missing report file: $textPath_")
        }
    }

    $lines | Set-Content -Path $reportPath -Encoding UTF8
    $indexRows | Export-Csv -Path $indexPath -NoTypeInformation -Encoding UTF8

    $htmlResult = Convert-DiscoveryMarkdownReportToHtml -MarkdownPath $reportPath -HtmlPath $htmlPath -Title $ReportTitle -RunId $Context.RunId -RunRoot $Context.RunRoot
    $pdfResult = Convert-DiscoveryHtmlReportToPdf -HtmlPath $htmlPath -PdfPath $pdfPath

    [pscustomobject]@{
        ReportPath = $reportPath
        HtmlPath = $htmlResult.HtmlPath
        PdfPath = $pdfResult.PdfPath
        PdfGenerated = $pdfResult.Generated
        PdfWarning = $pdfResult.Warning
        IndexPath = $indexPath
        ScriptCount = $ScriptResults.Count
    }
}

function Convert-DiscoveryMarkdownReportToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath,

        [Parameter(Mandatory = $true)]
        [string]$HtmlPath,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [string]$RunId,

        [string]$RunRoot
    )

    $markdown = ConvertFrom-Markdown -Path $MarkdownPath
    $reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $style = @"
<style>
:root {
  --bg: #f4f1ea;
  --surface: #fffdf9;
  --ink: #1c2430;
  --muted: #5f6b7a;
  --accent: #0f4c5c;
  --accent-soft: #d8e7eb;
  --line: #d6ddd9;
  --table-head: #eef4f6;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: "Segoe UI", Tahoma, sans-serif;
  line-height: 1.45;
}
.page {
  max-width: 1120px;
  margin: 0 auto;
  padding: 32px;
}
.hero {
  background: linear-gradient(135deg, #143642 0%, #1d5965 100%);
  color: #fff;
  padding: 36px 40px;
  border-radius: 18px;
  box-shadow: 0 10px 30px rgba(20, 54, 66, 0.18);
  margin-bottom: 24px;
}
.hero h1 {
  margin: 0 0 8px 0;
  font-size: 30px;
  letter-spacing: 0.02em;
}
.hero-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  margin-top: 20px;
}
.hero-card {
  background: rgba(255,255,255,0.12);
  border: 1px solid rgba(255,255,255,0.18);
  border-radius: 12px;
  padding: 12px 14px;
}
.hero-card .label {
  display: block;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  opacity: 0.8;
  margin-bottom: 4px;
}
.content {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: 28px 32px;
  box-shadow: 0 8px 24px rgba(28, 36, 48, 0.06);
}
h1, h2, h3, h4 {
  color: var(--accent);
  page-break-after: avoid;
}
h1 { font-size: 28px; margin-top: 0; }
h2 {
  font-size: 22px;
  margin-top: 28px;
  padding-bottom: 8px;
  border-bottom: 2px solid var(--accent-soft);
}
h3 {
  font-size: 18px;
  margin-top: 22px;
  background: var(--table-head);
  border-left: 5px solid var(--accent);
  padding: 8px 12px;
  border-radius: 8px;
}
p, li { color: var(--ink); }
ul { padding-left: 22px; }
code {
  font-family: Consolas, "Courier New", monospace;
  background: #f2f5f7;
  border-radius: 4px;
  padding: 0.1em 0.35em;
}
table {
  width: 100%;
  border-collapse: collapse;
  margin: 14px 0 22px 0;
  font-size: 12px;
}
thead tr, tr:first-child {
  background: var(--table-head);
}
th, td {
  border: 1px solid var(--line);
  padding: 8px 10px;
  text-align: left;
  vertical-align: top;
}
tr:nth-child(even) td {
  background: #fbfcfc;
}
blockquote {
  margin: 14px 0;
  padding: 10px 14px;
  border-left: 4px solid var(--accent);
  background: #f6fafb;
  color: var(--muted);
}
.footer {
  color: var(--muted);
  font-size: 11px;
  margin-top: 18px;
  text-align: right;
}
@media print {
  body { background: #fff; }
  .page { max-width: none; padding: 0; }
  .hero, .content {
    box-shadow: none;
    border: 0;
  }
  .content { padding: 0; }
  h2, h3, table { page-break-inside: avoid; }
}
</style>
"@

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$Title</title>
  $style
</head>
<body>
  <div class="page">
    <section class="hero">
      <h1>$Title</h1>
      <p>Management-ready summary export for the latest AD DS discovery pack.</p>
      <div class="hero-grid">
        <div class="hero-card"><span class="label">Run ID</span><span>$RunId</span></div>
        <div class="hero-card"><span class="label">Generated</span><span>$reportDate</span></div>
        <div class="hero-card"><span class="label">Run Root</span><span>$RunRoot</span></div>
      </div>
    </section>
    <main class="content">
      $($markdown.Html)
      <div class="footer">Generated by adds-decommissioning discovery tooling</div>
    </main>
  </div>
</body>
</html>
"@

    $html | Set-Content -Path $HtmlPath -Encoding UTF8

    [pscustomobject]@{
        HtmlPath = $HtmlPath
    }
}

function Convert-DiscoveryHtmlReportToPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HtmlPath,

        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )

    $edgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    if (-not (Test-Path -LiteralPath $edgePath)) {
        return [pscustomobject]@{
            PdfPath = $null
            Generated = $false
            Warning = "Microsoft Edge was not found at $edgePath"
        }
    }

    $htmlUri = ([System.Uri]$HtmlPath).AbsoluteUri
    $result = Invoke-ExternalCommand -FilePath $edgePath -Arguments @(
        '--headless',
        '--disable-gpu',
        "--print-to-pdf=$PdfPath",
        $htmlUri
    )

    if ((Test-Path -LiteralPath $PdfPath) -and $result.ExitCode -eq 0) {
        return [pscustomobject]@{
            PdfPath = $PdfPath
            Generated = $true
            Warning = $null
        }
    }

    return [pscustomobject]@{
        PdfPath = if (Test-Path -LiteralPath $PdfPath) { $PdfPath } else { $null }
        Generated = [bool](Test-Path -LiteralPath $PdfPath)
        Warning = "Edge PDF generation did not complete cleanly. ExitCode=$($result.ExitCode)"
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
