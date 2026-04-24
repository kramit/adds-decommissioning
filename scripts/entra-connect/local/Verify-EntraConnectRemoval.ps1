param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath

$context = New-EntraConnectLocalContext -ScriptName 'Verify-EntraConnectRemoval' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$installEntries = @(Get-EntraConnectLocalInstallEntries)
$services = @(Get-EntraConnectLocalServices)
$scheduledTasks = @(Get-EntraConnectLocalScheduledTasks)

$remainingServices = @($services | Where-Object { $_.Status -ne 'Stopped' -or $_.Name -in @('ADSync', 'AzureADConnectProvisioningAgent', 'AzureADConnectAuthenticationAgent') })
$removed = (-not $installEntries) -and (-not $remainingServices -or $remainingServices.Count -eq 0)

if ($installEntries) {
    $warnings += 'An Entra Connect installation entry is still present.'
}

if ($remainingServices) {
    $warnings += 'One or more sync-related services are still present.'
}

$data = [pscustomobject]@{
    InstallEntries = @($installEntries)
    Services = @($services)
    ScheduledTasks = @($scheduledTasks)
    Removed = $removed
    Notes = @(
        'This script verifies that the local sync footprint has been removed or reduced to zero.',
        'It is a post-uninstall validation step.'
    )
}

$summary = @(
    "Install entries: $(@($installEntries).Count)",
    "Services found: $(@($services).Count)",
    "Scheduled tasks matched: $(@($scheduledTasks).Count)",
    "Removed: $removed"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    Removed = $removed
}
