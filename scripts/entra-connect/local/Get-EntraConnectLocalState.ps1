param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot 'EntraConnect.Local.Common.ps1'
. $commonPath

$context = New-EntraConnectLocalContext -ScriptName 'Get-EntraConnectLocalState' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$installEntries = @(Get-EntraConnectLocalInstallEntries)
$services = @(Get-EntraConnectLocalServices)
$scheduledTasks = @(Get-EntraConnectLocalScheduledTasks)

$registryHits = @()
foreach ($path in @(
    'HKLM:\SOFTWARE\Microsoft\Azure AD Sync',
    'HKLM:\SOFTWARE\Microsoft\Microsoft Azure AD Connect',
    'HKLM:\SOFTWARE\Microsoft\CloudSync'
)) {
    try {
        $item = Get-ItemProperty $path -ErrorAction Stop
        $registryHits += [pscustomobject]@{
            Path = $path
            Present = $true
            Values = $item.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }
        }
    }
    catch {
        $registryHits += [pscustomobject]@{
            Path = $path
            Present = $false
            Values = @()
        }
    }
}

$data = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    IsAdministrator = Test-IsLocalAdministrator
    InstallEntries = @($installEntries)
    Services = @($services)
    ScheduledTasks = @($scheduledTasks)
    RegistryHits = @($registryHits)
    Notes = @(
        'This script inventories the local Entra Connect / sync host footprint.',
        'Use it before stopping services or uninstalling the sync client.'
    )
}

$summary = @(
    "Computer: $($env:COMPUTERNAME)",
    "Administrator: $(Test-IsLocalAdministrator)",
    "Install entries: $(@($installEntries).Count)",
    "Services found: $(@($services).Count)",
    "Scheduled tasks matched: $(@($scheduledTasks).Count)"
)

$artifact = Save-EntraArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
