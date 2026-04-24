function New-EntraConnectContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),

        [string]$RunId
    )

    if (-not $RunId) {
        $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
    }

    $safeScriptName = $ScriptName -replace '[^A-Za-z0-9._-]', '_'
    $runRoot = Join-Path (Join-Path $OutputRoot 'entra-connect') $RunId
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

function Import-GraphAuthModule {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is not installed. Install the Microsoft Graph PowerShell SDK before running these scripts.'
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Connect-EntraGraphSession {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Scopes,

        [string]$TenantId,

        [switch]$UseDeviceCode
    )

    Import-GraphAuthModule

    $params = @{
        Scopes = $Scopes
        ContextScope = 'Process'
        NoWelcome = $true
        ErrorAction = 'Stop'
    }

    if ($TenantId) {
        $params.TenantId = $TenantId
    }

    if ($UseDeviceCode) {
        $params.UseDeviceCode = $true
    }

    Connect-MgGraph @params | Out-Null

    $context = Get-MgContext

    [pscustomobject]@{
        TenantId = $context.TenantId
        Account = $context.Account
        Scopes = @($context.Scopes)
        AuthType = $context.AuthType
        AppName = $context.AppName
        ContextScope = $context.ContextScope
    }
}

function Get-GraphCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers
    )

    $items = New-Object System.Collections.Generic.List[object]
    $nextUri = $Uri

    while ($nextUri) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri -Headers $Headers -OutputType PSObject -ErrorAction Stop
        if ($null -eq $response) {
            break
        }

        if ($response.PSObject.Properties.Name -contains 'value') {
            foreach ($item in @($response.value)) {
                $items.Add($item)
            }
            $nextUri = $response.'@odata.nextLink'
            continue
        }

        $items.Add($response)
        break
    }

    return @($items)
}

function Get-GraphSingle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers
    )

    Invoke-MgGraphRequest -Method GET -Uri $Uri -Headers $Headers -OutputType PSObject -ErrorAction Stop
}

function Invoke-GraphPatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [object]$Body
    )

    Invoke-MgGraphRequest -Method PATCH -Uri $Uri -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
}

function Save-EntraArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [object]$Data,

        [string[]]$SummaryLines = @(),

        [string[]]$Warnings = @()
    )

    $json = $Data | ConvertTo-Json -Depth 12
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
