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
        $service = Get-Service -Name $name -ErrorAction Stop
        $cimService = Get-CimInstance Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue
        $services += [pscustomobject]@{
            Name = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartType = if ($cimService) { $cimService.StartMode } else { $null }
            StartName = if ($cimService) { $cimService.StartName } else { $null }
            State = if ($cimService) { $cimService.State } else { $null }
        }
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

$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Azure AD Sync',
    'HKLM:\SOFTWARE\Microsoft\Microsoft Azure AD Connect',
    'HKLM:\SOFTWARE\Microsoft\CloudSync'
)

foreach ($registryPath in $registryPaths) {
    try {
        $item = Get-ItemProperty $registryPath -ErrorAction Stop
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -notmatch '^PS') {
                $registryHits += [pscustomobject]@{
                    RegistryPath = $registryPath
                    PropertyName = $property.Name
                    PropertyValue = $property.Value
                }
            }
        }
    }
    catch {
    }
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
    RegistryHits = @($registryHits)
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
    "Registry key/property rows: $(@($registryHits).Count)",
    "ADSync scheduler captured: $([bool]$adsyncScheduler)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings -Tables @{
    'Services' = @($services)
    'InstalledApplications' = @($installedApps)
    'RegistryEntries' = @($registryHits)
    'ADSyncScheduler' = @([pscustomobject]@{
        Exists = [bool]$adsyncScheduler
        StagingMode = if ($adsyncScheduler) { $adsyncScheduler.StagingMode } else { $null }
        SyncCycleEnabled = if ($adsyncScheduler) { $adsyncScheduler.SyncCycleEnabled } else { $null }
        NextSyncCyclePolicyType = if ($adsyncScheduler) { $adsyncScheduler.NextSyncCyclePolicyType } else { $null }
        CustomizedSyncCycleInterval = if ($adsyncScheduler) { $adsyncScheduler.CustomizedSyncCycleInterval } else { $null }
        AllowedSyncCycleInterval = if ($adsyncScheduler) { $adsyncScheduler.AllowedSyncCycleInterval } else { $null }
        SchedulerSuspended = if ($adsyncScheduler) { $adsyncScheduler.SchedulerSuspended } else { $null }
    })
}
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    CsvFiles = $artifact.CsvFiles
    RunRoot = $context.RunRoot
}
