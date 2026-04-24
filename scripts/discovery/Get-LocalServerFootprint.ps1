param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-LocalServerFootprint' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$installedFeatures = @()
$keyServices = @()
$shares = @()
$shareAccess = @()
$scheduledTasks = @()

try {
    if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
        $installedFeatures = @(Get-WindowsFeature | Where-Object Installed | Select-Object Name, DisplayName)
    }
    else {
        $warnings += 'Get-WindowsFeature was not available.'
    }
}
catch {
    $warnings += "Unable to enumerate Windows features: $($_.Exception.Message)"
}

foreach ($name in 'NTDS', 'DNS', 'DFSR', 'Netlogon', 'ADWS', 'W32Time', 'ADSync', 'AzureADConnectProvisioningAgent') {
    try {
        $keyServices += Get-Service -Name $name -ErrorAction Stop | Select-Object Name, DisplayName, Status, StartType
    }
    catch {
    }
}

try {
    $shares = @(Get-SmbShare | Select-Object Name, Path, Description, Special, ScopeName, CachingMode, ConcurrentUserLimit)
    foreach ($share in @($shares)) {
        try {
            $shareAccess += @(Get-SmbShareAccess -Name $share.Name | Select-Object @{Name='ShareName';Expression={$share.Name}}, AccountName, AccessControlType, AccessRight)
        }
        catch {
            $warnings += "Unable to read access list for SMB share '$($share.Name)': $($_.Exception.Message)"
        }
    }
}
catch {
    $warnings += "Unable to enumerate SMB shares: $($_.Exception.Message)"
}

try {
    $scheduledTasks = @(Get-ScheduledTask | Where-Object {
        $_.TaskName -match 'AD|Azure|Entra|Sync|Dir|DNS' -or $_.TaskPath -match 'AD|Azure|Entra|Sync|Dir|DNS'
    } | Select-Object TaskName, TaskPath, State, Author, Description)
}
catch {
    $warnings += "Unable to enumerate scheduled tasks: $($_.Exception.Message)"
}

$data = [pscustomobject]@{
    InstalledFeatures = @($installedFeatures)
    KeyServices = @($keyServices)
    SMBShares = @($shares)
    SMBShareAccess = @($shareAccess)
    ScheduledTasks = @($scheduledTasks)
    Notes = @(
        'This script captures local server footprint that may affect the decommission.',
        'It focuses on services, features, shares, and scheduled tasks that are relevant to AD DS, DNS, and sync.'
    )
}

$summary = @(
    "Installed features: $(@($installedFeatures).Count)",
    "Key services found: $(@($keyServices).Count)",
    "SMB shares: $(@($shares).Count)",
    "SMB share access entries: $(@($shareAccess).Count)",
    "Scheduled tasks matched: $(@($scheduledTasks).Count)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings -Tables @{
    'InstalledFeatures' = @($installedFeatures)
    'KeyServices' = @($keyServices)
    'SMBShares' = @($shares)
    'SMBShareAccess' = @($shareAccess)
    'ScheduledTasks' = @($scheduledTasks)
}
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    CsvFiles = $artifact.CsvFiles
    RunRoot = $context.RunRoot
}
