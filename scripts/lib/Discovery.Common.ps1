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

        [string[]]$Warnings = @()
    )

    $json = $Data | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $Context.JsonPath -Encoding UTF8

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
