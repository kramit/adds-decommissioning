param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-SyncFootprint' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$services = @()
$registryHits = @()
$installedApps = @()
$adsyncScheduler = $null
$adsyncModuleAvailable = $false

foreach ($name in 'ADSync', 'AzureADConnectProvisioningAgent', 'AzureADConnectAuthenticationAgent') {
    try {
        $services += Get-Service -Name $name -ErrorAction Stop | Select-Object Name, DisplayName, Status, StartType
    }
    catch {
    }
}

$uninstallRoots = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($root in $uninstallRoots) {
    try {
        $installedApps += @(Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'Azure AD Connect|Entra Connect|Provisioning Agent|Azure AD Sync|Microsoft Entra'
        } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate)
    }
    catch {
    }
}

try {
    $registryHits += @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Azure AD Sync' -ErrorAction SilentlyContinue)
}
catch {
}

try {
    $registryHits += @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft Azure AD Connect' -ErrorAction SilentlyContinue)
}
catch {
}

try {
    $registryHits += @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\CloudSync' -ErrorAction SilentlyContinue)
}
catch {
}

$adsyncModuleAvailable = Test-OptionalModule -Name 'ADSync'
if ($adsyncModuleAvailable) {
    try {
        if (Get-Command Get-ADSyncScheduler -ErrorAction SilentlyContinue) {
            $adsyncScheduler = Get-ADSyncScheduler
        }
    }
    catch {
        $warnings += "Unable to query ADSync scheduler: $($_.Exception.Message)"
    }
}
else {
    $warnings += 'ADSync module was not available.'
}

$classification = if ($services.Name -contains 'ADSync' -or ($installedApps.DisplayName -match 'Azure AD Connect|Entra Connect')) {
    'EntraConnectSync'
}
elseif ($services.Name -contains 'AzureADConnectProvisioningAgent' -or ($installedApps.DisplayName -match 'Provisioning Agent')) {
    'CloudSyncAgent'
}
else {
    'No sync footprint detected'
}

$data = [pscustomobject]@{
    Classification = $classification
    Services = @($services)
    InstalledApplications = @($installedApps)
    RegistryHits = @($registryHits | ForEach-Object { $_.PSObject.Properties | Select-Object Name, Value })
    ADSyncScheduler = $adsyncScheduler
    Notes = @(
        'This script looks for Entra Connect Sync and Cloud Sync footprints on the server.',
        'It is a detection script, not an uninstall script.'
    )
}

$summary = @(
    "Classification: $classification",
    "Services matched: $(@($services).Count)",
    "Installed application matches: $(@($installedApps).Count)",
    "Registry hits: $(@($registryHits).Count)",
    "ADSync scheduler captured: $([bool]$adsyncScheduler)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
