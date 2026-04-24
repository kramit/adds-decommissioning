param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

if (-not $RunId) {
    $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
}

$scriptNames = @(
    'Get-DCOverview.ps1',
    'Get-FSMOState.ps1',
    'Get-ADReplicationHealth.ps1',
    'Get-DNSState.ps1',
    'Get-LocalServerFootprint.ps1',
    'Get-ADDependencyInventory.ps1',
    'Get-SyncFootprint.ps1'
)

$results = @()
foreach ($scriptName in $scriptNames) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path $scriptPath)) {
        throw "Missing script: $scriptPath"
    }

    $results += & $scriptPath -OutputRoot $OutputRoot -RunId $RunId
}

$packContext = New-DiscoveryContext -ScriptName 'Export-DiscoveryPack' -OutputRoot $OutputRoot -RunId $RunId
$summary = @(
    "Scripts run: $($results.Count)",
    "Output root: $($packContext.RunRoot)"
)

$data = [pscustomobject]@{
    RunId = $RunId
    OutputRoot = $OutputRoot
    RunRoot = $packContext.RunRoot
    Scripts = @($results)
    Notes = @(
        'This wrapper runs all discovery scripts with a shared RunId.',
        'Use it when you want one evidence pack for a single discovery pass.'
    )
}

$artifact = Save-DiscoveryArtifact -Context $packContext -Data $data -SummaryLines $summary
[pscustomobject]@{
    ScriptName = $packContext.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $packContext.RunRoot
}
