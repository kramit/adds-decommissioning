param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$IncludeFullList
)

if (-not $RunId) {
    $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
}

$scriptPaths = @(
    (Join-Path $PSScriptRoot 'discovery\Get-EntraSyncTenantState.ps1'),
    (Join-Path $PSScriptRoot 'discovery\Get-EntraSyncObjectInventory.ps1')
)

$results = @()
foreach ($scriptPath in $scriptPaths) {
    if (-not (Test-Path $scriptPath)) {
        throw "Missing script: $scriptPath"
    }

    $invokeParams = @{
        OutputRoot = $OutputRoot
        RunId = $RunId
        TenantId = $TenantId
        UseDeviceCode = $UseDeviceCode
    }

    if ($scriptPath -match 'ObjectInventory') {
        $invokeParams.IncludeFullList = $IncludeFullList
    }

    $results += & $scriptPath @invokeParams
}

$commonPath = Join-Path $PSScriptRoot 'lib\EntraConnect.Common.ps1'
. $commonPath
$context = New-EntraConnectContext -ScriptName 'Export-EntraConnectPack' -OutputRoot $OutputRoot -RunId $RunId

$data = [pscustomobject]@{
    RunId = $RunId
    TenantId = $TenantId
    OutputRoot = $OutputRoot
    Results = @($results)
    Notes = @(
        'This wrapper runs the read-only EntraConnect discovery scripts with a shared RunId.'
    )
}

$summary = @(
    "Scripts run: $($results.Count)",
    "Output root: $($context.RunRoot)"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
