param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath

$context = New-EntraConnectLocalContext -ScriptName 'Test-EntraConnectLocalPrereqs' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$isAdmin = Test-IsLocalAdministrator
$installEntries = @(Get-EntraConnectLocalInstallEntries)
$services = @(Get-EntraConnectLocalServices)

if (-not $isAdmin) {
    $warnings += 'The current session is not elevated as local Administrator.'
}

if (-not $installEntries) {
    $warnings += 'No Entra Connect installation entry was detected on this host.'
}

if (-not $services) {
    $warnings += 'No Entra Connect-related services were detected.'
}

$commandLines = @($installEntries | ForEach-Object { $_.UninstallString })
$msiCommands = @($installEntries | ForEach-Object { Convert-MsiUninstallString -UninstallString $_.UninstallString } | Where-Object { $_ })

$ready = $isAdmin -and $installEntries.Count -gt 0

$data = [pscustomobject]@{
    IsAdministrator = $isAdmin
    Ready = $ready
    InstallEntries = @($installEntries)
    Services = @($services)
    UninstallStrings = @($commandLines)
    CandidateMsiCommands = @($msiCommands)
    Notes = @(
        'This script checks whether the host is ready for a controlled Entra Connect uninstall.',
        'It does not stop services or uninstall anything.'
    )
}

$summary = @(
    "Administrator: $isAdmin",
    "Install entries: $(@($installEntries).Count)",
    "Services found: $(@($services).Count)",
    "MSI uninstall commands found: $(@($msiCommands).Count)",
    "Ready: $ready"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
    Ready = $ready
}
