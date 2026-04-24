param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId
)

if (-not $RunId) {
    $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
}

$results = @()
foreach ($scriptName in @(
    'Get-EntraConnectLocalState.ps1',
    'Test-EntraConnectLocalPrereqs.ps1'
)) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path $scriptPath)) {
        throw "Missing script: $scriptPath"
    }

    $results += & $scriptPath -OutputRoot $OutputRoot -RunId $RunId
}

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath
$context = New-EntraConnectLocalContext -ScriptName 'Export-EntraConnectLocalPack' -OutputRoot $OutputRoot -RunId $RunId

$data = [pscustomobject]@{
    RunId = $RunId
    OutputRoot = $OutputRoot
    RunRoot = $context.RunRoot
    Results = @($results)
    Notes = @(
        'This wrapper runs the read-only local sync-host discovery scripts with one shared RunId.'
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
